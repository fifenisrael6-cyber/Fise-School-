-- Legacy group-message notifications did not always include a group target.
-- Resolve those notifications to a group only when the recipient is a current
-- member and the sender/body match a stored group message.
create or replace function public.enrich_legacy_group_message_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_group_id uuid;
begin
  if new.target_type is not null and new.target_id is not null then
    return new;
  end if;
  if lower(coalesce(new.type, '')) <> 'message' then
    return new;
  end if;

  select m.group_id into v_group_id
  from public.message_group_messages m
  join public.profiles p on p.id = m.sender_id
  join public.message_group_members gm
    on gm.group_id = m.group_id
   and gm.user_id = new.user_id
  where trim(concat(p.first_name, ' ', p.last_name)) = new.title
    and coalesce(nullif(left(m.body, 500), ''), 'Nouvelle pièce jointe') = new.body
  order by m.created_at desc
  limit 1;

  if v_group_id is not null then
    new.target_type := 'group';
    new.target_id := v_group_id;
  end if;
  return new;
end;
$function$;

drop trigger if exists notifications_legacy_group_target
  on public.notifications;
create trigger notifications_legacy_group_target
before insert or update on public.notifications
for each row
execute function public.enrich_legacy_group_message_notification();

revoke all on function public.enrich_legacy_group_message_notification()
  from public, anon, authenticated;

-- Re-run target enrichment for older message notifications that predate
-- target_type/target_id support. Explicitly populated targets stay untouched.
update public.notifications
set target_type = target_type
where type = 'message' and target_type is null;
