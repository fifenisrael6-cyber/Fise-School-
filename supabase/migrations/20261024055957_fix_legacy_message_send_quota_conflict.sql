-- The legacy two-message sender quota conflicts with the current central
-- msg_sent quota and the Premium gate. Keep recipient visibility limits, but
-- let enforce_message_send_quota be the single authoritative send-side gate.

create or replace function public.apply_free_group_message_limits()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_member record;
  v_allowed jsonb;
  v_visible uuid[] := '{}';
begin
  if auth.uid() is null or new.sender_id <> auth.uid() then
    raise exception 'Authenticated sender required';
  end if;

  new.free_limited := true;
  for v_member in
    select gm.user_id, p.role
    from public.message_group_members gm
    join public.profiles p on p.id = gm.user_id
    where gm.group_id = new.group_id and gm.user_id <> new.sender_id
  loop
    if v_member.role <> 'student' or public.is_student_premium(v_member.user_id) then
      v_visible := array_append(v_visible, v_member.user_id);
    else
      v_allowed := public.consume_free_quota_for_user(v_member.user_id, 'group_receive', null);
      if coalesce((v_allowed ->> 'allowed')::boolean, false) is true then
        v_visible := array_append(v_visible, v_member.user_id);
      end if;
    end if;
  end loop;

  new.free_visible_to := v_visible;
  return new;
end;
$function$;

create or replace function public.apply_free_private_message_limits()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_recipient_role text;
  v_allowed jsonb;
  v_visible uuid[] := '{}';
begin
  if auth.uid() is null or new.sender_id <> auth.uid() then
    raise exception 'Authenticated sender required';
  end if;

  select p.role into v_recipient_role
  from public.profiles p
  where p.id = new.recipient_id;

  new.free_limited := true;
  if v_recipient_role <> 'student' or public.is_student_premium(new.recipient_id) then
    v_visible := array_append(v_visible, new.recipient_id);
  else
    v_allowed := public.consume_free_quota_for_user(new.recipient_id, 'group_receive', null);
    if coalesce((v_allowed ->> 'allowed')::boolean, false) is true then
      v_visible := array_append(v_visible, new.recipient_id);
    end if;
  end if;

  new.free_visible_to := v_visible;
  return new;
end;
$function$;
