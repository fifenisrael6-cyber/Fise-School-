-- Fise School: align technical specialties with the official MINESEC cycle/subsystem lists.
-- Existing records are retained; unsupported room options are deactivated rather than deleted.
-- Sources:
-- https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone
-- https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone

insert into public.specialties (code, name_fr, name_en, verification_status, source_url, active)
values
  ('af sci','Affûteur-scieur','Saw Filer', 'verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('afsci','Affûteur-scieur','Saw Filer','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('ajus','Ajustage','Fitting and Machining','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('bpa','Boulangerie-pâtisserie','Bakery and Pastry','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('cu','Cuisine','Cookery','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('escom','Employé des services comptables','Accounting Services Clerk','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('esfi','Employé des services financiers','Financial Services Clerk','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('re','Restauration','Catering','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('sebu','Secrétariat et bureautique','Secretarial and Office Skills','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('seme','Secrétariat médical','Medical Secretarial Studies','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('ses','Sciences économiques et sociales','Economic and Social Studies','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('afsci','Affûteur-scieur','Saw Filer','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('reca','Réparation carrosserie automobile','Automotive Body Repair','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('bijo','Bijouterie','Jewellery','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('cm','Construction mécanique','Mechanical Engineering','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('cma_mvpl','Construction et maintenance automobile — poids lourds','Automotive Maintenance — Heavy Vehicles','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('cma_mvt','Construction et maintenance automobile — véhicules de tourisme','Automotive Maintenance — Passenger Vehicles','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('e','Technique et mathématique','Mathematics and Mechanics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('f1','Fabrication mécanique','Manufacturing Mechanics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('ma','Mécanique automobile','Automobile Mechanics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('mem','Maintenance électromécanique','Electro-mechanical Maintenance','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('mf_cm','Métaux en feuilles et construction métallique','Sheet Metal and Metallic Construction','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('aicb','Aide chimique biologiste','Bio-chemical Industry Assistant','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('aici','Aide chimique industrielle','Chemical Industry Assistant','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('elau','Électricité automobile','Automobile Electrical Works','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('elba','Électricité bâtiment','Building Electrical Installation','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('eleq','Électricité d’équipement','Electrical Installation','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('elme','Électromécanique','Electro-mechanics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('elni','Électronique','Electronics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('frcl','Froid et climatisation','Refrigeration and Air Conditioning','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('ci','Chimie industrielle','Industrial Chemistry','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('f2','Électronique','Electronics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('f6_bipe','Génie chimique — bioprocédés et pétrochimie','Chemical Engineering — Bioprocesses and Petrochemistry','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('f6_coph','Génie chimique — cosmétique et pharmacie','Chemical Engineering — Cosmetics and Pharmacy','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('f6_mipe','Génie chimique — mines et pétrole','Chemical Engineering — Mining and Petroleum','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('mehb','Maintenance des équipements hospitaliers et biomédicaux','Hospital and Biomedical Equipment Maintenance','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('ceram','Céramique','Ceramics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('ch','Chaudronnerie','Boilermaking','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('ch_ti','Chaudronnerie et tuyauterie industrielle','Industrial Boilermaking and Pipefitting','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('ef','Exploitation forestière','Forestry Exploitation','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('f4ba','Génie civil — bâtiment','Building Construction','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('f4be','Génie civil — bureau d’études','Civil Engineering — Drafting Office','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('f4tp','Génie civil — travaux publics','Civil Engineering — Public Works','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('gtto','Géomètre topographe','Surveying and Topography','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('ib','Industrie du bois','Wood Processing Industry','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('is','Installation sanitaire','Sanitary Equipment Installation','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('mea','Maintenance des équipements agricoles','Agricultural Equipment Maintenance','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('meb','Menuiserie-ébénisterie','Carpentry and Cabinet Making','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('pa_ppo','Production animale — producteur de porc','Animal Production — Pig Farming','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('pa_pv','Production animale — producteur de volaille','Animal Production — Poultry Farming','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('pa_aq','Production animale — aquaculture','Animal Production — Aquaculture','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('pa_pm','Production animale — monogastriques','Animal Production — Monogastrics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('pa_pp','Production animale — polygastriques','Animal Production — Polygastrics','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('pv_pc','Production végétale — céréales','Crop Production — Cereals','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('pv_pm','Production végétale — maraîchers','Crop Production — Market Gardening','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('pv_pclgc','Production végétale — céréales, légumineuses et champignons','Crop Production — Cereals, Legumes and Mushrooms','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('pv_pcp','Production végétale — cultures pérennes','Crop Production — Perennial Crops','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('pv_pmf','Production végétale — maraîchers et fourrage','Crop Production — Market Gardening and Fodder','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('pv_ps','Production végétale — plants et semences','Crop Production — Seedlings and Seeds','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('tc_pa','Transformation et conservation des produits agropastoraux','Agropastoral Product Processing and Preservation','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('tgf','Techniques et gestion forestières','Forestry Techniques and Management','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('tp','Transformation des produits','Product Processing','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('bp_cf','Brevet professionnel — couture flou','Professional Certificate — Soft Tailoring','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('ih','Industrie d’habillement','Clothing Industry','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true),
  ('sculp','Sculpture','Sculpture','verified','https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone',true)
on conflict (code) do update
set name_fr = excluded.name_fr,
    name_en = excluded.name_en,
    verification_status = 'verified',
    source_url = excluded.source_url,
    active = true,
    updated_at = now();

create temporary table fise_minesec_valid_technical_specialties (
  subsystem text not null,
  cycle integer not null,
  code text not null,
  primary key (subsystem, cycle, code)
) on commit drop;

insert into fise_minesec_valid_technical_specialties (subsystem, cycle, code) values
-- Francophone technical first cycle (cycle 1)
('francophone',1,'escom'),('francophone',1,'esf'),('francophone',1,'esfi'),('francophone',1,'re'),('francophone',1,'sebu'),('francophone',1,'seme'),('francophone',1,'sh'),('francophone',1,'vente'),
('francophone',1,'afsci'),('francophone',1,'ajus'),('francophone',1,'capa'),('francophone',1,'coom'),('francophone',1,'mael'),('francophone',1,'main'),('francophone',1,'mare'),('francophone',1,'mefa'),('francophone',1,'mefe'),('francophone',1,'reca'),
('francophone',1,'aicb'),('francophone',1,'aici'),('francophone',1,'elau'),('francophone',1,'elba'),('francophone',1,'eleq'),('francophone',1,'elme'),('francophone',1,'elni'),('francophone',1,'frcl'),
('francophone',1,'carr'),('francophone',1,'ceram'),('francophone',1,'deba'),('francophone',1,'insa'),('francophone',1,'maco'),('francophone',1,'menu'),('francophone',1,'pa'),('francophone',1,'pa_ppo'),('francophone',1,'pa_pv'),('francophone',1,'pv'),('francophone',1,'pv_pc'),('francophone',1,'pv_pm'),
('francophone',1,'come'),('francophone',1,'decor'),('francophone',1,'esco'),('francophone',1,'peint'),('francophone',1,'sculp'),
-- Francophone technical second cycle (cycle 2)
('francophone',2,'aat'),('francophone',2,'aca'),('francophone',2,'acc'),('francophone',2,'av'),('francophone',2,'bpa'),('francophone',2,'cg'),('francophone',2,'cu'),('francophone',2,'esf'),('francophone',2,'fig'),('francophone',2,'he'),('francophone',2,'ho'),('francophone',2,'ses'),('francophone',2,'to'),
('francophone',2,'bijo'),('francophone',2,'cm'),('francophone',2,'cma_mvpl'),('francophone',2,'cma_mvt'),('francophone',2,'e'),('francophone',2,'f1'),('francophone',2,'ma'),('francophone',2,'mem'),('francophone',2,'mf_cm'),
('francophone',2,'ci'),('francophone',2,'f2'),('francophone',2,'f3'),('francophone',2,'f5'),('francophone',2,'f6_bipe'),('francophone',2,'f6_coph'),('francophone',2,'f6_mipe'),('francophone',2,'f7'),('francophone',2,'f8'),('francophone',2,'mav'),('francophone',2,'mehb'),('francophone',2,'mise'),
('francophone',2,'ceram'),('francophone',2,'ch'),('francophone',2,'ch_ti'),('francophone',2,'ef'),('francophone',2,'f4ba'),('francophone',2,'f4be'),('francophone',2,'f4tp'),('francophone',2,'gtto'),('francophone',2,'ib'),('francophone',2,'is'),('francophone',2,'mea'),('francophone',2,'meb'),('francophone',2,'pa'),('francophone',2,'pa_aq'),('francophone',2,'pa_pm'),('francophone',2,'pa_pp'),('francophone',2,'pv'),('francophone',2,'pv_pclgc'),('francophone',2,'pv_pcp'),('francophone',2,'pv_pmf'),('francophone',2,'pv_ps'),('francophone',2,'tc_pa'),('francophone',2,'tgf'),('francophone',2,'tp'),
('francophone',2,'bp_cf'),('francophone',2,'ih'),('francophone',2,'peint'),('francophone',2,'sculp'),
-- Anglophone technical first cycle (cycle 1)
('anglophone',1,'capa'),('anglophone',1,'coom'),('anglophone',1,'mael'),('anglophone',1,'main'),('anglophone',1,'mare'),('anglophone',1,'mefa'),('anglophone',1,'mefe'),
('anglophone',1,'aicb'),('anglophone',1,'aici'),('anglophone',1,'eleq'),('anglophone',1,'elme'),('anglophone',1,'elni'),('anglophone',1,'frcl'),
('anglophone',1,'carr'),('anglophone',1,'deba'),('anglophone',1,'maco'),('anglophone',1,'menu'),('anglophone',1,'come'),('anglophone',1,'decor'),('anglophone',1,'esco'),
-- Anglophone technical second cycle (cycle 2)
('anglophone',2,'aca'),('anglophone',2,'acc'),('anglophone',2,'cg'),('anglophone',2,'esf'),
('anglophone',2,'bijo'),('anglophone',2,'e'),('anglophone',2,'f1'),('anglophone',2,'ma'),('anglophone',2,'mem'),('anglophone',2,'mf_cm'),
('anglophone',2,'ci'),('anglophone',2,'f2'),('anglophone',2,'f3'),('anglophone',2,'f5'),('anglophone',2,'f7'),('anglophone',2,'f8'),('anglophone',2,'mehb'),('anglophone',2,'mise'),
('anglophone',2,'ef'),('anglophone',2,'f4ba'),('anglophone',2,'f4be'),('anglophone',2,'f4tp'),('anglophone',2,'gtto'),('anglophone',2,'ib'),('anglophone',2,'is'),('anglophone',2,'meb'),('anglophone',2,'ih');

-- First deactivate obsolete rooms while their old specialty links still validate.
update public.school_classes c
set is_active = false, updated_at = now()
from public.academic_years ay, public.exam_levels el, public.specialties sp
where ay.id = c.academic_year_id
  and ay.is_current
  and el.id = c.exam_level_id
  and sp.id = c.specialty_id
  and c.is_active
  and c.sector = 'technical'
  and not exists (
    select 1 from fise_minesec_valid_technical_specialties v
    where v.subsystem = c.subsystem::text
      and v.code = sp.code
      and ((v.cycle = 1 and el.level_order <= 4) or (v.cycle = 2 and el.level_order >= 5))
  )
  and not exists (select 1 from public.class_students cs where cs.class_id = c.id and cs.is_active);

-- Rebuild active specialty-to-level links from the official subsystem/cycle list.
update public.exam_level_specialties es
set active = false
from public.exam_levels el
where es.exam_level_id = el.id
  and el.active
  and el.sector = 'technical'
  and es.active;

insert into public.exam_level_specialties (exam_level_id, specialty_id, verification_status, active)
select el.id, sp.id, 'verified', true
from public.exam_levels el
join fise_minesec_valid_technical_specialties v
  on v.subsystem = el.subsystem::text
 and ((v.cycle = 1 and el.level_order <= 4) or (v.cycle = 2 and el.level_order >= 5))
join public.specialties sp on sp.code = v.code and sp.active
where el.active and el.sector = 'technical'
on conflict (exam_level_id, specialty_id) do update
set active = true, verification_status = 'verified';

-- Ensure one correctly localized room exists for every valid technical specialty.
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
join fise_minesec_valid_technical_specialties v
  on v.subsystem = el.subsystem::text
 and ((v.cycle = 1 and el.level_order <= 4) or (v.cycle = 2 and el.level_order >= 5))
join public.specialties sp on sp.code = v.code and sp.active
where el.active and el.sector = 'technical'
on conflict (name, academic_year_id) do update
set display_name = excluded.display_name,
    specialty_id = excluded.specialty_id,
    is_active = true,
    updated_at = now();

-- Make the room-change RPC reject stale/unsupported catalog links as well as
-- rooms from a different subsystem or sector.
create or replace function public.list_student_available_classes()
returns table (
  class_id uuid, class_name text, subsystem text, sector text,
  exam_level_id uuid, exam_id uuid, series_id uuid, specialty_id uuid,
  level_order integer, language_option text, academic_year_id uuid,
  exam_level_label text, exam_label text, track_label text,
  relation text, recommended boolean
)
language plpgsql stable security definer set search_path = public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_current public.school_classes%rowtype;
  v_current_order integer;
  v_year uuid;
  v_subsystem text;
  v_sector text;
  v_series uuid;
  v_specialty uuid;
begin
  if v_user_id is null then raise exception 'Authentication is required'; end if;
  select * into v_profile from public.profiles where id = v_user_id and role = 'student';
  if not found then raise exception 'Only student accounts can change classroom'; end if;

  select sc.* into v_current
  from public.class_students cs
  join public.school_classes sc on sc.id = cs.class_id
  join public.academic_years ay on ay.id = sc.academic_year_id
  where cs.student_id = v_user_id and cs.is_active and sc.is_active and ay.is_current
  order by cs.joined_at desc limit 1;

  if v_current.id is not null then
    select el.level_order into v_current_order from public.exam_levels el where el.id = v_current.exam_level_id;
    v_year := v_current.academic_year_id;
    v_subsystem := v_current.subsystem::text;
    v_sector := v_current.sector::text;
    v_series := coalesce(v_profile.series_id, v_current.series_id);
    v_specialty := coalesce(v_profile.specialty_id, v_current.specialty_id);
  else
    select ay.id into v_year from public.academic_years ay where ay.is_current limit 1;
    v_subsystem := v_profile.subsystem::text;
    v_sector := v_profile.sector::text;
    v_series := v_profile.series_id;
    v_specialty := v_profile.specialty_id;
  end if;

  if v_subsystem is null or v_sector is null
     or v_subsystem not in ('francophone','anglophone')
     or v_sector not in ('general','technical') then
    raise exception 'Student subsystem and sector must be set before changing classroom';
  end if;

  return query
  select dest.id, dest.display_name, dest.subsystem::text, dest.sector::text,
    dest.exam_level_id, level.exam_id, dest.series_id, dest.specialty_id,
    level.level_order, dest.language_option, dest.academic_year_id,
    case when v_profile.preferred_language = 'en' then level.level_name_en else level.level_name_fr end,
    case when v_profile.preferred_language = 'en' then exam.name_en else exam.name_fr end,
    case when v_profile.preferred_language = 'en' then coalesce(series.name_en, specialty.name_en)
      else coalesce(series.name_fr, specialty.name_fr) end,
    case when level.level_order = v_current_order + 1 then 'next'
      when level.level_order = v_current_order then 'same'
      when level.level_order < v_current_order then 'previous' else 'other' end,
    (v_current_order is not null and level.level_order = v_current_order + 1
      and (v_series is null or dest.series_id = v_series)
      and (v_specialty is null or dest.specialty_id = v_specialty))
  from public.school_classes dest
  join public.academic_years ay on ay.id = dest.academic_year_id
  join public.exam_levels level on level.id = dest.exam_level_id and level.active
  left join public.exams exam on exam.id = level.exam_id
  left join public.series series on series.id = dest.series_id
  left join public.specialties specialty on specialty.id = dest.specialty_id
  where dest.is_active and ay.is_current and dest.academic_year_id = v_year
    and dest.id is distinct from v_current.id
    and dest.subsystem::text = v_subsystem and dest.sector::text = v_sector
    and position('_' in coalesce(dest.language_option,'')) = 0
    and exists (select 1 from public.teacher_followed_classes tfc where tfc.class_id = dest.id)
    and (dest.series_id is null or exists (
      select 1 from public.exam_level_series els
      where els.exam_level_id = dest.exam_level_id and els.series_id = dest.series_id and els.active))
    and (dest.specialty_id is null or exists (
      select 1 from public.exam_level_specialties es
      where es.exam_level_id = dest.exam_level_id and es.specialty_id = dest.specialty_id and es.active))
    and not (dest.series_id is null and dest.specialty_id is null and exists (
      select 1 from public.school_classes specific
      where specific.is_active and specific.id <> dest.id
        and specific.academic_year_id = dest.academic_year_id
        and specific.exam_level_id = dest.exam_level_id
        and specific.subsystem = dest.subsystem and specific.sector = dest.sector
        and (specific.series_id is not null or specific.specialty_id is not null)))
  order by 16 desc, level.level_order, dest.display_name;
end;
$function$;

revoke all on function public.list_student_available_classes() from public, anon;
grant execute on function public.list_student_available_classes() to authenticated;
notify pgrst, 'reload schema';
