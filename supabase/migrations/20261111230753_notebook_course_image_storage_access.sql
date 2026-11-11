-- Allow enrolled students to read images embedded in published legacy course pages.
-- Keep chapter-content item rules and require active class + subject membership.
DROP POLICY IF EXISTS "students read published chapter media files"
  ON storage.objects;

CREATE POLICY "students read published chapter media files"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'chapter-content'
  AND (
    EXISTS (
      SELECT 1
      FROM public.chapter_content_items ci
      WHERE ci.storage_path = objects.name
        AND ci.is_published
        AND ci.content_type IN ('video','pdf','image','audio')
        AND public.student_can_access_chapter(ci.chapter_id)
    )
    OR EXISTS (
      SELECT 1
      FROM public.chapter_content_items ci
      WHERE ci.source_pdf_path = objects.name
        AND ci.is_published
        AND ci.content_type = 'course'
        AND public.student_can_access_chapter_content(ci.id)
    )
    OR EXISTS (
      SELECT 1
      FROM public.chapter_content_items ci
      CROSS JOIN LATERAL jsonb_array_elements(ci.pages_json) AS page
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(page.value -> 'blocks', '[]'::jsonb)) AS block
      WHERE block.value ->> 'storage_path' = objects.name
        AND block.value ->> 'type' = 'image'
        AND ci.is_published
        AND ci.content_type = 'course'
        AND public.student_can_access_chapter_content(ci.id)
    )
    OR EXISTS (
      SELECT 1
      FROM public.courses c
      CROSS JOIN LATERAL jsonb_array_elements(c.pages_json) AS page
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(page.value -> 'blocks', '[]'::jsonb)) AS block
      WHERE block.value ->> 'storage_path' = objects.name
        AND block.value ->> 'type' = 'image'
        AND c.status = 'published'
        AND EXISTS (
          SELECT 1
          FROM public.class_students cs
          WHERE cs.class_id = c.class_id
            AND cs.student_id = auth.uid()
            AND cs.is_active
        )
        AND EXISTS (
          SELECT 1
          FROM public.class_subjects csub
          WHERE csub.class_id = c.class_id
            AND csub.subject_id = c.subject_id
            AND csub.is_active
        )
        AND (
          c.chapter_id IS NULL
          OR public.student_can_access_chapter(c.chapter_id)
        )
    )
  )
);
