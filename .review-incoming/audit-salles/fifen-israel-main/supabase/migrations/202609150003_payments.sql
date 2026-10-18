create table if not exists public.payment_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reference text not null unique,
  amount bigint not null check (amount > 0),
  currency text not null default 'XAF',
  status text not null default 'NOTPAY',
  description text,
  provider text,
  provider_transaction_id text,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint payment_orders_status_valid
    check (
      status in (
        'NOTPAY',
        'PENDING',
        'SUCCESS',
        'FAILED',
        'CLOSED',
        'REFUND'
      )
    )
);

create index if not exists payment_orders_user_id_idx
  on public.payment_orders(user_id);

create index if not exists payment_orders_status_idx
  on public.payment_orders(status);

alter table public.payment_orders enable row level security;

drop policy if exists "users_can_read_own_payment_orders"
on public.payment_orders;

create policy "users_can_read_own_payment_orders"
on public.payment_orders
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "users_can_create_own_payment_orders"
on public.payment_orders;

create policy "users_can_create_own_payment_orders"
on public.payment_orders
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "users_cannot_update_payment_orders"
on public.payment_orders;

create policy "users_cannot_update_payment_orders"
on public.payment_orders
for update
to authenticated
using (false)
with check (false);

drop policy if exists "users_cannot_delete_payment_orders"
on public.payment_orders;

create policy "users_cannot_delete_payment_orders"
on public.payment_orders
for delete
to authenticated
using (false);