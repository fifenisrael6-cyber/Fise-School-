-- Fise School — catalogue complet des matières par niveau (MINESEC / GCE) et
-- emploi du temps personnel de l'élève.
--
-- Le catalogue est une base de départ construite à partir de la structure des
-- programmes du MINESEC (francophone), du GCE (anglophone) et de l'enseignement
-- technique. L'administrateur peut ajuster les matières de chaque salle.

-- ============================================================
-- 1. Nouvelles matières
-- ============================================================
insert into public.subjects (code, name_fr, name_en, subsystem, sector)
values
('litterature','Littérature','Literature','francophone','general'),
('sciences','Sciences','Sciences','francophone','general'),
('pct','Physique-Chimie-Technologie','Physics-Chemistry-Technology','francophone','general'),
('eps','Éducation physique et sportive','Physical Education','francophone','general'),
('travail_manuel','Travail manuel','Manual Work','francophone','general'),
('education_artistique','Éducation artistique','Art Education','francophone','general'),
('esf','Économie sociale et familiale','Social and Family Economy','francophone','general'),
('langues_nationales','Langues et cultures nationales','National Languages and Cultures','francophone','general'),
('allemand','Allemand','German','francophone','general'),
('espagnol','Espagnol','Spanish','francophone','general'),
('italien','Italien','Italian','francophone','general'),
('chinois','Chinois','Chinese','francophone','general'),
('arabe','Arabe','Arabic','francophone','general'),
('comptabilite_fr','Comptabilité','Accounting','francophone','general'),
('commerce_fr','Commerce','Commerce','francophone','general'),
('general_science','Sciences générales','General Science','anglophone','general'),
('physical_education','Éducation physique','Physical Education','anglophone','general'),
('art_craft','Art et artisanat','Art and Craft','anglophone','general'),
('manual_labour','Travail manuel','Manual Labour','anglophone','general'),
('communication_skills','Techniques de communication','Communication Skills','anglophone','general'),
('further_mathematics','Mathématiques approfondies','Further Mathematics','anglophone','general'),
('philosophy_en','Philosophie','Philosophy','anglophone','general'),
('fr_tech_francais','Français','French','francophone','technical'),
('fr_tech_histoire_geo','Histoire-Géographie','History-Geography','francophone','technical'),
('fr_tech_ecm','Éducation à la citoyenneté','Citizenship Education','francophone','technical'),
('fr_tech_physique_chimie','Physique-Chimie','Physics-Chemistry','francophone','technical'),
('fr_tech_informatique','Informatique','Computer Science','francophone','technical'),
('fr_tech_eps','Éducation physique et sportive','Physical Education','francophone','technical'),
('fr_tech_atelier','Atelier / Travaux pratiques','Workshop / Practicals','francophone','technical'),
('en_tech_english','Anglais','English Language','anglophone','technical'),
('en_tech_citizenship','Éducation à la citoyenneté','Citizenship Education','anglophone','technical'),
('en_tech_ict','Informatique (TIC)','ICT','anglophone','technical'),
('en_tech_pe','Éducation physique','Physical Education','anglophone','technical'),
('en_tech_drawing','Dessin technique','Technical Drawing','anglophone','technical'),
('en_tech_entrepreneurship','Entrepreneuriat','Entrepreneurship','anglophone','technical')
on conflict (code) do update set
  name_fr = excluded.name_fr,
  name_en = excluded.name_en,
  subsystem = excluded.subsystem,
  sector = excluded.sector,
  is_active = true,
  updated_at = now();

-- ============================================================
-- 2. Matières de chaque niveau
-- ============================================================
create table if not exists public.level_subject_catalog (
  level_code text not null,
  subject_code text not null,
  is_compulsory boolean not null default true,
  option_group text,
  position integer not null default 0 check (position >= 0),
  primary key (level_code, subject_code)
);

alter table public.level_subject_catalog enable row level security;

drop policy if exists "authenticated read level subject catalog" on public.level_subject_catalog;
create policy "authenticated read level subject catalog"
on public.level_subject_catalog for select to authenticated using (true);

drop policy if exists "admins manage level subject catalog" on public.level_subject_catalog;
create policy "admins manage level subject catalog"
on public.level_subject_catalog for all to authenticated
using (public.is_catalog_admin()) with check (public.is_catalog_admin());

delete from public.level_subject_catalog;

insert into public.level_subject_catalog (level_code, subject_code, is_compulsory, option_group, position)
values
('fr_general_sixieme','francais',true,null,0),
('fr_general_sixieme','anglais',true,null,1),
('fr_general_sixieme','mathematiques',true,null,2),
('fr_general_sixieme','sciences',true,null,3),
('fr_general_sixieme','histoire',true,null,4),
('fr_general_sixieme','geographie',true,null,5),
('fr_general_sixieme','education_civique',true,null,6),
('fr_general_sixieme','informatique',true,null,7),
('fr_general_sixieme','eps',true,null,8),
('fr_general_sixieme','travail_manuel',true,null,9),
('fr_general_sixieme','education_artistique',true,null,10),
('fr_general_sixieme','esf',true,null,11),
('fr_general_sixieme','langues_nationales',false,'Matières complémentaires',112),
('fr_general_cinquieme','francais',true,null,0),
('fr_general_cinquieme','anglais',true,null,1),
('fr_general_cinquieme','mathematiques',true,null,2),
('fr_general_cinquieme','sciences',true,null,3),
('fr_general_cinquieme','histoire',true,null,4),
('fr_general_cinquieme','geographie',true,null,5),
('fr_general_cinquieme','education_civique',true,null,6),
('fr_general_cinquieme','informatique',true,null,7),
('fr_general_cinquieme','eps',true,null,8),
('fr_general_cinquieme','travail_manuel',true,null,9),
('fr_general_cinquieme','education_artistique',true,null,10),
('fr_general_cinquieme','esf',true,null,11),
('fr_general_cinquieme','langues_nationales',false,'Matières complémentaires',112),
('fr_general_quatrieme','francais',true,null,0),
('fr_general_quatrieme','anglais',true,null,1),
('fr_general_quatrieme','mathematiques',true,null,2),
('fr_general_quatrieme','svt',true,null,3),
('fr_general_quatrieme','pct',true,null,4),
('fr_general_quatrieme','histoire',true,null,5),
('fr_general_quatrieme','geographie',true,null,6),
('fr_general_quatrieme','education_civique',true,null,7),
('fr_general_quatrieme','informatique',true,null,8),
('fr_general_quatrieme','eps',true,null,9),
('fr_general_quatrieme','travail_manuel',true,null,10),
('fr_general_quatrieme','education_artistique',true,null,11),
('fr_general_quatrieme','esf',true,null,12),
('fr_general_quatrieme','allemand',false,'Langue vivante II',113),
('fr_general_quatrieme','espagnol',false,'Langue vivante II',114),
('fr_general_quatrieme','italien',false,'Langue vivante II',115),
('fr_general_quatrieme','chinois',false,'Langue vivante II',116),
('fr_general_quatrieme','arabe',false,'Langue vivante II',117),
('fr_general_quatrieme','latin',false,'Langues anciennes',118),
('fr_general_quatrieme','grec',false,'Langues anciennes',119),
('fr_general_quatrieme','langues_nationales',false,'Matières complémentaires',120),
('fr_general_troisieme','francais',true,null,0),
('fr_general_troisieme','anglais',true,null,1),
('fr_general_troisieme','mathematiques',true,null,2),
('fr_general_troisieme','svt',true,null,3),
('fr_general_troisieme','pct',true,null,4),
('fr_general_troisieme','histoire',true,null,5),
('fr_general_troisieme','geographie',true,null,6),
('fr_general_troisieme','education_civique',true,null,7),
('fr_general_troisieme','informatique',true,null,8),
('fr_general_troisieme','eps',true,null,9),
('fr_general_troisieme','travail_manuel',true,null,10),
('fr_general_troisieme','education_artistique',true,null,11),
('fr_general_troisieme','esf',true,null,12),
('fr_general_troisieme','allemand',false,'Langue vivante II',113),
('fr_general_troisieme','espagnol',false,'Langue vivante II',114),
('fr_general_troisieme','italien',false,'Langue vivante II',115),
('fr_general_troisieme','chinois',false,'Langue vivante II',116),
('fr_general_troisieme','arabe',false,'Langue vivante II',117),
('fr_general_troisieme','latin',false,'Langues anciennes',118),
('fr_general_troisieme','grec',false,'Langues anciennes',119),
('fr_general_troisieme','langues_nationales',false,'Matières complémentaires',120),
('fr_general_seconde','francais',true,null,0),
('fr_general_seconde','litterature',true,null,1),
('fr_general_seconde','anglais',true,null,2),
('fr_general_seconde','mathematiques',true,null,3),
('fr_general_seconde','physique',true,null,4),
('fr_general_seconde','chimie',true,null,5),
('fr_general_seconde','svt',true,null,6),
('fr_general_seconde','histoire',true,null,7),
('fr_general_seconde','geographie',true,null,8),
('fr_general_seconde','education_civique',true,null,9),
('fr_general_seconde','informatique',true,null,10),
('fr_general_seconde','eps',true,null,11),
('fr_general_seconde','allemand',false,'Langue vivante II',112),
('fr_general_seconde','espagnol',false,'Langue vivante II',113),
('fr_general_seconde','italien',false,'Langue vivante II',114),
('fr_general_seconde','chinois',false,'Langue vivante II',115),
('fr_general_seconde','arabe',false,'Langue vivante II',116),
('fr_general_seconde','latin',false,'Langues anciennes',117),
('fr_general_seconde','grec',false,'Langues anciennes',118),
('fr_general_seconde','arts_cinematographiques',false,'Série / option',119),
('fr_general_seconde','comptabilite_fr',false,'Série / option',120),
('fr_general_seconde','commerce_fr',false,'Série / option',121),
('fr_general_premiere','francais',true,null,0),
('fr_general_premiere','litterature',true,null,1),
('fr_general_premiere','anglais',true,null,2),
('fr_general_premiere','mathematiques',true,null,3),
('fr_general_premiere','physique',true,null,4),
('fr_general_premiere','chimie',true,null,5),
('fr_general_premiere','svt',true,null,6),
('fr_general_premiere','histoire',true,null,7),
('fr_general_premiere','geographie',true,null,8),
('fr_general_premiere','education_civique',true,null,9),
('fr_general_premiere','informatique',true,null,10),
('fr_general_premiere','eps',true,null,11),
('fr_general_premiere','allemand',false,'Langue vivante II',112),
('fr_general_premiere','espagnol',false,'Langue vivante II',113),
('fr_general_premiere','italien',false,'Langue vivante II',114),
('fr_general_premiere','chinois',false,'Langue vivante II',115),
('fr_general_premiere','arabe',false,'Langue vivante II',116),
('fr_general_premiere','latin',false,'Langues anciennes',117),
('fr_general_premiere','grec',false,'Langues anciennes',118),
('fr_general_premiere','arts_cinematographiques',false,'Série / option',119),
('fr_general_premiere','comptabilite_fr',false,'Série / option',120),
('fr_general_premiere','commerce_fr',false,'Série / option',121),
('fr_general_premiere','philosophie',false,'Série / option',122),
('fr_general_terminale','francais',true,null,0),
('fr_general_terminale','litterature',true,null,1),
('fr_general_terminale','anglais',true,null,2),
('fr_general_terminale','mathematiques',true,null,3),
('fr_general_terminale','physique',true,null,4),
('fr_general_terminale','chimie',true,null,5),
('fr_general_terminale','svt',true,null,6),
('fr_general_terminale','histoire',true,null,7),
('fr_general_terminale','geographie',true,null,8),
('fr_general_terminale','education_civique',true,null,9),
('fr_general_terminale','informatique',true,null,10),
('fr_general_terminale','eps',true,null,11),
('fr_general_terminale','philosophie',true,null,12),
('fr_general_terminale','allemand',false,'Langue vivante II',113),
('fr_general_terminale','espagnol',false,'Langue vivante II',114),
('fr_general_terminale','italien',false,'Langue vivante II',115),
('fr_general_terminale','chinois',false,'Langue vivante II',116),
('fr_general_terminale','arabe',false,'Langue vivante II',117),
('fr_general_terminale','latin',false,'Langues anciennes',118),
('fr_general_terminale','grec',false,'Langues anciennes',119),
('fr_general_terminale','arts_cinematographiques',false,'Série / option',120),
('fr_general_terminale','comptabilite_fr',false,'Série / option',121),
('fr_general_terminale','commerce_fr',false,'Série / option',122),
('en_general_form_1','english_language',true,null,0),
('en_general_form_1','literature_in_english',true,null,1),
('en_general_form_1','french_language',true,null,2),
('en_general_form_1','mathematics_en',true,null,3),
('en_general_form_1','general_science',true,null,4),
('en_general_form_1','history_en',true,null,5),
('en_general_form_1','geography_en',true,null,6),
('en_general_form_1','citizenship_en',true,null,7),
('en_general_form_1','computer_science_en',true,null,8),
('en_general_form_1','physical_education',true,null,9),
('en_general_form_1','art_craft',true,null,10),
('en_general_form_1','manual_labour',true,null,11),
('en_general_form_1','religious_studies',false,'Matières complémentaires',112),
('en_general_form_1','food_nutrition',false,'Matières complémentaires',113),
('en_general_form_2','english_language',true,null,0),
('en_general_form_2','literature_in_english',true,null,1),
('en_general_form_2','french_language',true,null,2),
('en_general_form_2','mathematics_en',true,null,3),
('en_general_form_2','general_science',true,null,4),
('en_general_form_2','history_en',true,null,5),
('en_general_form_2','geography_en',true,null,6),
('en_general_form_2','citizenship_en',true,null,7),
('en_general_form_2','computer_science_en',true,null,8),
('en_general_form_2','physical_education',true,null,9),
('en_general_form_2','art_craft',true,null,10),
('en_general_form_2','manual_labour',true,null,11),
('en_general_form_2','religious_studies',false,'Matières complémentaires',112),
('en_general_form_2','food_nutrition',false,'Matières complémentaires',113),
('en_general_form_3','english_language',true,null,0),
('en_general_form_3','literature_in_english',true,null,1),
('en_general_form_3','french_language',true,null,2),
('en_general_form_3','mathematics_en',true,null,3),
('en_general_form_3','biology_en',true,null,4),
('en_general_form_3','chemistry_en',true,null,5),
('en_general_form_3','physics_en',true,null,6),
('en_general_form_3','history_en',true,null,7),
('en_general_form_3','geography_en',true,null,8),
('en_general_form_3','citizenship_en',true,null,9),
('en_general_form_3','computer_science_en',true,null,10),
('en_general_form_3','physical_education',true,null,11),
('en_general_form_3','art_craft',true,null,12),
('en_general_form_3','manual_labour',true,null,13),
('en_general_form_3','religious_studies',false,'Matières complémentaires',114),
('en_general_form_3','food_nutrition',false,'Matières complémentaires',115),
('en_general_form_4','english_language',true,null,0),
('en_general_form_4','literature_in_english',true,null,1),
('en_general_form_4','french_language',true,null,2),
('en_general_form_4','mathematics_en',true,null,3),
('en_general_form_4','biology_en',true,null,4),
('en_general_form_4','chemistry_en',true,null,5),
('en_general_form_4','physics_en',true,null,6),
('en_general_form_4','history_en',true,null,7),
('en_general_form_4','geography_en',true,null,8),
('en_general_form_4','citizenship_en',true,null,9),
('en_general_form_4','computer_science_en',true,null,10),
('en_general_form_4','physical_education',true,null,11),
('en_general_form_4','additional_mathematics',false,'GCE O-Level options',112),
('en_general_form_4','economics',false,'GCE O-Level options',113),
('en_general_form_4','accounting',false,'GCE O-Level options',114),
('en_general_form_4','commerce',false,'GCE O-Level options',115),
('en_general_form_4','food_nutrition',false,'GCE O-Level options',116),
('en_general_form_4','religious_studies',false,'GCE O-Level options',117),
('en_general_form_4','logic',false,'GCE O-Level options',118),
('en_general_form_4','human_biology',false,'GCE O-Level options',119),
('en_general_form_5','english_language',true,null,0),
('en_general_form_5','literature_in_english',true,null,1),
('en_general_form_5','french_language',true,null,2),
('en_general_form_5','mathematics_en',true,null,3),
('en_general_form_5','biology_en',true,null,4),
('en_general_form_5','chemistry_en',true,null,5),
('en_general_form_5','physics_en',true,null,6),
('en_general_form_5','history_en',true,null,7),
('en_general_form_5','geography_en',true,null,8),
('en_general_form_5','citizenship_en',true,null,9),
('en_general_form_5','computer_science_en',true,null,10),
('en_general_form_5','physical_education',true,null,11),
('en_general_form_5','additional_mathematics',false,'GCE O-Level options',112),
('en_general_form_5','economics',false,'GCE O-Level options',113),
('en_general_form_5','accounting',false,'GCE O-Level options',114),
('en_general_form_5','commerce',false,'GCE O-Level options',115),
('en_general_form_5','food_nutrition',false,'GCE O-Level options',116),
('en_general_form_5','religious_studies',false,'GCE O-Level options',117),
('en_general_form_5','logic',false,'GCE O-Level options',118),
('en_general_form_5','human_biology',false,'GCE O-Level options',119),
('en_general_lower_sixth','communication_skills',true,null,0),
('en_general_lower_sixth','mathematics_en',false,'GCE A-Level subjects',101),
('en_general_lower_sixth','further_mathematics',false,'GCE A-Level subjects',102),
('en_general_lower_sixth','physics_en',false,'GCE A-Level subjects',103),
('en_general_lower_sixth','chemistry_en',false,'GCE A-Level subjects',104),
('en_general_lower_sixth','biology_en',false,'GCE A-Level subjects',105),
('en_general_lower_sixth','economics',false,'GCE A-Level subjects',106),
('en_general_lower_sixth','geography_en',false,'GCE A-Level subjects',107),
('en_general_lower_sixth','history_en',false,'GCE A-Level subjects',108),
('en_general_lower_sixth','literature_in_english',false,'GCE A-Level subjects',109),
('en_general_lower_sixth','french_language',false,'GCE A-Level subjects',110),
('en_general_lower_sixth','english_language',false,'GCE A-Level subjects',111),
('en_general_lower_sixth','computer_science_en',false,'GCE A-Level subjects',112),
('en_general_lower_sixth','accounting',false,'GCE A-Level subjects',113),
('en_general_lower_sixth','geology',false,'GCE A-Level subjects',114),
('en_general_lower_sixth','logic',false,'GCE A-Level subjects',115),
('en_general_lower_sixth','philosophy_en',false,'GCE A-Level subjects',116),
('en_general_lower_sixth','religious_studies',false,'GCE A-Level subjects',117),
('en_general_lower_sixth','food_nutrition',false,'GCE A-Level subjects',118),
('en_general_lower_sixth','human_biology',false,'GCE A-Level subjects',119),
('en_general_upper_sixth','communication_skills',true,null,0),
('en_general_upper_sixth','mathematics_en',false,'GCE A-Level subjects',101),
('en_general_upper_sixth','further_mathematics',false,'GCE A-Level subjects',102),
('en_general_upper_sixth','physics_en',false,'GCE A-Level subjects',103),
('en_general_upper_sixth','chemistry_en',false,'GCE A-Level subjects',104),
('en_general_upper_sixth','biology_en',false,'GCE A-Level subjects',105),
('en_general_upper_sixth','economics',false,'GCE A-Level subjects',106),
('en_general_upper_sixth','geography_en',false,'GCE A-Level subjects',107),
('en_general_upper_sixth','history_en',false,'GCE A-Level subjects',108),
('en_general_upper_sixth','literature_in_english',false,'GCE A-Level subjects',109),
('en_general_upper_sixth','french_language',false,'GCE A-Level subjects',110),
('en_general_upper_sixth','english_language',false,'GCE A-Level subjects',111),
('en_general_upper_sixth','computer_science_en',false,'GCE A-Level subjects',112),
('en_general_upper_sixth','accounting',false,'GCE A-Level subjects',113),
('en_general_upper_sixth','geology',false,'GCE A-Level subjects',114),
('en_general_upper_sixth','logic',false,'GCE A-Level subjects',115),
('en_general_upper_sixth','philosophy_en',false,'GCE A-Level subjects',116),
('en_general_upper_sixth','religious_studies',false,'GCE A-Level subjects',117),
('en_general_upper_sixth','food_nutrition',false,'GCE A-Level subjects',118),
('en_general_upper_sixth','human_biology',false,'GCE A-Level subjects',119),
('fr_technical_sixieme','fr_tech_francais',true,null,0),
('fr_technical_sixieme','technical_english',true,null,1),
('fr_technical_sixieme','technical_math',true,null,2),
('fr_technical_sixieme','fr_tech_histoire_geo',true,null,3),
('fr_technical_sixieme','fr_tech_ecm',true,null,4),
('fr_technical_sixieme','technical_science',true,null,5),
('fr_technical_sixieme','fr_tech_informatique',true,null,6),
('fr_technical_sixieme','technologie',true,null,7),
('fr_technical_sixieme','dessin_technique',true,null,8),
('fr_technical_sixieme','fr_tech_eps',true,null,9),
('fr_technical_sixieme','fr_tech_atelier',true,null,10),
('fr_technical_sixieme','entrepreneuriat',true,null,11),
('fr_technical_cinquieme','fr_tech_francais',true,null,0),
('fr_technical_cinquieme','technical_english',true,null,1),
('fr_technical_cinquieme','technical_math',true,null,2),
('fr_technical_cinquieme','fr_tech_histoire_geo',true,null,3),
('fr_technical_cinquieme','fr_tech_ecm',true,null,4),
('fr_technical_cinquieme','technical_science',true,null,5),
('fr_technical_cinquieme','fr_tech_informatique',true,null,6),
('fr_technical_cinquieme','technologie',true,null,7),
('fr_technical_cinquieme','dessin_technique',true,null,8),
('fr_technical_cinquieme','fr_tech_eps',true,null,9),
('fr_technical_cinquieme','fr_tech_atelier',true,null,10),
('fr_technical_cinquieme','entrepreneuriat',true,null,11),
('fr_technical_quatrieme','fr_tech_francais',true,null,0),
('fr_technical_quatrieme','technical_english',true,null,1),
('fr_technical_quatrieme','technical_math',true,null,2),
('fr_technical_quatrieme','fr_tech_histoire_geo',true,null,3),
('fr_technical_quatrieme','fr_tech_ecm',true,null,4),
('fr_technical_quatrieme','technical_science',true,null,5),
('fr_technical_quatrieme','fr_tech_informatique',true,null,6),
('fr_technical_quatrieme','technologie',true,null,7),
('fr_technical_quatrieme','dessin_technique',true,null,8),
('fr_technical_quatrieme','fr_tech_eps',true,null,9),
('fr_technical_quatrieme','fr_tech_atelier',true,null,10),
('fr_technical_quatrieme','entrepreneuriat',true,null,11),
('fr_technical_troisieme','fr_tech_francais',true,null,0),
('fr_technical_troisieme','technical_english',true,null,1),
('fr_technical_troisieme','technical_math',true,null,2),
('fr_technical_troisieme','fr_tech_histoire_geo',true,null,3),
('fr_technical_troisieme','fr_tech_ecm',true,null,4),
('fr_technical_troisieme','technical_science',true,null,5),
('fr_technical_troisieme','fr_tech_informatique',true,null,6),
('fr_technical_troisieme','technologie',true,null,7),
('fr_technical_troisieme','dessin_technique',true,null,8),
('fr_technical_troisieme','fr_tech_eps',true,null,9),
('fr_technical_troisieme','fr_tech_atelier',true,null,10),
('fr_technical_troisieme','entrepreneuriat',true,null,11),
('fr_technical_cap','fr_tech_francais',true,null,0),
('fr_technical_cap','technical_english',true,null,1),
('fr_technical_cap','technical_math',true,null,2),
('fr_technical_cap','fr_tech_ecm',true,null,3),
('fr_technical_cap','technical_science',true,null,4),
('fr_technical_cap','technologie',true,null,5),
('fr_technical_cap','dessin_technique',true,null,6),
('fr_technical_cap','fr_tech_atelier',true,null,7),
('fr_technical_cap','entrepreneuriat',true,null,8),
('fr_technical_cap','fr_tech_eps',true,null,9),
('fr_technical_1ere_annee','fr_tech_francais',true,null,0),
('fr_technical_1ere_annee','technical_english',true,null,1),
('fr_technical_1ere_annee','technical_math',true,null,2),
('fr_technical_1ere_annee','fr_tech_ecm',true,null,3),
('fr_technical_1ere_annee','technical_science',true,null,4),
('fr_technical_1ere_annee','technologie',true,null,5),
('fr_technical_1ere_annee','dessin_technique',true,null,6),
('fr_technical_1ere_annee','fr_tech_atelier',true,null,7),
('fr_technical_1ere_annee','entrepreneuriat',true,null,8),
('fr_technical_1ere_annee','fr_tech_eps',true,null,9),
('fr_technical_2eme_annee','fr_tech_francais',true,null,0),
('fr_technical_2eme_annee','technical_english',true,null,1),
('fr_technical_2eme_annee','technical_math',true,null,2),
('fr_technical_2eme_annee','fr_tech_ecm',true,null,3),
('fr_technical_2eme_annee','technical_science',true,null,4),
('fr_technical_2eme_annee','technologie',true,null,5),
('fr_technical_2eme_annee','dessin_technique',true,null,6),
('fr_technical_2eme_annee','fr_tech_atelier',true,null,7),
('fr_technical_2eme_annee','entrepreneuriat',true,null,8),
('fr_technical_2eme_annee','fr_tech_eps',true,null,9),
('fr_technical_3eme_annee','fr_tech_francais',true,null,0),
('fr_technical_3eme_annee','technical_english',true,null,1),
('fr_technical_3eme_annee','technical_math',true,null,2),
('fr_technical_3eme_annee','fr_tech_ecm',true,null,3),
('fr_technical_3eme_annee','technical_science',true,null,4),
('fr_technical_3eme_annee','technologie',true,null,5),
('fr_technical_3eme_annee','dessin_technique',true,null,6),
('fr_technical_3eme_annee','fr_tech_atelier',true,null,7),
('fr_technical_3eme_annee','entrepreneuriat',true,null,8),
('fr_technical_3eme_annee','fr_tech_eps',true,null,9),
('fr_technical_seconde','fr_tech_francais',true,null,0),
('fr_technical_seconde','technical_english',true,null,1),
('fr_technical_seconde','technical_math',true,null,2),
('fr_technical_seconde','fr_tech_physique_chimie',true,null,3),
('fr_technical_seconde','fr_tech_ecm',true,null,4),
('fr_technical_seconde','fr_tech_informatique',true,null,5),
('fr_technical_seconde','technologie',true,null,6),
('fr_technical_seconde','dessin_technique',true,null,7),
('fr_technical_seconde','fr_tech_atelier',true,null,8),
('fr_technical_seconde','entrepreneuriat',true,null,9),
('fr_technical_seconde','fr_tech_eps',true,null,10),
('fr_technical_premiere','fr_tech_francais',true,null,0),
('fr_technical_premiere','technical_english',true,null,1),
('fr_technical_premiere','technical_math',true,null,2),
('fr_technical_premiere','fr_tech_physique_chimie',true,null,3),
('fr_technical_premiere','fr_tech_ecm',true,null,4),
('fr_technical_premiere','fr_tech_informatique',true,null,5),
('fr_technical_premiere','technologie',true,null,6),
('fr_technical_premiere','dessin_technique',true,null,7),
('fr_technical_premiere','fr_tech_atelier',true,null,8),
('fr_technical_premiere','entrepreneuriat',true,null,9),
('fr_technical_premiere','fr_tech_eps',true,null,10),
('fr_technical_terminale','fr_tech_francais',true,null,0),
('fr_technical_terminale','technical_english',true,null,1),
('fr_technical_terminale','technical_math',true,null,2),
('fr_technical_terminale','fr_tech_physique_chimie',true,null,3),
('fr_technical_terminale','fr_tech_ecm',true,null,4),
('fr_technical_terminale','fr_tech_informatique',true,null,5),
('fr_technical_terminale','technologie',true,null,6),
('fr_technical_terminale','dessin_technique',true,null,7),
('fr_technical_terminale','fr_tech_atelier',true,null,8),
('fr_technical_terminale','entrepreneuriat',true,null,9),
('fr_technical_terminale','fr_tech_eps',true,null,10),
('fr_technical_brevet_technicien','fr_tech_francais',true,null,0),
('fr_technical_brevet_technicien','technical_english',true,null,1),
('fr_technical_brevet_technicien','technical_math',true,null,2),
('fr_technical_brevet_technicien','fr_tech_physique_chimie',true,null,3),
('fr_technical_brevet_technicien','fr_tech_ecm',true,null,4),
('fr_technical_brevet_technicien','fr_tech_informatique',true,null,5),
('fr_technical_brevet_technicien','technologie',true,null,6),
('fr_technical_brevet_technicien','dessin_technique',true,null,7),
('fr_technical_brevet_technicien','fr_tech_atelier',true,null,8),
('fr_technical_brevet_technicien','entrepreneuriat',true,null,9),
('fr_technical_brevet_technicien','fr_tech_eps',true,null,10),
('en_technical_form_1','en_tech_english',true,null,0),
('en_technical_form_1','technical_french',true,null,1),
('en_technical_form_1','technical_math_en',true,null,2),
('en_technical_form_1','technical_science_en',true,null,3),
('en_technical_form_1','en_tech_drawing',true,null,4),
('en_technical_form_1','workshop_practice',true,null,5),
('en_technical_form_1','en_tech_ict',true,null,6),
('en_technical_form_1','en_tech_pe',true,null,7),
('en_technical_form_1','en_tech_citizenship',true,null,8),
('en_technical_form_2','en_tech_english',true,null,0),
('en_technical_form_2','technical_french',true,null,1),
('en_technical_form_2','technical_math_en',true,null,2),
('en_technical_form_2','technical_science_en',true,null,3),
('en_technical_form_2','en_tech_drawing',true,null,4),
('en_technical_form_2','workshop_practice',true,null,5),
('en_technical_form_2','en_tech_ict',true,null,6),
('en_technical_form_2','en_tech_pe',true,null,7),
('en_technical_form_2','en_tech_citizenship',true,null,8),
('en_technical_form_3','en_tech_english',true,null,0),
('en_technical_form_3','technical_french',true,null,1),
('en_technical_form_3','technical_math_en',true,null,2),
('en_technical_form_3','technical_science_en',true,null,3),
('en_technical_form_3','en_tech_drawing',true,null,4),
('en_technical_form_3','workshop_practice',true,null,5),
('en_technical_form_3','en_tech_ict',true,null,6),
('en_technical_form_3','en_tech_pe',true,null,7),
('en_technical_form_3','en_tech_citizenship',true,null,8),
('en_technical_form_4','en_tech_english',true,null,0),
('en_technical_form_4','technical_french',true,null,1),
('en_technical_form_4','technical_math_en',true,null,2),
('en_technical_form_4','technical_science_en',true,null,3),
('en_technical_form_4','en_tech_drawing',true,null,4),
('en_technical_form_4','workshop_practice',true,null,5),
('en_technical_form_4','en_tech_ict',true,null,6),
('en_technical_form_4','en_tech_pe',true,null,7),
('en_technical_form_4','technical_communication',true,null,8),
('en_technical_form_4','en_tech_entrepreneurship',true,null,9),
('en_technical_form_5','en_tech_english',true,null,0),
('en_technical_form_5','technical_french',true,null,1),
('en_technical_form_5','technical_math_en',true,null,2),
('en_technical_form_5','technical_science_en',true,null,3),
('en_technical_form_5','en_tech_drawing',true,null,4),
('en_technical_form_5','workshop_practice',true,null,5),
('en_technical_form_5','en_tech_ict',true,null,6),
('en_technical_form_5','en_tech_pe',true,null,7),
('en_technical_form_5','technical_communication',true,null,8),
('en_technical_form_5','en_tech_entrepreneurship',true,null,9),
('en_technical_lower_sixth','en_tech_english',true,null,0),
('en_technical_lower_sixth','technical_french',true,null,1),
('en_technical_lower_sixth','technical_math_en',true,null,2),
('en_technical_lower_sixth','technical_science_en',true,null,3),
('en_technical_lower_sixth','en_tech_drawing',true,null,4),
('en_technical_lower_sixth','workshop_practice',true,null,5),
('en_technical_lower_sixth','en_tech_ict',true,null,6),
('en_technical_lower_sixth','en_tech_pe',true,null,7),
('en_technical_lower_sixth','technical_communication',true,null,8),
('en_technical_lower_sixth','en_tech_entrepreneurship',true,null,9),
('en_technical_upper_sixth','en_tech_english',true,null,0),
('en_technical_upper_sixth','technical_french',true,null,1),
('en_technical_upper_sixth','technical_math_en',true,null,2),
('en_technical_upper_sixth','technical_science_en',true,null,3),
('en_technical_upper_sixth','en_tech_drawing',true,null,4),
('en_technical_upper_sixth','workshop_practice',true,null,5),
('en_technical_upper_sixth','en_tech_ict',true,null,6),
('en_technical_upper_sixth','en_tech_pe',true,null,7),
('en_technical_upper_sixth','technical_communication',true,null,8),
('en_technical_upper_sixth','en_tech_entrepreneurship',true,null,9);

create table if not exists public.series_subject_catalog (
  series_code text not null,
  subject_code text not null,
  primary key (series_code, subject_code)
);

alter table public.series_subject_catalog enable row level security;

drop policy if exists "authenticated read series subject catalog" on public.series_subject_catalog;
create policy "authenticated read series subject catalog"
on public.series_subject_catalog for select to authenticated using (true);

drop policy if exists "admins manage series subject catalog" on public.series_subject_catalog;
create policy "admins manage series subject catalog"
on public.series_subject_catalog for all to authenticated
using (public.is_catalog_admin()) with check (public.is_catalog_admin());

delete from public.series_subject_catalog;

insert into public.series_subject_catalog (series_code, subject_code)
values
('c','mathematiques'),
('c','physique'),
('c','chimie'),
('c','svt'),
('d','mathematiques'),
('d','svt'),
('d','physique'),
('d','chimie'),
('a1','litterature'),
('a1','latin'),
('a1','grec'),
('a1','philosophie'),
('a2','litterature'),
('a2','latin'),
('a2','philosophie'),
('a2','allemand'),
('a2','espagnol'),
('a2','italien'),
('a2','chinois'),
('a2','arabe'),
('a3','litterature'),
('a3','latin'),
('a3','philosophie'),
('a4','litterature'),
('a4','philosophie'),
('a4','allemand'),
('a4','espagnol'),
('a4','italien'),
('a4','chinois'),
('a4','arabe'),
('a5','litterature'),
('a5','allemand'),
('a5','espagnol'),
('a5','italien'),
('a5','chinois'),
('a5','arabe'),
('ac','arts_cinematographiques'),
('ac','litterature'),
('ac','philosophie'),
('ti','informatique'),
('ti','mathematiques'),
('ti','physique'),
('gce_arts','literature_in_english'),
('gce_arts','history_en'),
('gce_arts','geography_en'),
('gce_arts','french_language'),
('gce_arts','economics'),
('gce_arts','religious_studies'),
('gce_arts','logic'),
('gce_arts','philosophy_en'),
('gce_science','mathematics_en'),
('gce_science','physics_en'),
('gce_science','chemistry_en'),
('gce_science','biology_en'),
('gce_science','further_mathematics'),
('gce_science','computer_science_en'),
('gce_science','geology');

-- ============================================================
-- 3. Application du catalogue aux salles
-- ============================================================
create or replace function public.apply_base_subjects_to_class(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Matières du niveau de la salle. Un réglage d'activation de l'admin est conservé.
  insert into public.class_subjects (class_id, subject_id, is_compulsory, option_group, position, is_active)
  select c.id, s.id, lc.is_compulsory, lc.option_group, lc.position, true
  from public.school_classes c
  join public.exam_levels el on el.id = c.exam_level_id
  join public.level_subject_catalog lc on lc.level_code = el.code
  join public.subjects s
    on s.code = lc.subject_code
   and s.is_active
   and s.subsystem = c.subsystem
   and s.sector = c.sector
  where c.id = p_class_id
    and c.is_active
  on conflict (class_id, subject_id) do update set
    is_compulsory = excluded.is_compulsory,
    option_group = excluded.option_group,
    position = excluded.position;

  -- Salle rattachée à une série : les matières de la série deviennent obligatoires.
  update public.class_subjects cs
  set is_compulsory = true, option_group = null
  from public.school_classes c
  join public.series se on se.id = c.series_id
  join public.series_subject_catalog ss on ss.series_code = se.code
  join public.subjects s on s.code = ss.subject_code
  where c.id = p_class_id
    and cs.class_id = c.id
    and cs.subject_id = s.id;

  -- Salle sans niveau d'examen : ancienne liste minimale.
  insert into public.class_subjects (class_id, subject_id, is_compulsory, option_group, position, is_active)
  select c.id, s.id, true, null,
         row_number() over (partition by c.id order by s.code) - 1, true
  from public.school_classes c
  join public.subjects s
    on s.is_active
   and s.subsystem = c.subsystem
   and s.sector = c.sector
  where c.id = p_class_id
    and c.is_active
    and c.exam_level_id is null
    and (
      (c.subsystem = 'francophone' and c.sector = 'general' and s.code in
        ('francais','anglais','mathematiques','histoire','geographie','education_civique'))
      or (c.subsystem = 'anglophone' and c.sector = 'general' and s.code in
        ('english_language','french_language','mathematics_en','history_en','geography_en','citizenship_en'))
      or (c.subsystem = 'francophone' and c.sector = 'technical' and s.code in
        ('technical_math','technical_science','dessin_technique','technologie','entrepreneuriat','technical_english'))
      or (c.subsystem = 'anglophone' and c.sector = 'technical' and s.code in
        ('technical_french','technical_communication','technical_math_en','technical_science_en','workshop_practice'))
    )
  on conflict (class_id, subject_id) do nothing;
end;
$$;

revoke all on function public.apply_base_subjects_to_class(uuid) from public;

-- Bouton « catalogue de base » de l'administration : applique le catalogue à toutes les salles.
create or replace function public.admin_apply_base_subject_catalog()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  processed integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can apply the classroom catalogue';
  end if;

  for r in select id from public.school_classes where is_active loop
    perform public.apply_base_subjects_to_class(r.id);
    processed := processed + 1;
  end loop;

  return processed;
end;
$$;

revoke all on function public.admin_apply_base_subject_catalog() from public;
grant execute on function public.admin_apply_base_subject_catalog() to authenticated;

-- Salles déjà existantes.
do $$
declare
  r record;
begin
  for r in select id from public.school_classes where is_active loop
    perform public.apply_base_subjects_to_class(r.id);
  end loop;
end;
$$;

-- ============================================================
-- 4. Emploi du temps personnel de l'élève
-- ============================================================
alter table public.student_timetable_entries
  add column if not exists subject_id uuid references public.subjects(id) on delete set null,
  add column if not exists subject_en text,
  add column if not exists updated_at timestamptz not null default now();

drop policy if exists "students manage own timetable" on public.student_timetable_entries;
create policy "students manage own timetable"
on public.student_timetable_entries for all to authenticated
using (student_id = auth.uid())
with check (
  student_id = auth.uid()
  and public.check_profile_role(auth.uid(), 'student')
);
