-- Seed only the verifiable chapter/topic headings available on MINESEC's official Distance Learning portal.
-- The inserted records are title-only; no course/lesson body, quiz, assignment or media file is created.
WITH seed(level_code, subsystem, sector, subject_field, subject_name, chapter_title, source_url, seed_position) AS (
  VALUES
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Physical quantities', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 1),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Physical quantities (Continued)', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 2),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Temperature', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 3),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Kinematics', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 4),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Energy Transfer', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 5),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Dynamics and force', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 6),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Newton’s Laws of motion', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 7),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Newton’s Laws of motion and momentum', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 8),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Electrical energy', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 9),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Work, energy and power', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 10),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Circular motion', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 11),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Simple harmonic motion', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 12),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Solids and liquids', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 13),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Energy resources and environmental Physics', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 14),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Physics', 'Gases and thermodynamics', 'https://minesec-distance.schoolfaqs.net/learn/physics/lowersixth', 15),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Chemistry', 'The Mole Concept', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/lowersixth', 1),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Chemistry', 'Atomic Structure and Related Patterns in the Periodic Table', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/lowersixth', 2),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Chemistry', 'Bonding, Structure and Intermolecular Forces', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/lowersixth', 3),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Chemistry', 'Organic Chemistry: Fundamentals and the chemistry of hydrocarbons', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/lowersixth', 4),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Chemistry', 'Thermochemistry', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/lowersixth', 5),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Chemistry', 'Descriptive inorganic chemistry: modern periodic table, periodicity and s-block', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/lowersixth', 6),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Chemistry', 'Raoult''s Law and Phase equilibria', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/lowersixth', 7),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Biology', 'Understanding Biology', 'https://minesec-distance.schoolfaqs.net/learn/biology/lowersixth', 1),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Biology', 'Biomolecules', 'https://minesec-distance.schoolfaqs.net/learn/biology/lowersixth', 2),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Biology', 'Enzymes', 'https://minesec-distance.schoolfaqs.net/learn/biology/lowersixth', 3),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Biology', 'Cytology', 'https://minesec-distance.schoolfaqs.net/learn/biology/lowersixth', 4),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Biology', 'Cell Energy', 'https://minesec-distance.schoolfaqs.net/learn/biology/lowersixth', 5),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Biology', 'Cell Growth and Division', 'https://minesec-distance.schoolfaqs.net/learn/biology/lowersixth', 6),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Biology', 'Histology', 'https://minesec-distance.schoolfaqs.net/learn/biology/lowersixth', 7),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Mathematics', 'Theory of quadratic functions and quadratic equations', 'https://minesec-distance.schoolfaqs.net/learn/mathematics/lowersixth', 1),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Mathematics', 'Vectors', 'https://minesec-distance.schoolfaqs.net/learn/mathematics/lowersixth', 2),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Mathematics', 'Calculus 1 (Limits and Differentiation)', 'https://minesec-distance.schoolfaqs.net/learn/mathematics/lowersixth', 3),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Geography', 'The Atmosphere as a Centre of Weather and Climate', 'https://minesec-distance.schoolfaqs.net/learn/geography/lowersixth', 1),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Geography', 'Energy in the Atmosphere', 'https://minesec-distance.schoolfaqs.net/learn/geography/lowersixth', 2),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Economics', 'Introductory Ideas', 'https://minesec-distance.schoolfaqs.net/learn/economics/lowersixth', 1),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Economics', 'The Economic problems', 'https://minesec-distance.schoolfaqs.net/learn/economics/lowersixth', 2),
('en_general_lower_sixth', 'anglophone', 'general', 'en', 'Further Mathematics', 'DIVISION AND EUCLIDEAN ALGORITHMS', 'https://minesec-distance.schoolfaqs.net/learn/further-mathematics/lowersixth', 1),
('en_general_form_1', 'anglophone', 'general', 'en', 'Mathematics', 'Numbers and Numerals', 'https://minesec-distance.schoolfaqs.net/learn/mathematics/form-one', 1),
('en_general_form_1', 'anglophone', 'general', 'en', 'Mathematics', 'The set of natural numbers and Number bases', 'https://minesec-distance.schoolfaqs.net/learn/mathematics/form-one', 2),
('en_general_form_1', 'anglophone', 'general', 'en', 'Physics', 'Introduction to sciences', 'https://minesec-distance.schoolfaqs.net/learn/physics/form-one', 1),
('en_general_form_1', 'anglophone', 'general', 'en', 'Physics', 'Scientific contributions and discoveries', 'https://minesec-distance.schoolfaqs.net/learn/physics/form-one', 2),
('en_general_form_1', 'anglophone', 'general', 'en', 'Physics', 'Introduction to Physics', 'https://minesec-distance.schoolfaqs.net/learn/physics/form-one', 3),
('en_general_form_1', 'anglophone', 'general', 'en', 'Physics', 'Basic laboratory equipment', 'https://minesec-distance.schoolfaqs.net/learn/physics/form-one', 4),
('en_general_form_1', 'anglophone', 'general', 'en', 'Physics', 'Safety laboratory rules', 'https://minesec-distance.schoolfaqs.net/learn/physics/form-one', 5),
('en_general_form_1', 'anglophone', 'general', 'en', 'Physics', 'Introduction to measurement', 'https://minesec-distance.schoolfaqs.net/learn/physics/form-one', 6),
('en_general_form_1', 'anglophone', 'general', 'en', 'Physics', 'Physical quantities', 'https://minesec-distance.schoolfaqs.net/learn/physics/form-one', 7),
('en_general_form_1', 'anglophone', 'general', 'en', 'Physics', 'Matter', 'https://minesec-distance.schoolfaqs.net/learn/physics/form-one', 8),
('en_general_form_1', 'anglophone', 'general', 'en', 'Physics', 'States of matter', 'https://minesec-distance.schoolfaqs.net/learn/physics/form-one', 9),
('en_general_form_1', 'anglophone', 'general', 'en', 'Physics', 'Measurement of length', 'https://minesec-distance.schoolfaqs.net/learn/physics/form-one', 10),
('en_general_form_1', 'anglophone', 'general', 'en', 'Physics', 'Measurement of mass', 'https://minesec-distance.schoolfaqs.net/learn/physics/form-one', 11),
('en_general_form_1', 'anglophone', 'general', 'en', 'Chemistry', 'Understanding Chemistry', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/form-one', 1),
('en_general_form_1', 'anglophone', 'general', 'en', 'Chemistry', 'Effect of heat on substances', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/form-one', 2),
('en_general_form_1', 'anglophone', 'general', 'en', 'Chemistry', 'Simple classification of substances', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/form-one', 3),
('en_general_form_1', 'anglophone', 'general', 'en', 'Chemistry', 'Chemical elements', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/form-one', 4),
('en_general_form_1', 'anglophone', 'general', 'en', 'Chemistry', 'Acids and bases (alkalis)', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/form-one', 5),
('en_general_form_1', 'anglophone', 'general', 'en', 'Chemistry', 'Air', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/form-one', 6),
('en_general_form_1', 'anglophone', 'general', 'en', 'Chemistry', 'Water and solutions', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/form-one', 7),
('en_general_form_1', 'anglophone', 'general', 'en', 'Biology', 'Understanding Biology', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-one', 1),
('en_general_form_1', 'anglophone', 'general', 'en', 'Biology', 'Environment and Habitats', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-one', 2),
('en_general_form_1', 'anglophone', 'general', 'en', 'Biology', 'Understanding soil', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-one', 3),
('en_general_form_1', 'anglophone', 'general', 'en', 'Biology', 'Soil erosion', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-one', 4),
('en_general_form_1', 'anglophone', 'general', 'en', 'Geography', 'Introduction to Geography', 'https://minesec-distance.schoolfaqs.net/index.php/learn/geography/form-one', 1),
('en_general_form_1', 'anglophone', 'general', 'en', 'Geography', 'The Earth: A Planet of the Solar System', 'https://minesec-distance.schoolfaqs.net/index.php/learn/geography/form-one', 2),
('en_general_form_1', 'anglophone', 'general', 'en', 'Citizenship Education', 'Introduction', 'https://minesec-distance.schoolfaqs.net/index.php/learn/citizenship-education/form-one', 1),
('en_general_form_1', 'anglophone', 'general', 'en', 'Citizenship Education', 'The family', 'https://minesec-distance.schoolfaqs.net/index.php/learn/citizenship-education/form-one', 2),
('en_general_form_1', 'anglophone', 'general', 'en', 'Citizenship Education', 'Protection of the family', 'https://minesec-distance.schoolfaqs.net/index.php/learn/citizenship-education/form-one', 3),
('en_general_form_1', 'anglophone', 'general', 'en', 'History', 'The Notion of History', 'https://minesec-distance.schoolfaqs.net/index.php/learn/history/form-one', 1),
('en_general_form_1', 'anglophone', 'general', 'en', 'History', 'Africa: Cradle of Humankind', 'https://minesec-distance.schoolfaqs.net/index.php/learn/history/form-one', 2),
('en_general_form_1', 'anglophone', 'general', 'en', 'Computer Science', 'Understanding Computer evolution', 'https://minesec-distance.schoolfaqs.net/learn/computer-science/form-one', 1),
('en_general_form_1', 'anglophone', 'general', 'en', 'Literature in English', 'Review of Oral Traditional Forms', 'https://minesec-distance.schoolfaqs.net/learn/literature-in-english/form-one', 1),
('en_general_form_1', 'anglophone', 'general', 'en', 'English Language', 'SATISFYING BASIC DAILY NEEDS RLS: Making New Aquaintainces', 'https://minesec-distance.schoolfaqs.net/learn/english-language/form-one', 1),
('en_general_form_1', 'anglophone', 'general', 'en', 'English Language', 'RLS: Commnicating at School and in the Classroom', 'https://minesec-distance.schoolfaqs.net/learn/english-language/form-one', 2),
('en_general_form_1', 'anglophone', 'general', 'en', 'English Language', 'RLS: At the Bank', 'https://minesec-distance.schoolfaqs.net/learn/english-language/form-one', 3),
('en_general_form_4', 'anglophone', 'general', 'en', 'Geography', 'The Soil', 'https://minesec-distance.schoolfaqs.net/learn/geography/form-four', 1),
('en_general_form_4', 'anglophone', 'general', 'en', 'Geography', 'The Ecosystem', 'https://minesec-distance.schoolfaqs.net/learn/geography/form-four', 2),
('en_general_form_4', 'anglophone', 'general', 'en', 'Geography', 'Conservation of World''s Biomes and Resources', 'https://minesec-distance.schoolfaqs.net/learn/geography/form-four', 3),
('en_general_form_4', 'anglophone', 'general', 'en', 'Geography', 'The Physical Geography of Cameroon', 'https://minesec-distance.schoolfaqs.net/learn/geography/form-four', 4),
('en_general_form_4', 'anglophone', 'general', 'en', 'Geography', 'Initiation into Map analysis', 'https://minesec-distance.schoolfaqs.net/learn/geography/form-four', 5),
('en_general_form_4', 'anglophone', 'general', 'en', 'Chemistry', 'Chemistry of Sulphur', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/form-four', 1),
('en_general_form_4', 'anglophone', 'general', 'en', 'Chemistry', 'Chemistry of Nitrogen', 'https://minesec-distance.schoolfaqs.net/learn/chemistry/form-four', 2),
('en_general_form_4', 'anglophone', 'general', 'en', 'Biology', 'Transport in plants', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-four', 1),
('en_general_form_4', 'anglophone', 'general', 'en', 'Biology', 'Nutrition in plants', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-four', 2),
('en_general_form_4', 'anglophone', 'general', 'en', 'Biology', 'Enzymes', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-four', 3),
('en_general_form_4', 'anglophone', 'general', 'en', 'Biology', 'Digestion', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-four', 4),
('en_general_form_4', 'anglophone', 'general', 'en', 'Biology', 'The circulatory system and its hygiene', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-four', 5),
('en_general_form_4', 'anglophone', 'general', 'en', 'Biology', 'Respiratory system and Hygiene of the system', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-four', 6),
('en_general_form_4', 'anglophone', 'general', 'en', 'Biology', 'The excretory system', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-four', 7),
('en_general_form_4', 'anglophone', 'general', 'en', 'Biology', 'The Skeletal system system', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-four', 8),
('en_general_form_4', 'anglophone', 'general', 'en', 'Biology', 'Human impact on the Ecosystem', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-four', 9),
('en_general_form_4', 'anglophone', 'general', 'en', 'Biology', 'pest control', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-four', 10),
('en_general_form_5', 'anglophone', 'general', 'en', 'Biology', 'Nuclear and cell division', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-five', 1),
('en_general_form_5', 'anglophone', 'general', 'en', 'Biology', 'Reproduction in plants', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-five', 2),
('en_general_form_5', 'anglophone', 'general', 'en', 'Biology', 'coordination in plants', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-five', 3),
('en_general_form_5', 'anglophone', 'general', 'en', 'Biology', 'Irritability in Humans', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-five', 4),
('en_general_form_5', 'anglophone', 'general', 'en', 'Biology', 'Endocrine system', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-five', 5),
('en_general_form_5', 'anglophone', 'general', 'en', 'Biology', 'Reproduction in Humans and Family planning', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-five', 6),
('en_general_form_5', 'anglophone', 'general', 'en', 'Biology', 'Genetics, Mutation and Variation', 'https://minesec-distance.schoolfaqs.net/learn/biology/form-five', 7),
('fr_general_sixieme', 'francophone', 'general', 'fr', 'Mathématiques', 'Ensemble IN des entiers naturels', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/sixieme', 1),
('fr_general_sixieme', 'francophone', 'general', 'fr', 'Mathématiques', 'Ensemble IN des entiers naturels (suite et fin)', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/sixieme', 2),
('fr_general_sixieme', 'francophone', 'general', 'fr', 'Histoire', 'La notion d’Histoire', 'https://minesec-distance.schoolfaqs.net/learn/histoire/sixieme', 3),
('fr_general_sixieme', 'francophone', 'general', 'fr', 'Histoire', 'L’Afrique, berceau de l’humanité', 'https://minesec-distance.schoolfaqs.net/learn/histoire/sixieme', 4),
('fr_general_sixieme', 'francophone', 'general', 'fr', 'Éducation à la citoyenneté', 'Introduction', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 5),
('fr_general_sixieme', 'francophone', 'general', 'fr', 'Éducation à la citoyenneté', 'La famille', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 6),
('fr_general_sixieme', 'francophone', 'general', 'fr', 'Éducation à la citoyenneté', 'La protection de la famille', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 7),
('fr_general_terminale', 'francophone', 'general', 'fr', 'Mathématiques', 'Arithmétique dans Z', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 1),
('fr_general_terminale', 'francophone', 'general', 'fr', 'Mathématiques', 'Arithmétique dans Z (suite)', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 2),
('fr_general_terminale', 'francophone', 'general', 'fr', 'Géographie', 'Promouvoir le développement intégré', 'https://minesec-distance.schoolfaqs.net/learn/geographie/terminale', 1),
('fr_technical_terminale', 'francophone', 'technical', 'fr', 'Mathématiques', 'Nombres complexes: approche algébrique', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale-1', 1),
('fr_technical_terminale', 'francophone', 'technical', 'fr', 'Mathématiques', 'Fonctions numériques d’une variable réelle', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale-1', 2)
),
matched AS (
  SELECT
    cu.id AS curriculum_id,
    trim(seed.chapter_title) AS chapter_title,
    CASE WHEN seed.subsystem = 'anglophone' THEN trim(seed.chapter_title) ELSE trim(seed.chapter_title) END AS title_fr,
    trim(seed.chapter_title) AS title_en,
    seed.source_url,
    'MINESEC Distance Learning — subject syllabus page'::text AS source_title,
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
   AND (
     (seed.subject_field = 'en' AND lower(trim(s.name_en)) = lower(trim(seed.subject_name)))
     OR
     (seed.subject_field = 'fr' AND lower(trim(s.name_fr)) = lower(trim(seed.subject_name)))
   )
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
      ORDER BY m.seed_position, m.source_url
    ) AS seed_rank
  FROM matched m
  WHERE length(trim(m.chapter_title)) > 0
    AND NOT EXISTS (
      SELECT 1
      FROM public.course_chapters ch
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
    ), 0)
    + row_number() OVER (
      PARTITION BY c.curriculum_id
      ORDER BY c.seed_position, c.chapter_title
    ) AS new_position
  FROM chosen c
)
INSERT INTO public.course_chapters
  (curriculum_id, title_fr, title_en, description_fr, description_en,
   position, is_active, verification_status, source_url, source_title)
SELECT
  p.curriculum_id, p.title_fr, p.title_en,
  'Titre de chapitre relevé sur la page de programme MINESEC indiquée. Vérifier la correspondance exacte avec la classe et la série avant publication définitive.',
  'Chapter heading transcribed from the cited MINESEC syllabus page. Confirm the exact class/series mapping before final approval.',
  p.new_position, true, 'pending_official_confirmation', p.source_url, p.source_title
FROM positioned p;

-- Deliberately untouched: public.courses, public.lessons, public.chapter_content_items,
-- assignments, storage buckets and any multimedia content.
