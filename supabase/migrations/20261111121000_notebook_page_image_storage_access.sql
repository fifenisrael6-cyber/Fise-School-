-- Allow students to read image blocks embedded in a published notebook page.
-- Access remains scoped to the published parent course and authorized chapter.
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
      CROSS JOIN LATERAL jsonb_array_elements(
        COALESCE(page.value -> 'blocks', '[]'::jsonb)
      ) AS block
      WHERE block.value ->> 'storage_path' = objects.name
        AND block.value ->> 'type' = 'image'
        AND ci.is_published
        AND ci.content_type = 'course'
        AND public.student_can_access_chapter_content(ci.id)
    )
  )
);
