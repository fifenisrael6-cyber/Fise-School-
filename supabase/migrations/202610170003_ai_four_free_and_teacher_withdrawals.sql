-- Finalize the 4-free-AI rule, correct the Premium activation price,
-- and expose secure Orange Money / MTN Mobile Money teacher withdrawal requests.

create or replace function public.activate_student_premium(
  p_user_id uuid,
  p_payment_order_id uuid,
  p_duration_days integer default 30
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subscription_id uuid;
  v_expires_at timestamptz;
begin
  if p_duration_days <= 0 then
    raise exception 'Invalid subscription duration';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = p_user_id and role = 'student'
  ) then
    raise exception 'User is not a student';
  end if;

  if not exists (
    select 1 from public.payment_orders
    where id = p_payment_order_id
      and user_id = p_user_id
      and status = 'SUCCESS'
      and amount = 2000
      and currency = 'XAF'
  ) then
    raise exception 'Valid successful 2000 XAF payment not found';
  end if;

  select id into v_subscription_id
  from public.student_subscriptions
  where user_id = p_user_id and plan = 'premium' and status = 'active'
  order by expires_at desc nulls last
  limit 1
  for update;

  if v_subscription_id is not null then
    update public.student_subscriptions
    set expires_at = greatest(coalesce(expires_at, now()), now()) + make_interval(days => p_duration_days),
        payment_order_id = p_payment_order_id,
        updated_at = now()
    where id = v_subscription_id;
  else
    v_expires_at := now() + make_interval(days => p_duration_days);
    insert into public.student_subscriptions(user_id, plan, status, starts_at, expires_at, payment_order_id)
    values (p_user_id, 'premium', 'active', now(), v_expires_at, p_payment_order_id)
    returning id into v_subscription_id;
  end if;

  update public.profiles
  set subscription_plan = 'premium'
  where id = p_user_id and role = 'student';

  return v_subscription_id;
end;
$$;

-- The AI chat endpoint calls consume_student_free_quota('ai_question').
-- Keep all other quotas unchanged, but allow exactly four lifetime free text questions.
create or replace function public.consume_ai_free_question()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_used integer;
begin
  if v_user is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_user) then
    return jsonb_build_object('allowed', false, 'reason', 'profile_required');
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_user and p.role = 'student') then
    return jsonb_build_object('allowed', true, 'premium', true);
  end if;

  if public.is_student_premium(v_user) then
    return jsonb_build_object('allowed', true, 'premium', true);
  end if;

  insert into public.student_free_usage(user_id, feature, resource_id, used_count)
  values (v_user, 'ai_question', null, 1)
  on conflict (user_id, feature) where resource_id is null
  do update set used_count = public.student_free_usage.used_count + 1,
                updated_at = now()
  where public.student_free_usage.used_count < 4
  returning used_count into v_used;

  if v_used is null then
    select coalesce(max(used_count), 0) into v_used
    from public.student_free_usage
    where user_id = v_user and feature = 'ai_question' and resource_id is null;
    return jsonb_build_object('allowed', false, 'kind', 'question', 'limit', 4, 'used', v_used);
  end if;

  return jsonb_build_object('allowed', true, 'kind', 'question', 'limit', 4, 'used', v_used);
end;
$$;

revoke all on function public.consume_ai_free_question() from public, anon;
grant execute on function public.consume_ai_free_question() to authenticated;

create or replace function public.consume_student_free_quota(
  p_feature text,
  p_resource_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_feature = 'ai_question' then
    return public.consume_ai_free_question();
  end if;

  return public.consume_free_quota_for_user(auth.uid(), p_feature, p_resource_id);
end;
$$;

revoke all on function public.consume_student_free_quota(text,text) from public, anon;
grant execute on function public.consume_student_free_quota(text,text) to authenticated;

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
drop policy if exists "teachers_read_own_withdrawals" on public.teacher_withdrawal_requests;
create policy "teachers_read_own_withdrawals"
on public.teacher_withdrawal_requests for select to authenticated
using (teacher_id = auth.uid() or public.is_admin());

drop policy if exists "admins_update_withdrawals" on public.teacher_withdrawal_requests;
create policy "admins_update_withdrawals"
on public.teacher_withdrawal_requests for update to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "no_direct_withdrawal_inserts" on public.teacher_withdrawal_requests;
create policy "no_direct_withdrawal_inserts"
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

  return jsonb_build_object('request_id', v_request_id, 'status', 'pending',
    'amount_xaf', p_amount_xaf, 'provider', p_provider, 'phone', v_phone,
    'available_balance_xaf', v_balance);
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


-- Read-only preflight for the private chat UI; the insert trigger below remains authoritative.
create or replace function public.check_student_free_quota(p_feature text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_used integer := 0;
  v_limit integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_feature <> 'group_send' then
    return jsonb_build_object('allowed', false, 'reason', 'unknown_feature');
  end if;

  select role into v_role from public.profiles where id = v_user;
  if v_role is distinct from 'student' or public.is_student_premium(v_user) then
    return jsonb_build_object('allowed', true, 'premium', true);
  end if;

  v_limit := 2;
  select coalesce(max(used_count), 0) into v_used
  from public.student_free_usage
  where user_id = v_user and feature = p_feature and resource_id is null;

  return jsonb_build_object('allowed', v_used < v_limit, 'limit', v_limit, 'used', v_used);
end;
$$;

revoke all on function public.check_student_free_quota(text) from public, anon;
grant execute on function public.check_student_free_quota(text) to authenticated;

-- Share the same two-message lifetime quota between group and private chat sends.
create or replace function public.enforce_free_private_message_send()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_quota jsonb;
begin
  if exists (select 1 from public.private_messages m where m.id = new.id) then
    return new;
  end if;

  select p.role into v_role from public.profiles p where p.id = new.sender_id;
  if v_role = 'student' and not public.is_student_premium(new.sender_id) then
    v_quota := public.consume_free_quota_for_user(new.sender_id, 'group_send', null);
    if coalesce((v_quota ->> 'allowed')::boolean, false) is not true then
      raise exception 'FREE_MESSAGE_SEND_LIMIT: Tu as utilisé tes 2 messages gratuits. Passe à Premium pour continuer.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_free_private_message_send on public.private_messages;
create trigger enforce_free_private_message_send
before insert on public.private_messages
for each row execute function public.enforce_free_private_message_send();
