-- WhatsApp-style delivery/read receipts for group messages.
create table if not exists public.message_group_message_receipts (
  message_id uuid not null references public.message_group_messages(id) on delete cascade,
  group_id uuid not null references public.message_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (message_id, user_id)
);

create index if not exists message_group_receipts_group_user_idx
  on public.message_group_message_receipts (group_id, user_id);

alter table public.message_group_message_receipts enable row level security;
-- Enable realtime receipt refresh when the project's realtime publication exists.
do $
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'message_group_message_receipts'
     ) then
    alter publication supabase_realtime add table public.message_group_message_receipts;
  end if;
end;
$;

drop policy if exists "members read group message receipts" on public.message_group_message_receipts;
create policy "members read group message receipts"
on public.message_group_message_receipts for select to authenticated
using (public.is_message_group_member(group_id));

create or replace function public.mark_group_messages_delivered(p_group_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare n integer;
begin
  if not public.is_message_group_member(p_group_id) then
    raise exception 'Not a member of this group';
  end if;

  insert into public.message_group_message_receipts
    (message_id, group_id, user_id, delivered_at)
  select m.id, m.group_id, (select auth.uid()), now()
  from public.message_group_messages m
  where m.group_id = p_group_id
    and m.sender_id <> (select auth.uid())
  on conflict (message_id, user_id) do update
    set delivered_at = coalesce(public.message_group_message_receipts.delivered_at, excluded.delivered_at)
    where public.message_group_message_receipts.delivered_at is null;

  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.mark_group_messages_read(p_group_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare n integer;
begin
  if not public.is_message_group_member(p_group_id) then
    raise exception 'Not a member of this group';
  end if;

  insert into public.message_group_message_receipts
    (message_id, group_id, user_id, delivered_at, read_at)
  select m.id, m.group_id, (select auth.uid()), now(), now()
  from public.message_group_messages m
  where m.group_id = p_group_id
    and m.sender_id <> (select auth.uid())
  on conflict (message_id, user_id) do update
    set delivered_at = coalesce(public.message_group_message_receipts.delivered_at, excluded.delivered_at),
        read_at = coalesce(public.message_group_message_receipts.read_at, excluded.read_at)
    where public.message_group_message_receipts.delivered_at is null
       or public.message_group_message_receipts.read_at is null;

  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.mark_group_messages_delivered(uuid) from public;
revoke all on function public.mark_group_messages_read(uuid) from public;
grant execute on function public.mark_group_messages_delivered(uuid) to authenticated;
grant execute on function public.mark_group_messages_read(uuid) to authenticated;

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
  delivered_count bigint,
  read_count bigint,
  recipient_count bigint
)
language plpgsql
stable
security definer
set search_path = public
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
    m.body,
    m.attachment_path,
    m.attachment_name,
    m.attachment_type,
    m.created_at,
    (select count(*) from public.message_group_message_receipts r
      where r.message_id = m.id and r.delivered_at is not null and r.user_id <> m.sender_id),
    (select count(*) from public.message_group_message_receipts r
      where r.message_id = m.id and r.read_at is not null and r.user_id <> m.sender_id),
    (select count(*) from public.message_group_members gm
      where gm.group_id = p_group_id and gm.user_id <> m.sender_id)
  from public.message_group_messages m
  left join public.profiles p on p.id = m.sender_id
  where m.group_id = p_group_id
  order by m.created_at asc;
end;
$$;

revoke all on function public.list_message_group_messages(uuid) from public;
grant execute on function public.list_message_group_messages(uuid) to authenticated;
