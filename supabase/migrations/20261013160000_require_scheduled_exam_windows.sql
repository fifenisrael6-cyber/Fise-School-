-- Require complete scheduling metadata before an official exam can be published.
create or replace function public.validate_assignment_context()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_course public.courses%rowtype;
begin
  -- Trusted database migrations/service-role writes have no end-user JWT.
  if auth.uid() is null then return new; end if;
  if new.course_id is null then
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
    if not exists (
      select 1 from public.class_subjects cs
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
$$;

create or replace function public.student_can_access_assignment(
  target_assignment_id uuid,
  target_student_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
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
            a.starts_at is not null
            and a.due_at is not null
            and a.results_publish_at is not null
            and a.results_publish_at >= a.due_at
            and nullif(trim(coalesce(a.evaluation_file_path, '')), '') is not null
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
$$;

-- Preserve existing rows, but keep invalid published official exams hidden until an admin
-- assigns a real window, a PDF and a result-release date. Nothing is deleted.
update public.assignments
set status = 'draft'
where course_id is null
  and status = 'published'
  and (
    starts_at is null
    or due_at is null
    or nullif(trim(coalesce(evaluation_file_path, '')), '') is null
    or results_publish_at is null
    or results_publish_at < due_at
  );

update public.assignments
set results_publish_at = due_at
where results_publish_at is null
  and due_at is not null;

-- Let grading publication update a submission already marked corrected without exposing
-- the private grade early. Publication is still restricted by results_publish_at.
create or replace function public.publish_due_assignment_results()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer := 0;
begin
  with due as (
    select g.submission_id, g.score, g.feedback_fr, g.feedback_en
    from public.assignment_private_grades g
    join public.assignments a on a.id = g.assignment_id
    where g.status = 'graded'
      and g.published_at is null
      and a.results_publish_at is not null
      and a.results_publish_at <= statement_timestamp()
  )
  update public.assignment_submissions s
  set score = due.score,
      teacher_feedback_fr = due.feedback_fr,
      teacher_feedback_en = due.feedback_en,
      corrected_at = statement_timestamp(),
      status = 'corrected',
      updated_at = statement_timestamp()
  from due
  where s.id = due.submission_id
    and s.status in ('submitted', 'corrected');

  get diagnostics affected = row_count;

  update public.assignment_answers aa
  set is_correct = (detail.value->>'is_correct')::boolean,
      points_awarded = nullif(detail.value->>'points_awarded', '')::numeric,
      teacher_feedback_fr = detail.value->>'feedback_fr',
      teacher_feedback_en = detail.value->>'feedback_en',
      updated_at = statement_timestamp()
  from public.assignment_private_grades g
  join public.assignments a on a.id = g.assignment_id
  cross join lateral jsonb_array_elements(g.details) as detail(value)
  where g.submission_id = aa.submission_id
    and g.status = 'graded'
    and g.published_at is null
    and a.results_publish_at is not null
    and a.results_publish_at <= statement_timestamp()
    and aa.question_id::text = detail.value->>'question_id';

  update public.assignment_private_grades g
  set status = 'published', published_at = statement_timestamp(), updated_at = statement_timestamp()
  from public.assignments a
  where a.id = g.assignment_id
    and g.status = 'graded'
    and g.published_at is null
    and a.results_publish_at is not null
    and a.results_publish_at <= statement_timestamp();

  return affected;
end;
$$;

revoke all on function public.publish_due_assignment_results() from public, anon;
grant execute on function public.publish_due_assignment_results() to authenticated, service_role;
