-- Extend the legacy/admin courses table with the same editable page model.
-- Existing course text and publication status are preserved.
ALTER TABLE public.courses
  ADD COLUMN IF NOT EXISTS pages_json jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.courses
  DROP CONSTRAINT IF EXISTS courses_pages_json_array_check;

ALTER TABLE public.courses
  ADD CONSTRAINT courses_pages_json_array_check
  CHECK (jsonb_typeof(pages_json) = 'array');

UPDATE public.courses
SET pages_json = jsonb_build_array(
  jsonb_build_object(
    'id', 'legacy-page-1',
    'position', 1,
    'format', 'A4',
    'blocks', jsonb_build_array(
      jsonb_build_object(
        'type', 'text',
        'text_fr', COALESCE(content_fr, ''),
        'text_en', COALESCE(content_en, content_fr, '')
      )
    )
  )
)
WHERE jsonb_array_length(pages_json) = 0
  AND (NULLIF(trim(COALESCE(content_fr, '')), '') IS NOT NULL
       OR NULLIF(trim(COALESCE(content_en, '')), '') IS NOT NULL);

CREATE INDEX IF NOT EXISTS courses_pages_updated_idx
  ON public.courses (updated_at DESC)
  WHERE status <> 'archived';
