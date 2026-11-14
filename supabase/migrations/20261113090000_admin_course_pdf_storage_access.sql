-- Allow catalog administrators to manage private course PDF files.
-- Student reads remain restricted to members of the corresponding course.
DROP POLICY IF EXISTS "course members read course resources storage"
  ON storage.objects;
CREATE POLICY "course members read course resources storage"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'course-resources'
  AND (
    public.is_catalog_admin()
    OR public.is_course_student(((storage.foldername(name))[1])::uuid)
    OR EXISTS (
      SELECT 1
      FROM public.courses c
      WHERE c.id = ((storage.foldername(name))[1])::uuid
        AND c.teacher_id = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS "course owners upload resources storage"
  ON storage.objects;
CREATE POLICY "course owners upload resources storage"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'course-resources'
  AND (
    public.is_catalog_admin()
    OR EXISTS (
      SELECT 1
      FROM public.courses c
      WHERE c.id = ((storage.foldername(name))[1])::uuid
        AND c.teacher_id = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS "course owners update resources storage"
  ON storage.objects;
CREATE POLICY "course owners update resources storage"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'course-resources'
  AND (
    public.is_catalog_admin()
    OR EXISTS (
      SELECT 1
      FROM public.courses c
      WHERE c.id = ((storage.foldername(name))[1])::uuid
        AND c.teacher_id = auth.uid()
    )
  )
)
WITH CHECK (
  bucket_id = 'course-resources'
  AND (
    public.is_catalog_admin()
    OR EXISTS (
      SELECT 1
      FROM public.courses c
      WHERE c.id = ((storage.foldername(name))[1])::uuid
        AND c.teacher_id = auth.uid()
    )
  )
);

DROP POLICY IF EXISTS "course owners delete resources storage"
  ON storage.objects;
CREATE POLICY "course owners delete resources storage"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'course-resources'
  AND (
    public.is_catalog_admin()
    OR EXISTS (
      SELECT 1
      FROM public.courses c
      WHERE c.id = ((storage.foldername(name))[1])::uuid
        AND c.teacher_id = auth.uid()
    )
  )
);
