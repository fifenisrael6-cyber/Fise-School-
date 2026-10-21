-- Membership changes already create a dedicated group_member notification.
-- Keep the in-chat system message, but do not emit a second generic message notification for it.
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
  if coalesce(new.body, '') like 'ℹ️ %' then
    return new;
  end if;

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
    insert into public.notifications(user_id, title, body, type, target_type, target_id)
    values (recipient.user_id, coalesce(nullif(sender_name, ''), 'Fise School'),
            notification_body, 'message', 'group', new.group_id);
  end loop;
  return new;
end;
$function$;

notify pgrst, 'reload schema';
