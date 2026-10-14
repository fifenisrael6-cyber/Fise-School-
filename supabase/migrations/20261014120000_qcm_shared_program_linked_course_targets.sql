-- Allow manually authored QCMs linked to a course to reach other classes
-- only when both classes share the exact active subject programme.
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
            select 1 from public.class_students exact_membership
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
          or (
            a.exam_id is null
            and coalesce(a.subject_id, course.subject_id) is not null
            and (
              a.course_id is null
              or exists (
                select 1
                from public.assignment_questions aq
                where aq.assignment_id = a.id
                  and aq.question_type = 'qcm'
              )
            )
            and exists (
              select 1
              from public.class_students membership
              join public.school_classes enrolled_class
                on enrolled_class.id = membership.class_id
              where membership.student_id = target_student_id
                and membership.is_active
                and public.classes_share_subject_program(
                  a.class_id,
                  enrolled_class.id,
                  coalesce(a.subject_id, course.subject_id)
                )
            )
          )
        )
    );
$function$;
