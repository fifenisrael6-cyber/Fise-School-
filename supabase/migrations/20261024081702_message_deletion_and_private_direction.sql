-- Message deletion controls and teacher moderation for group messages.
-- "For me" hides only for the current user. "For everyone" preserves a tombstone.
create or replace function public.delete_group_message(
  p_message_id uuid,
  p_for_everyone boolean default true
)
returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_message public.message_group_messages%rowtype;
  v_user_id uuid := auth.uid();
  v_group_owner uuid;
  v_user_role text;
  v_attachment_path text;
  v_can_moderate boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_message
  from public.message_group_messages
  where id = p_message_id
  for update;

  if not found then
    raise exception 'Message not found';
  end if;

  if not public.is_message_group_member(v_message.group_id) then
    raise exception 'Not a member of this group';
  end if;

  if coalesce(p_for_everyone, false) then
    select g.owner_id into v_group_owner
    from public.message_groups g
    where g.id = v_message.group_id;

    select p.role into v_user_role
    from public.profiles p
    where p.id = v_user_id;

    v_can_moderate := v_user_role = 'teacher' and v_group_owner = v_user_id;

    if v_message.sender_id <> v_user_id and not v_can_moderate then
      raise exception 'Only the sender or the group teacher can delete a message for everyone';
    end if;

    if v_message.deleted_at is not null then
      raise exception 'Message has already been deleted for everyone';
    end if;

    v_attachment_path := v_message.attachment_path;
    update public.message_group_messages
    set deleted_at = now(),
        deleted_by = v_user_id,
        body = '[deleted]',
        attachment_path = null,
        attachment_name = null,
        attachment_type = null
    where id = p_message_id;

    return v_attachment_path;
  end if;

  update public.message_group_messages
  set hidden_for = case
    when v_user_id = any(coalesce(hidden_for, '{}'::uuid[]))
      then coalesce(hidden_for, '{}'::uuid[])
    else array_append(coalesce(hidden_for, '{}'::uuid[]), v_user_id)
  end
  where id = p_message_id;

  return null;
end;
$function$;

create or replace function public.delete_private_message(
  p_message_id uuid,
  p_for_everyone boolean default true
)
returns text
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_message public.private_messages%rowtype;
  v_user_id uuid := auth.uid();
  v_attachment_path text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_message
  from public.private_messages
  where id = p_message_id
  for update;

  if not found then
    raise exception 'Message not found';
  end if;

  if v_user_id <> v_message.sender_id and v_user_id <> v_message.recipient_id then
    raise exception 'You are not a participant in this conversation';
  end if;

  if coalesce(p_for_everyone, false) then
    if v_message.sender_id <> v_user_id then
      raise exception 'Only the sender can delete a private message for everyone';
    end if;

    if v_message.deleted_at is not null then
      raise exception 'Message has already been deleted for everyone';
    end if;

    v_attachment_path := v_message.attachment_path;
    update public.private_messages
    set deleted_at = now(),
        deleted_by = v_user_id,
        body = '[deleted]',
        attachment_path = null,
        attachment_name = null,
        attachment_type = null
    where id = p_message_id;

    return v_attachment_path;
  end if;

  update public.private_messages
  set hidden_for = case
    when v_user_id = any(coalesce(hidden_for, '{}'::uuid[]))
      then coalesce(hidden_for, '{}'::uuid[])
    else array_append(coalesce(hidden_for, '{}'::uuid[]), v_user_id)
  end
  where id = p_message_id;

  return null;
end;
$function$;

revoke all on function public.delete_group_message(uuid, boolean) from public, anon;
revoke all on function public.delete_private_message(uuid, boolean) from public, anon;
grant execute on function public.delete_group_message(uuid, boolean) to authenticated;
grant execute on function public.delete_private_message(uuid, boolean) to authenticated;
