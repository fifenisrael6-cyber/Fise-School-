-- ============================================================================
-- Fise School / Cyber — Premium 2 000 FCFA / 30 jours, quotas gratuits 24 h,
-- durcissement du paiement Notch Pay.
--
-- ATTENTION : ce fichier est dans supabase/migrations/ et le workflow
-- .github/workflows/supabase-migrations.yml l'applique automatiquement
-- à chaque push sur main. Relire avant de pousser.
--
-- Hypothèses à confirmer (voir rapport) :
--  * « enseignant scientifique / littéraire » : aucune classification n'existait
--    dans le dépôt. On ajoute profiles.teaching_stream (renseigné par l'admin).
--    Sans enseignant renseigné, la part reste à la plateforme (tracée).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Constantes tarifaires
-- ---------------------------------------------------------------------------
create or replace function public.premium_price_xaf() returns integer
language sql immutable as $$ select 2000 $$;

create or replace function public.premium_duration_days() returns integer
language sql immutable as $$ select 30 $$;

-- ---------------------------------------------------------------------------
-- 2. Classification des enseignants (scientifique / littéraire)
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists teaching_stream text;

alter table public.profiles
  drop constraint if exists profiles_teaching_stream_check;
alter table public.profiles
  add constraint profiles_teaching_stream_check
  check (teaching_stream is null or teaching_stream in ('scientific', 'literary'));

-- ---------------------------------------------------------------------------
-- 3. payment_orders : répartition tracée + suppression de l'écriture client
-- ---------------------------------------------------------------------------
alter table public.payment_orders
  add column if not exists science_teacher_id uuid references auth.users(id) on delete set null,
  add column if not exists literary_teacher_id uuid references auth.users(id) on delete set null,
  add column if not exists science_commission_xaf bigint not null default 0,
  add column if not exists literary_commission_xaf bigint not null default 0,
  add column if not exists failure_reason text;

alter table public.payment_orders
  drop constraint if exists payment_orders_status_valid;
alter table public.payment_orders
  add constraint payment_orders_status_valid
  check (status in ('NOTPAY','PENDING','SUCCESS','FAILED','CLOSED','CANCELED','REFUND'));

-- Un élève ne doit plus pouvoir fabriquer lui-même une commande (montant,
-- statut, commissions...). Seules les fonctions Edge (service_role) écrivent.
drop policy if exists "users_can_create_own_payment_orders" on public.payment_orders;
revoke insert, update, delete on public.payment_orders from authenticated, anon;

-- Journal des notifications reçues (audit + déduplication)
create table if not exists public.payment_events (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,          -- hash de (type, référence, statut, id transaction)
  reference text,
  event_type text,
  source text not null check (source in ('webhook', 'callback', 'client_sync')),
  signature_valid boolean,
  provider_status text,
  amount bigint,
  currency text,
  outcome text,                             -- processed / duplicate / rejected / pending ...
  received_at timestamptz not null default now()
);
alter table public.payment_events enable row level security;
revoke all on public.payment_events from anon, authenticated;
-- aucune policy : accessible uniquement via service_role

-- ---------------------------------------------------------------------------
-- 4. Portefeuille enseignant : une commission par (commande, enseignant)
-- ---------------------------------------------------------------------------
do $$
declare v_name text;
begin
  select conname into v_name
  from pg_constraint
  where conrelid = 'public.teacher_wallet_transactions'::regclass
    and contype = 'u'
    and pg_get_constraintdef(oid) = 'UNIQUE (payment_order_id)';
  if v_name is not null then
    execute format('alter table public.teacher_wallet_transactions drop constraint %I', v_name);
  end if;
end $$;

alter table public.teacher_wallet_transactions
  add column if not exists stream text;
create unique index if not exists teacher_wallet_tx_order_teacher_uidx
  on public.teacher_wallet_transactions (payment_order_id, teacher_id);

-- ---------------------------------------------------------------------------
-- 5. Résolution des enseignants concernés (règle d'affectation : classe active)
-- ---------------------------------------------------------------------------
create or replace function public.resolve_premium_teachers(p_student_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_science uuid;
  v_literary uuid;
begin
  select ct.teacher_id into v_science
  from public.class_students cs
  join public.class_teachers ct on ct.class_id = cs.class_id and ct.is_active
  join public.profiles t on t.id = ct.teacher_id and t.role = 'teacher'
  where cs.student_id = p_student_id and cs.is_active
    and t.teaching_stream = 'scientific'
  order by ct.assigned_at desc
  limit 1;

  select ct.teacher_id into v_literary
  from public.class_students cs
  join public.class_teachers ct on ct.class_id = cs.class_id and ct.is_active
  join public.profiles t on t.id = ct.teacher_id and t.role = 'teacher'
  where cs.student_id = p_student_id and cs.is_active
    and t.teaching_stream = 'literary'
  order by ct.assigned_at desc
  limit 1;

  return jsonb_build_object('science_teacher_id', v_science, 'literary_teacher_id', v_literary);
end;
$$;
revoke all on function public.resolve_premium_teachers(uuid) from public, anon, authenticated;
grant execute on function public.resolve_premium_teachers(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 6. Finalisation idempotente (prix, devise et montant réellement payé vérifiés)
-- ---------------------------------------------------------------------------
drop function if exists public.finalize_notchpay_payment(text, text);

create or replace function public.finalize_notchpay_payment(
  p_reference text,
  p_provider_transaction_id text default null,
  p_paid_amount bigint default null,
  p_paid_currency text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.payment_orders%rowtype;
  v_subscription_id uuid;
  v_price integer := public.premium_price_xaf();
begin
  select * into v_order
  from public.payment_orders
  where reference = trim(p_reference)
  for update;

  if not found then
    raise exception 'Payment order not found';
  end if;

  if v_order.processed_at is not null then
    return jsonb_build_object('success', true, 'already_processed', true,
      'payment_order_id', v_order.id, 'user_id', v_order.user_id);
  end if;

  -- Montant/devise de la commande ET montant effectivement encaissé
  if v_order.amount <> v_price or upper(v_order.currency) <> 'XAF' then
    raise exception 'Invalid Premium order amount/currency';
  end if;
  if p_paid_amount is null or p_paid_amount <> v_price
     or upper(coalesce(p_paid_currency, '')) <> 'XAF' then
    update public.payment_orders
      set status = 'FAILED', failure_reason = 'amount_or_currency_mismatch', updated_at = now()
      where id = v_order.id;
    raise exception 'Paid amount does not match Premium price';
  end if;

  update public.payment_orders
  set status = 'SUCCESS',
      provider_transaction_id = coalesce(p_provider_transaction_id, provider_transaction_id),
      paid_at = coalesce(paid_at, now()),
      processed_at = now(),
      updated_at = now()
  where id = v_order.id;

  v_subscription_id := public.activate_student_premium(v_order.user_id, v_order.id, public.premium_duration_days());

  -- Commissions : 200 scientifique + 200 littéraire (1 600 restent à la plateforme)
  if v_order.science_teacher_id is not null and v_order.science_commission_xaf > 0 then
    insert into public.teacher_wallets (teacher_id, balance_xaf)
      values (v_order.science_teacher_id, 0) on conflict (teacher_id) do nothing;
    insert into public.teacher_wallet_transactions (teacher_id, payment_order_id, amount_xaf, type, stream)
      values (v_order.science_teacher_id, v_order.id, v_order.science_commission_xaf, 'commission', 'scientific')
      on conflict (payment_order_id, teacher_id) do nothing;
    if found then
      update public.teacher_wallets set balance_xaf = balance_xaf + v_order.science_commission_xaf, updated_at = now()
      where teacher_id = v_order.science_teacher_id;
    end if;
  end if;

  if v_order.literary_teacher_id is not null and v_order.literary_commission_xaf > 0 then
    insert into public.teacher_wallets (teacher_id, balance_xaf)
      values (v_order.literary_teacher_id, 0) on conflict (teacher_id) do nothing;
    insert into public.teacher_wallet_transactions (teacher_id, payment_order_id, amount_xaf, type, stream)
      values (v_order.literary_teacher_id, v_order.id, v_order.literary_commission_xaf, 'commission', 'literary')
      on conflict (payment_order_id, teacher_id) do nothing;
    if found then
      update public.teacher_wallets set balance_xaf = balance_xaf + v_order.literary_commission_xaf, updated_at = now()
      where teacher_id = v_order.literary_teacher_id;
    end if;
  end if;

  return jsonb_build_object('success', true, 'already_processed', false,
    'payment_order_id', v_order.id, 'user_id', v_order.user_id,
    'subscription_id', v_subscription_id);
end;
$$;
revoke all on function public.finalize_notchpay_payment(text, text, bigint, text) from public, anon, authenticated;
grant execute on function public.finalize_notchpay_payment(text, text, bigint, text) to service_role;

-- Marquer un paiement refusé / annulé / expiré (jamais après un succès)
create or replace function public.mark_notchpay_payment_failed(
  p_reference text, p_status text, p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.payment_orders
  set status = case upper(p_status) when 'CANCELED' then 'CANCELED' when 'CANCELLED' then 'CANCELED'
                                    when 'EXPIRED' then 'CLOSED' else 'FAILED' end,
      failure_reason = left(coalesce(p_reason, lower(p_status)), 200),
      updated_at = now()
  where reference = trim(p_reference)
    and processed_at is null
    and status in ('NOTPAY', 'PENDING');
end;
$$;
revoke all on function public.mark_notchpay_payment_failed(text, text, text) from public, anon, authenticated;
grant execute on function public.mark_notchpay_payment_failed(text, text, text) to service_role;

-- activate_student_premium : prix aligné, exécutable uniquement par le serveur
create or replace function public.activate_student_premium(
  p_user_id uuid, p_payment_order_id uuid, p_duration_days integer default 30
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subscription_id uuid;
begin
  if p_duration_days <= 0 then raise exception 'Invalid subscription duration'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id and role = 'student') then
    raise exception 'User is not a student';
  end if;
  if not exists (
    select 1 from public.payment_orders
    where id = p_payment_order_id and user_id = p_user_id and status = 'SUCCESS'
      and amount = public.premium_price_xaf() and currency = 'XAF'
  ) then
    raise exception 'Valid successful payment not found';
  end if;

  -- Un même paiement ne peut prolonger qu'une seule fois
  select id into v_subscription_id from public.student_subscriptions
  where payment_order_id = p_payment_order_id limit 1;
  if v_subscription_id is not null then return v_subscription_id; end if;

  select id into v_subscription_id from public.student_subscriptions
  where user_id = p_user_id and plan = 'premium' and status = 'active'
  order by expires_at desc nulls last limit 1
  for update;

  if v_subscription_id is not null then
    update public.student_subscriptions
    set expires_at = greatest(coalesce(expires_at, now()), now()) + make_interval(days => p_duration_days),
        payment_order_id = p_payment_order_id,
        updated_at = now()
    where id = v_subscription_id;
  else
    insert into public.student_subscriptions (user_id, plan, status, starts_at, expires_at, payment_order_id)
    values (p_user_id, 'premium', 'active', now(), now() + make_interval(days => p_duration_days), p_payment_order_id)
    returning id into v_subscription_id;
  end if;

  update public.profiles set subscription_plan = 'premium' where id = p_user_id and role = 'student';
  return v_subscription_id;
end;
$$;
revoke all on function public.activate_student_premium(uuid, uuid, integer) from public, anon, authenticated;
grant execute on function public.activate_student_premium(uuid, uuid, integer) to service_role;

-- is_student_premium : un utilisateur ne peut interroger que son propre compte
create or replace function public.is_student_premium(p_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and auth.uid() <> p_user_id
     and not coalesce(public.is_catalog_admin(), false) then
    return false;
  end if;
  return exists (
    select 1 from public.student_subscriptions s
    where s.user_id = p_user_id and s.plan = 'premium' and s.status = 'active'
      and (s.expires_at is null or s.expires_at > now())
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Quotas gratuits : fenêtre de 24 h glissante, compteurs côté serveur
-- ---------------------------------------------------------------------------
create table if not exists public.feature_quota_windows (
  user_id uuid not null references auth.users(id) on delete cascade,
  feature text not null,
  window_start timestamptz not null default now(),
  used integer not null default 0 check (used >= 0),
  primary key (user_id, feature)
);
alter table public.feature_quota_windows enable row level security;
revoke all on public.feature_quota_windows from anon, authenticated;

-- Droits déjà accordés dans la fenêtre courante (réouvrir la même leçon = 0 unité)
create table if not exists public.feature_quota_grants (
  user_id uuid not null references auth.users(id) on delete cascade,
  feature text not null,
  resource_id text not null,
  window_start timestamptz not null,
  granted_at timestamptz not null default now(),
  primary key (user_id, feature, resource_id, window_start)
);
alter table public.feature_quota_grants enable row level security;
revoke all on public.feature_quota_grants from anon, authenticated;

create or replace function public.free_quota_limit(p_feature text)
returns integer
language sql
immutable
as $$
  select case p_feature
    when 'lesson'   then 2
    when 'qcm'      then 2
    when 'annale'   then 2
    when 'ai_text'  then 3
    when 'msg_sent' then 2
    when 'msg_recv' then 2
    else null end
$$;

-- Consomme (ou vérifie) une unité. Atomique : verrou par (utilisateur, fonctionnalité).
create or replace function public.consume_feature_quota(
  p_feature text,
  p_resource_id text default null,
  p_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := coalesce(p_user_id, auth.uid());
  v_limit integer := public.free_quota_limit(p_feature);
  v_role text;
  v_now timestamptz := now();
  v_win public.feature_quota_windows%rowtype;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if v_limit is null then raise exception 'Unknown feature %', p_feature; end if;

  -- Seul le serveur peut agir pour un autre utilisateur
  if p_user_id is not null and auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception 'Forbidden';
  end if;

  select role into v_role from public.profiles where id = v_uid;
  if v_role is distinct from 'student' then
    return jsonb_build_object('allowed', true, 'premium', false, 'exempt', true, 'feature', p_feature);
  end if;

  if public.is_student_premium(v_uid) then
    return jsonb_build_object('allowed', true, 'premium', true, 'feature', p_feature);
  end if;

  perform pg_advisory_xact_lock(hashtext(v_uid::text || ':' || p_feature));

  insert into public.feature_quota_windows (user_id, feature, window_start, used)
  values (v_uid, p_feature, v_now, 0)
  on conflict (user_id, feature) do nothing;

  select * into v_win from public.feature_quota_windows
  where user_id = v_uid and feature = p_feature for update;

  -- Nouvelle période de 24 h (horloge serveur uniquement)
  if v_win.window_start + interval '24 hours' <= v_now then
    update public.feature_quota_windows
      set window_start = v_now, used = 0
      where user_id = v_uid and feature = p_feature
      returning * into v_win;
  end if;

  -- Même ressource déjà ouverte dans cette fenêtre : pas de double comptage
  if p_resource_id is not null and exists (
    select 1 from public.feature_quota_grants g
    where g.user_id = v_uid and g.feature = p_feature
      and g.resource_id = p_resource_id and g.window_start = v_win.window_start
  ) then
    return jsonb_build_object('allowed', true, 'premium', false, 'feature', p_feature,
      'limit', v_limit, 'used', v_win.used, 'remaining', greatest(v_limit - v_win.used, 0),
      'resets_at', v_win.window_start + interval '24 hours', 'already_granted', true);
  end if;

  if v_win.used >= v_limit then
    return jsonb_build_object('allowed', false, 'premium', false, 'feature', p_feature,
      'limit', v_limit, 'used', v_win.used, 'remaining', 0,
      'resets_at', v_win.window_start + interval '24 hours', 'code', 'QUOTA_EXCEEDED');
  end if;

  update public.feature_quota_windows set used = used + 1
    where user_id = v_uid and feature = p_feature
    returning * into v_win;

  if p_resource_id is not null then
    insert into public.feature_quota_grants (user_id, feature, resource_id, window_start)
    values (v_uid, p_feature, p_resource_id, v_win.window_start)
    on conflict do nothing;
  end if;

  return jsonb_build_object('allowed', true, 'premium', false, 'feature', p_feature,
    'limit', v_limit, 'used', v_win.used, 'remaining', greatest(v_limit - v_win.used, 0),
    'resets_at', v_win.window_start + interval '24 hours');
end;
$$;
revoke all on function public.consume_feature_quota(text, text, uuid) from public, anon;
grant execute on function public.consume_feature_quota(text, text, uuid) to authenticated, service_role;

-- Lecture seule : quotas restants + prochaine réinitialisation + état Premium
create or replace function public.get_my_quota_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_premium boolean;
  v_expires timestamptz;
  v_out jsonb := '{}'::jsonb;
  v_feature text;
  v_win public.feature_quota_windows%rowtype;
  v_limit integer;
  v_used integer;
  v_reset timestamptz;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  v_premium := public.is_student_premium(v_uid);
  select max(expires_at) into v_expires from public.student_subscriptions
    where user_id = v_uid and plan = 'premium' and status = 'active';

  foreach v_feature in array array['lesson','qcm','annale','ai_text','msg_sent','msg_recv'] loop
    v_limit := public.free_quota_limit(v_feature);
    select * into v_win from public.feature_quota_windows where user_id = v_uid and feature = v_feature;
    if found and v_win.window_start + interval '24 hours' > now() then
      v_used := v_win.used; v_reset := v_win.window_start + interval '24 hours';
    else
      v_used := 0; v_reset := null;
    end if;
    v_out := v_out || jsonb_build_object(v_feature, jsonb_build_object(
      'limit', v_limit, 'used', v_used, 'remaining', greatest(v_limit - v_used, 0), 'resets_at', v_reset));
  end loop;

  return jsonb_build_object(
    'premium', v_premium,
    'premium_expires_at', case when v_premium then v_expires else null end,
    'price_xaf', public.premium_price_xaf(),
    'duration_days', public.premium_duration_days(),
    'has_pending_payment', exists (
      select 1 from public.payment_orders
      where user_id = v_uid and status in ('NOTPAY','PENDING') and created_at > now() - interval '2 hours'),
    'was_premium', (not v_premium) and exists (
      select 1 from public.student_subscriptions where user_id = v_uid and plan = 'premium'),
    'quotas', v_out
  );
end;
$$;
revoke all on function public.get_my_quota_status() from public, anon;
grant execute on function public.get_my_quota_status() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. IA : fonction appelée par gemini-chat (absente des migrations jusqu'ici)
--    Texte : 3 / 24 h. Photos et PDF : réservés au Premium.
-- ---------------------------------------------------------------------------
create or replace function public.consume_ai_daily_limits(p_kinds text[])
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_res jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = v_uid;
  if v_role is distinct from 'student' then
    return jsonb_build_object('allowed', true, 'exempt', true);
  end if;

  if not public.is_student_premium(v_uid) and ('photo' = any(p_kinds) or 'pdf' = any(p_kinds)) then
    return jsonb_build_object('allowed', false, 'kind', case when 'pdf' = any(p_kinds) then 'pdf' else 'photo' end,
      'limit', 0, 'used', 0, 'code', 'PREMIUM_REQUIRED');
  end if;

  v_res := public.consume_feature_quota('ai_text');
  if (v_res ->> 'allowed')::boolean then
    return v_res;
  end if;
  return v_res || jsonb_build_object('kind', 'question');
end;
$$;
revoke all on function public.consume_ai_daily_limits(text[]) from public, anon;
grant execute on function public.consume_ai_daily_limits(text[]) to authenticated;

-- Rembourser une unité si l'IA échoue après consommation (erreur réseau/Gemini)
create or replace function public.refund_feature_quota(p_feature text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then return; end if;
  update public.feature_quota_windows
    set used = greatest(used - 1, 0)
    where user_id = auth.uid() and feature = p_feature
      and window_start + interval '24 hours' > now();
end;
$$;
revoke all on function public.refund_feature_quota(text) from public, anon;
grant execute on function public.refund_feature_quota(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Messagerie : quota d'envoi appliqué par le serveur (contourne-proof)
--    Les envois rejoués par la file hors ligne (même id) ne consomment rien.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_message_send_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res jsonb;
  v_exists boolean;
begin
  if tg_table_name = 'private_messages' then
    select exists(select 1 from public.private_messages where id = new.id) into v_exists;
  else
    select exists(select 1 from public.message_group_messages where id = new.id) into v_exists;
  end if;
  if v_exists then return new; end if;

  -- Pièces jointes (photo, document, audio, vidéo) : Premium uniquement pour les élèves
  if new.attachment_path is not null
     and exists (select 1 from public.profiles where id = new.sender_id and role = 'student')
     and not public.is_student_premium(new.sender_id) then
    raise exception 'PREMIUM_REQUIRED:attachments' using errcode = 'P0001';
  end if;

  v_res := public.consume_feature_quota('msg_sent', new.id::text, new.sender_id);
  if not (v_res ->> 'allowed')::boolean then
    raise exception 'QUOTA_EXCEEDED:msg_sent' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_private_messages_quota on public.private_messages;
create trigger trg_private_messages_quota
  before insert on public.private_messages
  for each row execute function public.enforce_message_send_quota();

drop trigger if exists trg_group_messages_quota on public.message_group_messages;
create trigger trg_group_messages_quota
  before insert on public.message_group_messages
  for each row execute function public.enforce_message_send_quota();

-- ---------------------------------------------------------------------------
-- 10. QCM : une tentative exige un droit valide (quota ou Premium)
--     submit_chapter_quiz insère dans chapter_quiz_attempts : le trigger bloque
--     tout contournement, y compris par appel RPC direct.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_qcm_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_res jsonb;
begin
  v_res := public.consume_feature_quota('qcm', new.quiz_id::text, new.student_id);
  if not (v_res ->> 'allowed')::boolean then
    raise exception 'QUOTA_EXCEEDED:qcm' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_chapter_quiz_attempts_quota on public.chapter_quiz_attempts;
create trigger trg_chapter_quiz_attempts_quota
  before insert on public.chapter_quiz_attempts
  for each row execute function public.enforce_qcm_quota();

-- ---------------------------------------------------------------------------
-- 11. Expiration : nettoyage planifiable (exécutable par le serveur uniquement)
-- ---------------------------------------------------------------------------
revoke all on function public.expire_student_subscriptions() from public, anon, authenticated;
grant execute on function public.expire_student_subscriptions() to service_role;
