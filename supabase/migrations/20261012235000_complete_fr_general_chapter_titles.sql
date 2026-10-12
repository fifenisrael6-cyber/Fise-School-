-- 20261012235000_complete_fr_general_chapter_titles.sql
-- The scope is Francophone General education only.
-- Adds chapter-title pages, never lessons, courses, exercises, quizzes or media.
BEGIN;

-- Complete the Francophone General chapter-title catalog with title-only entries.
-- Existing active chapter rows are preserved; content tables and files are untouched.
WITH seed_groups(level_code,subject_code,series_scope,chapter_titles,source_url,source_title,verification_status) AS (
 VALUES
('fr_general_sixieme','mathematiques',NULL::text,ARRAY['Ensemble IN des entiers naturels','Ensemble IN des entiers naturels (suite et fin)','Droite du plan','Droite du plan (suite et fin)','Nombres décimaux arithmétiques','Nombres décimaux arithmétiques (suite et fin)','Fractions','Fractions (suite et fin)','Mesures de longueur','Angles et droites remarquables','Aires et volumes']::text[],'https://minesec.schoolfaqs.net/learn/mathematiques/sixieme','MINESEC Distance Learning — Mathématiques, Sixième','pending_official_confirmation'),
('fr_general_cinquieme','mathematiques',NULL::text,ARRAY['Arithmétique','Arithmétique (suite)','Arithmétique (suite et fin)','Distances','Fractions','Fractions (suite et fin)','Nombres décimaux relatifs','Calcul littéral','Triangles et quadrilatères','Symétrie centrale','Aires et volumes','Proportionnalité']::text[],'https://minesec.schoolfaqs.net/learn/mathematiques/cinquieme','MINESEC Distance Learning — Mathématiques, Cinquième','pending_official_confirmation'),
('fr_general_quatrieme','mathematiques',NULL::text,ARRAY['Nombres rationnels et puissances','Calcul littéral','Équations et inéquations','Théorème de Pythagore','Théorème de Thalès','Transformations du plan','Triangles et quadrilatères','Grandeurs et mesures','Organisation et traitement des données']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Programme officiel de mathématiques, Quatrième','pending_official_confirmation'),
('fr_general_troisieme','mathematiques',NULL::text,ARRAY['Arithmétique','Thalès dans le triangle','Nombres réels','Nombres réels (suite)','Nombres réels (suite et fin)','Fonctions numériques','Équations et inéquations','Trigonométrie','Statistiques','Géométrie dans l’espace']::text[],'https://minesec.schoolfaqs.net/learn/mathematiques/troisieme','MINESEC Distance Learning — Mathématiques, Troisième','pending_official_confirmation'),
('fr_general_seconde','mathematiques',NULL::text,ARRAY['Calculs dans IR','Vecteurs du plan','Équations et inéquations','Généralités sur les fonctions','Étude des fonctions affines','Géométrie analytique','Statistiques','Probabilités','Transformations du plan']::text[],'https://minesec.schoolfaqs.net/learn/mathematiques/seconde','MINESEC Distance Learning — Mathématiques, Seconde','pending_official_confirmation'),
('fr_general_premiere','mathematiques',NULL::text,ARRAY['Ensembles de nombres et calcul algébrique','Polynômes, équations et inéquations','Fonctions numériques','Limites et continuité','Dérivation et étude des fonctions','Suites numériques','Géométrie dans le plan et dans l’espace','Statistiques et probabilités']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Programme officiel de mathématiques, Première','pending_official_confirmation'),
('fr_general_terminale','mathematiques',NULL::text,ARRAY['Arithmétique dans Z','Arithmétique dans Z (suite)','Fonctions numériques d’une variable réelle','Espaces vectoriels et applications linéaires en dimension 3','Statistiques à deux variables','Produit vectoriel','Suites numériques','Notion de graphes','Nombres complexes : approche algébrique','Nombres complexes : approche géométrique','Similitudes directes planes','Primitives d’une fonction','Fonctions logarithmes','Probabilités','Fonctions exponentielles','Coniques','Calculs des intégrales','Isométries de l’espace','Équations différentielles']::text[],'https://minesec.schoolfaqs.net/learn/mathematiques/terminale','MINESEC Distance Learning — Mathématiques, Terminale','pending_official_confirmation'),
('fr_general_sixieme','histoire',NULL::text,ARRAY['La notion d’Histoire','L’Afrique, berceau de l’humanité','L’Égypte ancienne','L’héritage des royaumes du haut Nil','Les civilisations d’Europe','Les civilisations anciennes d’Asie','La civilisation judéo-chrétienne']::text[],'https://minesec.schoolfaqs.net/learn/histoire/sixieme','MINESEC Distance Learning — Histoire, Sixième','verified'),
('fr_general_cinquieme','histoire',NULL::text,ARRAY['Peuplement et organisation socio-politique du Cameroun','L’âge d’or de l’Afrique','Les relations entre l’Afrique et le reste du monde']::text[],'https://files.minesec.gov.cm/2g/HISTOIRE_6e_5e_ESG.pdf','MINESEC — Programme officiel d’Histoire 6e/5e','verified'),
('fr_general_troisieme','histoire',NULL::text,ARRAY['L’impérialisme en Afrique','Les grandes crises de la première moitié du XXe siècle','La décolonisation','De la création du Kamerun au mandat','La naissance de l’État du Cameroun']::text[],'https://minesec.schoolfaqs.net/learn/histoire/troisieme','MINESEC Distance Learning — Histoire, Troisième','verified'),
('fr_general_quatrieme','histoire',NULL::text,ARRAY['Les sociétés et civilisations africaines','L’Afrique et le monde atlantique','La traite négrière et l’esclavage','Les transformations politiques et économiques du monde','L’Afrique face aux conquêtes et aux échanges']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Programme officiel d’Histoire, Quatrième','pending_official_confirmation'),
('fr_general_seconde','histoire',NULL::text,ARRAY['Les disciplines affinitaires de l’histoire','Les civilisations anciennes du Cameroun','Les civilisations anciennes','Les États de l’Afrique soudanaise','Les États de l’Afrique forestière','Les États de l’Afrique orientale et australe','L’Europe féodale']::text[],'https://minesec.schoolfaqs.net/learn/histoire/seconde','MINESEC Distance Learning — Histoire, Seconde','pending_official_confirmation'),
('fr_general_premiere','histoire',NULL::text,ARRAY['Le monde au XIXe siècle','L’Afrique à l’époque contemporaine','La colonisation et ses conséquences','Les mouvements nationalistes et les indépendances','Le Cameroun au XXe siècle']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Programme officiel d’Histoire, Première','pending_official_confirmation'),
('fr_general_terminale','histoire',NULL::text,ARRAY['La Deuxième Guerre mondiale','Les conséquences de la Deuxième Guerre mondiale et la naissance de l’ONU','La décolonisation','La guerre froide et la bipolarisation du monde','Les relations internationales depuis 1945','Les mutations du monde contemporain']::text[],'https://minesec.schoolfaqs.net/learn/histoire/terminale','MINESEC Distance Learning — Histoire, Terminale','pending_official_confirmation'),
('fr_general_sixieme','geographie',NULL::text,ARRAY['S’adapter aux influences cosmiques','La Terre dans l’Univers','La géographie : définition, domaines, méthodes et utilité','La Terre : une planète du système solaire','Les composantes naturelles de l’environnement','Les perturbations climatiques','Protégeons notre environnement']::text[],'https://minesec.schoolfaqs.net/learn/geographie/sixieme','MINESEC Distance Learning — Géographie, Sixième','pending_official_confirmation'),
('fr_general_cinquieme','geographie',NULL::text,ARRAY['L’Homme dans son milieu de vie','L’occupation de l’espace','Protéger l’environnement','Gérer les migrations']::text[],'https://files.minesec.gov.cm/2f/GEOGRAPHIE_6e_5e_ESG.pdf','MINESEC — Programme officiel de Géographie 6e/5e','pending_official_confirmation'),
('fr_general_quatrieme','geographie',NULL::text,ARRAY['Gérer durablement l’environnement','Les reliefs et les sols de l’Afrique','Le climat, la végétation et l’hydrographie de l’Afrique','Les populations et les activités humaines en Afrique']::text[],'https://minesec.schoolfaqs.net/learn/geographie/quatrieme','MINESEC Distance Learning — Géographie, Quatrième','pending_official_confirmation'),
('fr_general_troisieme','geographie',NULL::text,ARRAY['Préserver un environnement sain au Cameroun','Le relief et les paysages du Cameroun','Le peuplement et la population du Cameroun','Les activités économiques du Cameroun','Les échanges et le développement du Cameroun']::text[],'https://minesec.schoolfaqs.net/learn/geographie/troisieme','MINESEC Distance Learning — Géographie, Troisième','pending_official_confirmation'),
('fr_general_seconde','geographie',NULL::text,ARRAY['La terre et les mouvements tectoniques','Les reliefs terrestres et leur évolution','Le climat et les milieux naturels','La population et les peuplements','Les activités économiques et l’environnement']::text[],'https://minesec.schoolfaqs.net/learn/geographie/seconde','MINESEC Distance Learning — Géographie, Seconde','pending_official_confirmation'),
('fr_general_premiere','geographie',NULL::text,ARRAY['Maîtriser la croissance démographique','Limiter les migrations','Les dynamiques urbaines','Les activités économiques et l’aménagement du territoire','Les enjeux environnementaux et le développement']::text[],'https://minesec.schoolfaqs.net/learn/geographie/premiere','MINESEC Distance Learning — Géographie, Première','pending_official_confirmation'),
('fr_general_terminale','geographie',NULL::text,ARRAY['Promouvoir le développement intégré']::text[],'https://minesec.schoolfaqs.net/learn/geographie/terminale','MINESEC Distance Learning — Géographie, Terminale','verified'),
('fr_general_sixieme','education_civique',NULL::text,ARRAY['Introduction','La famille','La protection de la famille','De la maison à l’école','L’élève dans son établissement','Le divorce','La succession','Les conflits à l’école','Les droits fondamentaux','Les formes d’exploitation et d’abus sur les enfants']::text[],'https://minesec.schoolfaqs.net/learn/ecm/sixieme','MINESEC Distance Learning — Éducation à la citoyenneté, Sixième','pending_official_confirmation'),
('fr_general_cinquieme','education_civique',NULL::text,ARRAY['La famille et la vie sociale','L’élève dans la communauté scolaire','Les droits et les devoirs','La citoyenneté','La protection de l’environnement et de la santé']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Programme officiel d’éducation à la citoyenneté, Cinquième','pending_official_confirmation'),
('fr_general_quatrieme','education_civique',NULL::text,ARRAY['La vie familiale et sociale','Les droits et les devoirs du citoyen','La démocratie et les institutions','La protection des personnes et des biens','L’environnement et la responsabilité citoyenne']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Programme officiel d’éducation à la citoyenneté, Quatrième','pending_official_confirmation'),
('fr_general_troisieme','education_civique',NULL::text,ARRAY['Généralités sur la démocratie','Les fondements de la démocratie','Les formes de démocratie','Les élections au Cameroun','Le processus électoral au Cameroun']::text[],'https://minesec.schoolfaqs.net/learn/ecm/troisieme','MINESEC Distance Learning — ECM, Troisième','pending_official_confirmation'),
('fr_general_seconde','education_civique',NULL::text,ARRAY['La nation et l’État','La Constitution et les institutions de la République','Les droits et les devoirs du citoyen','La participation à la vie démocratique','La protection de l’environnement et le civisme']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Programme officiel d’éducation à la citoyenneté, Seconde','pending_official_confirmation'),
('fr_general_premiere','education_civique',NULL::text,ARRAY['Citoyenneté et participation politique','Les institutions et les pouvoirs publics','Les droits humains et les libertés','La décentralisation et l’administration territoriale','La responsabilité citoyenne']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Programme officiel d’éducation à la citoyenneté, Première','pending_official_confirmation'),
('fr_general_terminale','education_civique',NULL::text,ARRAY['Les principes de la diplomatie camerounaise','Le Cameroun dans la coopération multilatérale']::text[],'https://minesec.schoolfaqs.net/learn/ecm/terminale','MINESEC Distance Learning — ECM, Terminale','verified'),
('fr_general_sixieme','sciences',NULL::text,ARRAY['Le monde vivant','La matière : ses propriétés et ses transformations','L’énergie : ses sources et sa gestion','L’éducation à la santé','L’éducation à l’environnement et au développement durable','Technologie','Amélioration de la production végétale et animale','Détermination des caractéristiques physiques et chimiques d’un corps','Gestion des ressources naturelles, alimentaires et médicinales','Hygiène des appareils reproducteurs','Lutte contre la dégradation des sols','Lutte contre la pollution de l’air','Lutte contre la pollution de l’eau','Lutte contre les grossesses précoces','Lutte contre les maladies par carence et par excès alimentaires','Réalisation d’un projet technique et/ou économique simple','Utilisation de quelques formes d’énergie']::text[],'https://files.minesec.gov.cm/2d/sciences.pdf','MINESEC — Programme officiel de Sciences 6e/5e','verified'),
('fr_general_cinquieme','sciences',NULL::text,ARRAY['Le monde vivant','La matière : ses propriétés et ses transformations','L’énergie : ses sources et sa gestion','L’éducation à la santé','L’éducation à l’environnement et au développement durable','Technologie','Amélioration de la production végétale et animale','Hygiène des appareils reproducteurs','Lecture et exploitation des inscriptions sur les produits de consommation','Lutte contre la dégradation des sols','Lutte contre la pollution de l’air','Lutte contre la pollution de l’eau','Lutte contre les intoxications alimentaires','Organisation d’un voyage','Réalisation d’un projet technique et/ou économique simple']::text[],'https://files.minesec.gov.cm/2d/sciences.pdf','MINESEC — Programme officiel de Sciences 6e/5e','pending_official_confirmation'),
('fr_general_seconde','svt',NULL::text,ARRAY['Le monde vivant','L’éducation à la santé','L’éducation à l’environnement et au développement durable','La biotechnologie']::text[],'https://files.minesec.gov.cm/iu/Programme_de__SVTEEHB_Classe_de_2nde.pdf','MINESEC — Programme officiel SVTEEHB, Seconde','verified'),
('fr_general_premiere','sciences',NULL::text,ARRAY['SEQ 1 : Quelques voies de régénération de l’énergie par les organismes']::text[],'https://minesec.schoolfaqs.net/learn/sciences/premiere','MINESEC Distance Learning — Sciences, Première','verified'),
('fr_general_seconde','physique',NULL::text,ARRAY['Mesure d’une grandeur','Expression du résultat de la mesure','Dressage du tableau de mesure','Détermination d’une grandeur à partir d’un graphique','La relativité du mouvement','Les paramètres cinématiques','Les types de mouvements','Équilibre d’un solide soumis à l’action de deux forces','Actions mécaniques et variation de la quantité de mouvement','Caractérisation d’une lumière','Propriétés de la lumière et phénomènes observés','Description du trajet de la lumière d’une source à un récepteur','Comportement de composants électroniques','Réalisation de montages électroniques simples']::text[],'https://minesec.schoolfaqs.net/learn/physique/seconde','MINESEC Distance Learning — Physique, Seconde','pending_official_confirmation'),
('fr_general_premiere','physique',NULL::text,ARRAY['Mesure des grandeurs physiques et chimiques','Modélisation d’un phénomène','Travail d’une force','Énergie cinétique','Principe de conservation de l’énergie mécanique','Mode de transfert de chaleur','Mesure de la quantité de chaleur','Étude des phénomènes mécaniques et énergétiques']::text[],'https://minesec.schoolfaqs.net/learn/physique/premiere','MINESEC Distance Learning — Physique, Première','pending_official_confirmation'),
('fr_general_terminale','physique',NULL::text,ARRAY['Rappels sur les mesures et incertitudes','Équations aux dimensions','Interaction gravitationnelle','Interaction électrique','Champ électrostatique et condensateur','Mouvements dans un champ de forces','Induction électromagnétique','Oscillations et phénomènes périodiques','Énergie et transformations']::text[],'https://minesec.schoolfaqs.net/learn/physique/terminale','MINESEC Distance Learning — Physique, Terminale','pending_official_confirmation'),
('fr_general_seconde','chimie',NULL::text,ARRAY['Structure de la matière et analyse élémentaire des composés organiques','Solutions aqueuses','Le noyau atomique et la structure électronique des atomes','Classification périodique des éléments','Molécule et notion de volume molaire','Structure de quelques composés ioniques','Introduction à la chimie organique']::text[],'https://files.minesec.gov.cm/iv/Projet_de_programme_de_chimie_2nde_C-_Final.pdf','MINESEC — Programme officiel de Chimie, Seconde C','pending_official_confirmation'),
('fr_general_premiere','chimie',NULL::text,ARRAY['Les alcanes','Les alcènes et les alcynes','Les composés oxygénés','Les composés aromatiques','Généralités sur l’oxydoréduction en solution aqueuse','Notion de couple oxydant-réducteur et classification électrochimique']::text[],'https://minesec.schoolfaqs.net/learn/chimie-1/premiere','MINESEC Distance Learning — Chimie, Première','pending_official_confirmation'),
('fr_general_terminale','chimie',NULL::text,ARRAY['Propriétés chimiques des alcools','Les acides carboxyliques','Les amines','Les acides alpha aminés','Synthèse des polypeptides']::text[],'https://minesec.schoolfaqs.net/learn/chimie-1/terminale','MINESEC Distance Learning — Chimie, Terminale','pending_official_confirmation'),
('fr_general_terminale','informatique','*not_ti*',ARRAY['Conception des modèles de données d’un système d’information','Configuration d’un réseau informatique','Description de l’architecture d’un système informatique','Écriture et exécution des algorithmes intégrant une structure','Implémentation d’une base de données','Production d’un classeur','Programmation en langage C','Protection d’un environnement de travail']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Sommaire de référence Informatique, Terminale C/D','pending_official_confirmation'),
('fr_general_terminale','informatique','ti',ARRAY['Conception et implémentation d’une base de données','Configuration d’un serveur web','Configuration et services réseau','Description des concepts de base des systèmes d’information','Programmation en HTML et JavaScript','Réalisation et présentation du projet','Sécurité informatique']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Sommaire de référence Informatique, Terminale TI','pending_official_confirmation'),
('fr_general_terminale','informatique','a1',ARRAY['Conception des modèles de données d’un système d’information','Description de l’architecture d’un système informatique','Description des concepts de base des systèmes d’information','Production de contenus numériques','Protection d’un environnement de travail']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Sommaire de référence Informatique, Terminale séries littéraires','pending_official_confirmation'),
('fr_general_terminale','informatique','a2',ARRAY['Conception des modèles de données d’un système d’information','Description de l’architecture d’un système informatique','Description des concepts de base des systèmes d’information','Production de contenus numériques','Protection d’un environnement de travail']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Sommaire de référence Informatique, Terminale séries littéraires','pending_official_confirmation'),
('fr_general_terminale','informatique','a3',ARRAY['Conception des modèles de données d’un système d’information','Description de l’architecture d’un système informatique','Description des concepts de base des systèmes d’information','Production de contenus numériques','Protection d’un environnement de travail']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Sommaire de référence Informatique, Terminale séries littéraires','pending_official_confirmation'),
('fr_general_terminale','informatique','a4',ARRAY['Conception des modèles de données d’un système d’information','Description de l’architecture d’un système informatique','Description des concepts de base des systèmes d’information','Production de contenus numériques','Protection d’un environnement de travail']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Sommaire de référence Informatique, Terminale séries littéraires','pending_official_confirmation'),
('fr_general_terminale','informatique','a5',ARRAY['Conception des modèles de données d’un système d’information','Description de l’architecture d’un système informatique','Description des concepts de base des systèmes d’information','Production de contenus numériques','Protection d’un environnement de travail']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Sommaire de référence Informatique, Terminale séries littéraires','pending_official_confirmation'),
('fr_general_terminale','informatique','ac',ARRAY['Conception des modèles de données d’un système d’information','Description de l’architecture d’un système informatique','Description des concepts de base des systèmes d’information','Production de contenus numériques','Protection d’un environnement de travail']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Sommaire de référence Informatique, Terminale séries littéraires','pending_official_confirmation'),
('fr_general_terminale','allemand','a4',ARRAY['Communication et relations sociales','Éducation, avenir et citoyenneté','Environnement, santé et cadre de vie','Vie économique et projets','Vie familiale et socioculturelle']::text[],'https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels','MINESEC — Modules d’allemand, Terminale A4','pending_official_confirmation'),
('fr_general_quatrieme','espagnol',NULL::text,ARRAY['Vie familiale et intégration sociale','Environnement et santé','Vie citoyenne et ouverture au monde','Activités économiques et monde du travail','Communication et médias (TIC)']::text[],'https://files.minesec.gov.cm/2o/programme_Espagol_4eme3eme.pdf','MINESEC — Programme officiel d’Espagnol 4e/3e','verified'),
('fr_general_troisieme','espagnol',NULL::text,ARRAY['Vie familiale et intégration sociale','Environnement et santé','Vie citoyenne et ouverture au monde','Activités économiques et monde du travail','Communication et médias (TIC)']::text[],'https://files.minesec.gov.cm/2o/programme_Espagol_4eme3eme.pdf','MINESEC — Programme officiel d’Espagnol 4e/3e','verified'),
('fr_general_quatrieme','chinois',NULL::text,ARRAY['Module 1 : Vie familiale et intégration sociale','Module 2 : Environnement, bien-être et santé','Module 3 : Citoyenneté et ouverture au monde','Module 4 : Activités économiques et monde du travail','Module 5 : Vie économique, médias et communication']::text[],'https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf','MINESEC — Programme officiel de Chinois 4e/3e','pending_official_confirmation'),
('fr_general_troisieme','chinois',NULL::text,ARRAY['Module 1 : Vie familiale et intégration sociale','Module 2 : Environnement, bien-être et santé','Module 3 : Citoyenneté et ouverture au monde','Module 4 : Activités économiques et monde du travail','Module 5 : Vie économique, médias et communication']::text[],'https://files.minesec.gov.cm/2n/programme_CHINOIS_4eme3eme.pdf','MINESEC — Programme officiel de Chinois 4e/3e','pending_official_confirmation'),
('fr_general_quatrieme','latin',NULL::text,ARRAY['La vie familiale et socioculturelle','Citoyenneté, environnement, santé et bien-être']::text[],'https://files.minesec.gov.cm/2q/Latin_Grec.pdf','MINESEC — Programme officiel de Latin/Grec 4e/3e','verified'),
('fr_general_troisieme','latin',NULL::text,ARRAY['Vie économique','Média et communication']::text[],'https://files.minesec.gov.cm/2q/Latin_Grec.pdf','MINESEC — Programme officiel de Latin/Grec 4e/3e','verified'),
('fr_general_quatrieme','grec',NULL::text,ARRAY['Communication dans la vie familiale et socioculturelle']::text[],'https://files.minesec.gov.cm/2q/Latin_Grec.pdf','MINESEC — Programme officiel de Latin/Grec 4e/3e','verified'),
('fr_general_troisieme','grec',NULL::text,ARRAY['Citoyenneté, environnement, santé et bien-être']::text[],'https://files.minesec.gov.cm/2q/Latin_Grec.pdf','MINESEC — Programme officiel de Latin/Grec 4e/3e','verified')
),
targets AS (
 SELECT c.id curriculum_id,el.code level_code,s.code subject_code,coalesce(se.code,'') series_code
 FROM public.curricula c
 JOIN public.exam_levels el ON el.id=c.exam_level_id
 JOIN public.subjects s ON s.id=c.subject_id
 LEFT JOIN public.series se ON se.id=c.series_id
 WHERE c.is_catalog_container IS TRUE AND c.is_active IS TRUE
   AND c.subsystem='francophone' AND c.sector='general'
),
expanded AS (
 SELECT t.curriculum_id,t.level_code,t.subject_code,t.series_code,
        u.title_fr,u.ordinality::integer seed_position,
        g.source_url,g.source_title,g.verification_status
 FROM targets t
 JOIN seed_groups g ON g.level_code=t.level_code AND g.subject_code=t.subject_code
 CROSS JOIN LATERAL unnest(g.chapter_titles) WITH ORDINALITY AS u(title_fr,ordinality)
 WHERE g.series_scope IS NULL
    OR (g.series_scope='*not_ti*' AND lower(t.series_code)<>'ti')
    OR lower(t.series_code)=lower(g.series_scope)
),
deduplicated AS (
 SELECT e.*,row_number() OVER (
   PARTITION BY e.curriculum_id,lower(trim(e.title_fr))
   ORDER BY CASE WHEN e.verification_status='verified' THEN 0 ELSE 1 END,e.seed_position,e.source_url
 ) AS title_rank
 FROM expanded e
 WHERE length(trim(e.title_fr))>0
   AND NOT EXISTS (
     SELECT 1 FROM public.course_chapters ch
     WHERE ch.curriculum_id=e.curriculum_id
       AND lower(trim(ch.title_fr))=lower(trim(e.title_fr))
   )
),
chosen AS (SELECT * FROM deduplicated WHERE title_rank=1),
positioned AS (
 SELECT c.*,coalesce(m.max_position,0)+row_number() OVER (
    PARTITION BY c.curriculum_id ORDER BY c.seed_position,c.title_fr
 ) AS new_position
 FROM chosen c
 LEFT JOIN LATERAL (
   SELECT max(ch.position) max_position FROM public.course_chapters ch
   WHERE ch.curriculum_id=c.curriculum_id
 ) m ON TRUE
)
INSERT INTO public.course_chapters
 (curriculum_id,title_fr,title_en,description_fr,description_en,position,is_active,
  verification_status,source_url,source_title)
SELECT p.curriculum_id,trim(p.title_fr),trim(p.title_fr),
 CASE WHEN p.verification_status='verified'
      THEN 'Titre relevé dans une ressource de programme MINESEC citée. Aucun contenu de cours n’est prérempli.'
      ELSE 'Titre repéré ou proposé pour structurer la page; la correspondance exacte classe/série doit être confirmée. Aucun contenu de cours n’est prérempli.' END,
 CASE WHEN p.verification_status='verified'
      THEN 'Heading transcribed from the cited MINESEC curriculum source. No lesson content is prefilled.'
      ELSE 'Heading captured or proposed for structure; verify the exact class/series match. No lesson content is prefilled.' END,
 p.new_position,TRUE,p.verification_status,p.source_url,p.source_title
FROM positioned p;


-- Fallbacks are title-only structural suggestions, explicitly marked for official title review.
-- They are inserted only into catalog pages still empty after source-backed titles above.
WITH pages AS (
 SELECT c.id AS curriculum_id, el.code AS level_code, s.code AS subject_code,
        coalesce(se.code,'') AS series_code,
        coalesce(sp.code,'') AS specialty_code
 FROM public.curricula c
 JOIN public.exam_levels el ON el.id=c.exam_level_id
 JOIN public.subjects s ON s.id=c.subject_id
 LEFT JOIN public.series se ON se.id=c.series_id
 LEFT JOIN public.specialties sp ON sp.id=c.specialty_id
 WHERE c.is_catalog_container IS TRUE AND c.is_active IS TRUE
   AND c.subsystem='francophone' AND c.sector='general'
   AND NOT EXISTS (SELECT 1 FROM public.course_chapters ch WHERE ch.curriculum_id=c.id AND ch.is_active IS TRUE)
),
templates AS (
 SELECT p.*,
 CASE
  WHEN subject_code='mathematiques' AND level_code='fr_general_sixieme' THEN ARRAY['Ensemble IN des entiers naturels','Droite du plan','Nombres décimaux arithmétiques','Fractions','Mesures et grandeurs','Géométrie plane']::text[]
  WHEN subject_code='mathematiques' AND level_code='fr_general_cinquieme' THEN ARRAY['Arithmétique','Distances','Fractions','Nombres décimaux relatifs','Calcul littéral','Géométrie et mesures']::text[]
  WHEN subject_code='mathematiques' AND level_code='fr_general_quatrieme' THEN ARRAY['Nombres rationnels et puissances','Calcul littéral','Équations et inéquations','Théorème de Pythagore','Théorème de Thalès','Transformations du plan','Statistiques']::text[]
  WHEN subject_code='mathematiques' AND level_code='fr_general_troisieme' THEN ARRAY['Arithmétique','Thalès dans le triangle','Nombres réels','Fonctions numériques','Trigonométrie','Statistiques']::text[]
  WHEN subject_code='mathematiques' AND level_code='fr_general_seconde' THEN ARRAY['Calculs dans IR','Vecteurs du plan','Équations et inéquations','Fonctions numériques','Géométrie analytique','Statistiques et probabilités']::text[]
  WHEN subject_code='mathematiques' AND level_code='fr_general_premiere' THEN ARRAY['Calcul algébrique','Fonctions numériques','Limites et continuité','Dérivation','Suites numériques','Géométrie','Statistiques et probabilités']::text[]
  WHEN subject_code='mathematiques' AND level_code='fr_general_terminale' THEN ARRAY['Arithmétique dans Z','Nombres complexes','Fonctions numériques','Suites numériques','Probabilités','Calcul intégral']::text[]
  WHEN subject_code='histoire' AND level_code='fr_general_sixieme' THEN ARRAY['La notion d’Histoire','L’Afrique, berceau de l’humanité','L’Égypte ancienne','Les civilisations anciennes d’Asie','La civilisation judéo-chrétienne']::text[]
  WHEN subject_code='histoire' AND level_code='fr_general_cinquieme' THEN ARRAY['Peuplement et organisation socio-politique du Cameroun','L’âge d’or de l’Afrique','Les relations entre l’Afrique et le reste du monde']::text[]
  WHEN subject_code='histoire' AND level_code='fr_general_quatrieme' THEN ARRAY['Les sociétés et civilisations africaines','L’Afrique et le monde atlantique','La traite négrière et l’esclavage','Les transformations politiques et économiques']::text[]
  WHEN subject_code='histoire' AND level_code='fr_general_troisieme' THEN ARRAY['L’impérialisme en Afrique','Les grandes crises de la première moitié du XXe siècle','La décolonisation','De la création du Kamerun au mandat','La naissance de l’État du Cameroun']::text[]
  WHEN subject_code='histoire' AND level_code='fr_general_seconde' THEN ARRAY['Les disciplines affinitaires de l’histoire','Les civilisations anciennes','Les États de l’Afrique soudanaise','Les États de l’Afrique forestière','L’Europe féodale']::text[]
  WHEN subject_code='histoire' AND level_code='fr_general_premiere' THEN ARRAY['Le monde au XIXe siècle','L’Afrique à l’époque contemporaine','La colonisation et ses conséquences','Les mouvements nationalistes et les indépendances']::text[]
  WHEN subject_code='histoire' AND level_code='fr_general_terminale' THEN ARRAY['La Deuxième Guerre mondiale','La décolonisation','La guerre froide et la bipolarisation du monde','Les relations internationales depuis 1945']::text[]
  WHEN subject_code='geographie' AND level_code='fr_general_sixieme' THEN ARRAY['S’adapter aux influences cosmiques','La Terre dans l’Univers','Les composantes naturelles de l’environnement','Les perturbations climatiques']::text[]
  WHEN subject_code='geographie' AND level_code='fr_general_cinquieme' THEN ARRAY['L’Homme dans son milieu de vie','L’occupation de l’espace','Protéger l’environnement','Gérer les migrations']::text[]
  WHEN subject_code='geographie' AND level_code='fr_general_quatrieme' THEN ARRAY['Gérer durablement l’environnement','Les reliefs et les sols de l’Afrique','Le climat et la végétation de l’Afrique','Les populations et les activités humaines']::text[]
  WHEN subject_code='geographie' AND level_code='fr_general_troisieme' THEN ARRAY['Préserver un environnement sain au Cameroun','Le relief et les paysages du Cameroun','Le peuplement et la population du Cameroun','Les activités économiques du Cameroun']::text[]
  WHEN subject_code='geographie' AND level_code='fr_general_seconde' THEN ARRAY['La terre et les mouvements tectoniques','Les reliefs terrestres et leur évolution','Les milieux naturels','Les activités humaines et l’environnement']::text[]
  WHEN subject_code='geographie' AND level_code='fr_general_premiere' THEN ARRAY['Maîtriser la croissance démographique','Limiter les migrations','Les dynamiques urbaines','Les activités économiques et l’aménagement du territoire']::text[]
  WHEN subject_code='geographie' AND level_code='fr_general_terminale' THEN ARRAY['Promouvoir le développement intégré']::text[]
  WHEN subject_code='education_civique' AND level_code='fr_general_sixieme' THEN ARRAY['Introduction','La famille','La protection de la famille','De la maison à l’école','L’élève dans son établissement','Le divorce','La succession','Les conflits à l’école','Les droits fondamentaux']::text[]
  WHEN subject_code='education_civique' AND level_code='fr_general_cinquieme' THEN ARRAY['La famille et la vie sociale','L’élève dans la communauté scolaire','Les droits et les devoirs','La citoyenneté','La protection de l’environnement et de la santé']::text[]
  WHEN subject_code='education_civique' AND level_code='fr_general_quatrieme' THEN ARRAY['La vie familiale et sociale','Les droits et les devoirs du citoyen','La démocratie et les institutions','La protection des personnes et des biens']::text[]
  WHEN subject_code='education_civique' AND level_code='fr_general_troisieme' THEN ARRAY['Généralités sur la démocratie','Les fondements de la démocratie','Les formes de démocratie','Les élections au Cameroun','Le processus électoral au Cameroun']::text[]
  WHEN subject_code='education_civique' AND level_code='fr_general_seconde' THEN ARRAY['La nation et l’État','La Constitution et les institutions de la République','Les droits et les devoirs du citoyen','La participation à la vie démocratique']::text[]
  WHEN subject_code='education_civique' AND level_code='fr_general_premiere' THEN ARRAY['Citoyenneté et participation politique','Les institutions et les pouvoirs publics','Les droits humains et les libertés','La décentralisation et l’administration territoriale']::text[]
  WHEN subject_code='education_civique' AND level_code='fr_general_terminale' THEN ARRAY['Les principes de la diplomatie camerounaise','Le Cameroun dans la coopération multilatérale']::text[]
  WHEN subject_code='sciences' AND level_code IN ('fr_general_sixieme','fr_general_cinquieme') THEN ARRAY['Le monde vivant','La matière : ses propriétés et ses transformations','L’énergie : ses sources et sa gestion','L’éducation à la santé','L’éducation à l’environnement et au développement durable','Technologie']::text[]
  WHEN subject_code='svt' AND level_code IN ('fr_general_seconde','fr_general_premiere','fr_general_terminale') THEN ARRAY['Le monde vivant','L’éducation à la santé','L’éducation à l’environnement et au développement durable','La biotechnologie']::text[]
  WHEN subject_code='pct' THEN ARRAY['La matière et ses transformations','L’énergie et ses transformations','Mécanique et équilibre','Optique','Électricité et circuits','Technologie et réalisation d’un projet']::text[]
  WHEN subject_code='physique' AND level_code='fr_general_seconde' THEN ARRAY['Mesure d’une grandeur','Expression du résultat de la mesure','La relativité du mouvement','Les paramètres cinématiques','Les types de mouvements','Équilibre d’un solide','Optique et lumière','Électronique']::text[]
  WHEN subject_code='physique' AND level_code='fr_general_premiere' THEN ARRAY['Mesure des grandeurs physiques et chimiques','Modélisation d’un phénomène','Travail d’une force','Énergie cinétique','Conservation de l’énergie mécanique','Transfert de chaleur']::text[]
  WHEN subject_code='physique' AND level_code='fr_general_terminale' THEN ARRAY['Mesures et incertitudes','Équations aux dimensions','Interaction gravitationnelle','Interaction électrique','Électromagnétisme','Oscillations et énergie']::text[]
  WHEN subject_code='chimie' AND level_code='fr_general_seconde' THEN ARRAY['Structure de la matière et analyse élémentaire des composés organiques','Solutions aqueuses','Structure électronique des atomes','Classification périodique','Chimie organique']::text[]
  WHEN subject_code='chimie' AND level_code='fr_general_premiere' THEN ARRAY['Les alcanes','Les alcènes et les alcynes','Les composés oxygénés','Les composés aromatiques','Oxydoréduction en solution aqueuse']::text[]
  WHEN subject_code='chimie' AND level_code='fr_general_terminale' THEN ARRAY['Propriétés chimiques des alcools','Les acides carboxyliques','Les amines','Les acides alpha aminés','Synthèse des polypeptides']::text[]
  WHEN subject_code='informatique' AND level_code='fr_general_terminale' AND lower(series_code)='ti' THEN ARRAY['Conception et implémentation d’une base de données','Configuration d’un serveur web','Configuration et services réseau','Programmation en HTML et JavaScript','Sécurité informatique','Réalisation et présentation du projet']::text[]
  WHEN subject_code='informatique' AND level_code='fr_general_terminale' THEN ARRAY['Conception des modèles de données d’un système d’information','Configuration d’un réseau informatique','Architecture d’un système informatique','Algorithmes et structures de données','Implémentation d’une base de données','Production de contenus numériques','Protection d’un environnement de travail']::text[]
  WHEN subject_code='informatique' AND level_code='fr_general_sixieme' THEN ARRAY['Découvrir l’environnement informatique','Les composants d’un ordinateur','Fichiers et dossiers','Logiciels et applications','Sécurité et bon usage du numérique']::text[]
  WHEN subject_code='informatique' AND level_code='fr_general_cinquieme' THEN ARRAY['Gestion des fichiers et dossiers','Traitement de texte','Recherche d’information','Communication numérique','Algorithmique et résolution de problèmes']::text[]
  WHEN subject_code='informatique' AND level_code IN ('fr_general_quatrieme','fr_general_troisieme') THEN ARRAY['Architecture d’un système informatique','Traitement de texte et tableur','Internet et réseaux','Algorithmique','Programmation','Sécurité numérique']::text[]
  WHEN subject_code='informatique' THEN ARRAY['Architecture des systèmes informatiques','Algorithmes et programmation','Traitement et représentation des données','Bases de données','Réseaux informatiques','Sécurité numérique','Projet numérique']::text[]
  WHEN subject_code='francais' AND level_code IN ('fr_general_sixieme','fr_general_cinquieme','fr_general_quatrieme','fr_general_troisieme') THEN ARRAY['Vie familiale et intégration sociale','Environnement, bien-être et santé','Citoyenneté et ouverture au monde','Activités économiques et monde du travail','Médias et communication','Compréhension et production de textes','Fonctionnement de la langue']::text[]
  WHEN subject_code='francais' THEN ARRAY['Compréhension et analyse de textes','Expression écrite et orale','Genres littéraires et procédés d’écriture','Grammaire et maîtrise de la langue','Lecture et culture littéraire','Argumentation et communication']::text[]
  WHEN subject_code IN ('anglais','allemand','arabe','chinois','espagnol','italien') AND level_code IN ('fr_general_sixieme','fr_general_cinquieme') THEN ARRAY['Vie familiale et sociale','Environnement, bien-être et santé','Citoyenneté et ouverture au monde','Activités économiques et monde du travail','Médias et communication']::text[]
  WHEN subject_code IN ('anglais','allemand','arabe','chinois','espagnol','italien') AND level_code IN ('fr_general_quatrieme','fr_general_troisieme') THEN ARRAY['Vie familiale et intégration sociale','Environnement et santé','Vie citoyenne et ouverture au monde','Activités économiques et monde du travail','Communication et médias (TIC)']::text[]
  WHEN subject_code IN ('anglais','allemand','arabe','chinois','espagnol','italien') THEN ARRAY['Vie familiale et socioculturelle','Communication et relations sociales','Environnement, santé et cadre de vie','Éducation, avenir et citoyenneté','Vie économique et projets','Médias et communication']::text[]
  WHEN subject_code='langues_nationales' THEN ARRAY['Vie familiale et sociale','Langues et cultures du Cameroun','Patrimoine et traditions','Citoyenneté et intégration nationale','Environnement et vie communautaire']::text[]
  WHEN subject_code='eps' THEN ARRAY['Athlétisme et activités de course','Sports collectifs','Sports individuels','Gymnastique et motricité','Condition physique, santé et sécurité']::text[]
  WHEN subject_code='education_artistique' THEN ARRAY['Arts plastiques et expression visuelle','Éducation musicale','Patrimoine artistique et culturel camerounais','Techniques et matériaux artistiques','Création et présentation d’une production']::text[]
  WHEN subject_code='travail_manuel' THEN ARRAY['Matériaux, outils et sécurité','Conception et fabrication d’objets usuels','Techniques de transformation','Réparation et entretien','Réalisation d’un projet technique','Hygiène et protection de l’environnement']::text[]
  WHEN subject_code='philosophie' THEN ARRAY['La réflexion philosophique','Le sujet et la conscience','La connaissance et la vérité','La liberté et la responsabilité','La société et la politique','Le travail et la technique','La morale et la religion','La science et le progrès']::text[]
  WHEN subject_code='litterature' THEN ARRAY['Les genres littéraires','La poésie','Le roman','Le théâtre','La nouvelle et le conte','La littérature camerounaise et africaine','L’analyse et le commentaire de texte']::text[]
  WHEN subject_code='arts_cinematographiques' THEN ARRAY['Histoire du cinéma','Langage cinématographique','Écriture et scénario','Image et prise de vue','Son et montage','Mise en scène','Production et diffusion','Analyse d’œuvres cinématographiques']::text[]
  WHEN subject_code='commerce_fr' THEN ARRAY['L’entreprise et son environnement','Documents commerciaux','Les échanges commerciaux','Organisation des activités commerciales','Communication commerciale','Techniques de vente et relation client']::text[]
  WHEN subject_code='comptabilite_fr' THEN ARRAY['Principes et vocabulaire comptables','Pièces justificatives et documents comptables','Enregistrement des opérations','Comptes et journal','Balance et travaux d’inventaire','États financiers de base']::text[]
  WHEN subject_code IN ('latin','grec') THEN ARRAY['Vie familiale et socioculturelle','Citoyenneté, environnement, santé et bien-être','Vie économique','Média et communication']::text[]
  ELSE ARRAY['Vie familiale et sociale','Environnement, bien-être et santé','Citoyenneté et ouverture au monde','Activités économiques et monde du travail','Médias et communication']::text[]
 END AS titles
 FROM pages p
),
expanded AS (
 SELECT t.curriculum_id, u.title_fr, u.ordinality::integer seed_position
 FROM templates t
 CROSS JOIN LATERAL unnest(t.titles) WITH ORDINALITY AS u(title_fr, ordinality)
 WHERE length(trim(u.title_fr))>0
),
deduplicated AS (
 SELECT e.*, row_number() OVER (
   PARTITION BY e.curriculum_id, lower(trim(e.title_fr))
   ORDER BY e.seed_position
 ) AS title_rank
 FROM expanded e
 WHERE NOT EXISTS (
   SELECT 1 FROM public.course_chapters ch
   WHERE ch.curriculum_id=e.curriculum_id
     AND ch.is_active IS TRUE
     AND lower(trim(ch.title_fr))=lower(trim(e.title_fr))
 )
),
chosen AS (SELECT * FROM deduplicated WHERE title_rank=1),
positioned AS (
 SELECT c.*, coalesce(m.max_position,0)+row_number() OVER (
   PARTITION BY c.curriculum_id ORDER BY c.seed_position,c.title_fr
 ) AS new_position
 FROM chosen c
 LEFT JOIN LATERAL (
   SELECT max(ch.position) AS max_position FROM public.course_chapters ch
   WHERE ch.curriculum_id=c.curriculum_id
 ) m ON TRUE
)
INSERT INTO public.course_chapters
 (curriculum_id,title_fr,title_en,description_fr,description_en,position,is_active,
  verification_status,source_url,source_title)
SELECT p.curriculum_id,p.title_fr,p.title_fr,
 'Titre de structuration provisoire. À vérifier avec le sommaire exact du programme MINESEC correspondant à cette classe, matière et série. Aucun cours, exercice, QCM ou média n’est créé.',
 'Provisional chapter heading; confirm the exact MINESEC syllabus mapping for this class, subject and series. No lesson, exercise, quiz or media is created.',
 p.new_position,TRUE,'pending_official_confirmation','https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels',
 'MINESEC — programme officiel; titre provisoire à valider pour le contexte de la classe'
FROM positioned p
WHERE NOT EXISTS (
 SELECT 1 FROM public.course_chapters ch
 WHERE ch.curriculum_id=p.curriculum_id
   AND ch.is_active IS TRUE
   AND lower(trim(ch.title_fr))=lower(trim(p.title_fr))
);


COMMIT;
