-- Additive foundation for group entitlement, teacher compliance and immutable wallet ledger.
-- Existing message groups and payment tables are preserved.
alter table public.message_groups
  add column if not exists group_category text,
  add column if not exists teacher_id uuid references public.profiles(id) on delete set null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'message_groups_group_category_check') then
    alter table public.message_groups add constraint message_groups_group_category_check
      check (group_category is null or group_category in ('literary','scientific','other'));
  end if;
end $$;

create table if not exists public.student_group_memberships (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  group_id uuid not null references public.message_groups(id) on delete restrict,
  category text not null check (category in ('literary','scientific','other')),
  teacher_id uuid references public.profiles(id) on delete set null,
  access_type text not null default 'standard' check (access_type in ('standard','extra')),
  status text not null default 'active' check (status in ('active','replaced','expired','suspended')),
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  created_at timestamptz not null default now(),
  replaced_at timestamptz,
  constraint student_group_membership_dates check (effective_until is null or effective_until > effective_from)
);
create unique index if not exists student_one_active_standard_group_per_category
  on public.student_group_memberships(student_id, category)
  where status = 'active' and access_type = 'standard' and category in ('literary','scientific');
create unique index if not exists student_one_active_group_membership
  on public.student_group_memberships(student_id, group_id)
  where status = 'active';
create index if not exists student_group_memberships_student_status_idx
  on public.student_group_memberships(student_id, status, category);

create table if not exists public.extra_group_subscriptions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  group_id uuid not null references public.message_groups(id) on delete restrict,
  teacher_id uuid references public.profiles(id) on delete set null,
  payment_reference text unique,
  amount_xaf integer not null default 250 check (amount_xaf = 250),
  status text not null default 'pending' check (status in ('pending','active','expired','cancelled')),
  starts_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  constraint extra_group_subscription_dates check (expires_at is null or starts_at is null or expires_at > starts_at)
);
create index if not exists extra_group_subscriptions_student_active_idx
  on public.extra_group_subscriptions(student_id, status, expires_at);

create table if not exists public.wallet_ledger (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.profiles(id) on delete restrict,
  owner_type text not null check (owner_type in ('teacher','admin')),
  entry_type text not null check (entry_type in ('premium_commission','extra_group_commission','withdrawal_request','withdrawal_paid','withdrawal_rejected','adjustment')),
  amount_xaf bigint not null check (amount_xaf <> 0),
  currency text not null default 'XAF' check (currency = 'XAF'),
  payment_reference text,
  group_membership_id uuid references public.student_group_memberships(id) on delete set null,
  related_entry_id uuid references public.wallet_ledger(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','available','held','paid','rejected','reversed')),
  available_at timestamptz,
  description text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create unique index if not exists wallet_ledger_unique_payment_owner_type
  on public.wallet_ledger(payment_reference, owner_id, entry_type)
  where payment_reference is not null and entry_type in ('premium_commission','extra_group_commission');
create index if not exists wallet_ledger_owner_status_idx
  on public.wallet_ledger(owner_type, owner_id, status, created_at desc);

create table if not exists public.teacher_compliance_notices (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  notice_type text not null,
  title text not null,
  body text not null,
  required_action text not null default '',
  status text not null default 'open' check (status in ('open','acknowledged','resolved','dismissed')),
  acknowledged_at timestamptz,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);
create index if not exists teacher_compliance_notices_open_idx
  on public.teacher_compliance_notices(teacher_id, status, created_at desc);

create table if not exists public.teacher_compliance_status (
  teacher_id uuid primary key references public.profiles(id) on delete cascade,
  photos_published integer not null default 0 check (photos_published >= 0),
  pdfs_published integer not null default 0 check (pdfs_published >= 0),
  annals_published integer not null default 0 check (annals_published >= 0),
  evaluations_complete boolean not null default false,
  compliant boolean not null default false,
  checked_at timestamptz not null default now(),
  blockers jsonb not null default '[]'::jsonb
);

alter table public.student_group_memberships enable row level security;
alter table public.extra_group_subscriptions enable row level security;
alter table public.wallet_ledger enable row level security;
alter table public.teacher_compliance_notices enable row level security;
alter table public.teacher_compliance_status enable row level security;

drop policy if exists student_group_memberships_read_self_or_teacher on public.student_group_memberships;
create policy student_group_memberships_read_self_or_teacher on public.student_group_memberships
  for select to authenticated using (student_id = (select auth.uid()) or teacher_id = (select auth.uid()));
drop policy if exists extra_group_subscriptions_read_self on public.extra_group_subscriptions;
create policy extra_group_subscriptions_read_self on public.extra_group_subscriptions
  for select to authenticated using (student_id = (select auth.uid()));
drop policy if exists wallet_ledger_read_owner on public.wallet_ledger;
create policy wallet_ledger_read_owner on public.wallet_ledger
  for select to authenticated using (owner_id = (select auth.uid()));
drop policy if exists teacher_compliance_notices_read_self on public.teacher_compliance_notices;
create policy teacher_compliance_notices_read_self on public.teacher_compliance_notices
  for select to authenticated using (teacher_id = (select auth.uid()));
drop policy if exists teacher_compliance_status_read_self on public.teacher_compliance_status;
create policy teacher_compliance_status_read_self on public.teacher_compliance_status
  for select to authenticated using (teacher_id = (select auth.uid()));

revoke insert, update, delete on public.student_group_memberships from anon, authenticated;
revoke insert, update, delete on public.extra_group_subscriptions from anon, authenticated;
revoke insert, update, delete on public.wallet_ledger from anon, authenticated;
revoke insert, update, delete on public.teacher_compliance_status from anon, authenticated;
