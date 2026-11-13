-- Allow administrators to create and publish course records without
-- impersonating a teacher. Teacher-owned courses remain subject to the
-- original role and classroom-assignment checks.

create or replace function public.validate_pedagogy_context()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  subject_subsystem public.catalog_subsystem;
  subject_sector public.catalog_sector;
  curriculum_subsystem public.catalog_subsystem;
  curriculum_sector public.catalog_sector;
  class_subsystem public.catalog_subsystem;
  class_sector public.catalog_sector;
  actor_is_admin boolean;
begin
  actor_is_admin := coalesce(public.is_admin(), false)
    or coalesce(public.is_catalog_admin(), false);

  if tg_table_name = 'curricula' then
    select subsystem, sector
      into subject_subsystem, subject_sector
      from public.subjects
      where id = new.subject_id and is_active;

    if not found
      or subject_subsystem is distinct from new.subsystem
      or subject_sector is distinct from new.sector then
      raise exception 'Curriculum context does not match its subject';
    end if;

  elsif tg_table_name = 'courses' then
    select subsystem, sector
      into curriculum_subsystem, curriculum_sector
      from public.curricula
      where id = new.curriculum_id and is_active;

    if not found then
      raise exception 'Curriculum is not active';
    end if;

    select subsystem, sector
      into subject_subsystem, subject_sector
      from public.subjects
      where id = new.subject_id and is_active;

    if not found
      or curriculum_subsystem is distinct from subject_subsystem
      or curriculum_sector is distinct from subject_sector then
      raise exception 'Course context does not match its curriculum and subject';
    end if;

    if not exists (
      select 1
      from public.course_chapters
      where id = new.chapter_id
        and curriculum_id = new.curriculum_id
        and is_active
    ) then
      raise exception 'Course chapter does not belong to its curriculum';
    end if;

    -- Administrators may publish courses directly. Non-admin users must
    -- still own the course as an assigned teacher.
    if not actor_is_admin then
      if not public.check_profile_role(new.teacher_id, 'teacher') then
        raise exception 'Only teachers or administrators can own courses';
      end if;
    end if;

    if new.class_id is not null then
      select subsystem, sector
        into class_subsystem, class_sector
        from public.school_classes
        where id = new.class_id and is_active;

      if not found
        or class_subsystem is distinct from subject_subsystem
        or class_sector is distinct from subject_sector then
        raise exception 'Course class context does not match its subject';
      end if;

      if not actor_is_admin
        and not public.is_teacher_assigned(new.class_id, new.teacher_id) then
        raise exception 'Teacher is not assigned to this class';
      end if;
    end if;

  elsif tg_table_name = 'lessons' then
    if not exists (
      select 1
      from public.courses
      where id = new.course_id and status <> 'archived'
    ) then
      raise exception 'Course is not available';
    end if;
  end if;

  return new;
end;
$$;
