-- Backfill contextual curriculum records for every active classroom/subject pairing.
-- This deliberately does NOT fabricate chapter titles. All newly-created records stay
-- pending official source verification until the corresponding MINESEC/GCE syllabus is checked.

ALTER TABLE public.curricula
  ADD COLUMN IF NOT EXISTS verification_status public.catalog_verification_status
    NOT NULL DEFAULT 'pending_official_confirmation',
  ADD COLUMN IF NOT EXISTS source_url text,
  ADD COLUMN IF NOT EXISTS source_title text;

ALTER TABLE public.course_chapters
  ADD COLUMN IF NOT EXISTS verification_status public.catalog_verification_status
    NOT NULL DEFAULT 'pending_official_confirmation',
  ADD COLUMN IF NOT EXISTS source_url text,
  ADD COLUMN IF NOT EXISTS source_title text;

UPDATE public.curricula
SET verification_status = 'pending_official_confirmation',
    source_url = COALESCE(source_url,
      CASE WHEN subsystem = 'anglophone'
        THEN 'https://www.minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en'
        ELSE 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels'
      END),
    source_title = COALESCE(source_title,
      CASE WHEN subsystem = 'anglophone'
        THEN 'MINESEC — Programmes of study (Anglophone subsystem)'
        ELSE 'MINESEC — Programmes officiels (sous-système francophone)'
      END)
WHERE source_url IS NULL OR source_title IS NULL
   OR verification_status <> 'pending_official_confirmation';

UPDATE public.course_chapters ch
SET verification_status = 'pending_official_confirmation',
    source_url = COALESCE(ch.source_url, cu.source_url),
    source_title = COALESCE(ch.source_title, cu.source_title)
FROM public.curricula cu
WHERE cu.id = ch.curriculum_id
  AND (ch.source_url IS NULL OR ch.source_title IS NULL
       OR ch.verification_status <> 'pending_official_confirmation');

WITH catalog_context AS (
  SELECT
    s.id AS subject_id,
    cl.subsystem,
    cl.sector,
    cl.exam_level_id,
    cl.series_id,
    cl.specialty_id,
    s.name_fr AS subject_fr,
    s.name_en AS subject_en,
    MAX(COALESCE(NULLIF(trim(el.level_name_fr), ''), NULLIF(trim(cl.display_name), ''), cl.name)) AS level_fr,
    MAX(COALESCE(NULLIF(trim(el.level_name_en), ''), NULLIF(trim(cl.display_name), ''), cl.name)) AS level_en,
    MAX(sr.name_fr) AS series_fr,
    MAX(sr.name_en) AS series_en,
    MAX(sp.name_fr) AS specialty_fr,
    MAX(sp.name_en) AS specialty_en
  FROM public.class_subjects cs
  JOIN public.school_classes cl ON cl.id = cs.class_id
  JOIN public.subjects s ON s.id = cs.subject_id
  LEFT JOIN public.exam_levels el ON el.id = cl.exam_level_id
  LEFT JOIN public.series sr ON sr.id = cl.series_id
  LEFT JOIN public.specialties sp ON sp.id = cl.specialty_id
  WHERE cl.is_active
    AND cs.is_active
    AND s.is_active
    AND s.subsystem = cl.subsystem
    AND s.sector = cl.sector
  GROUP BY s.id, cl.subsystem, cl.sector, cl.exam_level_id,
           cl.series_id, cl.specialty_id, s.name_fr, s.name_en
),
prepared AS (
  SELECT
    *,
    concat_ws(' — ', NULLIF(trim(subject_fr), ''), NULLIF(trim(level_fr), ''),
              NULLIF(trim(series_fr), ''), NULLIF(trim(specialty_fr), '')) AS title_fr,
    concat_ws(' — ', NULLIF(trim(subject_en), ''), NULLIF(trim(level_en), ''),
              NULLIF(trim(series_en), ''), NULLIF(trim(specialty_en), '')) AS title_en,
    CASE WHEN subsystem = 'anglophone'
      THEN 'https://www.minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en'
      ELSE 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels'
    END AS official_index_url,
    CASE WHEN subsystem = 'anglophone'
      THEN 'MINESEC — Programmes of study (Anglophone subsystem)'
      ELSE 'MINESEC — Programmes officiels (sous-système francophone)'
    END AS official_index_title
  FROM catalog_context
)
INSERT INTO public.curricula
  (subject_id, subsystem, sector, exam_level_id, series_id, specialty_id,
   title_fr, title_en, description_fr, description_en, is_active,
   verification_status, source_url, source_title)
SELECT
  p.subject_id, p.subsystem, p.sector, p.exam_level_id, p.series_id, p.specialty_id,
  p.title_fr, p.title_en,
  'Fiche de classement liée au catalogue de salles. Les chapitres doivent être importés et vérifiés dans le programme officiel correspondant avant validation.',
  'Classroom-catalog mapping record. Chapters must be imported from and verified against the matching official syllabus before validation.',
  true, 'pending_official_confirmation', p.official_index_url, p.official_index_title
FROM prepared p
WHERE NOT EXISTS (
  SELECT 1
  FROM public.curricula cu
  WHERE cu.subject_id = p.subject_id
    AND cu.subsystem = p.subsystem
    AND cu.sector = p.sector
    AND cu.exam_level_id IS NOT DISTINCT FROM p.exam_level_id
    AND cu.series_id IS NOT DISTINCT FROM p.series_id
    AND cu.specialty_id IS NOT DISTINCT FROM p.specialty_id
);

CREATE INDEX IF NOT EXISTS curricula_class_context_idx
  ON public.curricula
  (exam_level_id, subsystem, sector, series_id, specialty_id, subject_id)
  WHERE is_active;
