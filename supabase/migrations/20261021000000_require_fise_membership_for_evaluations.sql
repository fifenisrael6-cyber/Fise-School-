-- Require a joined teacher access code for teacher-created assignments/QCMs.
-- Admin/system assignments remain available under their existing class/program rules.
CREATE OR REPLACE FUNCTION public.student_can_access_assignment(target_assignment_id uuid, target_student_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  select target_student_id = auth.uid()
    and exists (
      select 1
      from public.assignments a
      join public.school_classes target_class on target_class.id = a.class_id
      left join public.courses course on course.id = a.course_id
      where a.id = target_assignment_id
        and a.status in ('published', 'closed')
        and (
          not exists (
            select 1 from public.profiles teacher_profile
            where teacher_profile.id = a.teacher_id
              and teacher_profile.role = 'teacher'
          )
          or exists (
            select 1 from public.teacher_fise_code_memberships fm
            where fm.student_id = target_student_id
              and fm.teacher_id = a.teacher_id
              and exists (
                select 1 from public.class_students active_class
                where active_class.student_id = fm.student_id
                  and active_class.class_id = fm.class_id
                  and active_class.is_active
              )
          )
        )
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

-- Prevent direct PDF/storage reads from bypassing the assignment row policy.
DROP POLICY IF EXISTS "authorized users read scheduled exam files" ON storage.objects;
CREATE POLICY "authorized users read scheduled exam files"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'assignment-files'
  AND EXISTS (
    SELECT 1
    FROM public.assignments a
    WHERE a.evaluation_file_path = objects.name
      AND (
        public.is_catalog_admin()
        OR a.teacher_id = auth.uid()
        OR (
          a.status IN ('published', 'closed')
          AND public.is_student_in_class(a.class_id, auth.uid())
          AND ((a.starts_at IS NULL) OR statement_timestamp() >= a.starts_at)
          AND ((a.due_at IS NULL) OR statement_timestamp() < a.due_at)
          AND (
            NOT EXISTS (
              SELECT 1 FROM public.profiles teacher_profile
              WHERE teacher_profile.id = a.teacher_id
                AND teacher_profile.role = 'teacher'
            )
            OR EXISTS (
              SELECT 1 FROM public.teacher_fise_code_memberships fm
              WHERE fm.student_id = auth.uid()
                AND fm.teacher_id = a.teacher_id
                AND EXISTS (
                  SELECT 1 FROM public.class_students active_class
                  WHERE active_class.student_id = fm.student_id
                    AND active_class.class_id = fm.class_id
                    AND active_class.is_active
                )
            )
          )
        )
      )
  )
);
