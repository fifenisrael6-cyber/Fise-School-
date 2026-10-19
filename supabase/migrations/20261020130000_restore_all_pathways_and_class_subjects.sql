-- Correct pathway repair: use explicit existing curriculum-to-specialty
-- relationships only. Never cross-assign every technical specialty to every level.
begin;

insert into public.exam_level_series
  (exam_level_id, series_id, verification_status, active)
select distinct el.id, s.id, 'verified', true
from public.exam_levels el
join public.series s
  on (el.subsystem = 'francophone' and lower(s.code) in
      ('a1','a2','a3','a4','a5','ac','c','d','ti','bil'))
  or (el.subsystem = 'anglophone' and lower(s.code) in ('gce_arts','gce_science'))
where el.active and el.sector = 'general' and s.active
  and el.level_order >= 5
on conflict (exam_level_id, series_id) do update
set active = true, verification_status = 'verified';

-- Restore only specialty links supported by an active curriculum tied to the
-- same technical level and specialty. Do not invent combinations.
insert into public.exam_level_specialties
  (exam_level_id, specialty_id, verification_status, active)
select distinct cu.exam_level_id, cu.specialty_id, 'verified', true
from public.curricula cu
join public.exam_levels el on el.id = cu.exam_level_id
join public.specialties sp on sp.id = cu.specialty_id
where cu.is_active and cu.specialty_id is not null
  and el.active and el.sector = 'technical'
  and sp.active
on conflict (exam_level_id, specialty_id) do update
set active = true, verification_status = 'verified';

-- Create missing general rooms for the current year. A2/A4/A5 language-specific
-- rooms are handled by the existing migration. Never overwrite existing rooms.
insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id,
   exam_level_id, series_id, specialty_id, language_option)
select el.code || '_' || s.code,
  case when el.subsystem = 'francophone'
       then el.level_name_fr || ' — ' || s.name_fr
       else el.level_name_en || ' — ' || s.name_en end,
  el.subsystem, el.sector, ay.id, el.id, s.id, null, null
from public.exam_levels el
join public.academic_years ay on ay.is_current
join public.exam_level_series els on els.exam_level_id = el.id and els.active
join public.series s on s.id = els.series_id and s.active
where el.active and el.sector = 'general' and el.level_order >= 5
  and not (el.subsystem = 'francophone' and lower(s.code) in ('a2','a4','a5'))
on conflict (name, academic_year_id) do nothing;

-- Create technical rooms only for validated level-specialty relationships.
insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id,
   exam_level_id, series_id, specialty_id, language_option)
select el.code || '_specialty_' || sp.code,
  case when el.subsystem = 'francophone'
       then el.level_name_fr || ' — ' || sp.name_fr
       else el.level_name_en || ' — ' || sp.name_en end,
  el.subsystem, el.sector, ay.id, el.id, null, sp.id, null
from public.exam_levels el
join public.academic_years ay on ay.is_current
join public.exam_level_specialties els
  on els.exam_level_id = el.id and els.active
join public.specialties sp on sp.id = els.specialty_id and sp.active
where el.active and el.sector = 'technical'
on conflict (name, academic_year_id) do nothing;

-- Reconcile only when a canonical catalogue exists for the exact room context.
-- Existing courses, chapters, and media/resource relationships are untouched.
with expected as (
  select distinct c.id as class_id, cu.subject_id
  from public.school_classes c
  join public.curricula cu
    on cu.subsystem = c.subsystem and cu.sector = c.sector
   and cu.is_active and cu.is_catalog_container
   and (cu.exam_level_id is null or cu.exam_level_id = c.exam_level_id)
   and (cu.series_id is null or cu.series_id = c.series_id)
   and (cu.specialty_id is null or cu.specialty_id = c.specialty_id)
  join public.subjects s on s.id = cu.subject_id and s.is_active
   and s.subsystem = c.subsystem and s.sector = c.sector
   and (
     s.code not in ('allemand','espagnol','arabe','italien','chinois')
     or (c.language_option is not null
         and s.code = any(regexp_split_to_array(c.language_option, '_')))
   )
  where c.is_active
), classes_with_catalog as (
  select class_id from expected group by class_id
)
update public.class_subjects cs
set is_active = false
from classes_with_catalog wc
where cs.class_id = wc.class_id and cs.is_active
  and not exists (
    select 1 from expected e
    where e.class_id = cs.class_id and e.subject_id = cs.subject_id
  );

with expected as (
  select distinct c.id as class_id, cu.subject_id
  from public.school_classes c
  join public.curricula cu
    on cu.subsystem = c.subsystem and cu.sector = c.sector
   and cu.is_active and cu.is_catalog_container
   and (cu.exam_level_id is null or cu.exam_level_id = c.exam_level_id)
   and (cu.series_id is null or cu.series_id = c.series_id)
   and (cu.specialty_id is null or cu.specialty_id = c.specialty_id)
  join public.subjects s on s.id = cu.subject_id and s.is_active
   and s.subsystem = c.subsystem and s.sector = c.sector
   and (
     s.code not in ('allemand','espagnol','arabe','italien','chinois')
     or (c.language_option is not null
         and s.code = any(regexp_split_to_array(c.language_option, '_')))
   )
  where c.is_active
), ranked as (
  select e.class_id, e.subject_id,
         row_number() over (partition by e.class_id order by s.code) - 1 as position
  from expected e join public.subjects s on s.id = e.subject_id
)
insert into public.class_subjects
  (class_id, subject_id, is_compulsory, option_group, position, is_active)
select class_id, subject_id, true, null, position, true
from ranked
on conflict (class_id, subject_id) do update
set is_active = true, position = excluded.position;

commit;
