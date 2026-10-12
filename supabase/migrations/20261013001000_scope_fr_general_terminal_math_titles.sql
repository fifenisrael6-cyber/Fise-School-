-- Terminale's 19 advanced Mathematics topics are sourced for the scientific syllabus,
-- not for A/AC/BIL/TI literary or technical-information series.
-- Keep existing chapter IDs and any published content intact; only hide wrongly scoped title rows.
BEGIN;

UPDATE public.course_chapters ch
SET is_active = FALSE,
    updated_at = now()
FROM public.curricula c
JOIN public.exam_levels el ON el.id = c.exam_level_id
JOIN public.subjects s ON s.id = c.subject_id
JOIN public.series sr ON sr.id = c.series_id
WHERE ch.curriculum_id = c.id
  AND c.is_catalog_container IS TRUE
  AND c.is_active IS TRUE
  AND c.subsystem = 'francophone'
  AND c.sector = 'general'
  AND el.code = 'fr_general_terminale'
  AND s.code = 'mathematiques'
  AND lower(sr.code) IN ('a1','a2','a3','a4','a5','ac','bil','ti')
  AND ch.is_active IS TRUE
  AND ch.source_title = 'MINESEC Distance Learning — Mathématiques, Terminale'
  AND ch.verification_status = 'pending_official_confirmation';

COMMIT;
