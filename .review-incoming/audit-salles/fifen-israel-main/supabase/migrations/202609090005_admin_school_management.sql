-- Fise School: administrative school management hardening.
-- Existing migrations are intentionally left unchanged.

create or replace function public.validate_school_class_catalog_links()
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
    select subsystem, sector into level_subsystem, level_sector
    from public.exam_levels
    where id = new.exam_level_id and active;
    if not found then
      raise exception 'The exam level is not active';
    end if;
    if new.subsystem is distinct from level_subsystem
       or new.sector is distinct from level_sector then
      raise exception 'Class pathway does not match exam level';
    end if;
  end if;

  if new.series_id is not null and not exists (
    select 1 from public.exam_level_series
    where exam_level_id = new.exam_level_id and series_id = new.series_id and active
  ) then
    raise exception 'Series is not linked to the class exam level';
  end if;

  if new.specialty_id is not null and not exists (
    select 1 from public.exam_level_specialties
    where exam_level_id = new.exam_level_id and specialty_id = new.specialty_id and active
  ) then
    raise exception 'Specialty is not linked to the class exam level';
  end if;

  if new.sector = 'general' and new.specialty_id is not null then
    raise exception 'General classes cannot reference technical specialties';
  end if;
  if new.sector = 'technical' and new.series_id is not null then
    raise exception 'Technical classes cannot reference general series';
  end if;
  return new;
end;
$$;

drop trigger if exists school_classes_validate_catalog on public.school_classes;
create trigger school_classes_validate_catalog
before insert or update on public.school_classes
for each row execute function public.validate_school_class_catalog_links();

create or replace function public.validate_teacher_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  teacher_subsystem public.catalog_subsystem;
  teacher_sector public.catalog_sector;
  class_subsystem public.catalog_subsystem;
  class_sector public.catalog_sector;
begin
  if not public.check_profile_role(new.teacher_id, 'teacher') then
    raise exception 'Only teacher profiles can be assigned to classes';
  end if;
  select subsystem, sector into teacher_subsystem, teacher_sector
  from public.profiles where id = new.teacher_id;
  select subsystem, sector into class_subsystem, class_sector
  from public.school_classes where id = new.class_id and is_active;
  if not found then raise exception 'The class is not active'; end if;
  if teacher_subsystem is not null and teacher_subsystem is distinct from class_subsystem then
    raise exception 'Teacher subsystem is incompatible with the class';
  end if;
  if teacher_sector is not null and teacher_sector is distinct from class_sector then
    raise exception 'Teacher sector is incompatible with the class';
  end if;
  return new;
end;
$$;

drop trigger if exists class_teachers_validate on public.class_teachers;
create trigger class_teachers_validate
before insert or update on public.class_teachers
for each row execute function public.validate_teacher_assignment();

create or replace function public.validate_student_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  student_subsystem public.catalog_subsystem;
  student_sector public.catalog_sector;
  class_subsystem public.catalog_subsystem;
  class_sector public.catalog_sector;
begin
  if not public.check_profile_role(new.student_id, 'student') then
    raise exception 'Only student profiles can be assigned to classes';
  end if;
  select subsystem, sector into student_subsystem, student_sector
  from public.profiles where id = new.student_id;
  select subsystem, sector into class_subsystem, class_sector
  from public.school_classes where id = new.class_id and is_active;
  if not found then raise exception 'The class is not active'; end if;
  if student_subsystem is not null and student_subsystem is distinct from class_subsystem then
    raise exception 'Student subsystem is incompatible with the class';
  end if;
  if student_sector is not null and student_sector is distinct from class_sector then
    raise exception 'Student sector is incompatible with the class';
  end if;
  return new;
end;
$$;

drop trigger if exists class_students_validate on public.class_students;
create trigger class_students_validate
before insert or update on public.class_students
for each row execute function public.validate_student_assignment();

create index if not exists profiles_subsystem_sector_role_idx
  on public.profiles (role, subsystem, sector);
create index if not exists class_students_class_active_idx
  on public.class_students (class_id, is_active);
create index if not exists class_teachers_class_active_idx
  on public.class_teachers (class_id, is_active);
