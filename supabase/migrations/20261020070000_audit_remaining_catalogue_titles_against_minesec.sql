-- Compare the remaining classroom chapter catalogues with publicly accessible
-- MINESEC sources, and correct their provenance. This does NOT claim ministry
-- approval where an exact class-level syllabus could not be located.
-- Preserve chapter titles and keep them pending; do not delete student content.

WITH catalogue_sources AS (
  SELECT
    cu.id AS curriculum_id,
    s.name_fr AS subject_fr,
    s.name_en AS subject_en,
    cu.subsystem,
    lower(trim(el.level_name_fr)) AS level_key,
    lower(trim(coalesce(sr.name_fr, ''))) AS series_key
  FROM public.curricula cu
  JOIN public.subjects s ON s.id = cu.subject_id
  LEFT JOIN public.exam_levels el ON el.id = cu.exam_level_id
  LEFT JOIN public.series sr ON sr.id = cu.series_id
  WHERE cu.is_active = true
    AND cu.is_catalog_container = true
    AND (
      (
        cu.subsystem = 'francophone'
        AND cu.sector = 'general'
        AND lower(trim(s.name_fr)) = lower(trim('Économie sociale et familiale'))
        AND lower(trim(el.level_name_fr)) IN (
          lower(trim('Sixième (6ème)')),
          lower(trim('Cinquième (5ème)')),
          lower(trim('Quatrième (4ème)')),
          lower(trim('Troisième'))
        )
      )
      OR (
        cu.subsystem = 'anglophone'
        AND cu.sector = 'general'
        AND lower(trim(s.name_en)) = 'citizenship education'
        AND lower(trim(el.level_name_en)) IN ('lower sixth', 'upper sixth')
        AND lower(trim(coalesce(sr.name_fr, ''))) IN ('arts', 'science')
      )
      OR (
        cu.subsystem = 'anglophone'
        AND cu.sector = 'general'
        AND lower(trim(s.name_en)) = 'commerce'
        AND lower(trim(el.level_name_en)) IN ('lower sixth', 'upper sixth')
        AND lower(trim(coalesce(sr.name_fr, ''))) = 'arts'
      )
      OR (
        cu.subsystem = 'anglophone'
        AND cu.sector = 'general'
        AND lower(trim(s.name_en)) = 'physical education'
        AND lower(trim(el.level_name_en)) IN ('lower sixth', 'upper sixth')
        AND lower(trim(coalesce(sr.name_fr, ''))) IN ('arts', 'science')
      )
    )
),
classified AS (
  SELECT cs.*,
    CASE
      WHEN cs.subject_fr = 'Économie sociale et familiale'
       AND cs.level_key IN (lower(trim('Sixième (6ème)')), lower(trim('Cinquième (5ème)')))
        THEN 'https://files.minesec.gov.cm/2d/sciences.pdf?download_token=92fa6eb619569069970df85564cc5e9def84218f923c95bae570db6750228d9e'
      WHEN cs.subject_fr = 'Économie sociale et familiale'
        THEN 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels'
      WHEN cs.subsystem = 'anglophone'
        THEN 'https://minesec.gov.cm/web/index.php/en/systeme-educatif-en/progammes-d-etudes-en'
      ELSE 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels'
    END AS official_source_url,
    CASE
      WHEN cs.subject_fr = 'Économie sociale et familiale'
       AND cs.level_key IN (lower(trim('Sixième (6ème)')), lower(trim('Cinquième (5ème)')))
        THEN 'MINESEC — Programme de Sciences 6e/5e: thematic cross-check only; not an ESF-specific chapter approval'
      WHEN cs.subject_fr = 'Économie sociale et familiale'
        THEN 'MINESEC — official programmes index; exact ESF chapter list for this class not located'
      WHEN cs.subject_en = 'Citizenship Education'
        THEN 'MINESEC — official anglophone syllabus index; Lower/Upper Sixth chapter list not located'
      WHEN cs.subject_en = 'Commerce'
        THEN 'MINESEC — official anglophone syllabus index; Commerce Lower/Upper Sixth chapter list not located'
      WHEN cs.subject_en = 'Physical Education'
       AND cs.level_key = 'upper sixth'
        THEN 'MINESEC — official syllabus index; existing headings originated from a non-government mirror and remain unverified'
      WHEN cs.subject_en = 'Physical Education'
        THEN 'MINESEC — official syllabus index; broad physical-education area found, exact Lower Sixth chapter list not located'
      ELSE 'MINESEC — official syllabus index; class-level chapter list not located'
    END AS official_source_title,
    CASE
      WHEN cs.subject_fr = 'Économie sociale et familiale'
       AND cs.level_key IN (lower(trim('Sixième (6ème)')), lower(trim('Cinquième (5ème)')))
        THEN 'Les thèmes déjà inscrits recoupent partiellement des domaines MINESEC du programme de Sciences 6e/5e (notamment alimentation, hygiène et environnement). Ce document est un programme de Sciences, et ne confirme pas les huit intitulés comme chapitres officiels d’ESF. Vérification ESF spécifique encore requise.'
      WHEN cs.subject_fr = 'Économie sociale et familiale'
        THEN 'Aucun document MINESEC consultable retrouvé pendant cette comparaison ne confirme la séquence exacte de chapitres ESF pour cette classe. Les intitulés restent provisoires.'
      WHEN cs.subject_en = 'Citizenship Education'
        THEN 'Le cadre MINESEC consultable présente Citizenship Education dans les domaines du premier cycle, mais aucune liste officielle de chapitres propre à Lower Sixth/Upper Sixth Arts/Science n’a été retrouvée. Ne pas présenter cette liste comme validée par MINESEC.'
      WHEN cs.subject_en = 'Commerce'
        THEN 'Le portail officiel MINESEC distingue les syllabus d’enseignement général, technique et professionnel, mais la séquence de chapitres Commerce propre à Lower Sixth/Upper Sixth Arts n’a pas pu être vérifiée dans un document officiel accessible.'
      WHEN cs.subject_en = 'Physical Education'
       AND cs.level_key = 'upper sixth'
        THEN 'Les deux intitulés déjà présents proviennent de minesec.schoolfaqs.net, un domaine tiers et non du domaine officiel minesec.gov.cm. Ils ne sont donc pas considérés comme confirmés par le ministère tant qu’une source officielle correspondant à Upper Sixth et à la série n’est pas retrouvée.'
      WHEN cs.subject_en = 'Physical Education'
        THEN 'Les documents-cadres MINESEC consultables reconnaissent l’éducation physique et sportive, mais aucune séquence officielle détaillée des chapitres Lower Sixth Arts/Science n’a été retrouvée. Intitulés provisoires.'
      ELSE 'Intitulés provisoires en attente d’une source officielle MINESEC spécifique à la classe.'
    END AS note_fr,
    CASE
      WHEN cs.subject_fr = 'Économie sociale et familiale'
       AND cs.level_key IN (lower(trim('Sixième (6ème)')), lower(trim('Cinquième (5ème)')))
        THEN 'Existing topics partly overlap MINESEC Science programme domains for classes 6e/5e (including nutrition, hygiene and environment). That document is a Science syllabus and does not confirm these eight headings as official ESF chapters. An ESF-specific source is still required.'
      WHEN cs.subject_fr = 'Économie sociale et familiale'
        THEN 'No accessible MINESEC document found during this comparison confirms the exact ESF chapter sequence for this class. Titles remain provisional.'
      WHEN cs.subject_en = 'Citizenship Education'
        THEN 'The accessible MINESEC framework presents Citizenship Education among first-cycle learning areas, but no official chapter list specific to Lower/Upper Sixth Arts/Science was located. Do not present this list as MINESEC-approved.'
      WHEN cs.subject_en = 'Commerce'
        THEN 'The official MINESEC portal separates general, technical and professional syllabuses, but an official chapter sequence for Commerce in Lower/Upper Sixth Arts could not be verified in an accessible document.'
      WHEN cs.subject_en = 'Physical Education'
       AND cs.level_key = 'upper sixth'
        THEN 'The two existing headings came from minesec.schoolfaqs.net, a third-party domain rather than the official minesec.gov.cm domain. They are not considered ministry-confirmed unless an official source for Upper Sixth and the series is located.'
      WHEN cs.subject_en = 'Physical Education'
        THEN 'Accessible MINESEC framework documents recognize physical and sports education, but no detailed official Lower Sixth Arts/Science chapter sequence was located. Titles remain provisional.'
      ELSE 'Provisional titles awaiting a class-specific official MINESEC source.'
    END AS note_en
  FROM catalogue_sources cs
)
UPDATE public.course_chapters ch
SET source_url = c.official_source_url,
    source_title = c.official_source_title,
    description_fr = c.note_fr,
    description_en = c.note_en,
    verification_status = 'pending_official_confirmation'
FROM classified c
WHERE ch.curriculum_id = c.curriculum_id
  AND ch.is_active = true;
