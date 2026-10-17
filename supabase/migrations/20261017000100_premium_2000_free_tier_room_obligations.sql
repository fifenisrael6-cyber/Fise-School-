-- Cyber/Fise School: Premium à 2 000 XAF, deux commissions enseignants,
-- quotas gratuits serveur et suivi mensuel des obligations par salle.
-- Migration additive : conserve les données et les fonctions hors périmètre.

alter table public.profiles
  add column if not exists teacher_vocation text;

alter table public.profiles
  drop constraint if exists profiles_teacher_vocation_check;
alter table public.profiles
  add constraint profiles_teacher_vocation_check
  check (teacher_vocation is null or teacher_vocation in ('scientific', 'literary'));

-- La vocation est issue des métadonnées d'inscription, jamais d'une valeur libre
-- envoyée pendant le paiement.
create or replace function public.sync_teacher_vocation_from_auth_metadata()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vocation text := lower(trim(coalesce(new.raw_user_meta_data ->> 'teacher_vocation', '')));
begin
  if v_vocation in ('scientific', 'literary') then
    update public.profiles
    set teacher_vocation = v_vocation
    where id = new.id and role = 'teacher';
  end if;
  return new;
end;
$$;

drop trigger if exists sync_teacher_vocation_from_auth_metadata on auth.users;
create trigger sync_teacher_vocation_from_auth_metadata
after insert on auth.users
for each row execute function public.sync_teacher_vocation_from_auth_metadata();

-- Répartition Premium par vocation. teacher_id et les anciennes colonnes sont
-- conservés pour compatibilité avec les paiements historiques.
alter table public.payment_orders
  add column if not exists scientific_teacher_id uuid references auth.users(id) on delete set null,
  add column if not exists literary_teacher_id uuid references auth.users(id) on delete set null,
  add column if not exists scientific_commission_xaf bigint not null default 0,
  add column if not exists literary_commission_xaf bigint not null default 0,
  add column if not exists related_class_id uuid references public.school_classes(id) on delete set null;

-- Les transactions de portefeuille doivent accepter deux enseignants distincts
-- pour le même paiement, sans permettre de créditer deux fois un même enseignant.
do $$
declare
  c record;
begin
  for c in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace n on n.oid = rel.relnamespace
    where n.nspname = 'public'
      and rel.relname = 'teacher_wallet_transactions'
      and con.contype = 'u'
      and pg_get_constraintdef(con.oid) ilike 'UNIQUE (payment_order_id)'
  loop
    execute format('alter table public.teacher_wallet_transactions drop constraint %I', c.conname);
  end loop;
end $$;

create unique index if not exists teacher_wallet_transactions_payment_teacher_uidx
  on public.teacher_wallet_transactions(payment_order_id, teacher_id);

alter table public.teacher_wallet_transactions
  add column if not exists class_id uuid references public.school_classes(id) on delete set null,
  add column if not exists teacher_vocation text;

-- Usage gratuit : les quotas sont stockés côté serveur, non dans le téléphone.
create table if not exists public.student_free_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  feature text not null check (feature in
    ('ai_question','group_send','group_receive','lesson','qcm','annal')),
  resource_id text,
  used_count integer not null default 1 check (used_count >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists student_free_usage_counter_uidx
  on public.student_free_usage(user_id, feature) where resource_id is null;
create unique index if not exists student_free_usage_resource_uidx
  on public.student_free_usage(user_id, feature, resource_id) where resource_id is not null;
create index if not exists student_free_usage_user_feature_idx
  on public.student_free_usage(user_id, feature);

alter table public.student_free_usage enable row level security;
drop policy if exists "students read own free usage" on public.student_free_usage;
create policy "students read own free usage"
on public.student_free_usage for select to authenticated
using (user_id = auth.uid());

create or replace function public.consume_free_quota_for_user(
  p_user_id uuid,
  p_feature text,
  p_resource_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit integer;
  v_count integer;
  v_allowed boolean := false;
begin
  if p_user_id is null then
    return jsonb_build_object('allowed', false, 'reason', 'authentication_required');
  end if;

  if not exists (select 1 from public.profiles p where p.id = p_user_id and p.role = 'student') then
    return jsonb_build_object('allowed', false, 'reason', 'student_only');
  end if;

  if public.is_student_premium(p_user_id) then
    return jsonb_build_object('allowed', true, 'premium', true);
  end if;

  v_limit := case p_feature
    when 'ai_question' then 3
    when 'group_send' then 2
    when 'group_receive' then 2
    when 'lesson' then 2
    when 'qcm' then 2
    when 'annal' then 2
    else null
  end;

  if v_limit is null then
    return jsonb_build_object('allowed', false, 'reason', 'unknown_feature');
  end if;

  if p_feature in ('lesson','qcm','annal') then
    if nullif(trim(coalesce(p_resource_id, '')), '') is null then
      return jsonb_build_object('allowed', false, 'reason', 'resource_required');
    end if;

    if exists (
      select 1 from public.student_free_usage u
      where u.user_id = p_user_id
        and u.feature = p_feature
        and u.resource_id = p_resource_id
    ) then
      return jsonb_build_object('allowed', true, 'already_counted', true);
    end if;

    select count(*)::integer into v_count
    from public.student_free_usage u
    where u.user_id = p_user_id and u.feature = p_feature and u.resource_id is not null;

    if v_count >= v_limit then
      return jsonb_build_object('allowed', false, 'limit', v_limit, 'used', v_count);
    end if;

    insert into public.student_free_usage(user_id, feature, resource_id)
    values (p_user_id, p_feature, p_resource_id)
    on conflict (user_id, feature, resource_id) where resource_id is not null do nothing;

    return jsonb_build_object('allowed', true, 'limit', v_limit, 'used', least(v_count + 1, v_limit));
  end if;

  insert into public.student_free_usage(user_id, feature, resource_id, used_count)
  values (p_user_id, p_feature, null, 1)
  on conflict (user_id, feature) where resource_id is null
  do update set used_count = public.student_free_usage.used_count + 1,
                updated_at = now()
  where public.student_free_usage.used_count < v_limit
  returning used_count into v_count;

  if v_count is not null then
    v_allowed := true;
  else
    select coalesce(max(used_count), 0) into v_count
    from public.student_free_usage
    where user_id = p_user_id and feature = p_feature and resource_id is null;
  end if;

  return jsonb_build_object('allowed', v_allowed, 'limit', v_limit, 'used', coalesce(v_count, 0));
end;
$$;

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
  return public.consume_free_quota_for_user(auth.uid(), p_feature, p_resource_id);
end;
$$;

revoke all on function public.consume_free_quota_for_user(uuid,text,text) from public, anon, authenticated;
revoke all on function public.consume_student_free_quota(text,text) from public, anon;
grant execute on function public.consume_student_free_quota(text,text) to authenticated;

-- Quotas de messages de groupe : un élève gratuit peut envoyer deux messages,
-- et ne reçoit que les deux premiers messages ciblés pour lui.
alter table public.message_group_messages
  add column if not exists free_limited boolean not null default false,
  add column if not exists free_visible_to uuid[] not null default '{}'::uuid[];

create or replace function public.apply_free_group_message_limits()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_allowed jsonb;
  v_member record;
  v_visible uuid[] := '{}'::uuid[];
begin
  select p.role into v_role from public.profiles p where p.id = new.sender_id;

  if v_role = 'student' and not public.is_student_premium(new.sender_id) then
    v_allowed := public.consume_free_quota_for_user(new.sender_id, 'group_send', null);
    if coalesce((v_allowed ->> 'allowed')::boolean, false) is not true then
      raise exception 'FREE_GROUP_SEND_LIMIT: les élèves gratuits peuvent envoyer deux messages de groupe.';
    end if;
  end if;

  new.free_limited := true;
  for v_member in
    select gm.user_id, p.role
    from public.message_group_members gm
    join public.profiles p on p.id = gm.user_id
    where gm.group_id = new.group_id
      and gm.user_id <> new.sender_id
      and p.role = 'student'
      and not public.is_student_premium(gm.user_id)
  loop
    v_allowed := public.consume_free_quota_for_user(v_member.user_id, 'group_receive', null);
    if coalesce((v_allowed ->> 'allowed')::boolean, false) is true then
      v_visible := array_append(v_visible, v_member.user_id);
    end if;
  end loop;
  new.free_visible_to := v_visible;
  return new;
end;
$$;

drop trigger if exists apply_free_group_message_limits on public.message_group_messages;
create trigger apply_free_group_message_limits
before insert on public.message_group_messages
for each row execute function public.apply_free_group_message_limits();

-- Maintient les droits de confidentialité existants et ajoute le quota gratuit.
drop policy if exists "members read group messages" on public.message_group_messages;
create policy "members read group messages"
on public.message_group_messages for select to authenticated
using (
  public.is_message_group_member(group_id)
  and not ((select auth.uid()) = any(coalesce(hidden_for, '{}'::uuid[])))
  and (
    not free_limited
    or sender_id = (select auth.uid())
    or public.is_student_premium((select auth.uid()))
    or (select auth.uid()) = any(coalesce(free_visible_to, '{}'::uuid[]))
    or public.is_admin()
  )
);

-- Obligations suivies indépendamment pour chaque enseignant, salle et mois.
create table if not exists public.teacher_room_monthly_obligations (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references auth.users(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  month_start date not null,
  qcm_count integer not null default 0 check (qcm_count >= 0),
  pdf_count integer not null default 0 check (pdf_count >= 0),
  photo_count integer not null default 0 check (photo_count >= 0),
  required_qcm integer not null default 20 check (required_qcm = 20),
  required_pdf integer not null default 5 check (required_pdf = 5),
  status text not null default 'pending' check (status in ('pending','met','missed','reviewed')),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (teacher_id, class_id, month_start)
);
alter table public.teacher_room_monthly_obligations enable row level security;
drop policy if exists "teachers and admins read room obligations" on public.teacher_room_monthly_obligations;
create policy "teachers and admins read room obligations"
on public.teacher_room_monthly_obligations for select to authenticated
using (teacher_id = auth.uid() or public.is_admin());
drop policy if exists "admins manage room obligations" on public.teacher_room_monthly_obligations;
create policy "admins manage room obligations"
on public.teacher_room_monthly_obligations for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create or replace function public.record_teacher_room_publication(
  p_class_id uuid,
  p_kind text,
  p_resource_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher uuid := auth.uid();
  v_month date := date_trunc('month', now())::date;
begin
  if v_teacher is null or not public.check_profile_role(v_teacher, 'teacher') then
    raise exception 'Only teachers can record a publication';
  end if;
  if p_kind not in ('qcm','pdf','photo') then
    raise exception 'Unsupported publication type';
  end if;
  if nullif(trim(coalesce(p_resource_id,'')), '') is null then
    raise exception 'Resource id required';
  end if;
  if not exists (
    select 1 from public.class_teachers ct
    where ct.teacher_id = v_teacher and ct.class_id = p_class_id and ct.is_active
  ) then
    raise exception 'Teacher is not assigned to this classroom';
  end if;

  insert into public.teacher_room_monthly_obligations(teacher_id,class_id,month_start)
  values (v_teacher,p_class_id,v_month)
  on conflict (teacher_id,class_id,month_start) do nothing;

  -- A resource cannot be counted twice for the same teacher/salle/month.
  if exists (
    select 1 from public.teacher_room_publication_events e
    where e.teacher_id = v_teacher and e.class_id = p_class_id
      and e.month_start = v_month and e.kind = p_kind and e.resource_id = p_resource_id
  ) then
    return jsonb_build_object('recorded',false,'reason','already_counted');
  end if;

  insert into public.teacher_room_publication_events(teacher_id,class_id,month_start,kind,resource_id)
  values (v_teacher,p_class_id,v_month,p_kind,p_resource_id);

  update public.teacher_room_monthly_obligations
  set qcm_count = qcm_count + case when p_kind = 'qcm' then 1 else 0 end,
      pdf_count = pdf_count + case when p_kind = 'pdf' then 1 else 0 end,
      photo_count = photo_count + case when p_kind = 'photo' then 1 else 0 end,
      status = case
        when qcm_count + case when p_kind = 'qcm' then 1 else 0 end >= 20
         and pdf_count + case when p_kind = 'pdf' then 1 else 0 end >= 5
        then 'met' else 'pending' end,
      updated_at = now()
  where teacher_id = v_teacher and class_id = p_class_id and month_start = v_month;

  return jsonb_build_object('recorded',true);
end;
$$;

create table if not exists public.teacher_room_publication_events (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references auth.users(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  month_start date not null,
  kind text not null check (kind in ('qcm','pdf','photo')),
  resource_id text not null,
  created_at timestamptz not null default now(),
  unique (teacher_id,class_id,month_start,kind,resource_id)
);
alter table public.teacher_room_publication_events enable row level security;
drop policy if exists "teachers and admins read publication events" on public.teacher_room_publication_events;
create policy "teachers and admins read publication events"
on public.teacher_room_publication_events for select to authenticated
using (teacher_id = auth.uid() or public.is_admin());

revoke all on function public.record_teacher_room_publication(uuid,text,text) from public, anon;
grant execute on function public.record_teacher_room_publication(uuid,text,text) to authenticated;

-- La fonction finale de paiement distribue 200 XAF à chaque enseignant affecté
-- (scientifique et littéraire), et le solde à l'administrateur. Les paiements
-- historiques de 1 000 XAF restent finalisables avec leurs anciennes règles.
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
  v_teacher record;
  v_amount bigint;
  v_total_commission bigint := 0;
  v_platform bigint;
  v_inserted integer;
begin
  select * into v_order
  from public.payment_orders
  where reference = trim(p_reference)
  for update;

  if not found then raise exception 'Payment order not found'; end if;

  if v_order.processed_at is not null then
    return jsonb_build_object(
      'success', true, 'already_processed', true,
      'payment_order_id', v_order.id, 'user_id', v_order.user_id
    );
  end if;

  if v_order.amount = 2000 and upper(v_order.currency) = 'XAF' then
    v_total_commission :=
      case when v_order.scientific_teacher_id is not null then 200 else 0 end
      + case when v_order.literary_teacher_id is not null
               and v_order.literary_teacher_id is distinct from v_order.scientific_teacher_id
             then 200
             when v_order.literary_teacher_id is not null
               and v_order.scientific_teacher_id is null
             then 200
             else 0 end;
    v_platform := greatest(2000 - v_total_commission, 0);
  elsif v_order.amount = 1000 and upper(v_order.currency) = 'XAF' then
    -- Compatibility for old unpaid orders only.
    v_total_commission := greatest(coalesce(v_order.teacher_commission_xaf, 0), 0);
    v_platform := greatest(v_order.amount - v_total_commission, 0);
  else
    raise exception 'Invalid Fise School subscription payment amount';
  end if;

  update public.payment_orders
  set status = 'SUCCESS',
      provider_transaction_id = coalesce(p_provider_transaction_id, provider_transaction_id),
      paid_at = coalesce(paid_at, now()),
      processed_at = now(),
      teacher_commission_xaf = v_total_commission,
      platform_revenue_xaf = v_platform,
      updated_at = now()
  where id = v_order.id;

  select public.activate_student_premium(v_order.user_id, v_order.id, 30)
  into v_subscription_id;

  if v_order.amount = 2000 then
    for v_teacher in
      select t.teacher_id, sum(t.commission)::bigint as commission, max(t.vocation) as vocation
      from (
        select v_order.scientific_teacher_id as teacher_id, 200::bigint as commission, 'scientific'::text as vocation
        where v_order.scientific_teacher_id is not null
        union all
        select v_order.literary_teacher_id, 200::bigint, 'literary'::text
        where v_order.literary_teacher_id is not null
      ) t
      group by t.teacher_id
    loop
      insert into public.teacher_wallets(teacher_id,balance_xaf)
      values(v_teacher.teacher_id,0)
      on conflict (teacher_id) do nothing;

      insert into public.teacher_wallet_transactions(
        teacher_id,payment_order_id,amount_xaf,type,class_id,teacher_vocation
      )
      values(
        v_teacher.teacher_id,v_order.id,v_teacher.commission,'commission',
        v_order.related_class_id,v_teacher.vocation
      )
      on conflict (payment_order_id,teacher_id) do nothing;

      get diagnostics v_inserted = row_count;
      if v_inserted > 0 then
        update public.teacher_wallets
        set balance_xaf = balance_xaf + v_teacher.commission, updated_at = now()
        where teacher_id = v_teacher.teacher_id;
      end if;
    end loop;
  elsif v_order.teacher_id is not null and v_total_commission > 0 then
    insert into public.teacher_wallets(teacher_id,balance_xaf)
    values(v_order.teacher_id,0)
    on conflict (teacher_id) do nothing;

    insert into public.teacher_wallet_transactions(teacher_id,payment_order_id,amount_xaf,type)
    values(v_order.teacher_id,v_order.id,v_total_commission,'commission')
    on conflict (payment_order_id,teacher_id) do nothing;
    get diagnostics v_inserted = row_count;
    if v_inserted > 0 then
      update public.teacher_wallets
      set balance_xaf = balance_xaf + v_total_commission, updated_at = now()
      where teacher_id = v_order.teacher_id;
    end if;
  end if;

  return jsonb_build_object(
    'success',true,'already_processed',false,
    'payment_order_id',v_order.id,'user_id',v_order.user_id,
    'scientific_teacher_id',v_order.scientific_teacher_id,
    'literary_teacher_id',v_order.literary_teacher_id,
    'teacher_commission_xaf',v_total_commission,
    'platform_revenue_xaf',v_platform,
    'subscription_id',v_subscription_id
  );
end;
$$;

revoke all on function public.finalize_notchpay_payment(text,text) from public, anon, authenticated;
grant execute on function public.finalize_notchpay_payment(text,text) to service_role;

-- Recalculer les répartitions des anciennes commandes encore en attente.
update public.payment_orders
set teacher_commission_xaf = case when teacher_id is null then 0 else 200 end,
    platform_revenue_xaf = greatest(amount - case when teacher_id is null then 0 else 200 end,0)
where provider = 'notchpay' and status in ('PENDING','NOTPAY') and amount = 1000;
