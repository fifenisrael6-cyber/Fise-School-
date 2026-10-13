-- Keep Terminale Informatics chapter headings aligned to the series-specific catalog.
-- Only deactivate the C/D-specific seed rows previously copied into A/AC/BIL series.
-- Never touch lesson content, media, quizzes, exercises, or student progress.
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
  AND s.code = 'informatique'
  AND lower(sr.code) IN ('a1','a2','a3','a4','a5','ac','bil')
  AND ch.is_active IS TRUE
  AND ch.source_title = 'MINESEC — Sommaire de référence Informatique, Terminale C/D'
  AND ch.title_fr IN (
    'Configuration d’un réseau informatique',
    'Écriture et exécution des algorithmes intégrant une structure',
    'Implémentation d’une base de données',
    'Production d’un classeur',
    'Programmation en langage C'
  );

-- Provenance clarification for titles intentionally shared by the literary series.
UPDATE public.course_chapters ch
SET source_title = 'MINESEC — Sommaire de référence Informatique, Terminale séries littéraires',
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
  AND s.code = 'informatique'
  AND lower(sr.code) IN ('a1','a2','a3','a4','a5','ac')
  AND ch.is_active IS TRUE
  AND ch.source_title = 'MINESEC — Sommaire de référence Informatique, Terminale C/D'
  AND ch.title_fr IN (
    'Conception des modèles de données d’un système d’information',
    'Description de l’architecture d’un système informatique',
    'Protection d’un environnement de travail'
  );

COMMIT;
