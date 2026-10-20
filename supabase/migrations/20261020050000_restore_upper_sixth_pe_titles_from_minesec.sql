-- Restore available MINESEC portal chapter headings for anglophone
-- General Education, Upper Sixth Physical Education and Sports.
-- The source page does not publish a series-specific split, so keep titles
-- pending official confirmation for Arts/Science catalogue mapping.
-- Idempotent: only fills currently empty catalogue containers.

WITH headings(position, title_fr, title_en) AS (
  VALUES
    (1, 'L’individu par rapport à lui-même', 'The individual in relation to himself'),
    (2, 'L’individu par rapport à son environnement physique', 'The individual in relation to their physical environment')
),
targets AS (
  SELECT cu.id AS curriculum_id
  FROM public.curricula cu
  JOIN public.subjects s ON s.id = cu.subject_id
  JOIN public.exam_levels el ON el.id = cu.exam_level_id
  WHERE cu.is_active
    AND cu.is_catalog_container
    AND cu.subsystem = 'anglophone'
    AND cu.sector = 'general'
    AND lower(el.level_name_fr) LIKE '%upper sixth%'
    AND (lower(trim(coalesce(s.name_en,''))) = 'physical education'
         OR lower(trim(coalesce(s.name_fr,''))) = 'éducation physique')
    AND NOT EXISTS (
      SELECT 1 FROM public.course_chapters ch
      WHERE ch.curriculum_id = cu.id AND ch.is_active
    )
)
INSERT INTO public.course_chapters
  (curriculum_id, title_fr, title_en, description_fr, description_en,
   position, is_active, verification_status, source_url, source_title)
SELECT
  t.curriculum_id, h.title_fr, h.title_en,
  'Intitulé repris de la page MINESEC Distance Learning Upper Sixth. Répartition exacte par série à confirmer.',
  'Heading taken from the MINESEC Distance Learning Upper Sixth page. Exact series-specific mapping remains pending confirmation.',
  h.position, true, 'pending_official_confirmation',
  'https://minesec.schoolfaqs.net/learn/physical-education-and-sports/uppersixth',
  'MINESEC Distance Learning — Physical Education and Sports — Upper Sixth'
FROM targets t
CROSS JOIN headings h;
