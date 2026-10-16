-- Fise School: additive group moderation and message privacy controls.
-- No existing tables or features are dropped. All destructive actions are scoped to
-- the authenticated member/owner and enforced by SECURITY DEFINER RPCs.

alter table public.message_groups
  add column if not exists announcements_only boolean not null default false;

alter table public.message_group_messages
  add column if not exists hidden_for uuid[] not null default '{}'::uuid[],
  add column if not exists deleted_at timestamptz;

alter table public.private_messages
  add column if not exists hidden_for uuid[] not null default '{}'::uuid[],
  add column if not exists deleted_at timestamptz;

-- "Delete for me" must also be respected by direct table reads, not only by the UI RPC.
drop policy if exists "members read group messages" on public.message_group_messages;
create policy "members read group messages"
on public.message_group_messages for select to authenticated
using (
  public.is_message_group_member(group_id)
  and not ((select auth.uid()) = any(coalesce(hidden_for, '{}'::uuid[])))
);

drop policy if exists "participants read private messages" on public.private_messages;
create policy "participants read private messages" on public.private_messages for select to authenticated
using (
  (sender_id = (select auth.uid()) or recipient_id = (select auth.uid()))
  and public.can_message(
    case when sender_id = (select auth.uid()) then recipient_id else sender_id end
  )
  and not ((select auth.uid()) = any(coalesce(hidden_for, '{}'::uuid[])))
);

-- A group owner may remove students, not other teachers; every member may leave themselves.
drop policy if exists "owner removes or member leaves" on public.message_group_members;
create policy "owner removes or member leaves"
on public.message_group_members for delete to authenticated
using (
  user_id = (select auth.uid())
  or (
    role = 'student'
    and exists (
      select 1 from public.message_groups g
      where g.id = group_id and g.owner_id = (select auth.uid())
    )
  )
);

-- Physical row deletion would bypass the per-user hiding and shared tombstone rules.
drop policy if exists "senders delete own private messages" on public.private_messages;
drop policy if exists "senders delete own group messages" on public.message_group_messages;

-- Permit users to remove only their own uploaded group files, including after
-- the message row has been converted to a deletion tombstone.
drop policy if exists "members delete own group attachments" on storage.objects;
create policy "members delete own group attachments"
on storage.objects for delete to authenticated
using (
  bucket_id = 'group-message-attachments'
  and owner_id = (select auth.uid())::text
);

-- Server-side enforcement: a locked group accepts messages only from its owner.
create or replace function public.enforce_message_group_send_rules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
  v_announcements_only boolean;
begin
  if auth.uid() is null or new.sender_id <> auth.uid() then
    raise exception 'Authenticated sender required';
  end if;

  if not exists (
    select 1 from public.message_group_members gm
    where gm.group_id = new.group_id and gm.user_id = auth.uid()
  ) then
    raise exception 'You are not a member of this group';
  end if;

  select g.owner_id, g.announcements_only
    into v_owner_id, v_announcements_only
  from public.message_groups g
  where g.id = new.group_id;

  if not found then
    raise exception 'Group not found';
  end if;

  if v_announcements_only and auth.uid() <> v_owner_id then
    raise exception 'This group is locked to teacher announcements';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_message_group_send_rules
  on public.message_group_messages;
create trigger enforce_message_group_send_rules
before insert on public.message_group_messages
for each row execute function public.enforce_message_group_send_rules();

revoke all on function public.enforce_message_group_send_rules() from public, anon;

create or replace function public.get_message_group_announcement_mode(p_group_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_mode boolean;
begin
  if auth.uid() is null or not public.is_message_group_member(p_group_id) then
    raise exception 'Not a member of this group';
  end if;

  select g.announcements_only into v_mode
  from public.message_groups g where g.id = p_group_id;

  if not found then raise exception 'Group not found'; end if;
  return v_mode;
end;
$$;

create or replace function public.set_message_group_announcement_mode(
  p_group_id uuid,
  p_enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  update public.message_groups
  set announcements_only = coalesce(p_enabled, false)
  where id = p_group_id and owner_id = auth.uid();

  if not found then
    raise exception 'Only the group owner can change announcement mode';
  end if;

  return coalesce(p_enabled, false);
end;
$$;

create or replace function public.leave_message_group(p_group_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  if exists (
    select 1 from public.message_groups g
    where g.id = p_group_id and g.owner_id = auth.uid()
  ) then
    raise exception 'The group owner must delete the group instead of leaving it';
  end if;

  delete from public.message_group_members
  where group_id = p_group_id and user_id = auth.uid();

  if not found then raise exception 'You are not a member of this group'; end if;
  return true;
end;
$$;

create or replace function public.remove_message_group_member(
  p_group_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_user_id = auth.uid() then
    raise exception 'Use leave_message_group to leave a group';
  end if;

  delete from public.message_group_members gm
  where gm.group_id = p_group_id
    and gm.user_id = p_user_id
    and gm.role = 'student'
    and exists (
      select 1 from public.message_groups g
      where g.id = gm.group_id and g.owner_id = auth.uid()
    );

  if not found then
    raise exception 'Only the group owner can remove a student from this group';
  end if;
  return true;
end;
$$;

create or replace function public.delete_message_group(p_group_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  delete from public.message_groups
  where id = p_group_id and owner_id = auth.uid();

  if not found then
    raise exception 'Only the group owner can delete this group';
  end if;
  return true;
end;
$$;

-- "For me" only adds the current user to hidden_for. "For everyone" is restricted
-- to the original sender and replaces the content with a deletion tombstone.
create or replace function public.delete_group_message(
  p_message_id uuid,
  p_for_everyone boolean DEFAULT true
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message public.message_group_messages%rowtype;
  v_user_id uuid := auth.uid();
  v_attachment_path text;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;

  select * into v_message
  from public.message_group_messages
  where id = p_message_id
  for update;

  if not found then raise exception 'Message not found'; end if;
  if not public.is_message_group_member(v_message.group_id) then
    raise exception 'Not a member of this group';
  end if;

  if coalesce(p_for_everyone, false) then
    if v_message.sender_id <> v_user_id then
      raise exception 'Only the sender can delete a message for everyone';
    end if;

    v_attachment_path := v_message.attachment_path;
    update public.message_group_messages
    set deleted_at = coalesce(deleted_at, now()),
        body = '',
        attachment_path = null,
        attachment_name = null,
        attachment_type = null
    where id = p_message_id;
    return v_attachment_path;
  end if;

  update public.message_group_messages
  set hidden_for = case
    when v_user_id = any(coalesce(hidden_for, '{}'::uuid[])) then coalesce(hidden_for, '{}'::uuid[])
    else array_append(coalesce(hidden_for, '{}'::uuid[]), v_user_id)
  end
  where id = p_message_id;
  return null;
end;
$$;

create or replace function public.delete_private_message(
  p_message_id uuid,
  p_for_everyone boolean DEFAULT true
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message public.private_messages%rowtype;
  v_user_id uuid := auth.uid();
  v_attachment_path text;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;

  select * into v_message
  from public.private_messages
  where id = p_message_id
  for update;

  if not found then raise exception 'Message not found'; end if;
  if v_user_id <> v_message.sender_id and v_user_id <> v_message.recipient_id then
    raise exception 'You are not a participant in this conversation';
  end if;

  if coalesce(p_for_everyone, false) then
    if v_message.sender_id <> v_user_id then
      raise exception 'Only the sender can delete a message for everyone';
    end if;

    v_attachment_path := v_message.attachment_path;
    update public.private_messages
    set deleted_at = coalesce(deleted_at, now()),
        body = '',
        attachment_path = null,
        attachment_name = null,
        attachment_type = null
    where id = p_message_id;
    return v_attachment_path;
  end if;

  update public.private_messages
  set hidden_for = case
    when v_user_id = any(coalesce(hidden_for, '{}'::uuid[])) then coalesce(hidden_for, '{}'::uuid[])
    else array_append(coalesce(hidden_for, '{}'::uuid[]), v_user_id)
  end
  where id = p_message_id;
  return null;
end;
$$;

revoke all on function public.get_message_group_announcement_mode(uuid) from public, anon;
revoke all on function public.set_message_group_announcement_mode(uuid, boolean) from public, anon;
revoke all on function public.leave_message_group(uuid) from public, anon;
revoke all on function public.remove_message_group_member(uuid, uuid) from public, anon;
revoke all on function public.delete_message_group(uuid) from public, anon;
revoke all on function public.delete_group_message(uuid, boolean) from public, anon;
revoke all on function public.delete_private_message(uuid, boolean) from public, anon;

grant execute on function public.get_message_group_announcement_mode(uuid) to authenticated;
grant execute on function public.set_message_group_announcement_mode(uuid, boolean) to authenticated;
grant execute on function public.leave_message_group(uuid) to authenticated;
grant execute on function public.remove_message_group_member(uuid, uuid) to authenticated;
grant execute on function public.delete_message_group(uuid) to authenticated;
grant execute on function public.delete_group_message(uuid, boolean) to authenticated;
grant execute on function public.delete_private_message(uuid, boolean) to authenticated;
