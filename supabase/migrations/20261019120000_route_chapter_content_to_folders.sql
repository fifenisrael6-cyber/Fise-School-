-- Give each chapter item a canonical destination folder. The server derives it
-- from content_type so teacher uploads cannot land in the wrong folder.
ALTER TABLE public.chapter_content_items
  ADD COLUMN IF NOT EXISTS folder_key text;

CREATE OR REPLACE FUNCTION public.set_chapter_content_folder_key()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.folder_key := CASE lower(trim(NEW.content_type))
    WHEN 'course' THEN 'course'
    WHEN 'pdf' THEN 'pdf'
    WHEN 'image' THEN 'images'
    WHEN 'audio' THEN 'audio'
    WHEN 'video' THEN 'video'
    ELSE NULL
  END;

  IF NEW.folder_key IS NULL THEN
    RAISE EXCEPTION 'Unsupported chapter content type: %', NEW.content_type
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS chapter_content_folder_key_before_write
  ON public.chapter_content_items;
CREATE TRIGGER chapter_content_folder_key_before_write
BEFORE INSERT OR UPDATE OF content_type, folder_key
ON public.chapter_content_items
FOR EACH ROW
EXECUTE FUNCTION public.set_chapter_content_folder_key();

UPDATE public.chapter_content_items
SET folder_key = CASE lower(trim(content_type))
  WHEN 'course' THEN 'course'
  WHEN 'pdf' THEN 'pdf'
  WHEN 'image' THEN 'images'
  WHEN 'audio' THEN 'audio'
  WHEN 'video' THEN 'video'
END
WHERE folder_key IS DISTINCT FROM CASE lower(trim(content_type))
  WHEN 'course' THEN 'course'
  WHEN 'pdf' THEN 'pdf'
  WHEN 'image' THEN 'images'
  WHEN 'audio' THEN 'audio'
  WHEN 'video' THEN 'video'
END;

ALTER TABLE public.chapter_content_items
  DROP CONSTRAINT IF EXISTS chapter_content_items_folder_key_check;
ALTER TABLE public.chapter_content_items
  ADD CONSTRAINT chapter_content_items_folder_key_check
  CHECK (folder_key IN ('course', 'pdf', 'images', 'audio', 'video'));

COMMENT ON COLUMN public.chapter_content_items.folder_key IS
  'Canonical chapter folder; derived server-side from content_type: course, pdf, images, audio, video. Smart QCM are stored in chapter_quizzes.';
