-- Restore second-cycle common subjects used in francophone literary/arts series.
-- Only additive catalogue rows are inserted; no existing courses or chapters change.
begin;

insert into public.level_subject_catalog(level_code, subject_code, is_compulsory, option_group, position)
select el.code, v.subject_code, true, null, v.position
from public.exam_levels el
cross join (values
  ('sciences',130),
  ('langues_nationales',131),
  ('education_artistique',132)
) as v(subject_code, position)
where el.subsystem='francophone'
  and el.sector='general'
  and el.code in ('fr_general_seconde','fr_general_premiere','fr_general_terminale')
on conflict (level_code, subject_code) do nothing;

insert into public.series_subject_catalog(series_code, subject_code)
select s.series_code, v.subject_code
from (values ('a1'),('a2'),('a3'),('a4'),('a5'),('ac'),('bil')) s(series_code)
cross join (values ('sciences'),('langues_nationales'),('education_artistique')) v(subject_code)
on conflict (series_code, subject_code) do nothing;

-- These three francophone common subjects do not belong to C/D/TI specialty lists.
delete from public.series_subject_catalog
where series_code in ('c','d','ti')
  and subject_code in ('sciences','langues_nationales','education_artistique');

with expected as (
  select distinct c.id as class_id, s.id as subject_id,
         coalesce(lsc.is_compulsory, true) as is_compulsory,
         lsc.option_group,
         coalesce(lsc.position, 0) as position
  from public.school_classes c
  join public.exam_levels el on el.id=c.exam_level_id
  join public.level_subject_catalog lsc on lsc.level_code=el.code
  join public.subjects s on s.code=lsc.subject_code
    and s.is_active and s.subsystem=c.subsystem and s.sector=c.sector
  left join public.series ser on ser.id=c.series_id
  left join public.series_subject_catalog ssc
    on ssc.series_code=ser.code and ssc.subject_code=s.code
  where c.is_active and c.sector='general'
    and (
      (c.series_id is not null and ssc.subject_code is not null)
      or (c.series_id is null and lsc.is_compulsory)
      or (c.series_id is null and c.language_option is not null
          and s.code=any(regexp_split_to_array(c.language_option,'_')))
    )
    and (
      s.code not in ('allemand','espagnol','arabe','italien','chinois')
      or (c.language_option is not null
          and s.code=any(regexp_split_to_array(c.language_option,'_')))
    )
), dedup as (
  select class_id, subject_id, bool_or(is_compulsory) as is_compulsory,
         min(option_group) filter (where option_group is not null) as option_group,
         min(position) as position
  from expected group by class_id,subject_id
)
update public.class_subjects cs
set is_active=false
from public.school_classes c
where cs.class_id=c.id and c.is_active and c.sector='general' and cs.is_active
  and not exists(select 1 from dedup e where e.class_id=cs.class_id and e.subject_id=cs.subject_id);

with expected as (
  select distinct c.id as class_id, s.id as subject_id,
         coalesce(lsc.is_compulsory, true) as is_compulsory,
         lsc.option_group,
         coalesce(lsc.position, 0) as position
  from public.school_classes c
  join public.exam_levels el on el.id=c.exam_level_id
  join public.level_subject_catalog lsc on lsc.level_code=el.code
  join public.subjects s on s.code=lsc.subject_code
    and s.is_active and s.subsystem=c.subsystem and s.sector=c.sector
  left join public.series ser on ser.id=c.series_id
  left join public.series_subject_catalog ssc
    on ssc.series_code=ser.code and ssc.subject_code=s.code
  where c.is_active and c.sector='general'
    and (
      (c.series_id is not null and ssc.subject_code is not null)
      or (c.series_id is null and lsc.is_compulsory)
      or (c.series_id is null and c.language_option is not null
          and s.code=any(regexp_split_to_array(c.language_option,'_')))
    )
    and (
      s.code not in ('allemand','espagnol','arabe','italien','chinois')
      or (c.language_option is not null
          and s.code=any(regexp_split_to_array(c.language_option,'_')))
    )
), dedup as (
  select class_id, subject_id, bool_or(is_compulsory) as is_compulsory,
         min(option_group) filter (where option_group is not null) as option_group,
         min(position) as position
  from expected group by class_id,subject_id
)
insert into public.class_subjects(class_id,subject_id,is_compulsory,option_group,position,is_active)
select class_id,subject_id,is_compulsory,option_group,position,true from dedup
on conflict(class_id,subject_id) do update
set is_active=true, is_compulsory=excluded.is_compulsory,
    option_group=excluded.option_group, position=excluded.position;

commit;
