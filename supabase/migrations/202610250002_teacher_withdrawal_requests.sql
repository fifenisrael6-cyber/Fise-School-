-- Teacher withdrawals are reserved from the wallet and processed by an admin.
-- Direct inserts are blocked by RLS; the authenticated RPC is the only request path.
create table if not exists public.teacher_withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references auth.users(id) on delete cascade,
  amount_xaf bigint not null check (amount_xaf >= 1000),
  provider text not null check (provider in ('cm.orange', 'cm.mtn')),
  phone text not null,
  status text not null default 'pending' check (status in ('pending', 'paid', 'rejected')),
  transfer_reference text,
  rejection_reason text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by uuid references auth.users(id) on delete set null
);

create index if not exists teacher_withdrawal_requests_teacher_created_idx
  on public.teacher_withdrawal_requests(teacher_id, created_at desc);
create index if not exists teacher_withdrawal_requests_status_idx
  on public.teacher_withdrawal_requests(status, created_at);

alter table public.teacher_withdrawal_requests enable row level security;
drop policy if exists teachers_read_own_withdrawals on public.teacher_withdrawal_requests;
create policy teachers_read_own_withdrawals
  on public.teacher_withdrawal_requests for select to authenticated
  using (teacher_id = auth.uid() or public.is_admin());

drop policy if exists admins_update_withdrawals on public.teacher_withdrawal_requests;
create policy admins_update_withdrawals
  on public.teacher_withdrawal_requests for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists no_direct_withdrawal_inserts on public.teacher_withdrawal_requests;
create policy no_direct_withdrawal_inserts
  on public.teacher_withdrawal_requests for insert to authenticated
  with check (false);

create or replace function public.request_teacher_withdrawal(
  p_amount_xaf bigint,
  p_provider text,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_phone_digits text;
  v_phone text;
  v_request_id uuid;
  v_balance bigint;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.profiles where id = v_user and role = 'teacher') then
    raise exception 'Only teachers can request a withdrawal';
  end if;
  if p_amount_xaf is null or p_amount_xaf < 1000 then
    raise exception 'Minimum withdrawal is 1000 XAF';
  end if;
  if p_provider not in ('cm.orange', 'cm.mtn') then
    raise exception 'Unsupported withdrawal provider';
  end if;

  v_phone_digits := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if left(v_phone_digits, 3) = '237' then
    v_phone_digits := substr(v_phone_digits, 4);
  end if;
  if v_phone_digits !~ '^[2368][0-9]{8}$' then
    raise exception 'Enter a valid Cameroon mobile number';
  end if;
  v_phone := '+237' || v_phone_digits;

  update public.teacher_wallets
  set balance_xaf = balance_xaf - p_amount_xaf, updated_at = now()
  where teacher_id = v_user and balance_xaf >= p_amount_xaf
  returning balance_xaf into v_balance;
  if v_balance is null then
    raise exception 'Insufficient available balance';
  end if;

  insert into public.teacher_withdrawal_requests(teacher_id, amount_xaf, provider, phone)
  values (v_user, p_amount_xaf, p_provider, v_phone)
  returning id into v_request_id;

  return jsonb_build_object(
    'request_id', v_request_id,
    'status', 'pending',
    'amount_xaf', p_amount_xaf,
    'provider', p_provider,
    'phone', v_phone,
    'available_balance_xaf', v_balance
  );
end;
$$;

revoke all on function public.request_teacher_withdrawal(bigint, text, text) from public, anon;
grant execute on function public.request_teacher_withdrawal(bigint, text, text) to authenticated;

create or replace function public.resolve_teacher_withdrawal(
  p_request_id uuid,
  p_status text,
  p_transfer_reference text default null,
  p_rejection_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.teacher_withdrawal_requests%rowtype;
begin
  if not public.is_admin() then raise exception 'Administrator access required'; end if;
  if p_status not in ('paid', 'rejected') then raise exception 'Invalid withdrawal status'; end if;

  select * into v_request
  from public.teacher_withdrawal_requests
  where id = p_request_id
  for update;
  if not found then raise exception 'Withdrawal request not found'; end if;
  if v_request.status <> 'pending' then
    return jsonb_build_object('success', true, 'already_processed', true, 'status', v_request.status);
  end if;

  if p_status = 'rejected' then
    update public.teacher_wallets
    set balance_xaf = balance_xaf + v_request.amount_xaf, updated_at = now()
    where teacher_id = v_request.teacher_id;
  end if;

  update public.teacher_withdrawal_requests
  set status = p_status,
      transfer_reference = nullif(trim(coalesce(p_transfer_reference, '')), ''),
      rejection_reason = nullif(trim(coalesce(p_rejection_reason, '')), ''),
      processed_at = now(),
      processed_by = auth.uid()
  where id = v_request.id;

  return jsonb_build_object('success', true, 'already_processed', false, 'status', p_status);
end;
$$;

revoke all on function public.resolve_teacher_withdrawal(uuid, text, text, text) from public, anon;
grant execute on function public.resolve_teacher_withdrawal(uuid, text, text, text) to authenticated;
