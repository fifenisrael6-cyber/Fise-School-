-- Fise School: student-initiated promotion requests.
-- This migration does not create any teaching or communication module.

do $$
begin
  create type public.student_promotion_status as enum (
    'pending',
    'approved',
    'rejected',
    'cancelled'
  );
exception
  when duplicate_object then null;
end
$$;

create table if not exists public.student_promotions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  source_class_id uuid not null references public.school_classes(id) on delete restrict,
  destination_class_id uuid not null references public.school_classes(id) on delete restrict,
  source_academic_year_id uuid not null references public.academic_years(id) on delete restrict,
  destination_academic_year_id uuid not null references public.academic_years(id) on delete restrict,
  status public.student_promotion_status not null default 'pending',
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  constraint student_promotions_different_classes check (
    source_class_id <> destination_class_id
  ),
  constraint student_promotions_different_years check (
    source_academic_year_id <> destination_academic_year_id
  ),
  constraint student_promotions_review_consistency check (
    (status = 'pending' and reviewed_at is null)
    or status <> 'pending'
  )
);

create index if not exists student_promotions_student_idx
  on public.student_promotions (student_id, requested_at desc);
create index if not exists student_promotions_status_idx
  on public.student_promotions (status, requested_at desc);
create index if not exists student_promotions_destination_year_idx
  on public.student_promotions (destination_academic_year_id, status);

create unique index if not exists student_promotions_one_active_request_idx
  on public.student_promotions (student_id, destination_academic_year_id)
  where status in ('pending', 'approved');

create or replace function public.validate_student_promotion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  source_year_id uuid;
  source_year_start date;
  destination_year_start date;
  next_year_exists boolean;
  profile_subsystem public.catalog_subsystem;
  profile_sector public.catalog_sector;
  profile_series_id uuid;
  profile_specialty_id uuid;
  destination_subsystem public.catalog_subsystem;
  destination_sector public.catalog_sector;
  destination_series_id uuid;
  destination_specialty_id uuid;
begin
  if not public.check_profile_role(new.student_id, 'student') then
    raise exception 'Promotion requests belong to students only';
  end if;

  if new.status = 'pending' and not public.is_catalog_admin()
     and new.student_id <> auth.uid() then
    raise exception 'A student can only request their own promotion';
  end if;

  select c.academic_year_id, y.start_date
    into source_year_id, source_year_start
    from public.school_classes c
    join public.academic_years y on y.id = c.academic_year_id
    where c.id = new.source_class_id
      and c.is_active
      and y.is_current;

  if not found then
    raise exception 'The source class is not active';
  end if;

  if source_year_id <> new.source_academic_year_id then
    raise exception 'The source class does not belong to the source academic year';
  end if;

  if not exists (
    select 1 from public.class_students cs
    where cs.class_id = new.source_class_id
      and cs.student_id = new.student_id
      and cs.is_active
  ) then
    raise exception 'The student does not belong to the source class';
  end if;

  select y.start_date
    into destination_year_start
    from public.academic_years y
    where y.id = new.destination_academic_year_id;

  if not found or source_year_start is null or destination_year_start is null
     or destination_year_start <= source_year_start then
    raise exception 'The destination academic year is not a valid next year';
  end if;

  select exists (
    select 1 from public.academic_years y
    where y.start_date > source_year_start
      and y.start_date < destination_year_start
  ) into next_year_exists;

  if next_year_exists then
    raise exception 'The destination must be the next available academic year';
  end if;

  select p.subsystem, p.sector, p.series_id, p.specialty_id
    into profile_subsystem, profile_sector, profile_series_id, profile_specialty_id
    from public.profiles p
    where p.id = new.student_id;

  select c.subsystem, c.sector, c.series_id, c.specialty_id
    into destination_subsystem, destination_sector,
      destination_series_id, destination_specialty_id
    from public.school_classes c
    where c.id = new.destination_class_id
      and c.academic_year_id = new.destination_academic_year_id
      and c.is_active;

  if not found then
    raise exception 'The destination class is not active in the destination year';
  end if;

  if profile_subsystem is distinct from destination_subsystem
     or profile_sector is distinct from destination_sector then
    raise exception 'The destination class is incompatible with the student pathway';
  end if;

  if destination_series_id is not null
     and profile_series_id is distinct from destination_series_id then
    raise exception 'The destination class series is incompatible with the student pathway';
  end if;

  if destination_specialty_id is not null
     and profile_specialty_id is distinct from destination_specialty_id then
    raise exception 'The destination class specialty is incompatible with the student pathway';
  end if;

  return new;
end;
$$;

drop trigger if exists student_promotions_validate on public.student_promotions;
create trigger student_promotions_validate
before insert on public.student_promotions
for each row execute function public.validate_student_promotion();

create or replace function public.protect_student_promotion_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.student_id is distinct from new.student_id
     or old.source_class_id is distinct from new.source_class_id
     or old.destination_class_id is distinct from new.destination_class_id
     or old.source_academic_year_id is distinct from new.source_academic_year_id
     or old.destination_academic_year_id is distinct from new.destination_academic_year_id then
    raise exception 'Promotion request source and destination are immutable';
  end if;

  if not public.is_catalog_admin() then
    if old.status <> 'pending' or new.status <> 'cancelled' then
      raise exception 'A student may only cancel a pending promotion request';
    end if;
  elsif old.status <> 'pending' or new.status not in ('approved', 'rejected') then
    raise exception 'An administrator may only approve or reject a pending request';
  end if;

  new.reviewed_at = now();
  new.reviewed_by = case
    when auth.uid() is not null then auth.uid()
    else new.reviewed_by
  end;
  return new;
end;
$$;

drop trigger if exists student_promotions_protect_update on public.student_promotions;
create trigger student_promotions_protect_update
before update on public.student_promotions
for each row execute function public.protect_student_promotion_update();

create or replace function public.apply_approved_student_promotion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'pending' and new.status = 'approved' then
    insert into public.class_students (class_id, student_id, joined_at, is_active)
    values (new.destination_class_id, new.student_id, now(), true);
  end if;
  return new;
end;
$$;

drop trigger if exists student_promotions_apply_approval on public.student_promotions;
create trigger student_promotions_apply_approval
after update on public.student_promotions
for each row execute function public.apply_approved_student_promotion();

create or replace function public.prevent_multiple_active_classes_per_year()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_active and exists (
    select 1
    from public.class_students current_membership
    join public.school_classes current_class
      on current_class.id = current_membership.class_id
    where current_membership.student_id = new.student_id
      and current_membership.is_active
      and current_class.academic_year_id = (
        select destination_class.academic_year_id
        from public.school_classes destination_class
        where destination_class.id = new.class_id
      )
      and current_membership.id <> coalesce(new.id, gen_random_uuid())
  ) then
    raise exception 'A student cannot have two active classes in the same academic year';
  end if;
  return new;
end;
$$;

drop trigger if exists class_students_one_year_only on public.class_students;
create trigger class_students_one_year_only
before insert or update on public.class_students
for each row execute function public.prevent_multiple_active_classes_per_year();

alter table public.student_promotions enable row level security;

create policy "students read their own promotion requests"
  on public.student_promotions for select to authenticated
  using (student_id = auth.uid() or public.is_catalog_admin());

create policy "students create their own pending promotion requests"
  on public.student_promotions for insert to authenticated
  with check (student_id = auth.uid() and status = 'pending');

create policy "students cancel their pending promotion requests"
  on public.student_promotions for update to authenticated
  using (student_id = auth.uid() and status = 'pending')
  with check (student_id = auth.uid() and status = 'cancelled');

create policy "admins review promotion requests"
  on public.student_promotions for update to authenticated
  using (public.is_catalog_admin())
  with check (public.is_catalog_admin());
