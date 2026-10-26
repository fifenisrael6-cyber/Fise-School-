-- Complete missing first-cycle technical specialties listed by MINESEC.
insert into public.specialties (code, name_fr, name_en, verification_status, source_url, active)
values
  ('capa','Carrosserie et peinture automobile','Automobile Body Work and Spraying','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('carr','Carrelage','Tile Laying','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('coom','Construction et ouvrage métallique','Metallic Framework Construction','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('deba','Dessin en bâtiment','Draftsmanship','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('mael','Mécanique automobile — électricité','Automobile Electrical Works','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('main','Mécanique automobile — injection diesel','Diesel Injection Engine Mechanics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('mare','Mécanique automobile — réparation','Automobile Repair Mechanics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('mefa','Mécanique de fabrication','Manufacturing Mechanics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('mefe','Métaux en feuilles','Sheet Metal Work','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('sh','Service hôtelier','Hotel Services','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true)
on conflict (code) do update
set name_fr = excluded.name_fr,
    name_en = excluded.name_en,
    verification_status = 'verified',
    source_url = excluded.source_url,
    active = true,
    updated_at = now();

-- These specialties are first-cycle technical pathways in both subsystems,
-- except SH, which MINESEC lists only in francophone STT.
insert into public.exam_level_specialties (exam_level_id, specialty_id, verification_status, active)
select el.id, sp.id, 'verified', true
from public.exam_levels el
join public.specialties sp on sp.code in ('capa','carr','coom','deba','mael','main','mare','mefa','mefe') and sp.active
where el.active and el.sector = 'technical' and el.level_order <= 4
on conflict (exam_level_id, specialty_id) do update
set active = true, verification_status = 'verified';

insert into public.exam_level_specialties (exam_level_id, specialty_id, verification_status, active)
select el.id, sp.id, 'verified', true
from public.exam_levels el
join public.specialties sp on sp.code = 'sh' and sp.active
where el.active and el.subsystem = 'francophone' and el.sector = 'technical' and el.level_order <= 4
on conflict (exam_level_id, specialty_id) do update
set active = true, verification_status = 'verified';

insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id, exam_level_id, series_id, specialty_id, language_option, is_active)
select
  case when el.subsystem = 'anglophone'
    then el.code || '_specialty_' || sp.code
    else el.code || '_' || sp.code end,
  (case when el.subsystem = 'anglophone' then el.level_name_en else el.level_name_fr end)
    || ' — ' ||
  (case when el.subsystem = 'anglophone' then sp.name_en else sp.name_fr end),
  el.subsystem, el.sector, ay.id, el.id, null, sp.id, null, true
from public.exam_levels el
join public.academic_years ay on ay.is_current
join public.exam_level_specialties es on es.exam_level_id = el.id and es.active
join public.specialties sp on sp.id = es.specialty_id and sp.active
where el.active and el.sector = 'technical'
  and el.level_order <= 4
  and sp.code in ('capa','carr','coom','deba','mael','main','mare','mefa','mefe')
on conflict (name, academic_year_id) do update
set display_name = excluded.display_name,
    specialty_id = excluded.specialty_id,
    is_active = true,
    updated_at = now();

insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id, exam_level_id, series_id, specialty_id, language_option, is_active)
select
  el.code || '_sh',
  el.level_name_fr || ' — ' || sp.name_fr,
  el.subsystem, el.sector, ay.id, el.id, null, sp.id, null, true
from public.exam_levels el
join public.academic_years ay on ay.is_current
join public.exam_level_specialties es on es.exam_level_id = el.id and es.active
join public.specialties sp on sp.id = es.specialty_id and sp.active and sp.code = 'sh'
where el.active and el.subsystem = 'francophone' and el.sector = 'technical' and el.level_order <= 4
on conflict (name, academic_year_id) do update
set display_name = excluded.display_name,
    specialty_id = excluded.specialty_id,
    is_active = true,
    updated_at = now();
