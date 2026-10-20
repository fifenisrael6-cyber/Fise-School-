-- Restore catalog containers that were missed when new classroom/subject
-- mappings were added after the original chapter catalogue migration.
-- This is additive and idempotent. It copies headings only; it does not copy
-- courses, lessons, quizzes, assignments, media, or storage files.

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
),
new_catalogs AS (
  INSERT INTO public.curricula
    (subject_id, subsystem, sector, exam_level_id, series_id, specialty_id,
     title_fr, title_en, description_fr, description_en, is_active,
     verification_status, source_url, source_title, is_catalog_container)
  SELECT
    p.subject_id, p.subsystem, p.sector, p.exam_level_id, p.series_id, p.specialty_id,
    p.title_fr, p.title_en,
    'Catalogue restauré pour une salle/matière active. Cette fiche contient des titres de chapitres uniquement ; les cours et fichiers restent séparés.',
    'Restored catalogue for an active classroom/subject. This record contains chapter headings only; lessons and files remain separate.',
    true, 'pending_official_confirmation', p.index_url, p.index_title, true
  FROM prepared p
  WHERE NOT EXISTS (
    SELECT 1 FROM public.curricula old
    WHERE old.is_catalog_container
      AND old.is_active
      AND old.subject_id = p.subject_id
      AND old.subsystem = p.subsystem
      AND old.sector = p.sector
      AND old.exam_level_id IS NOT DISTINCT FROM p.exam_level_id
      AND old.series_id IS NOT DISTINCT FROM p.series_id
      AND old.specialty_id IS NOT DISTINCT FROM p.specialty_id
  )
  RETURNING id, subject_id, subsystem, sector, exam_level_id, series_id, specialty_id
),
empty_catalogs AS (
  SELECT cu.id, cu.subject_id, cu.subsystem, cu.sector,
         cu.exam_level_id, cu.series_id, cu.specialty_id
  FROM public.curricula cu
  WHERE cu.is_active
    AND cu.is_catalog_container
    AND NOT EXISTS (
      SELECT 1 FROM public.course_chapters ch
      WHERE ch.curriculum_id = cu.id AND ch.is_active
    )
),
targets AS (
  SELECT * FROM new_catalogs
  UNION
  SELECT * FROM empty_catalogs
),
eligible_sources AS (
  SELECT
    t.id AS target_id,
    src.id AS source_id,
    src.is_catalog_container AS source_is_catalog_container,
    src.title_fr AS source_title_fr,
    src.title_en AS source_title_en,
    src.created_at AS source_created_at,
    src.source_url AS curriculum_source_url,
    src.source_title AS curriculum_source_title,
    src.description_fr AS source_description_fr,
    s.name_fr AS subject_name_fr,
    s.name_en AS subject_name_en,
    el.level_name_fr AS source_level_fr,
    el.level_name_en AS source_level_en,
    sr.name_fr AS source_series_fr,
    sr.name_en AS source_series_en,
    sp.name_fr AS source_specialty_fr,
    sp.name_en AS source_specialty_en,
    concat_ws(' — ',
      NULLIF(trim(s.name_fr), ''),
      NULLIF(trim(el.level_name_fr), ''),
      NULLIF(trim(sr.name_fr), ''),
      NULLIF(trim(sp.name_fr), '')
    ) AS canonical_source_fr,
    concat_ws(' — ',
      NULLIF(trim(s.name_en), ''),
      NULLIF(trim(el.level_name_en), ''),
      NULLIF(trim(sr.name_en), ''),
      NULLIF(trim(sp.name_en), '')
    ) AS canonical_source_en,
    (
      lower(trim(coalesce(s.name_fr, ''))) IN (
        'anglais', 'français', 'histoire', 'éducation à la citoyenneté',
        'éducation physique et sportive', 'éducation artistique',
        'allemand', 'arabe', 'chinois', 'espagnol', 'italien', 'grec',
        'latin', 'langues et cultures nationales', 'langue vivante ii'
      )
      OR lower(trim(coalesce(s.name_en, ''))) IN (
        'english', 'english language', 'french', 'history',
        'citizenship education', 'physical education',
        'german', 'arabic', 'chinese', 'spanish', 'italian', 'greek',
        'latin', 'national languages and cultures', 'modern language ii'
      )
    ) AS common_across_series,
    CASE WHEN t.subsystem = 'anglophone'
      THEN 'https://www.minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en'
      ELSE 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels'
    END AS fallback_source_url,
    CASE WHEN t.subsystem = 'anglophone'
      THEN 'MINESEC — Syllabus for the Anglophone subsystem'
      ELSE 'MINESEC — Programmes officiels du sous-système francophone'
    END AS fallback_source_title
  FROM targets t
  JOIN public.curricula src
    ON src.id <> t.id
   AND src.subject_id = t.subject_id
   AND src.subsystem = t.subsystem
   AND src.sector = t.sector
   AND src.is_active
   AND src.exam_level_id IS NOT DISTINCT FROM t.exam_level_id
   AND (
     src.series_id IS NULL
     OR src.series_id IS NOT DISTINCT FROM t.series_id
     OR lower(trim(coalesce((SELECT s2.name_fr FROM public.subjects s2 WHERE s2.id = t.subject_id), ''))) IN (
       'anglais', 'français', 'histoire', 'éducation à la citoyenneté',
       'éducation physique et sportive', 'éducation artistique',
       'allemand', 'arabe', 'chinois', 'espagnol', 'italien', 'grec',
       'latin', 'langues et cultures nationales', 'langue vivante ii'
     )
   )
   AND (
     src.specialty_id IS NULL
     OR src.specialty_id IS NOT DISTINCT FROM t.specialty_id
     OR lower(trim(coalesce((SELECT s2.name_fr FROM public.subjects s2 WHERE s2.id = t.subject_id), ''))) IN (
       'anglais', 'français', 'histoire', 'éducation à la citoyenneté',
       'éducation physique et sportive', 'éducation artistique',
       'allemand', 'arabe', 'chinois', 'espagnol', 'italien', 'grec',
       'latin', 'langues et cultures nationales', 'langue vivante ii'
     )
   )
  JOIN public.subjects s ON s.id = src.subject_id
  LEFT JOIN public.exam_levels el ON el.id = src.exam_level_id
  LEFT JOIN public.series sr ON sr.id = src.series_id
  LEFT JOIN public.specialties sp ON sp.id = src.specialty_id
),
source_rows AS (
  -- Some legacy curricula store the chapter heading directly in title_fr/en.
  SELECT
    e.target_id,
    e.source_id,
    coalesce(NULLIF(trim(e.source_title_fr), ''), NULLIF(trim(e.source_title_en), '')) AS heading_fr,
    coalesce(NULLIF(trim(e.source_title_en), ''), NULLIF(trim(e.source_title_fr), '')) AS heading_en,
    e.source_created_at,
    0 AS source_kind,
    0 AS source_position,
    e.source_title_fr AS source_order_title,
    coalesce(
      NULLIF(e.curriculum_source_url, ''),
      substring(e.source_description_fr from '(https?://[^[:space:]<>]+)'),
      e.fallback_source_url
    ) AS heading_source_url,
    coalesce(NULLIF(e.curriculum_source_title, ''), e.fallback_source_title) AS heading_source_title
  FROM eligible_sources e
  WHERE NOT e.source_is_catalog_container
    AND length(trim(coalesce(e.source_title_fr, e.source_title_en, ''))) > 0
    AND lower(trim(coalesce(e.source_title_fr, ''))) <> lower(trim(e.canonical_source_fr))
    AND lower(trim(coalesce(e.source_title_en, ''))) <> lower(trim(e.canonical_source_en))
    AND coalesce(e.curriculum_source_title, '') NOT ILIKE '%structure provisoire%'

  UNION ALL

  -- Copy chapter headings from compatible, populated curricula/catalogues.
  SELECT
    e.target_id,
    e.source_id,
    coalesce(NULLIF(trim(ch.title_fr), ''), NULLIF(trim(ch.title_en), '')) AS heading_fr,
    coalesce(NULLIF(trim(ch.title_en), ''), NULLIF(trim(ch.title_fr), '')) AS heading_en,
    e.source_created_at,
    1 AS source_kind,
    ch.position AS source_position,
    e.source_title_fr AS source_order_title,
    coalesce(
      NULLIF(ch.source_url, ''),
      NULLIF(e.curriculum_source_url, ''),
      substring(e.source_description_fr from '(https?://[^[:space:]<>]+)'),
      e.fallback_source_url
    ) AS heading_source_url,
    coalesce(
      NULLIF(ch.source_title, ''),
      NULLIF(e.curriculum_source_title, ''),
      e.fallback_source_title
    ) AS heading_source_title
  FROM eligible_sources e
  JOIN public.course_chapters ch
    ON ch.curriculum_id = e.source_id AND ch.is_active
),
deduplicated AS (
  SELECT sr.*,
    row_number() OVER (
      PARTITION BY sr.target_id, lower(trim(sr.heading_fr))
      ORDER BY sr.source_kind, sr.source_created_at,
               sr.source_order_title, sr.source_position, sr.heading_en
    ) AS title_rank
  FROM source_rows sr
  WHERE length(trim(coalesce(sr.heading_fr, ''))) > 0
    AND length(trim(coalesce(sr.heading_en, ''))) > 0
    AND coalesce(sr.heading_source_title, '') NOT ILIKE '%structure provisoire%'
    AND lower(trim(sr.heading_fr)) !~ '^(chapitre[[:space:]]+[0-9]+|module[[:space:]]+[0-9]+|chapitre à définir|titre à confirmer|structure provisoire)$'
    AND NOT EXISTS (
      SELECT 1 FROM public.course_chapters existing
      WHERE existing.curriculum_id = sr.target_id
        AND existing.is_active
        AND lower(trim(existing.title_fr)) = lower(trim(sr.heading_fr))
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
          ORDER BY c.source_kind, c.source_created_at,
                   c.source_order_title, c.source_position, c.heading_fr
        ) AS next_position
  FROM chosen c
)
INSERT INTO public.course_chapters
  (curriculum_id, title_fr, title_en, description_fr, description_en,
   position, is_active, verification_status, source_url, source_title)
SELECT
  p.target_id,
  trim(p.heading_fr),
  trim(p.heading_en),
  'Titre récupéré d’un programme/matière compatible déjà présent dans le catalogue. Vérifier la correspondance exacte avec la classe et la série.',
  'Heading restored from a compatible existing subject syllabus. Verify the exact class/series mapping before official approval.',
  p.next_position,
  true,
  'pending_official_confirmation',
  p.heading_source_url,
  p.heading_source_title
FROM positioned p;
