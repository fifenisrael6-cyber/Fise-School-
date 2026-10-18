-- Fise School: finalisation atomique des paiements Notch Pay.
-- Cette migration complète 202609150003 et 202609180001.

alter table public.payment_orders
  add column if not exists teacher_id uuid references auth.users(id) on delete set null,
  add column if not exists teacher_commission_xaf bigint not null default 0,
  add column if not exists platform_revenue_xaf bigint not null default 0,
  add column if not exists processed_at timestamptz;

create index if not exists payment_orders_teacher_id_idx
  on public.payment_orders(teacher_id);

create table if not exists public.teacher_wallets (
  teacher_id uuid primary key references auth.users(id) on delete cascade,
  balance_xaf bigint not null default 0 check (balance_xaf >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.teacher_wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references auth.users(id) on delete cascade,
  payment_order_id uuid not null unique references public.payment_orders(id) on delete restrict,
  amount_xaf bigint not null check (amount_xaf > 0),
  type text not null default 'commission' check (type in ('commission','adjustment')),
  created_at timestamptz not null default now()
);

alter table public.teacher_wallets enable row level security;
alter table public.teacher_wallet_transactions enable row level security;

drop policy if exists "teachers_can_read_own_wallet" on public.teacher_wallets;
create policy "teachers_can_read_own_wallet"
on public.teacher_wallets for select to authenticated
using (teacher_id = auth.uid());

drop policy if exists "teachers_can_read_own_wallet_transactions" on public.teacher_wallet_transactions;
create policy "teachers_can_read_own_wallet_transactions"
on public.teacher_wallet_transactions for select to authenticated
using (teacher_id = auth.uid());

create or replace function public.finalize_notchpay_payment(
  p_reference text,
  p_provider_transaction_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.payment_orders%rowtype;
  v_subscription_id uuid;
  v_commission bigint;
begin
  select * into v_order
  from public.payment_orders
  where reference = trim(p_reference)
  for update;

  if not found then
    raise exception 'Payment order not found';
  end if;

  if v_order.processed_at is not null then
    return jsonb_build_object(
      'success', true,
      'already_processed', true,
      'payment_order_id', v_order.id,
      'user_id', v_order.user_id
    );
  end if;

  if v_order.amount <> 1000 or upper(v_order.currency) <> 'XAF' then
    raise exception 'Invalid Fise School subscription payment';
  end if;

  update public.payment_orders
  set status = 'SUCCESS',
      provider_transaction_id = coalesce(p_provider_transaction_id, provider_transaction_id),
      paid_at = coalesce(paid_at, now()),
      processed_at = now(),
      updated_at = now()
  where id = v_order.id;

  select public.activate_student_premium(v_order.user_id, v_order.id, 30)
    into v_subscription_id;

  v_commission := greatest(coalesce(v_order.teacher_commission_xaf, 0), 0);

  if v_order.teacher_id is not null and v_commission > 0 then
    insert into public.teacher_wallets (teacher_id, balance_xaf)
    values (v_order.teacher_id, 0)
    on conflict (teacher_id) do nothing;

    begin
      insert into public.teacher_wallet_transactions (
        teacher_id, payment_order_id, amount_xaf, type
      ) values (
        v_order.teacher_id, v_order.id, v_commission, 'commission'
      );

      update public.teacher_wallets
      set balance_xaf = balance_xaf + v_commission,
          updated_at = now()
      where teacher_id = v_order.teacher_id;
    exception when unique_violation then
      null;
    end;
  end if;

  return jsonb_build_object(
    'success', true,
    'already_processed', false,
    'payment_order_id', v_order.id,
    'user_id', v_order.user_id,
    'teacher_id', v_order.teacher_id,
    'teacher_commission_xaf', v_commission,
    'subscription_id', v_subscription_id
  );
end;
$$;

revoke all on function public.finalize_notchpay_payment(text, text) from public;
grant execute on function public.finalize_notchpay_payment(text, text) to service_role;

-- Garder la commission cohérente avec le prix Premium actuel.
update public.payment_orders
set teacher_commission_xaf = 200,
    platform_revenue_xaf = greatest(amount - 200, 0)
where provider = 'notchpay'
  and amount = 1000;
