-- Group delivery/read receipts for WhatsApp-like message status.
create table if not exists public.message_group_message_receipts (
  message_id uuid not null references public.message_group_messages(id) on delete cascade,
  group_id uuid not null references public.message_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (message_id, user_id)
);

create index if not exists message_group_receipts_group_idx
  on public.message_group_message_receipts(group_id, message_id);

alter table public.message_group_message_receipts enable row level security;
drop policy if exists "group members read message receipts" on public.message_group_message_receipts;
create policy "group members read message receipts"
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
  if (select auth.uid()) is null or not public.is_message_group_member(p_group_id) then
    raise exception 'Group membership required';
  end if;
  insert into public.message_group_message_receipts(message_id, group_id, user_id, delivered_at)
  select m.id, m.group_id, (select auth.uid()), now()
  from public.message_group_messages m
  where m.group_id = p_group_id and m.sender_id <> (select auth.uid())
  on conflict (message_id, user_id) do update
    set delivered_at = coalesce(public.message_group_message_receipts.delivered_at, excluded.delivered_at);
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
  if (select auth.uid()) is null or not public.is_message_group_member(p_group_id) then
    raise exception 'Group membership required';
  end if;
  insert into public.message_group_message_receipts(message_id, group_id, user_id, delivered_at, read_at)
  select m.id, m.group_id, (select auth.uid()), now(), now()
  from public.message_group_messages m
  where m.group_id = p_group_id and m.sender_id <> (select auth.uid())
  on conflict (message_id, user_id) do update
    set delivered_at = coalesce(public.message_group_message_receipts.delivered_at, excluded.delivered_at),
        read_at = coalesce(public.message_group_message_receipts.read_at, excluded.read_at);
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.list_group_message_receipts(p_group_id uuid)
returns table(message_id uuid, delivered_count bigint, read_count bigint, recipient_count bigint)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not public.is_message_group_member(p_group_id) then
    raise exception 'Group membership required';
  end if;
  return query
  select m.id,
    count(r.user_id) filter (where r.delivered_at is not null and r.user_id <> m.sender_id),
    count(r.user_id) filter (where r.read_at is not null and r.user_id <> m.sender_id),
    greatest((select count(*) from public.message_group_members gm where gm.group_id = p_group_id and gm.user_id <> m.sender_id), 0)
  from public.message_group_messages m
  left join public.message_group_message_receipts r on r.message_id = m.id
  where m.group_id = p_group_id
  group by m.id, m.sender_id;
end;
$$;

revoke all on function public.mark_group_messages_delivered(uuid) from public;
revoke all on function public.mark_group_messages_read(uuid) from public;
revoke all on function public.list_group_message_receipts(uuid) from public;
grant execute on function public.mark_group_messages_delivered(uuid) to authenticated;
grant execute on function public.mark_group_messages_read(uuid) to authenticated;
grant execute on function public.list_group_message_receipts(uuid) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'message_group_message_receipts'
     ) then
    execute 'alter publication supabase_realtime add table public.message_group_message_receipts';
  end if;
end $$;
