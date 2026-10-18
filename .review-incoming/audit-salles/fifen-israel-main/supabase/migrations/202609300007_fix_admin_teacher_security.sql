-- Fise School: corrective security migration
-- Admin + teacher scope + unified role checks.
-- No password is stored or modified here.

-- ============================================================
-- 1. Promote the configured administrator
-- ============================================================
-- This migration runs as trusted backend. Temporarily remove the
-- client-side admin-role protection while assigning the first admin.
drop trigger if exists profiles_protect_role on public.profiles;

-- ============================================================

do $$
declare
  v_user_id uuid;
  v_existing_admin uuid;
begin
  select id
  into v_user_id
  from auth.users
  where lower(email) = lower('israelfifen544@gmail.com')
  limit 1;

  if v_user_id is null then
    raise exception
      'Admin Auth user israelfifen544@gmail.com was not found. Create the Auth account first.';
  end if;

  select id
  into v_existing_admin
  from public.profiles
  where role = 'admin'
    and id <> v_user_id
  limit 1;

  if v_existing_admin is not null then
    raise exception
      'Another administrator already exists: %. Only one administrator is allowed.',
      v_existing_admin;
  end if;

  update public.profiles
  set
    first_name = 'Israël',
    last_name = 'Fifen',
    email = 'israelfifen544@gmail.com',
    role = 'admin',
    preferred_language = coalesce(preferred_language, 'fr'),
    updated_at = now()
  where id = v_user_id;

  if not found then
    insert into public.profiles (
      id,
      first_name,
      last_name,
      email,
      role,
      preferred_language
    )
    values (
      v_user_id,
      'Israël',
      'Fifen',
      'israelfifen544@gmail.com',
      'admin',
      'fr'
    );
  end if;
end $$;

-- Restore the protection immediately after the trusted promotion.
create trigger profiles_protect_role
before insert or update on public.profiles
for each row execute function public.protect_profile_role();
-- ============================================================
-- 2. Unified administrator check
-- ============================================================

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

create or replace function public.is_catalog_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
  );
$$;

revoke all on function public.is_catalog_admin() from public;
grant execute on function public.is_catalog_admin() to authenticated;

-- ============================================================
-- 3. Correct teacher/class authorization function
-- ============================================================

-- Existing function is kept because RLS policies depend on it.


create or replace function public.teacher_can_manage_class(
  p_class_id uuid,
  p_teacher_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_admin()
    or (
      p_teacher_id = auth.uid()
      and exists (
        select 1
        from public.class_teachers ct
        where ct.class_id = p_class_id
          and ct.teacher_id = p_teacher_id
          and ct.is_active
      )
    );
$$;

revoke all on function public.teacher_can_manage_class(uuid, uuid) from public;
grant execute on function public.teacher_can_manage_class(uuid, uuid) to authenticated;

-- ============================================================
-- 4. Reapply strict course security
-- ============================================================

drop policy if exists "teachers manage own courses" on public.courses;
drop policy if exists "teachers manage assigned courses" on public.courses;

create policy "teachers manage assigned courses"
on public.courses
for all
to authenticated
using (
  public.is_admin()
  or (
    teacher_id = auth.uid()
    and public.teacher_can_manage_class(class_id, auth.uid())
  )
)
with check (
  public.is_admin()
  or (
    teacher_id = auth.uid()
    and public.teacher_can_manage_class(class_id, auth.uid())
  )
);

-- ============================================================
-- 5. Ensure course validation uses the corrected function
-- ============================================================

create or replace function public.validate_teacher_course_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class public.school_classes%rowtype;
  v_teacher public.profiles%rowtype;
  v_subject public.subjects%rowtype;
begin
  if public.is_admin() then
    return new;
  end if;

  if new.teacher_id <> auth.uid() then
    raise exception 'A teacher can only create or modify their own courses';
  end if;

  select *
  into v_teacher
  from public.profiles
  where id = new.teacher_id;

  if not found or v_teacher.role <> 'teacher' then
    raise exception 'Course owner must be a teacher';
  end if;

  if new.class_id is null then
    raise exception 'A teacher course must belong to an assigned class';
  end if;

  if not public.teacher_can_manage_class(
    new.class_id,
    new.teacher_id
  ) then
    raise exception 'Teacher is not assigned to this class';
  end if;

  select *
  into v_class
  from public.school_classes
  where id = new.class_id
    and is_active;

  if not found then
    raise exception 'Class is not active';
  end if;

  select *
  into v_subject
  from public.subjects
  where id = new.subject_id
    and is_active;

  if not found then
    raise exception 'Subject is not active';
  end if;

  if v_teacher.subsystem is distinct from v_class.subsystem
     or v_teacher.sector is distinct from v_class.sector
     or v_subject.subsystem is distinct from v_class.subsystem
     or v_subject.sector is distinct from v_class.sector then
    raise exception
      'Teacher, class and subject must use the same subsystem and sector';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_teacher_course_scope() from public;
grant execute on function public.validate_teacher_course_scope() to authenticated;

drop trigger if exists courses_validate_teacher_scope on public.courses;

create trigger courses_validate_teacher_scope
before insert or update on public.courses
for each row
execute function public.validate_teacher_course_scope();

-- ============================================================
-- 6. Keep lessons restricted to their course owner/admin
-- ============================================================

drop policy if exists "teachers manage own lessons" on public.lessons;

create policy "teachers manage assigned course lessons"
on public.lessons
for all
to authenticated
using (
  public.is_admin()
  or exists (
    select 1
    from public.courses c
    where c.id = lessons.course_id
      and c.teacher_id = auth.uid()
      and public.teacher_can_manage_class(c.class_id, auth.uid())
  )
)
with check (
  public.is_admin()
  or exists (
    select 1
    from public.courses c
    where c.id = lessons.course_id
      and c.teacher_id = auth.uid()
      and public.teacher_can_manage_class(c.class_id, auth.uid())
  )
);

-- ============================================================
-- 7. Resources follow the same course restriction
-- ============================================================

drop policy if exists "course owners manage resources" on public.course_resources;

create policy "assigned course owners manage resources"
on public.course_resources
for all
to authenticated
using (
  public.is_admin()
  or exists (
    select 1
    from public.courses c
    where c.id = course_resources.course_id
      and c.teacher_id = auth.uid()
      and public.teacher_can_manage_class(c.class_id, auth.uid())
  )
)
with check (
  public.is_admin()
  or exists (
    select 1
    from public.courses c
    where c.id = course_resources.course_id
      and c.teacher_id = auth.uid()
      and public.teacher_can_manage_class(c.class_id, auth.uid())
  )
);

-- ============================================================
-- 8. Teacher wallets
-- ============================================================

drop policy if exists "teachers_can_read_own_wallet" on public.teacher_wallets;
drop policy if exists "teachers_and_admins_read_wallets" on public.teacher_wallets;

create policy "teachers_and_admins_read_wallets"
on public.teacher_wallets
for select
to authenticated
using (
  teacher_id = auth.uid()
  or public.is_admin()
);

drop policy if exists "teachers_can_read_own_wallet_transactions"
on public.teacher_wallet_transactions;

drop policy if exists "teachers_and_admins_read_wallet_transactions"
on public.teacher_wallet_transactions;

create policy "teachers_and_admins_read_wallet_transactions"
on public.teacher_wallet_transactions
for select
to authenticated
using (
  teacher_id = auth.uid()
  or public.is_admin()
);

-- ============================================================
-- End
-- ============================================================
