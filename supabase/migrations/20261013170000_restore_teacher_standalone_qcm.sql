-- Restore teacher-created standalone QCMs while keeping official PDF exams admin-only.
-- The 2026-10-13 scheduled-exam guard unintentionally treated every assignment
-- without a course as an official exam, blocking QCMs created by qcm_builder_page.dart.
create or replace function public.validate_assignment_context()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_course public.courses%rowtype;
begin
  -- Trusted migrations/service-role writes may not carry an end-user JWT.
  if auth.uid() is null then
    return new;
  end if;

  if new.course_id is null then
    -- Official scheduled PDF exams are course-less, but must be created by an
    -- administrator and carry the complete exam window and publication data.
    if new.exam_id is not null
       or nullif(trim(coalesce(new.evaluation_file_path, '')), '') is not null then
      if not public.is_catalog_admin() then
        raise exception 'Only an administrator can schedule an official exam without a course';
      end if;
      if new.subject_id is null then
        raise exception 'An official exam must specify a subject';
      end if;
      if new.status = 'published' then
        if nullif(trim(coalesce(new.evaluation_file_path, '')), '') is null then
          raise exception 'A published official exam must include its PDF file';
        end if;
        if new.starts_at is null or new.due_at is null then
          raise exception 'A published official exam must have a start and end time';
        end if;
        if new.results_publish_at is null or new.results_publish_at < new.due_at then
          raise exception 'Results must have a release time at or after the exam end';
        end if;
      end if;
    else
      -- A teacher QCM can be linked to a class and subject even when no single
      -- published course matches. It is not an official PDF exam.
      if not public.is_admin() and (
        new.teacher_id is distinct from auth.uid()
        or not public.teacher_can_manage_class(new.class_id, auth.uid())
      ) then
        raise exception 'Teacher is not assigned to the selected class';
      end if;
      if new.subject_id is null then
        raise exception 'A standalone teacher QCM must specify a subject';
      end if;
    end if;

    if new.subject_id is null or not exists (
      select 1
      from public.class_subjects cs
      where cs.class_id = new.class_id
        and cs.subject_id = new.subject_id
        and cs.is_active
    ) then
      raise exception 'The selected subject is not assigned to this classroom';
    end if;

    if new.starts_at is not null and new.due_at is not null
       and new.due_at <= new.starts_at then
      raise exception 'The deadline must be later than the start time';
    end if;
    return new;
  end if;

  -- Course-linked assignments keep the existing class, owner and lesson checks.
  select * into v_course
  from public.courses
  where id = new.course_id;

  if not found or v_course.status = 'archived' then
    raise exception 'Assignment course is not available';
  end if;
  if new.class_id is distinct from v_course.class_id then
    raise exception 'Assignment class must match the course class';
  end if;
  if new.teacher_id is distinct from v_course.teacher_id and not public.is_admin() then
    raise exception 'Assignment teacher must own the selected course';
  end if;
  if not public.is_admin()
     and not public.teacher_can_manage_class(new.class_id, new.teacher_id) then
    raise exception 'Teacher is not assigned to the selected class';
  end if;
  if new.lesson_id is not null and not exists (
    select 1 from public.lessons l
    where l.id = new.lesson_id and l.course_id = new.course_id
  ) then
    raise exception 'Assignment lesson must belong to the selected course';
  end if;
  if new.starts_at is not null and new.due_at is not null
     and new.due_at <= new.starts_at then
    raise exception 'The deadline must be later than the start time';
  end if;
  return new;
end;
$$;
