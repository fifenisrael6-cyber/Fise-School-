-- Additive MINESEC Distance Learning chapter headings for General Education Mathematics.
-- The source portal contains duplicated and mixed lesson sequences; titles stay pending confirmation.
-- Existing chapter/content records are never updated or deleted.
WITH seed(level_code, subject_name, chapter_title, source_url, source_title, seed_position) AS (
 VALUES
 ('fr_general_seconde','Mathématiques','Calculs dans IR','https://minesec-distance.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde',1),
 ('fr_general_seconde','Mathématiques','Calcul littéral','https://minesec-distance.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde',2),
 ('fr_general_seconde','Mathématiques','Équations, inéquations et systèmes','https://minesec-distance.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde',3),
 ('fr_general_seconde','Mathématiques','Proportionnalité','https://minesec-distance.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde',4),
 ('fr_general_seconde','Mathématiques','Statistiques','https://minesec-distance.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde',5),
 ('fr_general_seconde','Mathématiques','Fonctions','https://minesec-distance.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde',6),
 ('fr_general_seconde','Mathématiques','Dénombrement','https://minesec-distance.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde',7),
 ('fr_general_seconde','Mathématiques','Suites numériques','https://minesec-distance.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde',8),
 ('fr_general_seconde','Mathématiques','Géométrie dans l’espace','https://minesec-distance.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde',9),
 ('fr_general_seconde','Mathématiques','Transformations du plan','https://minesec-distance.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde',10),
 ('fr_general_seconde','Mathématiques','Produit scalaire de deux vecteurs du plan','https://minesec-distance.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde',11),
 ('fr_general_terminale','Mathématiques','Arithmétique dans Z','https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale','MINESEC Distance Learning — Mathématiques, Terminale',1),
 ('fr_general_terminale','Mathématiques','Fonctions : limites et continuité','https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale','MINESEC Distance Learning — Mathématiques, Terminale',2),
 ('fr_general_terminale','Mathématiques','Statistiques','https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale','MINESEC Distance Learning — Mathématiques, Terminale',3),
 ('fr_general_terminale','Mathématiques','Fonctions : dérivées','https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale','MINESEC Distance Learning — Mathématiques, Terminale',4),
 ('fr_general_terminale','Mathématiques','Suites numériques','https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale','MINESEC Distance Learning — Mathématiques, Terminale',5),
 ('fr_general_terminale','Mathématiques','Nombres complexes','https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale','MINESEC Distance Learning — Mathématiques, Terminale',6),
 ('fr_general_terminale','Mathématiques','Fonctions numériques d’une variable réelle','https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale','MINESEC Distance Learning — Mathématiques, Terminale',7),
 ('fr_general_terminale','Mathématiques','Équations, inéquations et systèmes','https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale','MINESEC Distance Learning — Mathématiques, Terminale',8),
 ('fr_general_terminale','Mathématiques','Primitives et intégration','https://minesec-distance.schoolfaqs.net/learn/mathematiques/terminale','MINESEC Distance Learning — Mathématiques, Terminale',9)
),
matched AS (
 SELECT cu.id AS curriculum_id, seed.chapter_title, seed.source_url, seed.source_title, seed.seed_position
 FROM seed
 JOIN public.exam_levels el ON el.code=seed.level_code AND el.subsystem='francophone'::public.catalog_subsystem AND el.sector='general'::public.catalog_sector AND el.active=true
 JOIN public.subjects s ON s.subsystem=el.subsystem AND s.sector=el.sector AND s.is_active=true AND lower(trim(s.name_fr))=lower(trim(seed.subject_name))
 JOIN public.curricula cu ON cu.subject_id=s.id AND cu.exam_level_id=el.id AND cu.subsystem=el.subsystem AND cu.sector=el.sector AND cu.is_catalog_container=true AND cu.is_active=true
),
deduplicated AS (
 SELECT m.*, row_number() OVER(PARTITION BY m.curriculum_id,lower(trim(m.chapter_title)) ORDER BY m.seed_position) AS seed_rank
 FROM matched m
 WHERE NOT EXISTS (SELECT 1 FROM public.course_chapters ch WHERE ch.curriculum_id=m.curriculum_id AND lower(trim(ch.title_fr))=lower(trim(m.chapter_title)))
),
chosen AS (SELECT * FROM deduplicated WHERE seed_rank=1),
positioned AS (
 SELECT c.*, coalesce((SELECT max(ch.position) FROM public.course_chapters ch WHERE ch.curriculum_id=c.curriculum_id),0)
   + row_number() OVER(PARTITION BY c.curriculum_id ORDER BY c.seed_position,c.chapter_title) AS new_position
 FROM chosen c
)
INSERT INTO public.course_chapters
 (curriculum_id,title_fr,title_en,description_fr,description_en,position,is_active,verification_status,source_url,source_title)
SELECT p.curriculum_id,p.chapter_title,p.chapter_title,
 'Titre relevé du portail MINESEC Distance Learning. La correspondance exacte avec le programme officiel de cette classe et série reste à confirmer.',
 'Heading transcribed from the MINESEC Distance Learning portal. Exact mapping to this class and series still requires confirmation.',
 p.new_position,true,'pending_official_confirmation',p.source_url,p.source_title
FROM positioned p;
