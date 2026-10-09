-- WhatsApp-style messaging: private voice notes, view-once attachments, and message deletion.
-- Existing ordinary attachments remain private and continue to use signed URLs.

alter table public.private_messages
  add column if not exists view_once boolean not null default false,
  add column if not exists viewed_at timestamptz,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null,
  add column if not exists hidden_for uuid[] not null default '{}'::uuid[];

alter table public.message_group_messages
  add column if not exists view_once boolean not null default false,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null,
  add column if not exists hidden_for uuid[] not null default '{}'::uuid[];

create table if not exists public.message_group_message_views (
  message_id uuid not null references public.message_group_messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  opened_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
alter table public.message_group_message_views enable row level security;
revoke all on table public.message_group_message_views from anon, authenticated;

-- Hide "delete for me" messages from both the RPC and direct table queries.
drop policy if exists "participants read private messages" on public.private_messages;
create policy "participants read private messages"
on public.private_messages for select to authenticated
using (
  (sender_id = (select auth.uid()) or recipient_id = (select auth.uid()))
  and not ((select auth.uid()) = any(coalesce(hidden_for, '{}'::uuid[])))
);

drop policy if exists "members read group messages" on public.message_group_messages;
create policy "members read group messages"
on public.message_group_messages for select to authenticated
using (
  public.is_message_group_member(group_id)
  and not ((select auth.uid()) = any(coalesce(hidden_for, '{}'::uuid[])))
);

create or replace function public.list_private_messages(target_user_id uuid)
returns setof public.private_messages
language sql
stable
security definer
set search_path = ''
as $$
  select m.*
  from public.private_messages m
  where public.can_message(target_user_id)
    and (
      (m.sender_id = (select auth.uid()) and m.recipient_id = target_user_id)
      or (m.sender_id = target_user_id and m.recipient_id = (select auth.uid()))
    )
    and not ((select auth.uid()) = any(coalesce(m.hidden_for, '{}'::uuid[])))
  order by m.created_at;
$$;
revoke all on function public.list_private_messages(uuid) from public, anon;
grant execute on function public.list_private_messages(uuid) to authenticated;

drop function if exists public.list_message_group_messages(uuid);
create function public.list_message_group_messages(p_group_id uuid)
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
  deleted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_message_group_member(p_group_id) then
    raise exception 'Not a member of this group';
  end if;

  return query
  select
    m.id,
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
      select 1
      from public.message_group_message_views v
      where v.message_id = m.id and v.user_id = (select auth.uid())
    ),
    m.deleted_at
  from public.message_group_messages m
  left join public.profiles p on p.id = m.sender_id
  where m.group_id = p_group_id
    and not ((select auth.uid()) = any(coalesce(m.hidden_for, '{}'::uuid[])))
  order by m.created_at asc;
end;
$$;
revoke all on function public.list_message_group_messages(uuid) from public, anon;
grant execute on function public.list_message_group_messages(uuid) to authenticated;

create or replace function public.delete_private_message(
  p_message_id uuid,
  p_for_everyone boolean default true
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_message public.private_messages%rowtype;
  v_path text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;

  select * into v_message
  from public.private_messages
  where id = p_message_id
    and (sender_id = v_user or recipient_id = v_user)
  for update;

  if not found then raise exception 'Message not found or not available'; end if;

  if p_for_everyone then
    if v_message.sender_id <> v_user then
      raise exception 'Only the sender can delete a message for everyone';
    end if;
    v_path := v_message.attachment_path;
    update public.private_messages
       set body = 'Message supprimé',
           attachment_path = null,
           attachment_name = null,
           attachment_type = null,
           attachment_size = null,
           view_once = false,
           deleted_at = coalesce(deleted_at, now()),
           deleted_by = v_user
     where id = p_message_id;
    return v_path;
  end if;

  update public.private_messages
     set hidden_for = case
       when v_user = any(coalesce(hidden_for, '{}'::uuid[])) then coalesce(hidden_for, '{}'::uuid[])
       else array_append(coalesce(hidden_for, '{}'::uuid[]), v_user)
     end
   where id = p_message_id;
  return null;
end;
$$;
revoke all on function public.delete_private_message(uuid, boolean) from public, anon;
grant execute on function public.delete_private_message(uuid, boolean) to authenticated;

create or replace function public.delete_group_message(
  p_message_id uuid,
  p_for_everyone boolean default true
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_message public.message_group_messages%rowtype;
  v_path text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;

  select * into v_message
  from public.message_group_messages
  where id = p_message_id
    and public.is_message_group_member(group_id)
  for update;

  if not found then raise exception 'Message not found or not available'; end if;

  if p_for_everyone then
    if v_message.sender_id <> v_user then
      raise exception 'Only the sender can delete a message for everyone';
    end if;
    v_path := v_message.attachment_path;
    update public.message_group_messages
       set body = 'Message supprimé',
           attachment_path = null,
           attachment_name = null,
           attachment_type = null,
           view_once = false,
           deleted_at = coalesce(deleted_at, now()),
           deleted_by = v_user
     where id = p_message_id;
    return v_path;
  end if;

  update public.message_group_messages
     set hidden_for = case
       when v_user = any(coalesce(hidden_for, '{}'::uuid[])) then coalesce(hidden_for, '{}'::uuid[])
       else array_append(coalesce(hidden_for, '{}'::uuid[]), v_user)
     end
   where id = p_message_id;
  return null;
end;
$$;
revoke all on function public.delete_group_message(uuid, boolean) from public, anon;
grant execute on function public.delete_group_message(uuid, boolean) to authenticated;

-- Atomic claims prevent multiple recipients/devices from opening the same private attachment twice.
create or replace function public.claim_private_message_view_once(p_message_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_sender uuid;
  v_path text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;

  select m.sender_id, m.attachment_path
    into v_sender, v_path
  from public.private_messages m
  where m.id = p_message_id
    and m.recipient_id = v_user
    and m.view_once = true
    and m.viewed_at is null
    and m.deleted_at is null
  for update;

  if not found or v_path is null then
    raise exception 'This attachment has already been viewed or is unavailable';
  end if;
  if not public.can_message(v_sender) then
    raise exception 'Not an authorized conversation';
  end if;

  update public.private_messages set viewed_at = now() where id = p_message_id;
  return v_path;
end;
$$;
revoke all on function public.claim_private_message_view_once(uuid) from public, anon;
grant execute on function public.claim_private_message_view_once(uuid) to authenticated;

-- Each receiving member gets one opening for a group view-once attachment.
create or replace function public.claim_group_message_view_once(p_message_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_group uuid;
  v_sender uuid;
  v_path text;
  v_rows integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;

  select m.group_id, m.sender_id, m.attachment_path
    into v_group, v_sender, v_path
  from public.message_group_messages m
  where m.id = p_message_id
    and m.view_once = true
    and m.deleted_at is null
  for update;

  if not found or v_path is null then raise exception 'This attachment is unavailable'; end if;
  if v_sender = v_user then raise exception 'The sender cannot open their own view-once attachment'; end if;
  if not public.is_message_group_member(v_group) then raise exception 'Not a member of this group'; end if;

  insert into public.message_group_message_views(message_id, user_id)
  values (p_message_id, v_user)
  on conflict (message_id, user_id) do nothing;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'This attachment has already been viewed'; end if;

  return v_path;
end;
$$;
revoke all on function public.claim_group_message_view_once(uuid) from public, anon;
grant execute on function public.claim_group_message_view_once(uuid) to authenticated;

-- One-time attachments must never receive a client-created URL before the atomic claim.
drop policy if exists "private message attachments participants read" on storage.objects;
create policy "private message attachments participants read"
on storage.objects for select to authenticated
using (
  bucket_id = 'private-message-attachments'
  and exists (
    select 1 from public.private_messages pm
    where pm.attachment_path = name
      and pm.deleted_at is null
      and (
        pm.sender_id = (select auth.uid())
        or (pm.recipient_id = (select auth.uid()) and not pm.view_once)
      )
  )
);

drop policy if exists "group members read attachments" on storage.objects;
create policy "group members read attachments"
on storage.objects for select to authenticated
using (
  bucket_id = 'group-message-attachments'
  and exists (
    select 1 from public.message_group_messages m
    where m.attachment_path = name
      and m.deleted_at is null
      and public.is_message_group_member(m.group_id)
      and (not m.view_once or m.sender_id = (select auth.uid()))
  )
);

drop policy if exists "group members delete own attachments" on storage.objects;
create policy "group members delete own attachments"
on storage.objects for delete to authenticated
using (
  bucket_id = 'group-message-attachments'
  and owner_id = (select auth.uid())::text
);
