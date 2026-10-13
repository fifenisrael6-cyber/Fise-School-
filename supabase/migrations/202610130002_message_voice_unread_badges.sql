-- Fise School: message push alerts, unread badges, and safe QCM deletion UX support.
-- Existing private-message push trigger is preserved; voice messages get a clear notification body.
create or replace function public.notify_private_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  sender_name text;
  notification_body text;
begin
  select trim(concat(first_name, ' ', last_name))
    into sender_name
  from public.profiles
  where id = new.sender_id;

  notification_body :=
    case
      when lower(coalesce(new.attachment_type, '')) like 'audio/%'
        or lower(coalesce(new.attachment_name, '')) like 'voice-%'
        then '🎤 Message vocal reçu / New voice message'
      when nullif(trim(coalesce(new.body, '')), '') is null
        then 'Nouvelle pièce jointe / New attachment'
      else left(new.body, 500)
    end;

  insert into public.notifications(user_id, title, body, type)
  values (
    new.recipient_id,
    coalesce(nullif(sender_name, ''), 'Fise School'),
    notification_body,
    'message'
  );
  return new;
end;
$function$;

create or replace function public.notify_group_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  sender_name text;
  notification_body text;
  recipient record;
begin
  select trim(concat(first_name, ' ', last_name))
    into sender_name
  from public.profiles
  where id = new.sender_id;

  notification_body :=
    case
      when lower(coalesce(new.attachment_type, '')) like 'audio/%'
        or lower(coalesce(new.attachment_name, '')) like 'voice-%'
        then '🎤 Nouveau message vocal / New voice message'
      when nullif(trim(coalesce(new.body, '')), '') is null
        then 'Nouveau média de groupe / New group media'
      else left(new.body, 500)
    end;

  for recipient in
    select gm.user_id
    from public.message_group_members gm
    where gm.group_id = new.group_id
      and gm.user_id <> new.sender_id
  loop
    insert into public.notifications(user_id, title, body, type)
    values (
      recipient.user_id,
      coalesce(nullif(sender_name, ''), 'Fise School'),
      notification_body,
      'message'
    );
  end loop;

  return new;
end;
$function$;

drop trigger if exists group_message_notification on public.message_group_messages;
create trigger group_message_notification
after insert on public.message_group_messages
for each row execute function public.notify_group_message();

-- Extend the private contact RPC with a per-contact unread count.
drop function if exists public.list_private_message_contacts();
create function public.list_private_message_contacts()
returns table (
  id uuid,
  first_name text,
  last_name text,
  role text,
  class_name text,
  unread_count bigint
)
language sql
stable
security definer
set search_path = public
as $function$
  select distinct on (p.id)
    p.id,
    p.first_name,
    p.last_name,
    p.role,
    c.display_name as class_name,
    (
      select count(*)
      from public.private_messages pm
      where pm.sender_id = p.id
        and pm.recipient_id = auth.uid()
        and pm.read_at is null
        and not (auth.uid() = any(coalesce(pm.hidden_for, '{}'::uuid[])))
    ) as unread_count
  from public.teacher_access_memberships m
  join public.school_classes c on c.id = m.class_id
  join public.profiles p on p.id = case
    when m.student_id = auth.uid() then m.teacher_id
    else m.student_id
  end
  where m.student_id = auth.uid() or m.teacher_id = auth.uid()
  order by p.id, c.display_name;
$function$;

revoke all on function public.list_private_message_contacts() from public;
grant execute on function public.list_private_message_contacts() to authenticated;

-- Extend the group-list RPC with unread counts without exposing other groups.
drop function if exists public.list_my_message_groups();
create function public.list_my_message_groups()
returns table (
  id uuid,
  name text,
  class_id uuid,
  class_name text,
  owner_id uuid,
  invite_code text,
  member_count bigint,
  last_body text,
  last_at timestamptz,
  unread_count bigint
)
language sql
stable
security definer
set search_path = public
as $function$
  select
    g.id,
    g.name,
    g.class_id,
    c.display_name,
    g.owner_id,
    case
      when g.owner_id <> auth.uid() then null
      when g.class_id is null then g.invite_code
      else coalesce(
        (
          select 'FISE-' || upper(trim(t.code))
          from public.teacher_access_codes t
          where t.teacher_id = g.owner_id
            and t.class_id::text = g.class_id::text
            and t.is_active = true
          order by t.created_at
          limit 1
        ),
        g.invite_code
      )
    end,
    (select count(*) from public.message_group_members m2 where m2.group_id = g.id),
    (select case
              when length(trim(lm.body)) > 0 then lm.body
              else coalesce(lm.attachment_name, 'Pièce jointe')
            end
     from public.message_group_messages lm
     where lm.group_id = g.id
       and not (auth.uid() = any(coalesce(lm.hidden_for, '{}'::uuid[])))
     order by lm.created_at desc
     limit 1),
    (select max(lm.created_at)
     from public.message_group_messages lm
     where lm.group_id = g.id
       and not (auth.uid() = any(coalesce(lm.hidden_for, '{}'::uuid[])))),
    (
      select count(*)
      from public.message_group_messages unread
      where unread.group_id = g.id
        and unread.sender_id <> auth.uid()
        and unread.deleted_at is null
        and not (auth.uid() = any(coalesce(unread.hidden_for, '{}'::uuid[])))
        and not exists (
          select 1
          from public.message_group_message_receipts receipt
          where receipt.message_id = unread.id
            and receipt.user_id = auth.uid()
            and receipt.read_at is not null
        )
    ) as unread_count
  from public.message_groups g
  join public.message_group_members me
    on me.group_id = g.id and me.user_id = auth.uid()
  left join public.school_classes c on c.id = g.class_id
  order by coalesce(
    (select max(lm.created_at)
     from public.message_group_messages lm
     where lm.group_id = g.id
       and not (auth.uid() = any(coalesce(lm.hidden_for, '{}'::uuid[])))),
    g.created_at
  ) desc;
$function$;

revoke all on function public.list_my_message_groups() from public;
grant execute on function public.list_my_message_groups() to authenticated;
