-- Per-user QCM hiding. A user may remove an assignment from their own list
-- without deleting the QCM or changing visibility for other students/teachers.
create table if not exists public.assignment_user_hides (
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (assignment_id, user_id)
);

alter table public.assignment_user_hides enable row level security;

drop policy if exists "users manage own assignment hides" on public.assignment_user_hides;
create policy "users manage own assignment hides"
  on public.assignment_user_hides
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select, insert, update, delete on public.assignment_user_hides to authenticated;
