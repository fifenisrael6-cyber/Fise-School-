-- Page-based school notebook content. Additive and backward-compatible.
-- Existing course rows are preserved and represented as an initial editable page.
ALTER TABLE public.chapter_content_items
  ADD COLUMN IF NOT EXISTS pages_json jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.chapter_content_items
  DROP CONSTRAINT IF EXISTS chapter_content_pages_json_array_check;

ALTER TABLE public.chapter_content_items
  ADD CONSTRAINT chapter_content_pages_json_array_check
  CHECK (jsonb_typeof(pages_json) = 'array');

-- Backfill legacy written courses without overwriting their source text.
-- Each existing course starts as one A4 page; administrators can split it
-- into multiple pages and add images in the new page editor.
UPDATE public.chapter_content_items
SET pages_json = jsonb_build_array(
  jsonb_build_object(
    'id', 'legacy-page-1',
    'position', 1,
    'blocks', jsonb_build_array(
      jsonb_build_object(
        'type', 'text',
        'text_fr', COALESCE(body_text_fr, ''),
        'text_en', COALESCE(body_text_en, body_text_fr, '')
      )
    )
  )
)
WHERE content_type = 'course'
  AND jsonb_array_length(pages_json) = 0
  AND (NULLIF(trim(COALESCE(body_text_fr, '')), '') IS NOT NULL
       OR NULLIF(trim(COALESCE(body_text_en, '')), '') IS NOT NULL);

CREATE INDEX IF NOT EXISTS chapter_content_items_pages_updated_idx
  ON public.chapter_content_items (updated_at DESC)
  WHERE content_type = 'course';
