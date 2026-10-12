-- Fise School — verified MINESEC module and chapter-title catalogue.
-- This migration stores titles only. It never inserts lesson text, PDFs, exercises or quizzes.
-- Sources are official MINESEC study programmes; titles are scoped to the matching level,
-- subsystem, sector and series so a title from one class is not shown in another class.
-- The full national catalogue is intentionally additive: add another source-backed record
-- rather than guessing titles where an official programme has not yet been verified.

do $$
declare
  item record;
  v_level_id uuid;
  v_subject_id uuid;
  v_series_id uuid;
  v_curriculum_id uuid;
begin
  for item in
    select * from (values
      -- Francophone general, first cycle: History, Geography and Sciences.
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Afrique dans la pensée et l’édification du monde actuel','Legacy of Ancient African Civilizations in Today’s World','https://files.minesec.gov.cm/direct/view.php?%2FHISTOIRE_6e_5e_ESG.pdf=&s=2g'),
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Europe et d’Asie dans la pensée et l’édification du monde actuel','Legacy of Ancient European and Asian Civilizations in Today’s World','https://files.minesec.gov.cm/direct/view.php?%2FHISTOIRE_6e_5e_ESG.pdf=&s=2g'),
      ('fr_general_sixieme','histoire',null,'L’apport des religions monothéistes dans la pensée et l’édification du monde actuel','The Contribution of Monotheistic Religions to Today’s World','https://files.minesec.gov.cm/direct/view.php?%2FHISTOIRE_6e_5e_ESG.pdf=&s=2g'),
      ('fr_general_cinquieme','histoire',null,'Peuplement et organisation socio-politique du Cameroun','Settlement and Sociopolitical Organization of Cameroon','https://files.minesec.gov.cm/direct/view.php?%2FHISTOIRE_6e_5e_ESG.pdf=&s=2g'),
      ('fr_general_cinquieme','histoire',null,'L’âge d’or de l’Afrique','Africa’s Golden Age','https://files.minesec.gov.cm/direct/view.php?%2FHISTOIRE_6e_5e_ESG.pdf=&s=2g'),
      ('fr_general_cinquieme','histoire',null,'Les relations entre l’Afrique et le reste du monde','Africa and the Rest of the World','https://files.minesec.gov.cm/direct/view.php?%2FHISTOIRE_6e_5e_ESG.pdf=&s=2g'),

      ('fr_general_sixieme','geographie',null,'La Terre dans l’Univers','Earth in the Universe','https://files.minesec.gov.cm/direct/view.php?%2FGEOGRAPHIE_6e_5e_ESG.pdf=&s=2f'),
      ('fr_general_sixieme','geographie',null,'Préservons notre environnement','Let Us Preserve Our Environment','https://files.minesec.gov.cm/direct/view.php?%2FGEOGRAPHIE_6e_5e_ESG.pdf=&s=2f'),
      ('fr_general_sixieme','geographie',null,'Protégeons-nous des colères de la nature','Protecting Ourselves from Natural Hazards','https://files.minesec.gov.cm/direct/view.php?%2FGEOGRAPHIE_6e_5e_ESG.pdf=&s=2f'),
      ('fr_general_cinquieme','geographie',null,'L’Homme dans son milieu de vie','People in Their Living Environment','https://files.minesec.gov.cm/direct/view.php?%2FGEOGRAPHIE_6e_5e_ESG.pdf=&s=2f'),
      ('fr_general_cinquieme','geographie',null,'L’occupation de l’espace','Human Occupation of Space','https://files.minesec.gov.cm/direct/view.php?%2FGEOGRAPHIE_6e_5e_ESG.pdf=&s=2f'),

      ('fr_general_sixieme','sciences',null,'Le monde vivant','The Living World','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),
      ('fr_general_sixieme','sciences',null,'La matière : ses propriétés et ses transformations','Matter: Properties and Transformations','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),
      ('fr_general_sixieme','sciences',null,'L’énergie : ses sources et sa gestion','Energy: Sources and Management','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),
      ('fr_general_sixieme','sciences',null,'L’Éducation à la santé','Health Education','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),
      ('fr_general_sixieme','sciences',null,'L’Éducation à l’Environnement et au Développement Durable','Environmental and Sustainable Development Education','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),
      ('fr_general_sixieme','sciences',null,'Technologie','Technology','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),
      ('fr_general_cinquieme','sciences',null,'Le monde vivant','The Living World','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),
      ('fr_general_cinquieme','sciences',null,'La matière : ses propriétés et ses transformations','Matter: Properties and Transformations','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),
      ('fr_general_cinquieme','sciences',null,'L’énergie : ses sources et sa gestion','Energy: Sources and Management','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),
      ('fr_general_cinquieme','sciences',null,'L’Éducation à la santé','Health Education','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),
      ('fr_general_cinquieme','sciences',null,'L’Éducation à l’Environnement et au Développement Durable','Environmental and Sustainable Development Education','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),
      ('fr_general_cinquieme','sciences',null,'Technologie','Technology','https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d'),

      -- Terminale general and technical Geography programmes.
      ('fr_general_terminale','geographie',null,'Le Cameroun','Cameroon','https://files.minesec.gov.cm/direct/view.php?%2FPROGRAMME_GEO_Tle-ESG.pdf=&s=jo'),
      ('fr_general_terminale','geographie',null,'La libéralisation des échanges','Trade Liberalization','https://files.minesec.gov.cm/direct/view.php?%2FPROGRAMME_GEO_Tle-ESG.pdf=&s=jo'),
      ('fr_technical_terminale','fr_tech_histoire_geo',null,'Le Cameroun','Cameroon','https://files.minesec.gov.cm/direct/view.php?%2FPROGRAMME_GEO_Tle-EST.pdf=&s=jp'),
      ('fr_technical_terminale','fr_tech_histoire_geo',null,'La libéralisation des échanges','Trade Liberalization','https://files.minesec.gov.cm/direct/view.php?%2FPROGRAMME_GEO_Tle-EST.pdf=&s=jp'),

      -- Terminale C/D/E and Terminale A/ABI/SH/AC Informatics programmes.
      ('fr_general_terminale','informatique','a1','Module 1 : Systèmes informatiques et humanités numériques','Module 1: Computer Systems and Digital Humanities','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a2','Module 1 : Systèmes informatiques et humanités numériques','Module 1: Computer Systems and Digital Humanities','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a3','Module 1 : Systèmes informatiques et humanités numériques','Module 1: Computer Systems and Digital Humanities','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a4','Module 1 : Systèmes informatiques et humanités numériques','Module 1: Computer Systems and Digital Humanities','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a5','Module 1 : Systèmes informatiques et humanités numériques','Module 1: Computer Systems and Digital Humanities','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','ac','Module 1 : Systèmes informatiques et humanités numériques','Module 1: Computer Systems and Digital Humanities','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a1','Module 2 : Systèmes d’information et bases de données','Module 2: Information Systems and Databases','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a2','Module 2 : Systèmes d’information et bases de données','Module 2: Information Systems and Databases','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a3','Module 2 : Systèmes d’information et bases de données','Module 2: Information Systems and Databases','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a4','Module 2 : Systèmes d’information et bases de données','Module 2: Information Systems and Databases','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a5','Module 2 : Systèmes d’information et bases de données','Module 2: Information Systems and Databases','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','ac','Module 2 : Systèmes d’information et bases de données','Module 2: Information Systems and Databases','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a1','Module 3 : Production des contenus numériques','Module 3: Digital Content Production','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a2','Module 3 : Production des contenus numériques','Module 3: Digital Content Production','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a3','Module 3 : Production des contenus numériques','Module 3: Digital Content Production','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a4','Module 3 : Production des contenus numériques','Module 3: Digital Content Production','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','a5','Module 3 : Production des contenus numériques','Module 3: Digital Content Production','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),
      ('fr_general_terminale','informatique','ac','Module 3 : Production des contenus numériques','Module 3: Digital Content Production','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh'),

      -- Terminale TI: series-scoped, so it does not leak to other Terminale classes.
      ('fr_general_terminale','informatique','ti','Module 1 : Programmation','Module 1: Programming','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_T_TI_06_08_2020.pdf=&s=jk'),
      ('fr_general_terminale','informatique','ti','Module 2 : Réseaux, internet et sécurité informatique','Module 2: Networks, Internet and IT Security','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_T_TI_06_08_2020.pdf=&s=jk'),
      ('fr_general_terminale','informatique','ti','Module 3 : Systèmes d’information et bases de données','Module 3: Information Systems and Databases','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_T_TI_06_08_2020.pdf=&s=jk'),
      ('fr_general_terminale','informatique','ti','Module 4 : Projet','Module 4: Project','https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_T_TI_06_08_2020.pdf=&s=jk'),

      -- Seconde C physics: restrict to the C series.
      ('fr_general_seconde','physique','c','Mesures et incertitudes','Measurements and Uncertainties','https://files.minesec.gov.cm/direct/view.php?%2FProjet_de_programme_de_Physique_2nde_C_-_Final.pdf=&s=iw'),
      ('fr_general_seconde','physique','c','Mouvements et interactions mécaniques','Motion and Mechanical Interactions','https://files.minesec.gov.cm/direct/view.php?%2FProjet_de_programme_de_Physique_2nde_C_-_Final.pdf=&s=iw'),
      ('fr_general_seconde','physique','c','Propagation rectiligne de la lumière','Rectilinear Propagation of Light','https://files.minesec.gov.cm/direct/view.php?%2FProjet_de_programme_de_Physique_2nde_C_-_Final.pdf=&s=iw'),
      ('fr_general_seconde','physique','c','Résistors, diodes et transistors bipolaires, portes logiques','Resistors, Diodes, Bipolar Transistors and Logic Gates','https://files.minesec.gov.cm/direct/view.php?%2FProjet_de_programme_de_Physique_2nde_C_-_Final.pdf=&s=iw')
    ) as x(level_code, subject_code, series_code, title_fr, title_en, source_url)
  loop
    select id into v_level_id
    from public.exam_levels
    where code = item.level_code and active
    limit 1;

    select id into v_subject_id
    from public.subjects
    where code = item.subject_code and is_active
      and subsystem = (select subsystem from public.exam_levels where id = v_level_id)
      and sector = (select sector from public.exam_levels where id = v_level_id)
    limit 1;

    if v_level_id is null or v_subject_id is null then
      raise notice 'Skipping official title set for level %, subject %: catalogue row missing', item.level_code, item.subject_code;
      continue;
    end if;

    v_series_id := null;
    if item.series_code is not null then
      select id into v_series_id from public.series where code = item.series_code and active limit 1;
      if v_series_id is null then
        raise notice 'Skipping official title set for missing series %', item.series_code;
        continue;
      end if;
    end if;

    select id into v_curriculum_id
    from public.curricula
    where subject_id = v_subject_id
      and exam_level_id = v_level_id
      and series_id is not distinct from v_series_id
      and specialty_id is null
      and title_fr = item.title_fr
    limit 1;

    if v_curriculum_id is null then
      insert into public.curricula
        (subject_id, subsystem, sector, exam_level_id, series_id, specialty_id,
         title_fr, title_en, description_fr, description_en, is_active)
      select v_subject_id, el.subsystem, el.sector, v_level_id, v_series_id, null,
        item.title_fr, item.title_en,
        'Titre du programme officiel MINESEC. Source : ' || item.source_url,
        'Official programme title. Source: ' || item.source_url,
        true
      from public.exam_levels el where el.id = v_level_id
      returning id into v_curriculum_id;
    else
      update public.curricula
      set title_en = item.title_en,
          description_fr = 'Titre du programme officiel MINESEC. Source : ' || item.source_url,
          description_en = 'Official programme title. Source: ' || item.source_url,
          is_active = true,
          updated_at = now()
      where id = v_curriculum_id;
    end if;
    v_curriculum_id := null;
  end loop;
end $$;

-- Repair the first Terminale C/D/E Informatics tranche so it is explicitly scoped
-- to Terminale; without exam_level_id a series-based curriculum could leak into Seconde/Première.
update public.curricula c
set exam_level_id = el.id,
    updated_at = now()
from public.subjects s,
     public.exam_levels el,
     public.series sr
where c.subject_id = s.id
  and c.series_id = sr.id
  and c.exam_level_id is null
  and s.code = 'informatique'
  and s.subsystem = 'francophone'
  and s.sector = 'general'
  and sr.code in ('c','d','e')
  and el.code = 'fr_general_terminale'
  and el.active
  and c.title_fr in (
    'Module 1 : Systèmes informatiques',
    'Module 2 : Systèmes d’information et bases de données',
    'Module 3 : Algorithmique et programmation'
  );

-- Chapter and component headings. These are titles only; the source documents
-- distinguish each module from its internal topics, which this app displays as chapter headings.
do $$
declare
  item record;
  v_level_id uuid;
  v_subject_id uuid;
  v_series_id uuid;
  v_curriculum_id uuid;
begin
  for item in
    select * from (values
      -- History, Form 6e.
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Afrique dans la pensée et l’édification du monde actuel',1,'Introduction à l’étude de l’Histoire','Introduction to the Study of History'),
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Afrique dans la pensée et l’édification du monde actuel',2,'L’Afrique, berceau de l’humanité','Africa, Cradle of Humanity'),
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Afrique dans la pensée et l’édification du monde actuel',3,'Les premiers hommes et leur mode de vie','Early Humans and Their Way of Life'),
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Afrique dans la pensée et l’édification du monde actuel',4,'Les civilisations du Néolithique au Cameroun','Neolithic Civilizations in Cameroon'),
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Afrique dans la pensée et l’édification du monde actuel',5,'L’Égypte ancienne : son legs','Ancient Egypt and Its Legacy'),
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Afrique dans la pensée et l’édification du monde actuel',6,'Les avancées scientifiques et techniques dans l’Égypte ancienne','Scientific and Technical Advances in Ancient Egypt'),
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Afrique dans la pensée et l’édification du monde actuel',7,'Le culte des morts dans l’Égypte ancienne','Funerary Practices in Ancient Egypt'),
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Europe et d’Asie dans la pensée et l’édification du monde actuel',1,'Les civilisations d’Europe','European Civilizations'),
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Europe et d’Asie dans la pensée et l’édification du monde actuel',2,'La Grèce antique','Ancient Greece'),
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Europe et d’Asie dans la pensée et l’édification du monde actuel',3,'Les civilisations anciennes d’Asie','Ancient Asian Civilizations'),
      ('fr_general_sixieme','histoire',null,'Le legs des civilisations anciennes d’Europe et d’Asie dans la pensée et l’édification du monde actuel',4,'La Chine : essor des sciences et des techniques, vie culturelle et religieuse','China: Science, Technology, Culture and Religion'),
      ('fr_general_sixieme','histoire',null,'L’apport des religions monothéistes dans la pensée et l’édification du monde actuel',1,'La civilisation judéo-chrétienne','Judeo-Christian Civilization'),
      ('fr_general_sixieme','histoire',null,'L’apport des religions monothéistes dans la pensée et l’édification du monde actuel',2,'Le judaïsme et le christianisme','Judaism and Christianity'),
      ('fr_general_sixieme','histoire',null,'L’apport des religions monothéistes dans la pensée et l’édification du monde actuel',3,'L’expansion du christianisme en Afrique','The Expansion of Christianity in Africa'),

      -- History, Form 5e.
      ('fr_general_cinquieme','histoire',null,'Peuplement et organisation socio-politique du Cameroun',1,'Peuplement du Cameroun : les vagues successives de migrations','Settlement of Cameroon: Successive Migration Waves'),
      ('fr_general_cinquieme','histoire',null,'Peuplement et organisation socio-politique du Cameroun',2,'Les migrations anciennes','Ancient Migrations'),
      ('fr_general_cinquieme','histoire',null,'Peuplement et organisation socio-politique du Cameroun',3,'Les migrations récentes','Recent Migrations'),
      ('fr_general_cinquieme','histoire',null,'L’âge d’or de l’Afrique',1,'L’Afrique occidentale','West Africa'),
      ('fr_general_cinquieme','histoire',null,'L’âge d’or de l’Afrique',2,'Le Ghana du IXe au Xe siècle','Ghana from the 9th to the 10th Century'),
      ('fr_general_cinquieme','histoire',null,'L’âge d’or de l’Afrique',3,'Le Mali','Mali'),
      ('fr_general_cinquieme','histoire',null,'Les relations entre l’Afrique et le reste du monde',1,'Les contacts de l’Afrique occidentale et soudanaise avec le monde extérieur','Contacts between West/Sudanese Africa and the Outside World'),
      ('fr_general_cinquieme','histoire',null,'Les relations entre l’Afrique et le reste du monde',2,'Les contacts avec le monde arabe et l’Europe','Contacts with the Arab World and Europe'),

      -- Geography, first cycle. Exact module names follow the MINESEC synopsis.
      ('fr_general_sixieme','geographie',null,'La Terre dans l’Univers',1,'La géographie : définition, domaines, méthodes et utilité','Geography: Definition, Scope, Methods and Use'),
      ('fr_general_sixieme','geographie',null,'La Terre dans l’Univers',2,'La Terre : une planète du système solaire','Earth: A Planet in the Solar System'),
      ('fr_general_sixieme','geographie',null,'Préservons notre environnement',1,'Les composantes naturelles de l’environnement','The Natural Components of the Environment'),
      ('fr_general_sixieme','geographie',null,'Protégeons-nous des colères de la nature',1,'Les perturbations climatiques','Climate Disturbances'),
      ('fr_general_cinquieme','geographie',null,'L’Homme dans son milieu de vie',1,'L’Homme dans son milieu de vie','People in Their Living Environment'),
      ('fr_general_cinquieme','geographie',null,'L’occupation de l’espace',1,'L’occupation de l’espace','Human Occupation of Space'),

      -- Sciences 6e/5e: official module component headings.
      ('fr_general_sixieme','sciences',null,'Le monde vivant',1,'Amélioration de la production végétale et animale','Improving Plant and Animal Production'),
      ('fr_general_sixieme','sciences',null,'Le monde vivant',2,'Gestion des ressources naturelles, alimentaires et médicinales','Management of Natural, Food and Medicinal Resources'),
      ('fr_general_sixieme','sciences',null,'La matière : ses propriétés et ses transformations',1,'Détermination des caractéristiques physiques et chimiques d’un corps','Determining the Physical and Chemical Characteristics of a Body'),
      ('fr_general_sixieme','sciences',null,'L’énergie : ses sources et sa gestion',1,'Utilisation de quelques formes d’énergie','Using Different Forms of Energy'),
      ('fr_general_sixieme','sciences',null,'L’Éducation à la santé',1,'Lutte contre les grossesses précoces','Preventing Early Pregnancy'),
      ('fr_general_sixieme','sciences',null,'L’Éducation à la santé',2,'Hygiène des appareils reproducteurs','Reproductive Health and Hygiene'),
      ('fr_general_sixieme','sciences',null,'L’Éducation à la santé',3,'Lutte contre les maladies par carence et par excès alimentaires','Preventing Nutritional Deficiency and Excess Diseases'),
      ('fr_general_sixieme','sciences',null,'L’Éducation à l’Environnement et au Développement Durable',1,'Lutte contre la pollution de l’air','Preventing Air Pollution'),
      ('fr_general_sixieme','sciences',null,'L’Éducation à l’Environnement et au Développement Durable',2,'Lutte contre la dégradation des sols','Preventing Soil Degradation'),
      ('fr_general_sixieme','sciences',null,'L’Éducation à l’Environnement et au Développement Durable',3,'Lutte contre la pollution de l’eau','Preventing Water Pollution'),
      ('fr_general_sixieme','sciences',null,'Technologie',1,'Réalisation d’un projet technique et/ou économique simple','Developing a Simple Technical and/or Economic Project'),
      ('fr_general_cinquieme','sciences',null,'Le monde vivant',1,'Amélioration de la production végétale et animale','Improving Plant and Animal Production'),
      ('fr_general_cinquieme','sciences',null,'La matière : ses propriétés et ses transformations',1,'Lecture et exploitation des inscriptions sur les produits de consommation','Reading and Using Product Labels'),
      ('fr_general_cinquieme','sciences',null,'L’énergie : ses sources et sa gestion',1,'Organisation d’un voyage','Organizing a Trip'),
      ('fr_general_cinquieme','sciences',null,'L’Éducation à la santé',1,'Lutte contre les comportements émergents néfastes à la santé et la reproduction','Preventing Emerging Behaviours Harmful to Health and Reproduction'),
      ('fr_general_cinquieme','sciences',null,'L’Éducation à la santé',2,'Lutte contre les intoxications alimentaires','Preventing Food Poisoning'),
      ('fr_general_cinquieme','sciences',null,'L’Éducation à la santé',3,'Hygiène des appareils reproducteurs','Reproductive Health and Hygiene'),
      ('fr_general_cinquieme','sciences',null,'L’Éducation à l’Environnement et au Développement Durable',1,'Lutte contre la pollution de l’air','Preventing Air Pollution'),
      ('fr_general_cinquieme','sciences',null,'L’Éducation à l’Environnement et au Développement Durable',2,'Lutte contre la dégradation des sols','Preventing Soil Degradation'),
      ('fr_general_cinquieme','sciences',null,'L’Éducation à l’Environnement et au Développement Durable',3,'Lutte contre la pollution de l’eau','Preventing Water Pollution'),
      ('fr_general_cinquieme','sciences',null,'Technologie',1,'Réalisation d’un projet technique et/ou économique simple','Developing a Simple Technical and/or Economic Project'),

      -- Terminale IT (series TI): official component headings from the syllabus.
      ('fr_general_terminale','informatique','ti','Module 1 : Programmation',1,'Programmation en HTML et JavaScript','Programming with HTML and JavaScript'),
      ('fr_general_terminale','informatique','ti','Module 1 : Programmation',2,'Configuration d’un serveur web','Configuring a Web Server'),
      ('fr_general_terminale','informatique','ti','Module 2 : Réseaux, internet et sécurité informatique',1,'Configuration et services réseau','Network Configuration and Services'),
      ('fr_general_terminale','informatique','ti','Module 3 : Systèmes d’information et bases de données',1,'Description des concepts de base des systèmes d’information','Describing Basic Information-System Concepts'),
      ('fr_general_terminale','informatique','ti','Module 4 : Projet',1,'Réalisation et présentation du projet','Project Development and Presentation'),

      -- Terminale A/ABI/SH/AC Informatics: official module components.
      ('fr_general_terminale','informatique','a1','Module 1 : Systèmes informatiques et humanités numériques',1,'Description de l’architecture d’un système informatique','Describing Computer-System Architecture'),
      ('fr_general_terminale','informatique','a1','Module 1 : Systèmes informatiques et humanités numériques',2,'Protection d’un environnement de travail','Protecting a Work Environment'),
      ('fr_general_terminale','informatique','a1','Module 2 : Systèmes d’information et bases de données',1,'Description des concepts de base des systèmes d’information','Describing Basic Information-System Concepts'),
      ('fr_general_terminale','informatique','a1','Module 2 : Systèmes d’information et bases de données',2,'Conception des modèles de données d’un système d’information','Designing Information-System Data Models'),
      ('fr_general_terminale','informatique','a1','Module 3 : Production des contenus numériques',1,'Production de contenus numériques','Producing Digital Content'),
      ('fr_general_terminale','informatique','ti','Module 2 : Réseaux, internet et sécurité informatique',2,'Sécurité informatique','Computer Security'),
      ('fr_general_terminale','informatique','ti','Module 3 : Systèmes d’information et bases de données',2,'Conception et implémentation d’une base de données','Designing and Implementing a Database'),

      -- Seconde C: component headings from the official Physics programme.
      ('fr_general_seconde','physique','c','Mesures et incertitudes',1,'Mesure d’une grandeur et expression du résultat','Measuring a Quantity and Expressing the Result'),
      ('fr_general_seconde','physique','c','Mesures et incertitudes',2,'Représentation des mesures en tableaux et graphiques','Representing Measurements in Tables and Graphs'),
      ('fr_general_seconde','physique','c','Mesures et incertitudes',3,'Détermination d’une grandeur à partir d’un graphique','Determining a Quantity from a Graph'),
      ('fr_general_seconde','physique','c','Mouvements et interactions mécaniques',1,'Description et analyse d’un mouvement','Describing and Analysing Motion'),
      ('fr_general_seconde','physique','c','Mouvements et interactions mécaniques',2,'Actions mécaniques et variation de la quantité de mouvement','Mechanical Actions and Change in Momentum'),
      ('fr_general_seconde','physique','c','Propagation rectiligne de la lumière',1,'Caractérisation d’une lumière','Characterising Light'),
      ('fr_general_seconde','physique','c','Propagation rectiligne de la lumière',2,'Description du trajet de la lumière d’une source à un récepteur','Tracing Light from a Source to a Receiver'),
      ('fr_general_seconde','physique','c','Propagation rectiligne de la lumière',3,'Propriétés de la lumière et phénomènes observés','Light Properties and Observed Phenomena'),
      ('fr_general_seconde','physique','c','Résistors, diodes et transistors bipolaires, portes logiques',1,'Comportement de composants électroniques','Behaviour of Electronic Components'),
      ('fr_general_seconde','physique','c','Résistors, diodes et transistors bipolaires, portes logiques',2,'Réalisation de montages électroniques simples','Building Simple Electronic Circuits')
    ) as x(level_code, subject_code, series_code, module_title_fr, position, title_fr, title_en)
  loop
    select id into v_level_id from public.exam_levels
    where code = item.level_code and active limit 1;

    select id into v_subject_id from public.subjects
    where code = item.subject_code and is_active
      and subsystem = (select subsystem from public.exam_levels where id = v_level_id)
      and sector = (select sector from public.exam_levels where id = v_level_id)
    limit 1;

    if v_level_id is null or v_subject_id is null then
      continue;
    end if;

    v_series_id := null;
    if item.series_code is not null then
      select id into v_series_id from public.series where code = item.series_code and active limit 1;
      if v_series_id is null then
        continue;
      end if;
    end if;

    select id into v_curriculum_id from public.curricula
    where subject_id = v_subject_id
      and exam_level_id = v_level_id
      and series_id is not distinct from v_series_id
      and specialty_id is null
      and title_fr = item.module_title_fr
      and is_active
    limit 1;

    if v_curriculum_id is null then
      -- Module records are created by the first DO block. If the module was not
      -- found under the exact class/series context, do not attach a chapter elsewhere.
      continue;
    end if;

    insert into public.course_chapters
      (curriculum_id, title_fr, title_en, position, is_active)
    values
      (v_curriculum_id, item.title_fr, item.title_en, item.position, true)
    on conflict (curriculum_id, position) do update
    set title_fr = excluded.title_fr,
        title_en = excluded.title_en,
        is_active = true,
        updated_at = now();

    v_curriculum_id := null;
  end loop;
end $$;

-- English text in these rows is a translation label; the official source is the French programme.
-- Sources for this tranche:
-- History 6e/5e: https://files.minesec.gov.cm/direct/view.php?%2FHISTOIRE_6e_5e_ESG.pdf=&s=2g
-- Geography 6e/5e: https://files.minesec.gov.cm/direct/view.php?%2FGEOGRAPHIE_6e_5e_ESG.pdf=&s=2f
-- Sciences 6e/5e: https://files.minesec.gov.cm/direct/view.php?%2Fsciences.pdf=&s=2d
-- Terminale Geography ESG/EST: https://files.minesec.gov.cm/direct/view.php?%2FPROGRAMME_GEO_Tle-ESG.pdf=&s=jo
-- Terminale general Informatics A/ABI/SH/AC: https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_Terminales_A_06_08_2020.pdf=&s=jh
-- Terminale TI Informatics: https://files.minesec.gov.cm/direct/view.php?%2Fprogramme_T_TI_06_08_2020.pdf=&s=jk
-- Seconde C Physics: https://files.minesec.gov.cm/direct/view.php?%2FProjet_de_programme_de_Physique_2nde_C_-_Final.pdf=&s=iw
