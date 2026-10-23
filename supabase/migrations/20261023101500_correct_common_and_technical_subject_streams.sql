-- Correct subject classifications so common and technical subjects are not
-- accidentally captured by broader code prefixes. Keep curricula synchronized.
update public.subjects
set teaching_stream = case
  when code in ('anglais','en_tech_english','english_language','francais','fr_tech_francais','french_language',
    'education_civique','citizenship_en','en_tech_citizenship','fr_tech_ecm','eps','physical_education',
    'en_tech_pe','fr_tech_eps','entrepreneuriat','en_tech_entrepreneurship','religious_studies') then 'general'
  when code like 'en_tech_%' or code like 'fr_tech_%' or code like 'technical_%'
    or code in ('dessin_technique','technologie','manual_labour','travail_manuel','workshop_practice',
      'communication_skills','technical_communication','food_nutrition','esf','art_craft',
      'arts_cinematographiques','pct') then 'technical'
  when code in ('allemand','arabe','chinois','espagnol','grec','italien','latin','langues_nationales',
    'seconde_langue','litterature','literature_in_english','philosophie','philosophy_en','histoire',
    'history_en','geographie','geography_en','economics','commerce','commerce_fr','accounting','comptabilite_fr') then 'literary'
  when code in ('additional_mathematics','further_mathematics','mathematics_en','mathematiques','biology_en',
    'human_biology','chemistry_en','chimie','geology','general_science','physics_en','physique','sciences',
    'svt','computer_science_en','informatique','logic') then 'scientific'
  else teaching_stream end
where is_active;

update public.curricula cu
set teaching_stream = s.teaching_stream
from public.subjects s
where s.id = cu.subject_id
  and cu.teaching_stream is distinct from s.teaching_stream;

notify pgrst, 'reload schema';