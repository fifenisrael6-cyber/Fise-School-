-- ============================================================
-- FISE SCHOOL
-- Système Gratuit / Premium des élèves
-- ============================================================

-- ------------------------------------------------------------
-- 1. Ajouter le plan d'abonnement au profil
-- ------------------------------------------------------------

alter table public.profiles
add column if not exists subscription_plan text
not null
default 'free';

alter table public.profiles
drop constraint if exists profiles_subscription_plan_check;

alter table public.profiles
add constraint profiles_subscription_plan_check
check (
  subscription_plan in ('free', 'premium')
);


-- ------------------------------------------------------------
-- 2. Table des abonnements élèves
-- ------------------------------------------------------------

create table if not exists public.student_subscriptions (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  plan text not null default 'premium',

  status text not null default 'active',

  starts_at timestamptz not null default now(),

  expires_at timestamptz,

  payment_order_id uuid
    references public.payment_orders(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint student_subscriptions_plan_check
    check (
      plan in ('free', 'premium')
    ),

  constraint student_subscriptions_status_check
    check (
      status in (
        'active',
        'expired',
        'cancelled'
      )
    )
);


-- ------------------------------------------------------------
-- 3. Index
-- ------------------------------------------------------------

create index if not exists
student_subscriptions_user_id_idx
on public.student_subscriptions(user_id);

create index if not exists
student_subscriptions_status_idx
on public.student_subscriptions(status);

create index if not exists
student_subscriptions_expires_at_idx
on public.student_subscriptions(expires_at);


-- ------------------------------------------------------------
-- 4. RLS
-- ------------------------------------------------------------

alter table public.student_subscriptions
enable row level security;


-- ------------------------------------------------------------
-- 5. Un élève peut consulter son abonnement
-- ------------------------------------------------------------

drop policy if exists
"students_can_read_own_subscription"
on public.student_subscriptions;

create policy
"students_can_read_own_subscription"
on public.student_subscriptions
for select
to authenticated
using (
  auth.uid() = user_id
);


-- ------------------------------------------------------------
-- 6. Fonction : vérifier si Premium est actif
-- ------------------------------------------------------------

create or replace function public.is_student_premium(
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_premium boolean;
begin

  select exists (
    select 1
    from public.student_subscriptions s
    where s.user_id = p_user_id
      and s.plan = 'premium'
      and s.status = 'active'
      and (
        s.expires_at is null
        or s.expires_at > now()
      )
  )
  into v_premium;

  return coalesce(v_premium, false);

end;
$$;


-- ------------------------------------------------------------
-- 7. Fonction : synchroniser automatiquement le profil
-- ------------------------------------------------------------

create or replace function public.sync_student_subscription_plan(
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin

  if public.is_student_premium(p_user_id) then

    update public.profiles
    set
      subscription_plan = 'premium'
    where id = p_user_id
      and role = 'student';

  else

    update public.profiles
    set
      subscription_plan = 'free'
    where id = p_user_id
      and role = 'student';

  end if;

end;
$$;


-- ------------------------------------------------------------
-- 8. Fonction de nettoyage des abonnements expirés
-- ------------------------------------------------------------

create or replace function public.expire_student_subscriptions()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin

  update public.student_subscriptions
  set
    status = 'expired',
    updated_at = now()
  where plan = 'premium'
    and status = 'active'
    and expires_at is not null
    and expires_at <= now();


  update public.profiles p
  set
    subscription_plan = 'free'
  where p.role = 'student'
    and p.subscription_plan = 'premium'
    and not exists (
      select 1
      from public.student_subscriptions s
      where s.user_id = p.id
        and s.plan = 'premium'
        and s.status = 'active'
        and (
          s.expires_at is null
          or s.expires_at > now()
        )
    );

end;
$$;


-- ------------------------------------------------------------
-- 9. Fonction : activer Premium après paiement
-- ------------------------------------------------------------

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


  -- Vérifier que l'utilisateur est bien un élève
  if not exists (
    select 1
    from public.profiles
    where id = p_user_id
      and role = 'student'
  ) then

    raise exception 'User is not a student';

  end if;


  -- Vérifier le paiement
  if not exists (
    select 1
    from public.payment_orders
    where id = p_payment_order_id
      and user_id = p_user_id
      and status = 'SUCCESS'
      and amount = 1000
      and currency = 'XAF'
  ) then

    raise exception 'Valid successful payment not found';

  end if;


  v_expires_at :=
    now() + make_interval(
      days => p_duration_days
    );


  -- Si un abonnement Premium actif existe déjà,
  -- on prolonge sa date d'expiration.
  select id
  into v_subscription_id
  from public.student_subscriptions
  where user_id = p_user_id
    and plan = 'premium'
    and status = 'active'
  order by expires_at desc nulls last
  limit 1;


  if v_subscription_id is not null then

    update public.student_subscriptions
    set
      expires_at =
        greatest(
          coalesce(expires_at, now()),
          now()
        )
        + make_interval(
          days => p_duration_days
        ),
      payment_order_id = p_payment_order_id,
      updated_at = now()
    where id = v_subscription_id;

  else

    insert into public.student_subscriptions (
      user_id,
      plan,
      status,
      starts_at,
      expires_at,
      payment_order_id
    )
    values (
      p_user_id,
      'premium',
      'active',
      now(),
      v_expires_at,
      p_payment_order_id
    )
    returning id
    into v_subscription_id;

  end if;


  -- Synchroniser profiles
  update public.profiles
  set
    subscription_plan = 'premium'
  where id = p_user_id
    and role = 'student';


  return v_subscription_id;

end;
$$;


-- ------------------------------------------------------------
-- 10. Permissions
-- ------------------------------------------------------------

revoke all
on function public.is_student_premium(uuid)
from public;

grant execute
on function public.is_student_premium(uuid)
to authenticated;


revoke all
on function public.sync_student_subscription_plan(uuid)
from public;

grant execute
on function public.sync_student_subscription_plan(uuid)
to authenticated;


revoke all
on function public.expire_student_subscriptions()
from public;


revoke all
on function public.activate_student_premium(
  uuid,
  uuid,
  integer
)
from public;


-- ------------------------------------------------------------
-- 11. Valeur initiale : tous les élèves sont gratuits
-- ------------------------------------------------------------

update public.profiles
set subscription_plan = 'free'
where role = 'student'
  and (
    subscription_plan is null
    or subscription_plan not in ('premium')
  );