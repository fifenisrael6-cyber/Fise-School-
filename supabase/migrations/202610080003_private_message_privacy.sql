alter table public.private_messages add column if not exists delivered_at timestamptz;
create table if not exists public.private_message_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint private_message_blocks_not_self check (blocker_id <> blocked_id)
);
create index if not exists private_message_blocks_blocked_idx on public.private_message_blocks(blocked_id);
alter table public.private_message_blocks enable row level security;
drop policy if exists "users read own message blocks" on public.private_message_blocks;
create policy "users read own message blocks" on public.private_message_blocks for select to authenticated
using ((select auth.uid()) = blocker_id or (select auth.uid()) = blocked_id);
drop policy if exists "users create own message blocks" on public.private_message_blocks;
create policy "users create own message blocks" on public.private_message_blocks for insert to authenticated
with check ((select auth.uid()) = blocker_id);
drop policy if exists "users delete own message blocks" on public.private_message_blocks;
create policy "users delete own message blocks" on public.private_message_blocks for delete to authenticated
using ((select auth.uid()) = blocker_id);