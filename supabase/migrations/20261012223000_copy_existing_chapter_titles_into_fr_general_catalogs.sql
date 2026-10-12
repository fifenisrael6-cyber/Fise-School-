-- Copy existing legacy chapter headings into canonical chapter-list pages.
-- Titles only: do not copy courses, lessons, media, exercises, quizzes, or progress.
-- Safe to re-run: active chapter titles are deduplicated per target catalog page.
BEGIN;

WITH source_titles AS (
  SELECT DISTINCT ON (target.id, lower(trim(src_ch.title_fr)))
    target.id AS target_curriculum_id,
    src_ch.title_fr,
    src_ch.title_en,
    src_ch.description_fr,
    src_ch.description_en,
    src_ch.verification_status,
    src_ch.source_url,
    src_ch.source_title
  FROM public.curricula src
  JOIN public.exam_levels src_level ON src_level.id = src.exam_level_id
  JOIN public.course_chapters src_ch
    ON src_ch.curriculum_id = src.id AND src_ch.is_active
  JOIN public.curricula target
    ON target.is_catalog_container
   AND target.is_active
   AND target.subsystem = src.subsystem
   AND target.sector = src.sector
   AND target.subject_id = src.subject_id
   AND target.exam_level_id IS NOT DISTINCT FROM src.exam_level_id
   AND target.series_id IS NOT DISTINCT FROM src.series_id
   AND target.specialty_id IS NOT DISTINCT FROM src.specialty_id
  WHERE src.is_active
    AND NOT COALESCE(src.is_catalog_container, false)
    AND src.subsystem = 'francophone'
    AND src.sector = 'general'
    AND src_level.active
    AND src_level.subsystem = 'francophone'
    AND src_level.sector = 'general'
  ORDER BY target.id, lower(trim(src_ch.title_fr)),
           (src_ch.verification_status = 'verified') DESC,
           src_ch.position, src_ch.created_at
),
missing_titles AS (
  SELECT st.*,
    COALESCE((SELECT MAX(ch.position) FROM public.course_chapters ch
              WHERE ch.curriculum_id = st.target_curriculum_id), 0)
    + ROW_NUMBER() OVER (
        PARTITION BY st.target_curriculum_id
        ORDER BY lower(trim(st.title_fr)), st.title_fr
      ) AS next_position
  FROM source_titles st
  WHERE NOT EXISTS (
    SELECT 1 FROM public.course_chapters existing
    WHERE existing.curriculum_id = st.target_curriculum_id
      AND existing.is_active
      AND lower(trim(existing.title_fr)) = lower(trim(st.title_fr))
  )
)
INSERT INTO public.course_chapters
  (curriculum_id, title_fr, title_en, description_fr, description_en, position,
   is_active, verification_status, source_url, source_title)
SELECT target_curriculum_id, title_fr, title_en,
       COALESCE(description_fr, 'Titre récupéré depuis un programme déjà enregistré dans Fise School. Contenu pédagogique non copié.'),
       COALESCE(description_en, 'Title recovered from an existing Fise School curriculum. Teaching content was not copied.'),
       next_position, true,
       COALESCE(verification_status, 'pending_official_confirmation')::public.catalog_verification_status,
       source_url, source_title
FROM missing_titles;

COMMIT;