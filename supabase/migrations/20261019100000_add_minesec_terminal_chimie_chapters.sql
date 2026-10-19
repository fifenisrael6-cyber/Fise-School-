-- Add only chapter headings transcribed from the MINESEC Distance Learning Terminale chemistry page.
-- Additive and idempotent: never updates or deletes existing chapter/content records.
-- Titles remain pending confirmation because the portal page contains duplicate/mixed syllabus sections.
WITH seed(level_code, subsystem, sector, subject_name, chapter_title, source_url, seed_position) AS (
  VALUES
    ('fr_general_terminale', 'francophone', 'general', 'Chimie', 'Propriétés chimiques des alcools', 'https://minesec-distance.schoolfaqs.net/learn/chimie-1/terminale', 1),
    ('fr_general_terminale', 'francophone', 'general', 'Chimie', 'Les acides carboxyliques', 'https://minesec-distance.schoolfaqs.net/learn/chimie-1/terminale', 2),
    ('fr_general_terminale', 'francophone', 'general', 'Chimie', 'Les amines', 'https://minesec-distance.schoolfaqs.net/learn/chimie-1/terminale', 3),
    ('fr_general_terminale', 'francophone', 'general', 'Chimie', 'Les acides alpha-aminés', 'https://minesec-distance.schoolfaqs.net/learn/chimie-1/terminale', 4),
    ('fr_general_terminale', 'francophone', 'general', 'Chimie', 'Les acides alpha-aminés (suite)', 'https://minesec-distance.schoolfaqs.net/learn/chimie-1/terminale', 5),
    ('fr_general_terminale', 'francophone', 'general', 'Chimie', 'Stéréochimie', 'https://minesec-distance.schoolfaqs.net/learn/chimie-1/terminale', 6),
    ('fr_general_terminale', 'francophone', 'general', 'Chimie', 'Cinétique chimique', 'https://minesec-distance.schoolfaqs.net/learn/chimie-1/terminale', 7),
    ('fr_general_terminale', 'francophone', 'general', 'Chimie', 'Généralités sur les acides et les bases', 'https://minesec-distance.schoolfaqs.net/learn/chimie-1/terminale', 8),
    ('fr_general_terminale', 'francophone', 'general', 'Chimie', 'Force d’un acide et d’une base', 'https://minesec-distance.schoolfaqs.net/learn/chimie-1/terminale', 9)
),
matched AS (
  SELECT
    cu.id AS curriculum_id,
    trim(seed.chapter_title) AS chapter_title,
    seed.source_url,
    seed.seed_position
  FROM seed
  JOIN public.exam_levels el
    ON el.code = seed.level_code
   AND el.subsystem = seed.subsystem::public.catalog_subsystem
   AND el.sector = seed.sector::public.catalog_sector
   AND el.active = true
  JOIN public.subjects s
    ON s.subsystem = seed.subsystem::public.catalog_subsystem
   AND s.sector = seed.sector::public.catalog_sector
   AND s.is_active = true
   AND lower(trim(s.name_fr)) = lower(trim(seed.subject_name))
  JOIN public.curricula cu
    ON cu.subject_id = s.id
   AND cu.exam_level_id = el.id
   AND cu.subsystem = seed.subsystem::public.catalog_subsystem
   AND cu.sector = seed.sector::public.catalog_sector
   AND cu.is_catalog_container = true
   AND cu.is_active = true
),
deduplicated AS (
  SELECT m.*,
    row_number() OVER (
      PARTITION BY m.curriculum_id, lower(trim(m.chapter_title))
      ORDER BY m.seed_position
    ) AS seed_rank
  FROM matched m
  WHERE NOT EXISTS (
    SELECT 1 FROM public.course_chapters ch
    WHERE ch.curriculum_id = m.curriculum_id
      AND lower(trim(ch.title_fr)) = lower(trim(m.chapter_title))
  )
),
chosen AS (
  SELECT * FROM deduplicated WHERE seed_rank = 1
),
positioned AS (
  SELECT c.*,
    coalesce((
      SELECT max(ch.position)
      FROM public.course_chapters ch
      WHERE ch.curriculum_id = c.curriculum_id
    ), 0) + row_number() OVER (
      PARTITION BY c.curriculum_id ORDER BY c.seed_position, c.chapter_title
    ) AS new_position
  FROM chosen c
)
INSERT INTO public.course_chapters
  (curriculum_id, title_fr, title_en, description_fr, description_en,
   position, is_active, verification_status, source_url, source_title)
SELECT
  p.curriculum_id, p.chapter_title, p.chapter_title,
  'Titre relevé sur le portail MINESEC Distance Learning. La correspondance avec le programme officiel de la classe doit encore être confirmée.',
  'Heading transcribed from the MINESEC Distance Learning portal. Exact class-programme mapping still requires confirmation.',
  p.new_position, true, 'pending_official_confirmation', p.source_url,
  'MINESEC Distance Learning — Chimie, Terminale'
FROM positioned p;
