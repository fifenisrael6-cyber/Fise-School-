-- Restore missing chapter headings for Francophone general-education
-- Sciences catalogues from the MINESEC Distance Learning pages.
-- A title is added only when its exact catalogue container is still empty.
-- The set is shared because the public portal page does not expose per-series
-- splits; keep the rows pending confirmation rather than claiming a split.
-- No lessons, courses, QCM, documents, or media are inserted.

WITH seconde_titles(position, title_fr, title_en) AS (
  VALUES
    (1, 'Nutrition et organisation des végétaux chlorophylliens', 'Nutrition and organization of chlorophyll-bearing plants'),
    (2, 'L’activité photosynthétique : la production végétale', 'Photosynthetic activity and plant production'),
    (3, 'Organisation de la vie sociale chez les invertébrés : notion d’insectes alimentaires', 'Social organization in invertebrates and edible insects'),
    (4, 'Plan d’organisation des vertébrés', 'Organization plan of vertebrates'),
    (5, 'Génétique et hérédité humaines : transmission de l’information génétique', 'Human genetics and heredity: transmission of genetic information'),
    (6, 'La respiration', 'Respiration'),
    (7, 'Adaptations cardio-respiratoires et vasculaires au cours d’un effort physique', 'Cardiorespiratory and vascular adaptations during physical effort'),
    (8, 'L’excrétion urinaire', 'Urinary excretion'),
    (9, 'Perturbations du système immunitaire', 'Disorders of the immune system'),
    (10, 'Quelques maladies tropicales', 'Selected tropical diseases'),
    (11, 'La planète Terre', 'Planet Earth'),
    (12, 'Réchauffement climatique', 'Global warming'),
    (13, 'Étude des caractéristiques physico-chimiques et des caractères adaptatifs de quelques écosystèmes terrestres', 'Physicochemical characteristics and adaptive traits of selected terrestrial ecosystems'),
    (14, 'Les déchets de l’environnement de l’Homme', 'Waste in the human environment'),
    (15, 'Le génie génétique', 'Genetic engineering')
),
premiere_titles(position, title_fr, title_en) AS (
  VALUES
    (1, 'Quelques voies de régénération de l’énergie par les organismes', 'Ways organisms regenerate energy'),
    (2, 'Dépense énergétique des organismes', 'Energy expenditure in organisms'),
    (3, 'Les accidents cardiovasculaires', 'Cardiovascular accidents'),
    (4, 'Immunologie', 'Immunology'),
    (5, 'Éducation nutritionnelle', 'Nutrition education'),
    (6, 'La santé reproductive : problèmes liés à la santé reproductive des jeunes', 'Reproductive health: issues affecting young people'),
    (7, 'Le rayonnement solaire et ses influences à la surface de la Terre', 'Solar radiation and its effects at the Earth’s surface'),
    (8, 'L’altération des roches', 'Rock weathering'),
    (9, 'La structure et l’énergie interne de la Terre', 'The structure and internal energy of the Earth'),
    (10, 'Les mouvements des plaques lithosphériques', 'Movements of lithospheric plates'),
    (11, 'Flux d’énergie et cycle du carbone dans les écosystèmes', 'Energy flow and the carbon cycle in ecosystems'),
    (12, 'Éducation environnementale', 'Environmental education'),
    (13, 'La biotechnologie', 'Biotechnology'),
    (14, 'Identité biologique des organismes', 'Biological identity of organisms'),
    (15, 'Le renouvellement moléculaire et le code génétique', 'Molecular renewal and the genetic code'),
    (16, 'La catalyse enzymatique', 'Enzymatic catalysis'),
    (17, 'L’énergétique biologique', 'Biological energetics'),
    (18, 'La conversion de l’énergie lumineuse en énergie chimique', 'Conversion of light energy into chemical energy'),
    (19, 'Le flux d’énergie et les cycles du carbone et de l’azote dans les écosystèmes', 'Energy flow and the carbon and nitrogen cycles in ecosystems')
),
target_catalogues AS (
  SELECT cu.id AS curriculum_id,
         CASE
           WHEN lower(el.level_name_fr) LIKE '%seconde%' THEN 'seconde'
           WHEN lower(el.level_name_fr) LIKE '%première%' THEN 'premiere'
           ELSE NULL
         END AS level_key,
         CASE
           WHEN lower(el.level_name_fr) LIKE '%seconde%' THEN 'https://minesec.schoolfaqs.net/learn/sciences/seconde'
           WHEN lower(el.level_name_fr) LIKE '%première%' THEN 'https://minesec.schoolfaqs.net/learn/sciences/premiere'
           ELSE NULL
         END AS source_url,
         CASE
           WHEN lower(el.level_name_fr) LIKE '%seconde%' THEN 'MINESEC Distance Learning — Sciences — Seconde'
           WHEN lower(el.level_name_fr) LIKE '%première%' THEN 'MINESEC Distance Learning — Sciences — Première'
           ELSE NULL
         END AS source_title
  FROM public.curricula cu
  JOIN public.subjects s ON s.id = cu.subject_id
  JOIN public.exam_levels el ON el.id = cu.exam_level_id
  WHERE cu.is_active
    AND cu.is_catalog_container
    AND cu.subsystem = 'francophone'
    AND cu.sector = 'general'
    AND lower(trim(s.name_fr)) = 'sciences'
    AND (lower(el.level_name_fr) LIKE '%seconde%'
         OR lower(el.level_name_fr) LIKE '%première%')
    AND NOT EXISTS (
      SELECT 1 FROM public.course_chapters ch
      WHERE ch.curriculum_id = cu.id AND ch.is_active
    )
),
all_titles AS (
  SELECT 'seconde'::text AS level_key, position, title_fr, title_en FROM seconde_titles
  UNION ALL
  SELECT 'premiere'::text AS level_key, position, title_fr, title_en FROM premiere_titles
)
INSERT INTO public.course_chapters
  (curriculum_id, title_fr, title_en, description_fr, description_en,
   position, is_active, verification_status, source_url, source_title)
SELECT
  t.curriculum_id,
  titles.title_fr,
  titles.title_en,
  'Intitulé repris de la page MINESEC Distance Learning correspondant au niveau. Répartition exacte par série à confirmer avant validation définitive.',
  'Heading taken from the matching MINESEC Distance Learning level page. Exact series-specific mapping remains pending confirmation.',
  titles.position,
  true,
  'pending_official_confirmation',
  t.source_url,
  t.source_title
FROM target_catalogues t
JOIN all_titles titles ON titles.level_key = t.level_key
WHERE t.source_url IS NOT NULL;
