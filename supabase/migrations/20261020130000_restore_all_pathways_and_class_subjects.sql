-- Restore missing pathway classrooms and scope each classroom to its own
-- explicit curriculum catalogue. Additive migration: no course/chapter/resource
-- tables or existing course records are changed.
begin;

-- Restore valid general-series links for all active general levels. Keep the
-- francophone/anglophone catalogues separate.
insert into public.exam_level_series
  (exam_level_id, series_id, verification_status, active)
select el.id, s.id, 'verified', true
from public.exam_levels el
join public.series s
  on (el.subsystem = 'francophone' and s.code in
      ('a1','a2','a3','a4','a5','ac','c','d','ti','bil'))
  or (el.subsystem = 'anglophone' and s.code in ('gce_arts','gce_science'))
where el.active and el.sector = 'general' and s.active
  and (el.level_order is null or el.level_order >= 5)
on conflict (exam_level_id, series_id) do update
set active = true,
    verification_status = 'verified';

-- Restore technical pathways from the specialties already present in the
-- validated catalogue; do not invent or rename specialties.
insert into public.exam_level_specialties
  (exam_level_id, specialty_id, verification_status, active)
select el.id, sp.id, 'verified', true
from public.exam_levels el
cross join public.specialties sp
where el.active and el.sector = 'technical' and sp.active
  and (el.level_order is null or el.level_order >= 5)
on conflict (exam_level_id, specialty_id) do update
set active = true,
    verification_status = 'verified';

-- Create missing general rooms for the active academic year. DO NOTHING on
-- conflicts so existing/admin-renamed rooms are not overwritten.
insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id,
   exam_level_id, series_id, specialty_id, language_option)
select
  el.code || '_' || s.code,
  case when el.subsystem = 'francophone'
       then el.level_name_fr || ' — ' || s.name_fr
       else el.level_name_en || ' — ' || s.name_en end,
  el.subsystem, el.sector, ay.id, el.id, s.id, null, null
from public.exam_levels el
join public.academic_years ay on ay.is_current
join public.exam_level_series els
  on els.exam_level_id = el.id and els.active
join public.series s on s.id = els.series_id and s.active
where el.active and el.sector = 'general'
  and (el.level_order is null or el.level_order >= 5)
on conflict (name, academic_year_id) do nothing;

-- Create missing technical rooms per actual specialty, including technical
-- francophone and anglophone pathways. Existing rooms remain untouched.
insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id,
   exam_level_id, series_id, specialty_id, language_option)
select
  el.code || '_specialty_' || sp.code,
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
  and (el.level_order is null or el.level_order >= 5)
on conflict (name, academic_year_id) do nothing;

-- Use only official catalog-container curricula that match the classroom's
-- subsystem, sector, level, series and/or specialty. A null series/specialty
-- represents common content; it is not permission to import another pathway.
with expected as (
  select distinct c.id as class_id, cu.subject_id
  from public.school_classes c
  join public.curricula cu
    on cu.subsystem = c.subsystem
   and cu.sector = c.sector
   and cu.is_active
   and cu.is_catalog_container
   and (cu.exam_level_id is null or cu.exam_level_id = c.exam_level_id)
   and (cu.series_id is null or cu.series_id = c.series_id)
   and (cu.specialty_id is null or cu.specialty_id = c.specialty_id)
  join public.subjects s
    on s.id = cu.subject_id and s.is_active
   and s.subsystem = c.subsystem and s.sector = c.sector
  where c.is_active
    and (c.series_id is null or cu.series_id is null or cu.series_id = c.series_id)
    and (c.specialty_id is null or cu.specialty_id is null or cu.specialty_id = c.specialty_id)
),
classes_with_catalog as (
  select class_id, count(*) as subject_count
  from expected
  group by class_id
)
-- Only narrow a room when the official catalogue explicitly defines at least
-- one subject for it; leave rooms with no catalogue untouched for admin review.
update public.class_subjects cs
set is_active = false
from classes_with_catalog wc
where cs.class_id = wc.class_id
  and cs.is_active
  and not exists (
    select 1 from expected e
    where e.class_id = cs.class_id and e.subject_id = cs.subject_id
  );

with expected as (
  select distinct c.id as class_id, cu.subject_id
  from public.school_classes c
  join public.curricula cu
    on cu.subsystem = c.subsystem
   and cu.sector = c.sector
   and cu.is_active
   and cu.is_catalog_container
   and (cu.exam_level_id is null or cu.exam_level_id = c.exam_level_id)
   and (cu.series_id is null or cu.series_id = c.series_id)
   and (cu.specialty_id is null or cu.specialty_id = c.specialty_id)
  join public.subjects s
    on s.id = cu.subject_id and s.is_active
   and s.subsystem = c.subsystem and s.sector = c.sector
  where c.is_active
),
ranked as (
  select e.class_id, e.subject_id,
         row_number() over (partition by e.class_id order by s.code) - 1 as position
  from expected e
  join public.subjects s on s.id = e.subject_id
)
insert into public.class_subjects
  (class_id, subject_id, is_compulsory, option_group, position, is_active)
select class_id, subject_id, true, null, position, true
from ranked
on conflict (class_id, subject_id) do update
set is_active = true,
    position = excluded.position;

commit;
