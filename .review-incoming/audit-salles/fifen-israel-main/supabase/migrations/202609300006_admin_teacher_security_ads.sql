-- Fise School: final security, teacher scope, admin access, wallets and ads.
-- This migration never stores an administrator password.
-- Create the admin Auth user first, then this migration promotes that email.

-- ============================================================
-- 1) Admin helper: profile role + JWT app_metadata
-- ============================================================
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;


revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Promote the existing Auth account if it already exists.
-- Passwords are deliberately NOT handled in SQL migrations.
do $$
declare
  v_user_id uuid;
begin
  select id into v_user_id
  from auth.users
  where lower(email) = lower('israelfifen544@gmail.com')
  limit 1;

  if v_user_id is null then
    raise notice 'Admin Auth user not found. Create the Auth user first, then rerun this migration.';
  else
    update public.profiles
      set role = 'admin', updated_at = now()
    where id = v_user_id;

    if not found then
      insert into public.profiles (id, first_name, last_name, email, role, preferred_language)
      values (v_user_id, 'Israël', 'Fifen', 'israelfifen544@gmail.com', 'admin', 'fr');
    end if;

    update auth.users
    set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role','admin')
    where id = v_user_id;

    raise notice 'Fise School administrator promoted: %', v_user_id;
  end if;
end $$;

-- ============================================================
-- 2) Teacher scope: a teacher may only manage courses in classes
--    assigned to that teacher, unless the teacher is an admin.
-- ============================================================
create or replace function public.teacher_can_manage_class(p_class_id uuid, p_teacher_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_admin()
      or exists (
        select 1
        from public.class_teachers ct
        where ct.class_id = p_class_id
          and ct.teacher_id = p_teacher_id
          and ct.is_active
      );
$$;

revoke all on function public.teacher_can_manage_class(uuid, uuid) from public;
grant execute on function public.teacher_can_manage_class(uuid, uuid) to authenticated;

create or replace function public.validate_teacher_course_scope()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_class public.school_classes%rowtype;
  v_teacher public.profiles%rowtype;
  v_subject public.subjects%rowtype;
begin
  if public.is_admin() then
    return new;
  end if;

  select * into v_teacher from public.profiles where id = new.teacher_id;
  if not found or v_teacher.role <> 'teacher' then
    raise exception 'Course owner must be a teacher';
  end if;

  if new.class_id is null then
    raise exception 'A teacher course must belong to an assigned class';
  end if;

  if not public.teacher_can_manage_class(new.class_id, new.teacher_id) then
    raise exception 'Teacher is not assigned to this class';
  end if;

  select * into v_class from public.school_classes where id = new.class_id and is_active;
  if not found then
    raise exception 'Class is not active';
  end if;

  select * into v_subject from public.subjects where id = new.subject_id and is_active;
  if not found then
    raise exception 'Subject is not active';
  end if;

  if v_teacher.subsystem is distinct from v_class.subsystem
     or v_teacher.sector is distinct from v_class.sector
     or v_subject.subsystem is distinct from v_class.subsystem
     or v_subject.sector is distinct from v_class.sector then
    raise exception 'Teacher, class and subject must use the same subsystem and sector';
  end if;

  return new;
end;
$$;

drop trigger if exists courses_validate_teacher_scope on public.courses;
create trigger courses_validate_teacher_scope
before insert or update on public.courses
for each row execute function public.validate_teacher_course_scope();

-- Replace broad teacher course policy with assigned-class policy.
drop policy if exists "teachers manage own courses" on public.courses;
drop policy if exists "teachers manage assigned courses" on public.courses;
create policy "teachers manage assigned courses"
on public.courses for all to authenticated
using (
  public.is_admin()
  or (teacher_id = auth.uid() and public.teacher_can_manage_class(class_id, auth.uid()))
)
with check (
  public.is_admin()
  or (teacher_id = auth.uid() and public.teacher_can_manage_class(class_id, auth.uid()))
);

-- Lessons/resources inherit the course owner/administrator restriction.
-- Existing policies already check the course teacher or admin.

-- ============================================================
-- 3) Teacher wallet: teacher sees own wallet; admin sees everything.
-- ============================================================
drop policy if exists "teachers_can_read_own_wallet" on public.teacher_wallets;
create policy "teachers_and_admins_read_wallets"
on public.teacher_wallets for select to authenticated
using (teacher_id = auth.uid() or public.is_admin());

drop policy if exists "teachers_can_read_own_wallet_transactions" on public.teacher_wallet_transactions;
create policy "teachers_and_admins_read_wallet_transactions"
on public.teacher_wallet_transactions for select to authenticated
using (teacher_id = auth.uid() or public.is_admin());

-- Admin can audit payment orders.
drop policy if exists "admins_can_read_all_payment_orders" on public.payment_orders;
create policy "admins_can_read_all_payment_orders"
on public.payment_orders for select to authenticated
using (user_id = auth.uid() or public.is_admin());

-- ============================================================
-- 4) Advertisements
-- ============================================================
create table if not exists public.advertisements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  image_path text,
  target_url text,
  placement text not null default 'home'
    check (placement in ('home','student','teacher','courses','all')),
  is_active boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint advertisement_dates_valid check (ends_at is null or starts_at is null or ends_at > starts_at),
  constraint advertisement_title_not_blank check (length(trim(title)) > 0)
);

create index if not exists advertisements_active_idx
on public.advertisements (is_active, placement, starts_at, ends_at);

alter table public.advertisements enable row level security;

drop policy if exists "authenticated_read_active_ads" on public.advertisements;
create policy "authenticated_read_active_ads"
on public.advertisements for select to authenticated
using (
  is_active
  and (starts_at is null or starts_at <= now())
  and (ends_at is null or ends_at > now())
  or public.is_admin()
);

drop policy if exists "admins_manage_ads" on public.advertisements;
create policy "admins_manage_ads"
on public.advertisements for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.set_advertisement_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists advertisements_set_updated_at on public.advertisements;
create trigger advertisements_set_updated_at
before update on public.advertisements
for each row execute function public.set_advertisement_updated_at();

insert into storage.buckets (id, name, public)
values ('advertisements', 'advertisements', false)
on conflict (id) do nothing;

drop policy if exists "admins_manage_ad_storage" on storage.objects;
create policy "admins_manage_ad_storage"
on storage.objects for all to authenticated
using (bucket_id = 'advertisements' and public.is_admin())
with check (bucket_id = 'advertisements' and public.is_admin());

drop policy if exists "authenticated_read_active_ad_storage" on storage.objects;
create policy "authenticated_read_active_ad_storage"
on storage.objects for select to authenticated
using (
  bucket_id = 'advertisements'
  and exists (
    select 1 from public.advertisements a
    where a.image_path = name
      and a.is_active
      and (a.starts_at is null or a.starts_at <= now())
      and (a.ends_at is null or a.ends_at > now())
  )
);

-- ============================================================
-- 5) Ensure the admin has an explicit app role claim after refresh.
-- ============================================================
create or replace function public.refresh_admin_claim(p_user_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles where id = p_user_id and role = 'admin') then
    raise exception 'User is not an administrator';
  end if;
  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role','admin')
  where id = p_user_id;
end;
$$;
revoke all on function public.refresh_admin_claim(uuid) from public;
grant execute on function public.refresh_admin_claim(uuid) to service_role;

-- IMPORTANT: password changes are intentionally handled by Supabase Auth
-- (updateUser/updatePassword), not by a custom password column.
