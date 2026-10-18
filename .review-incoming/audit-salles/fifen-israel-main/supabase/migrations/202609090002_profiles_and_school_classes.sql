-- Fise School: user profiles and real school classes.
-- This migration intentionally does not create subjects, courses, lessons, assignments, forums, messages, notifications, grades, attendance, or storage.

create table if not exists public.academic_years (
  id uuid primary key default gen_random_uuid(),
  label text not null unique,
  start_date date,
  end_date date,
  is_current boolean not null default false,
  created_at timestamptz not null default now(),
  constraint academic_year_dates_valid check (
    end_date is null or start_date is null or end_date > start_date
  )
);

create unique index if not exists academic_year_one_current_idx
  on public.academic_years (is_current)
  where is_current = true;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  phone text,
  email text,
  role text not null default 'student',
  preferred_language text not null default 'fr',
  subsystem public.catalog_subsystem,
  sector public.catalog_sector,
  exam_level_id uuid references public.exam_levels(id) on delete set null,
  exam_id uuid references public.exams(id) on delete set null,
  series_id uuid references public.series(id) on delete set null,
  specialty_id uuid references public.specialties(id) on delete set null,
  class_name text,
  -- Transitional display labels used until the Flutter catalogue lookup stores FK ids.
  exam_level_label text,
  exam_label text,
  track_label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_role_valid check (role in ('student', 'teacher', 'admin')),
  constraint profiles_language_valid check (preferred_language in ('fr', 'en')),
  constraint profiles_identity_not_blank check (
    length(trim(first_name)) > 0 and length(trim(last_name)) > 0
  )
);

-- Database-level guarantee that there can be at most one administrator.
create unique index if not exists profiles_one_admin_idx
  on public.profiles ((role))
  where role = 'admin';

create table if not exists public.school_classes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  display_name text not null,
  subsystem public.catalog_subsystem not null,
  sector public.catalog_sector not null,
  academic_year_id uuid not null references public.academic_years(id) on delete restrict,
  exam_level_id uuid references public.exam_levels(id) on delete set null,
  series_id uuid references public.series(id) on delete set null,
  specialty_id uuid references public.specialties(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint school_classes_name_not_blank check (length(trim(name)) > 0),
  constraint school_classes_display_name_not_blank check (length(trim(display_name)) > 0),
  constraint school_classes_unique_per_year unique (name, academic_year_id)
);

create table if not exists public.class_students (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.school_classes(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.class_teachers (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.school_classes(id) on delete cascade,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  assigned_at timestamptz not null default now(),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.validate_profile_catalog_links()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  level_subsystem public.catalog_subsystem;
  level_sector public.catalog_sector;
begin
  if new.exam_level_id is not null then
    select subsystem, sector
      into level_subsystem, level_sector
      from public.exam_levels
      where id = new.exam_level_id and active;

    if not found then
      raise exception 'The selected exam level is not active';
    end if;

    if new.subsystem is distinct from level_subsystem
       or new.sector is distinct from level_sector then
      raise exception 'The exam level does not match the selected subsystem and sector';
    end if;
  end if;

  if new.exam_id is not null and not exists (
    select 1 from public.exam_levels
    where id = new.exam_level_id and exam_id = new.exam_id and active
  ) then
    raise exception 'The selected exam does not belong to the selected exam level';
  end if;

  if new.series_id is not null and not exists (
    select 1 from public.exam_level_series
    where exam_level_id = new.exam_level_id
      and series_id = new.series_id
      and active
  ) then
    raise exception 'The selected series is not linked to the selected exam level';
  end if;

  if new.specialty_id is not null and not exists (
    select 1 from public.exam_level_specialties
    where exam_level_id = new.exam_level_id
      and specialty_id = new.specialty_id
      and active
  ) then
    raise exception 'The selected specialty is not linked to the selected exam level';
  end if;

  if new.sector = 'general' and new.specialty_id is not null then
    raise exception 'A general level cannot use a technical specialty';
  end if;

  if new.sector = 'technical' and new.series_id is not null then
    raise exception 'A technical level cannot use a general series';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_validate_catalog_links on public.profiles;
create trigger profiles_validate_catalog_links
before insert or update on public.profiles
for each row execute function public.validate_profile_catalog_links();

create unique index if not exists class_students_one_active_membership_idx
  on public.class_students (class_id, student_id)
  where is_active = true;

create unique index if not exists class_teachers_one_active_assignment_idx
  on public.class_teachers (class_id, teacher_id)
  where is_active = true;

create index if not exists profiles_role_idx on public.profiles (role);
create index if not exists profiles_exam_level_id_idx on public.profiles (exam_level_id);
create index if not exists profiles_exam_id_idx on public.profiles (exam_id);
create index if not exists profiles_series_id_idx on public.profiles (series_id);
create index if not exists profiles_specialty_id_idx on public.profiles (specialty_id);
create index if not exists school_classes_filter_idx
  on public.school_classes (subsystem, sector, academic_year_id, is_active);
create index if not exists school_classes_exam_level_id_idx
  on public.school_classes (exam_level_id);
create index if not exists school_classes_series_id_idx
  on public.school_classes (series_id);
create index if not exists school_classes_specialty_id_idx
  on public.school_classes (specialty_id);
create index if not exists class_students_student_id_idx
  on public.class_students (student_id, is_active);
create index if not exists class_teachers_teacher_id_idx
  on public.class_teachers (teacher_id, is_active);

create or replace function public.set_profiles_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_profiles_updated_at();

drop trigger if exists school_classes_set_updated_at on public.school_classes;
create trigger school_classes_set_updated_at
before update on public.school_classes
for each row execute function public.set_profiles_updated_at();

-- Only a trusted backend/admin JWT can assign or change the admin role.
create or replace function public.protect_profile_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin'
     and (tg_op = 'INSERT' and new.role = 'admin'
          or tg_op = 'UPDATE' and new.role is distinct from old.role) then
    raise exception 'Only an administrator backend may assign the admin role';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_protect_role on public.profiles;
create trigger profiles_protect_role
before insert or update on public.profiles
for each row execute function public.protect_profile_role();

-- Signup metadata can create only student or teacher profiles. Admin creation is
-- intentionally excluded from this trigger and must be performed by a trusted backend.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  requested_role text := metadata ->> 'role';
  requested_subsystem text := metadata ->> 'subsystem';
  requested_sector text := metadata ->> 'sector';
begin
  insert into public.profiles (
    id, first_name, last_name, phone, email, role, preferred_language,
    subsystem, sector, exam_level_id, exam_id, series_id, specialty_id,
    class_name, exam_level_label, exam_label, track_label
  )
  values (
    new.id,
    coalesce(
      nullif(trim(metadata ->> 'first_name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Utilisateur'
    ),
    coalesce(
      nullif(trim(metadata ->> 'last_name'), ''),
      'Fise'
    ),
    new.phone,
    new.email,
    case when requested_role in ('student', 'teacher') then requested_role else 'student' end,
    case when metadata ->> 'preferred_language' in ('fr', 'en')
      then metadata ->> 'preferred_language' else 'fr' end,
    case when requested_subsystem in ('francophone', 'anglophone')
      then requested_subsystem::public.catalog_subsystem else null end,
    case when requested_sector in ('general', 'technical')
      then requested_sector::public.catalog_sector else null end,
    case when metadata ->> 'exam_level_id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then (metadata ->> 'exam_level_id')::uuid else null end,
    case when metadata ->> 'exam_id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then (metadata ->> 'exam_id')::uuid else null end,
    case when metadata ->> 'series_id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then (metadata ->> 'series_id')::uuid else null end,
    case when metadata ->> 'specialty_id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then (metadata ->> 'specialty_id')::uuid else null end,
    nullif(trim(metadata ->> 'class_name'), ''),
    nullif(trim(metadata ->> 'exam_level'), ''),
    nullif(trim(metadata ->> 'exam'), ''),
    nullif(trim(metadata ->> 'track'), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- Assignment operations are admin-only. The helper checks roles with definer
-- privileges so RLS cannot be bypassed by changing a client-side column.
create or replace function public.check_profile_role(target_id uuid, expected_role text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = target_id and role = expected_role
  );
$$;

create or replace function public.is_catalog_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin';
$$;

create or replace function public.is_student_in_class(target_class_id uuid, target_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.class_students
    where class_id = target_class_id
      and student_id = target_student_id
      and is_active
  );
$$;

create or replace function public.is_teacher_assigned(target_class_id uuid, target_teacher_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.class_teachers
    where class_id = target_class_id
      and teacher_id = target_teacher_id
      and is_active
  );
$$;

alter table public.academic_years enable row level security;
alter table public.profiles enable row level security;
alter table public.school_classes enable row level security;
alter table public.class_students enable row level security;
alter table public.class_teachers enable row level security;

create policy "academic years are readable when authenticated"
  on public.academic_years for select to authenticated using (true);
create policy "admins manage academic years"
  on public.academic_years for all to authenticated
  using (public.is_catalog_admin())
  with check (public.is_catalog_admin());

create policy "users can read their own profile"
  on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_catalog_admin());
create policy "users can create their own non-admin profile"
  on public.profiles for insert to authenticated
  with check (id = auth.uid() and role in ('student', 'teacher'));
create policy "admins can create profiles"
  on public.profiles for insert to authenticated
  with check (public.is_catalog_admin());
create policy "users can update their own profile without role changes"
  on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_catalog_admin())
  with check (id = auth.uid() or public.is_catalog_admin());
create policy "admins manage profiles"
  on public.profiles for delete to authenticated
  using (public.is_catalog_admin());

create policy "members can read active school classes"
  on public.school_classes for select to authenticated
  using (
    public.is_catalog_admin()
    or public.is_student_in_class(school_classes.id, auth.uid())
    or public.is_teacher_assigned(school_classes.id, auth.uid())
  );
create policy "admins manage school classes"
  on public.school_classes for all to authenticated
  using (public.is_catalog_admin())
  with check (public.is_catalog_admin());

create policy "users read their class memberships"
  on public.class_students for select to authenticated
  using (
    public.is_catalog_admin()
    or student_id = auth.uid()
    or public.is_teacher_assigned(class_students.class_id, auth.uid())
  );
create policy "admins manage class memberships"
  on public.class_students for all to authenticated
  using (public.is_catalog_admin())
  with check (
    public.is_catalog_admin()
    and public.check_profile_role(student_id, 'student')
  );

create policy "users read their class assignments"
  on public.class_teachers for select to authenticated
  using (
    public.is_catalog_admin()
    or teacher_id = auth.uid()
    or public.is_teacher_assigned(class_teachers.class_id, auth.uid())
  );
create policy "admins manage class assignments"
  on public.class_teachers for all to authenticated
  using (public.is_catalog_admin())
  with check (
    public.is_catalog_admin()
    and public.check_profile_role(teacher_id, 'teacher')
  );
