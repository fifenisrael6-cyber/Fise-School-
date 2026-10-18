-- Keep the live Supabase rule set reproducible from the repository.
-- Official exam schedule rows can be read before a teacher attaches the PDF.
-- A teacher may only attach the missing PDF to an admin-created schedule, without
-- changing any date, class, subject, result-release setting, status or ownership.
-- A standalone teacher QCM is visible to students when its questions exist.

create or replace function public.student_can_access_assignment(
  target_assignment_id uuid,
  target_student_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select target_student_id = auth.uid()
    and exists (
      select 1
      from public.assignments a
      join public.school_classes target_class on target_class.id = a.class_id
      left join public.courses course on course.id = a.course_id
      where a.id = target_assignment_id
        and a.status in ('published', 'closed')
        and (
          a.course_id is not null
          or (
            a.exam_id is not null
            and a.starts_at is not null
            and a.due_at is not null
            and a.due_at > a.starts_at
            and a.results_publish_at is not null
            and a.results_publish_at >= a.due_at
          )
          or (
            a.exam_id is null
            and exists (
              select 1 from public.assignment_questions aq
              where aq.assignment_id = a.id
            )
          )
        )
        and (
          exists (
            select 1
            from public.class_students exact_membership
            where exact_membership.class_id = a.class_id
              and exact_membership.student_id = target_student_id
              and exact_membership.is_active
          )
          or (
            target_class.series_id is null
            and target_class.specialty_id is null
            and target_class.exam_level_id is not null
            and coalesce(a.subject_id, course.subject_id) is not null
            and exists (
              select 1
              from public.class_students membership
              join public.school_classes enrolled_class
                on enrolled_class.id = membership.class_id
              where membership.student_id = target_student_id
                and membership.is_active
                and enrolled_class.exam_level_id = target_class.exam_level_id
                and enrolled_class.subsystem = target_class.subsystem
                and enrolled_class.sector = target_class.sector
                and exists (
                  select 1
                  from public.class_subjects cs
                  where cs.class_id = enrolled_class.id
                    and cs.subject_id = coalesce(a.subject_id, course.subject_id)
                    and cs.is_active
                )
            )
          )
        )
    );
$function$;

create or replace function public.validate_assignment_context()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_course public.courses%rowtype;
begin
  if auth.uid() is null then
    return new;
  end if;

  if new.course_id is null then
    if new.exam_id is not null
       or nullif(trim(coalesce(new.evaluation_file_path, '')), '') is not null then
      if public.is_catalog_admin() then
        null;
      elsif TG_OP = 'UPDATE'
         and old.exam_id is not null
         and new.exam_id is not distinct from old.exam_id
         and new.teacher_id = auth.uid()
         and new.teacher_id is not distinct from old.teacher_id
         and new.class_id is not distinct from old.class_id
         and new.subject_id is not distinct from old.subject_id
         and new.course_id is not distinct from old.course_id
         and new.lesson_id is not distinct from old.lesson_id
         and new.starts_at is not distinct from old.starts_at
         and new.due_at is not distinct from old.due_at
         and new.results_publish_at is not distinct from old.results_publish_at
         and new.status is not distinct from old.status
         and new.title_fr is not distinct from old.title_fr
         and new.title_en is not distinct from old.title_en
         and new.instructions_fr is not distinct from old.instructions_fr
         and new.instructions_en is not distinct from old.instructions_en
         and new.max_score is not distinct from old.max_score
         and new.published_at is not distinct from old.published_at
         and nullif(trim(coalesce(old.evaluation_file_path, '')), '') is null
         and nullif(trim(coalesce(new.evaluation_file_path, '')), '') is not null
         and public.teacher_can_manage_class(new.class_id, auth.uid()) then
        null;
      else
        raise exception 'Only an administrator can schedule an official exam; an assigned teacher may only attach its PDF';
      end if;

      if new.subject_id is null then
        raise exception 'An official exam must specify a subject';
      end if;

      if new.exam_id is not null then
        if new.starts_at is null or new.due_at is null then
          raise exception 'An official exam must have a start and end time';
        end if;
        if new.due_at <= new.starts_at then
          raise exception 'The deadline must be later than the start time';
        end if;
        if new.results_publish_at is null or new.results_publish_at < new.due_at then
          raise exception 'Results must have a release time at or after the exam end';
        end if;
      elsif new.status = 'published' and
            nullif(trim(coalesce(new.evaluation_file_path, '')), '') is null then
        raise exception 'A published standalone PDF evaluation must include its PDF file';
      end if;
    else
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
$function$;

drop policy if exists "teachers upload scheduled exam files" on storage.objects;
create policy "teachers upload scheduled exam files"
on storage.objects for insert to authenticated
with check (
  (select auth.uid()) is not null
  and bucket_id = 'assignment-files'
  and exists (
    select 1
    from public.assignments a
    where (storage.foldername(name))[1] = a.id::text
      and a.exam_id is not null
      and a.teacher_id = (select auth.uid())
      and a.status = 'published'
      and nullif(trim(coalesce(a.evaluation_file_path, '')), '') is null
      and public.teacher_can_manage_class(a.class_id, (select auth.uid()))
  )
);
