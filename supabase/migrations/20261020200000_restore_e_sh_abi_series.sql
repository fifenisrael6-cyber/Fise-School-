-- Restore official francophone second-cycle series that were absent from the
-- catalogue (E, SH and ABI) without deleting or renaming existing BIL/A4/etc rooms.
begin;

insert into public.series(code,name_fr,name_en,verification_status,active)
values
 ('e','E - Mathématiques et Techniques','E - Mathematics and Technology','verified'::public.catalog_verification_status,true),
 ('sh','SH - Sciences Humaines','SH - Humanities','verified'::public.catalog_verification_status,true),
 ('abi','ABI - A4 Bilingue','ABI - Bilingual Arts','verified'::public.catalog_verification_status,true)
on conflict(code) do nothing;

insert into public.exam_level_series(exam_level_id,series_id,verification_status,active)
select el.id,s.id,'verified'::public.catalog_verification_status,true
from public.exam_levels el
join public.series s on s.code in ('e','sh','abi')
where el.active and el.subsystem='francophone' and el.sector='general'
  and el.level_order>=5
on conflict(exam_level_id,series_id) do update
set active=true,verification_status='verified'::public.catalog_verification_status;

-- Add rooms for E and SH. Never overwrite existing/admin-named rooms.
insert into public.school_classes
  (name,display_name,subsystem,sector,academic_year_id,exam_level_id,series_id,specialty_id,language_option)
select el.code || '_' || s.code,
       el.level_name_fr || ' — ' || s.name_fr,
       el.subsystem,el.sector,ay.id,el.id,s.id,null,null
from public.exam_levels el
join public.academic_years ay on ay.is_current
join public.exam_level_series els on els.exam_level_id=el.id and els.active
join public.series s on s.id=els.series_id and s.active
where el.active and el.subsystem='francophone' and el.sector='general'
  and el.level_order>=5 and s.code in ('e','sh')
on conflict(name,academic_year_id) do nothing;

-- ABI has a selectable language-II option; keep all five existing language
-- choices distinct and preserve all legacy BIL rooms.
with language_options(code,label_fr) as (
 values ('allemand','Allemand'),('espagnol','Espagnol'),('arabe','Arabe'),
        ('italien','Italien'),('chinois','Chinois')
)
insert into public.school_classes
 (name,display_name,subsystem,sector,academic_year_id,exam_level_id,series_id,specialty_id,language_option)
select el.code || '_abi_lang_' || lo.code,
       el.level_name_fr || ' — ABI — ' || lo.label_fr,
       el.subsystem,el.sector,ay.id,el.id,s.id,null,lo.code
from public.exam_levels el
join public.academic_years ay on ay.is_current
join public.series s on s.code='abi' and s.active
cross join language_options lo
where el.active and el.subsystem='francophone' and el.sector='general'
  and el.level_order>=5
on conflict(name,academic_year_id) do nothing;

-- Give the restored series only subjects present in the level catalogue.
with common(series_code,subject_code) as (
 values
 ('e','francais'),('e','litterature'),('e','anglais'),('e','histoire'),
 ('e','geographie'),('e','education_civique'),('e','informatique'),('e','eps'),
 ('e','philosophie'),('e','sciences'),('e','langues_nationales'),('e','education_artistique'),
 ('sh','francais'),('sh','litterature'),('sh','anglais'),('sh','histoire'),
 ('sh','geographie'),('sh','education_civique'),('sh','informatique'),('sh','eps'),
 ('sh','philosophie'),('sh','sciences'),('sh','langues_nationales'),('sh','education_artistique'),
 ('abi','francais'),('abi','litterature'),('abi','anglais'),('abi','histoire'),
 ('abi','geographie'),('abi','education_civique'),('abi','informatique'),('abi','eps'),
 ('abi','philosophie'),('abi','sciences'),('abi','langues_nationales'),('abi','education_artistique')
), specialized(series_code,subject_code) as (
 values
 ('e','mathematiques'),('e','physique'),('e','chimie'),('e','svt'),
 ('sh','mathematiques'),
 ('abi','mathematiques'),
 ('abi','allemand'),('abi','espagnol'),('abi','arabe'),('abi','italien'),('abi','chinois')
)
insert into public.series_subject_catalog(series_code,subject_code)
select series_code,subject_code from common
union
select series_code,subject_code from specialized
on conflict(series_code,subject_code) do nothing;

-- Reconcile all active general classrooms using the explicit series list and
-- selected language. Technical mappings and all course/chapter/resource rows
-- remain untouched.
with expected as (
 select distinct c.id class_id,s.id subject_id,
        coalesce(lsc.is_compulsory,true) is_compulsory,
        lsc.option_group,coalesce(lsc.position,0) position
 from public.school_classes c
 join public.exam_levels el on el.id=c.exam_level_id
 join public.level_subject_catalog lsc on lsc.level_code=el.code
 join public.subjects s on s.code=lsc.subject_code and s.is_active
  and s.subsystem=c.subsystem and s.sector=c.sector
 left join public.series ser on ser.id=c.series_id
 left join public.series_subject_catalog ssc
  on ssc.series_code=ser.code and ssc.subject_code=s.code
 where c.is_active and c.sector='general'
  and ((c.series_id is not null and ssc.subject_code is not null)
    or (c.series_id is null and lsc.is_compulsory)
    or (c.series_id is null and c.language_option is not null
        and s.code=any(regexp_split_to_array(c.language_option,'_')))
  )
  and (s.code not in ('allemand','espagnol','arabe','italien','chinois')
    or (c.language_option is not null
        and s.code=any(regexp_split_to_array(c.language_option,'_'))))
), dedup as (
 select class_id,subject_id,bool_or(is_compulsory) is_compulsory,
        min(option_group) filter(where option_group is not null) option_group,
        min(position) position
 from expected group by class_id,subject_id
)
update public.class_subjects cs
set is_active=false
from public.school_classes c
where cs.class_id=c.id and c.is_active and c.sector='general' and cs.is_active
 and not exists(select 1 from dedup e where e.class_id=cs.class_id and e.subject_id=cs.subject_id);

with expected as (
 select distinct c.id class_id,s.id subject_id,
        coalesce(lsc.is_compulsory,true) is_compulsory,
        lsc.option_group,coalesce(lsc.position,0) position
 from public.school_classes c
 join public.exam_levels el on el.id=c.exam_level_id
 join public.level_subject_catalog lsc on lsc.level_code=el.code
 join public.subjects s on s.code=lsc.subject_code and s.is_active
  and s.subsystem=c.subsystem and s.sector=c.sector
 left join public.series ser on ser.id=c.series_id
 left join public.series_subject_catalog ssc
  on ssc.series_code=ser.code and ssc.subject_code=s.code
 where c.is_active and c.sector='general'
  and ((c.series_id is not null and ssc.subject_code is not null)
    or (c.series_id is null and lsc.is_compulsory)
    or (c.series_id is null and c.language_option is not null
        and s.code=any(regexp_split_to_array(c.language_option,'_')))
  )
  and (s.code not in ('allemand','espagnol','arabe','italien','chinois')
    or (c.language_option is not null
        and s.code=any(regexp_split_to_array(c.language_option,'_'))))
), dedup as (
 select class_id,subject_id,bool_or(is_compulsory) is_compulsory,
        min(option_group) filter(where option_group is not null) option_group,
        min(position) position
 from expected group by class_id,subject_id
)
insert into public.class_subjects(class_id,subject_id,is_compulsory,option_group,position,is_active)
select class_id,subject_id,is_compulsory,option_group,position,true from dedup
on conflict(class_id,subject_id) do update
set is_active=true,is_compulsory=excluded.is_compulsory,
    option_group=excluded.option_group,position=excluded.position;

commit;
