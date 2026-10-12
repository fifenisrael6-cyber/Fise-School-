-- Fise School: create a chapter-title page for every active classroom/subject context.
-- This migration adds titles only. It does NOT insert courses, lessons, quizzes, or media.
ALTER TABLE public.curricula
  ADD COLUMN IF NOT EXISTS is_catalog_container boolean NOT NULL DEFAULT false;

-- Identify already-existing subject/class headings so we can keep their existing chapter IDs.
UPDATE public.curricula cu
SET is_catalog_container = true,
    source_url = COALESCE(cu.source_url,
      CASE WHEN cu.subsystem = 'anglophone'
        THEN 'https://www.minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en'
        ELSE 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels'
      END),
    source_title = COALESCE(cu.source_title,
      CASE WHEN cu.subsystem = 'anglophone'
        THEN 'MINESEC — Syllabus for the Anglophone subsystem'
        ELSE 'MINESEC — Programmes officiels du sous-système francophone'
      END)
FROM public.subjects s
LEFT JOIN public.exam_levels el ON el.id IS NOT NULL
WHERE cu.subject_id = s.id
  AND cu.subsystem = s.subsystem
  AND cu.sector = s.sector
  AND (
    cu.title_fr = concat_ws(' — ',
      NULLIF(trim(s.name_fr), ''),
      NULLIF(trim((SELECT max(e.level_name_fr) FROM public.exam_levels e WHERE e.id = cu.exam_level_id)), ''),
      NULLIF(trim((SELECT max(sr.name_fr) FROM public.series sr WHERE sr.id = cu.series_id)), ''),
      NULLIF(trim((SELECT max(sp.name_fr) FROM public.specialties sp WHERE sp.id = cu.specialty_id)), '')
    )
    OR cu.title_en = concat_ws(' — ',
      NULLIF(trim(s.name_en), ''),
      NULLIF(trim((SELECT max(e.level_name_en) FROM public.exam_levels e WHERE e.id = cu.exam_level_id)), ''),
      NULLIF(trim((SELECT max(sr.name_en) FROM public.series sr WHERE sr.id = cu.series_id)), ''),
      NULLIF(trim((SELECT max(sp.name_en) FROM public.specialties sp WHERE sp.id = cu.specialty_id)), '')
    )
  );

CREATE INDEX IF NOT EXISTS curricula_catalog_context_lookup_idx
  ON public.curricula
  (subject_id, subsystem, sector, exam_level_id, series_id, specialty_id, is_active);

-- Create one canonical chapter-list container for each active classroom/subject context.
WITH contexts AS (
  SELECT
    s.id AS subject_id,
    cl.subsystem,
    cl.sector,
    cl.exam_level_id,
    cl.series_id,
    cl.specialty_id,
    s.name_fr AS subject_fr,
    s.name_en AS subject_en,
    max(NULLIF(trim(el.level_name_fr), '')) AS level_fr,
    max(NULLIF(trim(el.level_name_en), '')) AS level_en,
    max(NULLIF(trim(cl.display_name), '')) AS class_display,
    max(NULLIF(trim(cl.name), '')) AS class_name,
    max(NULLIF(trim(sr.name_fr), '')) AS series_fr,
    max(NULLIF(trim(sr.name_en), '')) AS series_en,
    max(NULLIF(trim(sp.name_fr), '')) AS specialty_fr,
    max(NULLIF(trim(sp.name_en), '')) AS specialty_en
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
  GROUP BY
    s.id, cl.subsystem, cl.sector, cl.exam_level_id, cl.series_id,
    cl.specialty_id, s.name_fr, s.name_en
),
prepared AS (
  SELECT *,
    concat_ws(' — ',
      NULLIF(trim(subject_fr), ''),
      NULLIF(trim(coalesce(level_fr, class_display, class_name)), ''),
      NULLIF(trim(series_fr), ''),
      NULLIF(trim(specialty_fr), '')
    ) AS title_fr,
    concat_ws(' — ',
      NULLIF(trim(subject_en), ''),
      NULLIF(trim(coalesce(level_en, class_display, class_name)), ''),
      NULLIF(trim(series_en), ''),
      NULLIF(trim(specialty_en), '')
    ) AS title_en,
    CASE WHEN subsystem = 'anglophone'
      THEN 'https://www.minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en'
      ELSE 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels'
    END AS index_url,
    CASE WHEN subsystem = 'anglophone'
      THEN 'MINESEC — Syllabus for the Anglophone subsystem'
      ELSE 'MINESEC — Programmes officiels du sous-système francophone'
    END AS index_title
  FROM contexts
)
INSERT INTO public.curricula
  (subject_id, subsystem, sector, exam_level_id, series_id, specialty_id,
   title_fr, title_en, description_fr, description_en, is_active,
   verification_status, source_url, source_title, is_catalog_container)
SELECT
  p.subject_id, p.subsystem, p.sector, p.exam_level_id, p.series_id, p.specialty_id,
  p.title_fr, p.title_en,
  'Catalogue de chapitres : cette fiche contient uniquement les titres des chapitres. Les cours et fichiers seront ajoutés ultérieurement par l’administration.',
  'Chapter catalogue: this record holds chapter titles only. Lessons and files will be added later by the administrator.',
  true, 'pending_official_confirmation', p.index_url, p.index_title, true
FROM prepared p
WHERE NOT EXISTS (
  SELECT 1 FROM public.curricula old
  WHERE old.is_catalog_container
    AND old.subject_id = p.subject_id
    AND old.subsystem = p.subsystem
    AND old.sector = p.sector
    AND old.exam_level_id IS NOT DISTINCT FROM p.exam_level_id
    AND old.series_id IS NOT DISTINCT FROM p.series_id
    AND old.specialty_id IS NOT DISTINCT FROM p.specialty_id
);

-- Build page-title rows only from existing curriculum/topic headings and child chapter headings.
-- Generic "Subject — Class — Series" labels are containers, not chapter titles, so they are excluded.
WITH containers AS (
  SELECT cu.*
  FROM public.curricula cu
  WHERE cu.is_active AND cu.is_catalog_container
),
source_rows AS (
  SELECT
    target.id AS target_id,
    source.id AS source_id,
    source.title_fr,
    source.title_en,
    source.created_at AS source_created_at,
    0 AS source_kind,
    0 AS source_position,
    source.title_fr AS source_order_title,
    coalesce(
      NULLIF(source.source_url, ''),
      substring(source.description_fr from '(https?://[^[:space:]<>]+)'),
      CASE WHEN target.subsystem = 'anglophone'
        THEN 'https://www.minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en'
        ELSE 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels'
      END
    ) AS heading_source_url,
    coalesce(source.source_title,
      CASE WHEN target.subsystem = 'anglophone'
        THEN 'MINESEC — Syllabus for the Anglophone subsystem'
        ELSE 'MINESEC — Programmes officiels du sous-système francophone'
      END
    ) AS heading_source_title
  FROM containers target
  JOIN public.curricula source
    ON source.id <> target.id
   AND source.subject_id = target.subject_id
   AND source.subsystem = target.subsystem
   AND source.sector = target.sector
   AND source.exam_level_id IS NOT DISTINCT FROM target.exam_level_id
   AND (source.series_id IS NOT DISTINCT FROM target.series_id OR source.series_id IS NULL)
   AND (source.specialty_id IS NOT DISTINCT FROM target.specialty_id OR source.specialty_id IS NULL)
   AND source.is_active
  JOIN public.subjects s ON s.id = source.subject_id
  WHERE NOT source.is_catalog_container
    AND length(trim(source.title_fr)) > 0
    AND length(trim(source.title_en)) > 0
    AND lower(trim(source.title_fr)) <> lower(trim(concat_ws(' — ',
      NULLIF(trim(s.name_fr), ''),
      NULLIF(trim((SELECT max(e.level_name_fr) FROM public.exam_levels e WHERE e.id = source.exam_level_id)), ''),
      NULLIF(trim((SELECT max(sr.name_fr) FROM public.series sr WHERE sr.id = source.series_id)), ''),
      NULLIF(trim((SELECT max(sp.name_fr) FROM public.specialties sp WHERE sp.id = source.specialty_id)), '')
    )))
    AND lower(trim(source.title_en)) <> lower(trim(concat_ws(' — ',
      NULLIF(trim(s.name_en), ''),
      NULLIF(trim((SELECT max(e.level_name_en) FROM public.exam_levels e WHERE e.id = source.exam_level_id)), ''),
      NULLIF(trim((SELECT max(sr.name_en) FROM public.series sr WHERE sr.id = source.series_id)), ''),
      NULLIF(trim((SELECT max(sp.name_en) FROM public.specialties sp WHERE sp.id = source.specialty_id)), '')
    )))
  UNION ALL
  SELECT
    target.id AS target_id,
    source.id AS source_id,
    ch.title_fr,
    ch.title_en,
    source.created_at AS source_created_at,
    1 AS source_kind,
    ch.position AS source_position,
    source.title_fr AS source_order_title,
    coalesce(
      NULLIF(source.source_url, ''),
      substring(source.description_fr from '(https?://[^[:space:]<>]+)'),
      CASE WHEN target.subsystem = 'anglophone'
        THEN 'https://www.minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en'
        ELSE 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels'
      END
    ) AS heading_source_url,
    coalesce(source.source_title,
      CASE WHEN target.subsystem = 'anglophone'
        THEN 'MINESEC — Syllabus for the Anglophone subsystem'
        ELSE 'MINESEC — Programmes officiels du sous-système francophone'
      END
    ) AS heading_source_title
  FROM containers target
  JOIN public.curricula source
    ON source.id <> target.id
   AND source.subject_id = target.subject_id
   AND source.subsystem = target.subsystem
   AND source.sector = target.sector
   AND source.exam_level_id IS NOT DISTINCT FROM target.exam_level_id
   AND (source.series_id IS NOT DISTINCT FROM target.series_id OR source.series_id IS NULL)
   AND (source.specialty_id IS NOT DISTINCT FROM target.specialty_id OR source.specialty_id IS NULL)
   AND source.is_active
  JOIN public.course_chapters ch ON ch.curriculum_id = source.id AND ch.is_active
),
deduplicated AS (
  SELECT sr.*,
    row_number() OVER (
      PARTITION BY sr.target_id, lower(trim(sr.title_fr))
      ORDER BY sr.source_kind, sr.source_created_at, sr.source_order_title, sr.source_position, sr.title_en
    ) AS title_rank
  FROM source_rows sr
  WHERE length(trim(sr.title_fr)) > 0
    AND length(trim(sr.title_en)) > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.course_chapters existing
      WHERE existing.curriculum_id = sr.target_id
        AND lower(trim(existing.title_fr)) = lower(trim(sr.title_fr))
    )
),
chosen AS (
  SELECT * FROM deduplicated WHERE title_rank = 1
),
positioned AS (
  SELECT c.*,
    (SELECT coalesce(max(existing.position), 0)
       FROM public.course_chapters existing
      WHERE existing.curriculum_id = c.target_id)
      + row_number() OVER (
          PARTITION BY c.target_id
          ORDER BY c.source_created_at,
            coalesce(NULLIF((regexp_match(c.title_fr, '^[[:space:]]*Module[[:space:]]+([0-9]+)'))[1], '')::integer, 999999),
            c.source_order_title, c.source_kind, c.source_position, c.title_fr
        ) AS next_position
  FROM chosen c
)
INSERT INTO public.course_chapters
  (curriculum_id, title_fr, title_en, description_fr, description_en,
   position, is_active, verification_status, source_url, source_title)
SELECT
  p.target_id, trim(p.title_fr), trim(p.title_en),
  'Titre importé du catalogue de programmes existant. À confirmer à partir du document officiel correspondant.',
  'Title imported from the existing syllabus catalogue. Verify it against the matching official document.',
  p.next_position, true, 'pending_official_confirmation',
  p.heading_source_url, p.heading_source_title
FROM positioned p;

-- No rows are added to courses, lessons, chapter_content_items, assignments, or storage.
