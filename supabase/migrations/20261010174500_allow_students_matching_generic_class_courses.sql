CREATE OR REPLACE FUNCTION public.is_course_student(target_course_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.courses c
    JOIN public.school_classes course_class
      ON course_class.id = c.class_id
    JOIN public.class_students cs
      ON cs.student_id = auth.uid()
     AND cs.is_active = true
    JOIN public.school_classes student_class
      ON student_class.id = cs.class_id
    WHERE c.id = target_course_id
      AND c.status = 'published'
      AND (
        course_class.id = student_class.id
        OR (
          course_class.series_id IS NULL
          AND course_class.specialty_id IS NULL
          AND course_class.exam_level_id = student_class.exam_level_id
          AND course_class.subsystem = student_class.subsystem
          AND course_class.sector = student_class.sector
        )
      )
  );
$function$;
