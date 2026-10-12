-- Fise School: restore source-backed chapter titles for selected francophone general curricula.
-- Title-only: this migration does not create courses, lessons, media, assignments or QCM.
-- Titles lacking a series-specific primary source remain pending official confirmation.
BEGIN;

CREATE TEMP TABLE _fise_fr_chapter_restore (
  level_code text NOT NULL,
  series_scope text NOT NULL, -- '-' = no series, '*' = every active series, otherwise a series code
  subject_code text NOT NULL,
  title_fr text NOT NULL,
  title_en text NOT NULL,
  chapter_position integer NOT NULL,
  verification_status text NOT NULL,
  source_url text NOT NULL,
  source_title text NOT NULL,
  replace_existing boolean NOT NULL DEFAULT true
) ON COMMIT DROP;

INSERT INTO _fise_fr_chapter_restore
(level_code, series_scope, subject_code, title_fr, title_en, chapter_position,
 verification_status, source_url, source_title, replace_existing)
VALUES
('fr_general_sixieme', '-', 'histoire', 'La notion d’Histoire', 'La notion d’Histoire', 1, 'verified', 'https://minesec-distance.schoolfaqs.net/learn/histoire/sixieme', 'MINESEC Distance Learning — Histoire — Sixième', true),
('fr_general_sixieme', '-', 'histoire', 'L’Afrique, berceau de l’humanité', 'L’Afrique, berceau de l’humanité', 2, 'verified', 'https://minesec-distance.schoolfaqs.net/learn/histoire/sixieme', 'MINESEC Distance Learning — Histoire — Sixième', true),
('fr_general_sixieme', '-', 'histoire', 'L’Égypte ancienne', 'L’Égypte ancienne', 3, 'verified', 'https://minesec-distance.schoolfaqs.net/learn/histoire/sixieme', 'MINESEC Distance Learning — Histoire — Sixième', true),
('fr_general_sixieme', '-', 'histoire', 'L’héritage des royaumes du haut Nil', 'L’héritage des royaumes du haut Nil', 4, 'verified', 'https://minesec-distance.schoolfaqs.net/learn/histoire/sixieme', 'MINESEC Distance Learning — Histoire — Sixième', true),
('fr_general_sixieme', '-', 'histoire', 'Les civilisations d’Europe', 'Les civilisations d’Europe', 5, 'verified', 'https://minesec-distance.schoolfaqs.net/learn/histoire/sixieme', 'MINESEC Distance Learning — Histoire — Sixième', true),
('fr_general_sixieme', '-', 'histoire', 'Les civilisations anciennes d’Asie', 'Les civilisations anciennes d’Asie', 6, 'verified', 'https://minesec-distance.schoolfaqs.net/learn/histoire/sixieme', 'MINESEC Distance Learning — Histoire — Sixième', true),
('fr_general_sixieme', '-', 'histoire', 'La civilisation judéo-chrétienne', 'La civilisation judéo-chrétienne', 7, 'verified', 'https://minesec-distance.schoolfaqs.net/learn/histoire/sixieme', 'MINESEC Distance Learning — Histoire — Sixième', true),
('fr_general_sixieme', '-', 'education_civique', 'Introduction', 'Introduction', 1, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 'MINESEC Distance Learning — Éducation à la citoyenneté — Sixième', true),
('fr_general_sixieme', '-', 'education_civique', 'La famille', 'La famille', 2, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 'MINESEC Distance Learning — Éducation à la citoyenneté — Sixième', true),
('fr_general_sixieme', '-', 'education_civique', 'La protection de la famille', 'La protection de la famille', 3, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 'MINESEC Distance Learning — Éducation à la citoyenneté — Sixième', true),
('fr_general_sixieme', '-', 'education_civique', 'De la maison à l’école', 'De la maison à l’école', 4, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 'MINESEC Distance Learning — Éducation à la citoyenneté — Sixième', true),
('fr_general_sixieme', '-', 'education_civique', 'L’élève dans son établissement', 'L’élève dans son établissement', 5, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 'MINESEC Distance Learning — Éducation à la citoyenneté — Sixième', true),
('fr_general_sixieme', '-', 'education_civique', 'Le divorce', 'Le divorce', 6, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 'MINESEC Distance Learning — Éducation à la citoyenneté — Sixième', true),
('fr_general_sixieme', '-', 'education_civique', 'La succession', 'La succession', 7, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 'MINESEC Distance Learning — Éducation à la citoyenneté — Sixième', true),
('fr_general_sixieme', '-', 'education_civique', 'Les conflits à l’école', 'Les conflits à l’école', 8, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 'MINESEC Distance Learning — Éducation à la citoyenneté — Sixième', true),
('fr_general_sixieme', '-', 'education_civique', 'Les droits fondamentaux', 'Les droits fondamentaux', 9, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 'MINESEC Distance Learning — Éducation à la citoyenneté — Sixième', true),
('fr_general_sixieme', '-', 'education_civique', 'Les formes d’exploitation et d’abus sur les enfants', 'Les formes d’exploitation et d’abus sur les enfants', 10, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/ecm/sixieme', 'MINESEC Distance Learning — Éducation à la citoyenneté — Sixième', true),
('fr_general_sixieme', '-', 'sciences', 'Le monde vivant', 'Le monde vivant', 1, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_sixieme', '-', 'sciences', 'La matière : ses propriétés et ses transformations', 'La matière : ses propriétés et ses transformations', 2, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_sixieme', '-', 'sciences', 'L’énergie : ses sources et sa gestion', 'L’énergie : ses sources et sa gestion', 3, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_sixieme', '-', 'sciences', 'L’éducation à la santé', 'L’éducation à la santé', 4, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_sixieme', '-', 'sciences', 'L’éducation à l’environnement et au développement durable', 'L’éducation à l’environnement et au développement durable', 5, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_sixieme', '-', 'sciences', 'Technologie', 'Technologie', 6, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_cinquieme', '-', 'sciences', 'Le monde vivant', 'Le monde vivant', 1, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_cinquieme', '-', 'sciences', 'La matière : ses propriétés et ses transformations', 'La matière : ses propriétés et ses transformations', 2, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_cinquieme', '-', 'sciences', 'L’énergie : ses sources et sa gestion', 'L’énergie : ses sources et sa gestion', 3, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_cinquieme', '-', 'sciences', 'L’éducation à la santé', 'L’éducation à la santé', 4, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_cinquieme', '-', 'sciences', 'L’éducation à l’environnement et au développement durable', 'L’éducation à l’environnement et au développement durable', 5, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_cinquieme', '-', 'sciences', 'Technologie', 'Technologie', 6, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de Sciences des classes de 6e et 5e', true),
('fr_general_troisieme', '-', 'education_civique', 'Généralités sur la démocratie', 'Généralités sur la démocratie', 1, 'verified', 'https://minesec-distance.schoolfaqs.net/learn/ecm/troisieme', 'MINESEC Distance Learning — Éducation à la citoyenneté — Troisième', false),
('fr_general_seconde', 'c', 'svt', 'Le monde vivant', 'Le monde vivant', 1, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de SVTEEHB, classe de Seconde C', true),
('fr_general_seconde', 'c', 'svt', 'L’éducation à la santé', 'L’éducation à la santé', 2, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de SVTEEHB, classe de Seconde C', true),
('fr_general_seconde', 'c', 'svt', 'L’éducation à l’environnement et au développement durable', 'L’éducation à l’environnement et au développement durable', 3, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de SVTEEHB, classe de Seconde C', true),
('fr_general_seconde', 'c', 'svt', 'La biotechnologie', 'La biotechnologie', 4, 'verified', 'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels', 'MINESEC — Programme de SVTEEHB, classe de Seconde C', true),
('fr_general_terminale', 'd', 'mathematiques', 'Arithmétique dans Z', 'Arithmétique dans Z', 1, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Nombres complexes : approche algébrique', 'Nombres complexes : approche algébrique', 2, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Fonctions numériques d’une variable réelle', 'Fonctions numériques d’une variable réelle', 3, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Espaces vectoriels et applications linéaires en dimension 3', 'Espaces vectoriels et applications linéaires en dimension 3', 4, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Statistiques à deux variables', 'Statistiques à deux variables', 5, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Produit vectoriel', 'Produit vectoriel', 6, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Suites numériques', 'Suites numériques', 7, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Notion de graphes', 'Notion de graphes', 8, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Nombres complexes : approche géométrique', 'Nombres complexes : approche géométrique', 9, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Similitudes directes planes', 'Similitudes directes planes', 10, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Primitives d’une fonction', 'Primitives d’une fonction', 11, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Fonctions logarithmes', 'Fonctions logarithmes', 12, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Probabilités', 'Probabilités', 13, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Fonctions exponentielles', 'Fonctions exponentielles', 14, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Coniques', 'Coniques', 15, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Calculs des intégrales', 'Calculs des intégrales', 16, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Isométries de l’espace', 'Isométries de l’espace', 17, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', 'd', 'mathematiques', 'Équations différentielles', 'Équations différentielles', 18, 'pending_official_confirmation', 'https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale', 'MINESEC Distance Learning — Mathématiques — Terminale (correspondance précise avec la série D à confirmer)', true),
('fr_general_terminale', '*', 'geographie', 'Promouvoir le développement intégré', 'Promouvoir le développement intégré', 1, 'verified', 'https://minesec-distance.schoolfaqs.net/learn/geographie/terminale', 'MINESEC Distance Learning — Géographie — Terminale', true);

-- Never deactivate an existing chapter that already has pedagogical data or progress.
DO $guard$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.course_chapters ch
    JOIN public.curricula cu ON cu.id = ch.curriculum_id
    JOIN public.exam_levels el ON el.id = cu.exam_level_id
    JOIN public.subjects sub ON sub.id = cu.subject_id
    WHERE ch.is_active
      AND cu.is_catalog_container
      AND EXISTS (
        SELECT 1 FROM _fise_fr_chapter_restore rs
        WHERE rs.replace_existing
          AND rs.level_code = el.code
          AND rs.subject_code = sub.code
          AND (
            rs.series_scope = '*'
            OR (rs.series_scope = '-' AND cu.series_id IS NULL)
            OR EXISTS (SELECT 1 FROM public.series sr
                       WHERE sr.id = cu.series_id AND sr.code = rs.series_scope)
          )
      )
      AND (
        EXISTS (SELECT 1 FROM public.courses co WHERE co.chapter_id = ch.id)
        OR EXISTS (SELECT 1 FROM public.chapter_content_items ci WHERE ci.chapter_id = ch.id)
        OR EXISTS (SELECT 1 FROM public.chapter_exercises ce WHERE ce.chapter_id = ch.id)
        OR EXISTS (SELECT 1 FROM public.chapter_quizzes cq WHERE cq.chapter_id = ch.id)
        OR EXISTS (SELECT 1 FROM public.chapter_learning_progress lp WHERE lp.chapter_id = ch.id)
      )
  ) THEN
    RAISE EXCEPTION 'Chapter restoration stopped: at least one chapter slated for replacement already has courses, content, exercises, quizzes, or learner progress.';
  END IF;
END;
$guard$;

-- Move current active rows out of the way before assigning canonical positions.
-- Rows not in the source-backed list are retained as inactive history; nothing is deleted.
UPDATE public.course_chapters ch
SET position = ch.position + 1000000,
    updated_at = now()
FROM public.curricula cu
JOIN public.exam_levels el ON el.id = cu.exam_level_id
JOIN public.subjects sub ON sub.id = cu.subject_id
WHERE ch.curriculum_id = cu.id
  AND ch.is_active
  AND cu.is_catalog_container
  AND EXISTS (
    SELECT 1 FROM _fise_fr_chapter_restore rs
    WHERE rs.replace_existing
      AND rs.level_code = el.code
      AND rs.subject_code = sub.code
      AND (
        rs.series_scope = '*'
        OR (rs.series_scope = '-' AND cu.series_id IS NULL)
        OR EXISTS (SELECT 1 FROM public.series sr
                   WHERE sr.id = cu.series_id AND sr.code = rs.series_scope)
      )
  );

-- Deactivate only rows whose titles are not part of the chosen syllabus heading list.
UPDATE public.course_chapters ch
SET is_active = false,
    updated_at = now()
FROM public.curricula cu
JOIN public.exam_levels el ON el.id = cu.exam_level_id
JOIN public.subjects sub ON sub.id = cu.subject_id
WHERE ch.curriculum_id = cu.id
  AND ch.is_active
  AND cu.is_catalog_container
  AND EXISTS (
    SELECT 1 FROM _fise_fr_chapter_restore rs
    WHERE rs.replace_existing
      AND rs.level_code = el.code
      AND rs.subject_code = sub.code
      AND (
        rs.series_scope = '*'
        OR (rs.series_scope = '-' AND cu.series_id IS NULL)
        OR EXISTS (SELECT 1 FROM public.series sr
                   WHERE sr.id = cu.series_id AND sr.code = rs.series_scope)
      )
  )
  AND NOT EXISTS (
    SELECT 1 FROM _fise_fr_chapter_restore rs
    WHERE rs.level_code = el.code
      AND rs.subject_code = sub.code
      AND lower(trim(rs.title_fr)) = lower(trim(ch.title_fr))
      AND (
        rs.series_scope = '*'
        OR (rs.series_scope = '-' AND cu.series_id IS NULL)
        OR EXISTS (SELECT 1 FROM public.series sr
                   WHERE sr.id = cu.series_id AND sr.code = rs.series_scope)
      )
  );

-- Normalize titles and positions for any already-present matching headings.
UPDATE public.course_chapters ch
SET title_en = rs.title_en,
    description_fr = 'Titre de chapitre issu de la source MINESEC indiquée. Le contenu pédagogique sera ajouté dans cette page séparément.',
    description_en = 'Chapter title only from the referenced MINESEC source. Teaching content is added separately.',
    position = rs.chapter_position,
    verification_status = rs.verification_status::public.catalog_verification_status,
    source_url = rs.source_url,
    source_title = rs.source_title,
    updated_at = now()
FROM public.curricula cu
JOIN public.exam_levels el ON el.id = cu.exam_level_id
JOIN public.subjects sub ON sub.id = cu.subject_id
JOIN _fise_fr_chapter_restore rs
  ON rs.level_code = el.code AND rs.subject_code = sub.code
WHERE ch.curriculum_id = cu.id
  AND cu.is_catalog_container
  AND ch.is_active
  AND lower(trim(ch.title_fr)) = lower(trim(rs.title_fr))
  AND (
    rs.series_scope = '*'
    OR (rs.series_scope = '-' AND cu.series_id IS NULL)
    OR EXISTS (SELECT 1 FROM public.series sr
               WHERE sr.id = cu.series_id AND sr.code = rs.series_scope)
  );

-- Insert missing headings. Running this migration again will not duplicate active titles.
INSERT INTO public.course_chapters
(curriculum_id, title_fr, title_en, description_fr, description_en, position,
 is_active, verification_status, source_url, source_title)
SELECT
  cu.id, rs.title_fr, rs.title_en,
  'Titre de chapitre issu de la source MINESEC indiquée. Le contenu pédagogique sera ajouté dans cette page séparément.',
  'Chapter title only from the referenced MINESEC source. Teaching content is added separately.',
  rs.chapter_position, true,
  rs.verification_status::public.catalog_verification_status,
  rs.source_url, rs.source_title
FROM _fise_fr_chapter_restore rs
JOIN public.exam_levels el
  ON el.code = rs.level_code
 AND el.subsystem = 'francophone'
 AND el.sector = 'general'
 AND el.active
JOIN public.subjects sub
  ON sub.code = rs.subject_code
 AND sub.subsystem = 'francophone'
 AND sub.sector = 'general'
 AND sub.is_active
JOIN public.curricula cu
  ON cu.subject_id = sub.id
 AND cu.exam_level_id = el.id
 AND cu.subsystem = 'francophone'
 AND cu.sector = 'general'
 AND cu.is_catalog_container
 AND cu.is_active
WHERE (
  rs.series_scope = '*'
  OR (rs.series_scope = '-' AND cu.series_id IS NULL)
  OR EXISTS (SELECT 1 FROM public.series sr
             WHERE sr.id = cu.series_id AND sr.code = rs.series_scope)
)
AND NOT EXISTS (
  SELECT 1 FROM public.course_chapters existing
  WHERE existing.curriculum_id = cu.id
    AND existing.is_active
    AND lower(trim(existing.title_fr)) = lower(trim(rs.title_fr))
);

COMMIT;