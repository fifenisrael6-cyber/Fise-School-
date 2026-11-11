-- Preserve the original PDF page range behind each AI-generated lesson.
-- Additive only: existing lesson text, publication state, media and RLS remain intact.
ALTER TABLE public.chapter_content_items
  ADD COLUMN IF NOT EXISTS source_pdf_path text,
  ADD COLUMN IF NOT EXISTS source_page_start integer,
  ADD COLUMN IF NOT EXISTS source_page_end integer;

ALTER TABLE public.chapter_content_items
  DROP CONSTRAINT IF EXISTS chapter_content_source_page_range_check;

ALTER TABLE public.chapter_content_items
  ADD CONSTRAINT chapter_content_source_page_range_check
  CHECK (
    (source_page_start IS NULL OR source_page_start >= 1)
    AND (source_page_end IS NULL OR source_page_end >= 1)
    AND (
      source_page_start IS NULL
      OR source_page_end IS NULL
      OR source_page_end >= source_page_start
    )
  );

CREATE INDEX IF NOT EXISTS chapter_content_source_pdf_lookup_idx
  ON public.chapter_content_items (source_pdf_path)
  WHERE content_type = 'course' AND is_published AND source_pdf_path IS NOT NULL;

-- Students may fetch the private original PDF only when it backs a published
-- lesson in a chapter they are already authorized to read.
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
        AND (
          public.student_can_access_chapter(ci.chapter_id)
          OR EXISTS (
            SELECT 1
            FROM public.chapter_content_item_chapters linked
            WHERE linked.content_item_id = ci.id
              AND public.student_can_access_chapter(linked.chapter_id)
          )
        )
    )
  )
);
