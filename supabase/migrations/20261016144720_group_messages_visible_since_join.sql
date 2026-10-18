-- New group members may read only messages posted from their membership start.
-- Enforce the cutoff in RPC, table RLS, group previews/unread counts and attachments.

drop policy if exists "members read group messages" on public.message_group_messages;
create policy "members read group messages since joining"
on public.message_group_messages
for select to authenticated
using (
  exists (
    select 1
    from public.message_group_members member
    where member.group_id = message_group_messages.group_id
      and member.user_id = (select auth.uid())
      and message_group_messages.created_at >= member.joined_at
  )
  and not ((select auth.uid()) = any(coalesce(hidden_for, '{}'::uuid[])))
);

-- Preserve the existing extended return contract used by delivery/read receipts
-- and view-once messages. Only the membership cutoff is added.
create or replace function public.list_message_group_messages(p_group_id uuid)
returns table (
  id uuid,
  sender_id uuid,
  sender_name text,
  sender_role text,
  body text,
  attachment_path text,
  attachment_name text,
  attachment_type text,
  created_at timestamptz,
  view_once boolean,
  viewed_by_me boolean,
  deleted_at timestamptz,
  delivered_count bigint,
  read_count bigint,
  recipient_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_joined_at timestamptz;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select member.joined_at into v_joined_at
  from public.message_group_members member
  where member.group_id = p_group_id
    and member.user_id = (select auth.uid());

  if v_joined_at is null then
    raise exception 'Not a member of this group';
  end if;

  return query
  select m.id,
    m.sender_id,
    trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')),
    p.role::text,
    case when m.deleted_at is null then m.body else '' end,
    case when m.deleted_at is null then m.attachment_path else null end,
    case when m.deleted_at is null then m.attachment_name else null end,
    case when m.deleted_at is null then m.attachment_type else null end,
    m.created_at,
    m.view_once,
    exists (
      select 1 from public.message_group_message_views v
      where v.message_id = m.id and v.user_id = (select auth.uid())
    ),
    m.deleted_at,
    (select count(*) from public.message_group_message_receipts r
      where r.message_id = m.id and r.delivered_at is not null and r.user_id <> m.sender_id),
    (select count(*) from public.message_group_message_receipts r
      where r.message_id = m.id and r.read_at is not null and r.user_id <> m.sender_id),
    (select count(*) from public.message_group_members gm
      where gm.group_id = p_group_id and gm.user_id <> m.sender_id)
  from public.message_group_messages m
  left join public.profiles p on p.id = m.sender_id
  where m.group_id = p_group_id
    and m.created_at >= v_joined_at
    and not ((select auth.uid()) = any(coalesce(m.hidden_for, '{}'::uuid[])))
  order by m.created_at asc;
end;
$$;

revoke all on function public.list_message_group_messages(uuid) from public;
grant execute on function public.list_message_group_messages(uuid) to authenticated;

-- Do not reveal pre-join message previews or unread counts in the group list.
create or replace function public.list_my_message_groups()
returns table (
  id uuid, name text, class_id uuid, class_name text, owner_id uuid,
  invite_code text, member_count bigint, last_body text,
  last_at timestamptz, unread_count bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    g.id,
    g.name,
    g.class_id,
    c.display_name,
    g.owner_id,
    case when g.owner_id = (select auth.uid()) then g.invite_code else null end,
    (select count(*) from public.message_group_members m2 where m2.group_id = g.id),
    (select case when length(trim(lm.body)) > 0 then lm.body
      else coalesce(lm.attachment_name, 'Pièce jointe') end
      from public.message_group_messages lm
      where lm.group_id = g.id
        and lm.created_at >= me.joined_at
        and not ((select auth.uid()) = any(coalesce(lm.hidden_for, '{}'::uuid[])))
      order by lm.created_at desc limit 1),
    (select max(lm.created_at) from public.message_group_messages lm
      where lm.group_id = g.id
        and lm.created_at >= me.joined_at
        and not ((select auth.uid()) = any(coalesce(lm.hidden_for, '{}'::uuid[])))),
    (select count(*) from public.message_group_messages unread
      where unread.group_id = g.id
        and unread.created_at >= me.joined_at
        and unread.sender_id <> (select auth.uid())
        and unread.deleted_at is null
        and not ((select auth.uid()) = any(coalesce(unread.hidden_for, '{}'::uuid[])))
        and not exists (
          select 1 from public.message_group_message_receipts receipt
          where receipt.message_id = unread.id and receipt.user_id = (select auth.uid())
            and receipt.read_at is not null
        ))
  from public.message_groups g
  join public.message_group_members me
    on me.group_id = g.id and me.user_id = (select auth.uid())
  left join public.school_classes c on c.id = g.class_id
  order by coalesce((
    select max(lm.created_at) from public.message_group_messages lm
    where lm.group_id = g.id
      and lm.created_at >= me.joined_at
      and not ((select auth.uid()) = any(coalesce(lm.hidden_for, '{}'::uuid[])))
  ), me.joined_at) desc;
$$;

revoke all on function public.list_my_message_groups() from public;
grant execute on function public.list_my_message_groups() to authenticated;

-- Keep existing deleted-message and view-once attachment protections,
-- and add the membership join-time cutoff.
drop policy if exists "group members read attachments" on storage.objects;
create policy "group members read attachments since joining"
on storage.objects
for select to authenticated
using (
  bucket_id = 'group-message-attachments'
  and exists (
    select 1
    from public.message_group_messages message
    join public.message_group_members member
      on member.group_id = message.group_id
     and member.user_id = (select auth.uid())
    where message.attachment_path = storage.objects.name
      and message.group_id = (storage.foldername(storage.objects.name))[1]::uuid
      and message.created_at >= member.joined_at
      and message.deleted_at is null
      and (not message.view_once or message.sender_id = (select auth.uid()))
  )
);

notify pgrst, 'reload schema';
