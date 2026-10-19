-- Reconcile general-subsystem subjects from explicit series mappings and the
-- level catalogue, rather than copying contaminated class_subjects-derived chapter
-- containers back into the classroom. Technical classes retain their exact
-- specialty curriculum mapping established by the previous migration.
begin;

-- Common second-cycle francophone subjects that are shared across the series.
-- Specialized subjects and language options are added per series below.
with common(series_code, subject_code) as (
  values
    ('a1','francais'),('a1','litterature'),('a1','anglais'),('a1','histoire'),
    ('a1','geographie'),('a1','education_civique'),('a1','informatique'),
    ('a1','eps'),('a1','philosophie'),('a1','sciences'),
    ('a1','langues_nationales'),('a1','education_artistique'),
    ('a2','francais'),('a2','litterature'),('a2','anglais'),('a2','histoire'),
    ('a2','geographie'),('a2','education_civique'),('a2','informatique'),
    ('a2','eps'),('a2','philosophie'),('a2','sciences'),
    ('a2','langues_nationales'),('a2','education_artistique'),
    ('a3','francais'),('a3','litterature'),('a3','anglais'),('a3','histoire'),
    ('a3','geographie'),('a3','education_civique'),('a3','informatique'),
    ('a3','eps'),('a3','philosophie'),('a3','sciences'),
    ('a3','langues_nationales'),('a3','education_artistique'),
    ('a4','francais'),('a4','litterature'),('a4','anglais'),('a4','histoire'),
    ('a4','geographie'),('a4','education_civique'),('a4','informatique'),
    ('a4','eps'),('a4','philosophie'),('a4','sciences'),
    ('a4','langues_nationales'),('a4','education_artistique'),
    ('a5','francais'),('a5','litterature'),('a5','anglais'),('a5','histoire'),
    ('a5','geographie'),('a5','education_civique'),('a5','informatique'),
    ('a5','eps'),('a5','philosophie'),('a5','sciences'),
    ('a5','langues_nationales'),('a5','education_artistique'),
    ('ac','francais'),('ac','litterature'),('ac','anglais'),('ac','histoire'),
    ('ac','geographie'),('ac','education_civique'),('ac','informatique'),
    ('ac','eps'),('ac','philosophie'),('ac','sciences'),
    ('ac','langues_nationales'),('ac','education_artistique'),
    ('c','francais'),('c','litterature'),('c','anglais'),('c','histoire'),
    ('c','geographie'),('c','education_civique'),('c','informatique'),
    ('c','eps'),('c','philosophie'),('c','sciences'),
    ('c','langues_nationales'),('c','education_artistique'),
    ('d','francais'),('d','litterature'),('d','anglais'),('d','histoire'),
    ('d','geographie'),('d','education_civique'),('d','informatique'),
    ('d','eps'),('d','philosophie'),('d','sciences'),
    ('d','langues_nationales'),('d','education_artistique'),
    ('ti','francais'),('ti','litterature'),('ti','anglais'),('ti','histoire'),
    ('ti','geographie'),('ti','education_civique'),('ti','informatique'),
    ('ti','eps'),('ti','philosophie'),('ti','sciences'),
    ('ti','langues_nationales'),('ti','education_artistique'),
    ('bil','francais'),('bil','litterature'),('bil','anglais'),('bil','histoire'),
    ('bil','geographie'),('bil','education_civique'),('bil','informatique'),
    ('bil','eps'),('bil','philosophie'),('bil','sciences'),
    ('bil','langues_nationales'),('bil','education_artistique')
), specialized(series_code, subject_code) as (
  values
    ('a1','latin'),('a1','grec'),
    ('a2','latin'),('a2','allemand'),('a2','espagnol'),('a2','arabe'),('a2','italien'),('a2','chinois'),
    ('a3','latin'),
    ('a4','allemand'),('a4','espagnol'),('a4','arabe'),('a4','italien'),('a4','chinois'),
    ('a5','allemand'),('a5','espagnol'),('a5','arabe'),('a5','italien'),('a5','chinois'),
    ('ac','arts_cinematographiques'),
    ('c','mathematiques'),('c','physique'),('c','chimie'),('c','svt'),
    ('d','mathematiques'),('d','physique'),('d','chimie'),('d','svt'),
    ('ti','mathematiques'),('ti','physique'),
    ('bil','mathematiques'),
    ('gce_arts','english_language'),('gce_arts','french_language'),
    ('gce_arts','citizenship_en'),('gce_arts','physical_education'),
    ('gce_arts','computer_science_en'),('gce_arts','economics'),
    ('gce_arts','religious_studies'),('gce_arts','logic'),
    ('gce_arts','philosophy_en'),('gce_arts','geography_en'),
    ('gce_arts','history_en'),('gce_arts','literature_in_english'),
    ('gce_arts','accounting'),('gce_arts','commerce'),
    ('gce_science','english_language'),('gce_science','french_language'),
    ('gce_science','citizenship_en'),('gce_science','physical_education'),
    ('gce_science','computer_science_en'),('gce_science','mathematics_en'),
    ('gce_science','physics_en'),('gce_science','chemistry_en'),
    ('gce_science','biology_en'),('gce_science','further_mathematics'),
    ('gce_science','geology'),('gce_science','human_biology')
)
insert into public.series_subject_catalog(series_code, subject_code)
select series_code, subject_code from common
union
select series_code, subject_code from specialized
on conflict (series_code, subject_code) do nothing;

-- Rebuild only general-class mappings using level catalogue + the selected
-- series. Language subjects are included only when selected for that room.
with expected as (
  select distinct c.id as class_id, s.id as subject_id,
         coalesce(lsc.is_compulsory, true) as is_compulsory,
         lsc.option_group,
         coalesce(lsc.position, 0) as position
  from public.school_classes c
  join public.exam_levels el on el.id = c.exam_level_id
  join public.level_subject_catalog lsc on lsc.level_code = el.code
  join public.subjects s on s.code = lsc.subject_code
    and s.is_active and s.subsystem = c.subsystem and s.sector = c.sector
  left join public.series ser on ser.id = c.series_id
  left join public.series_subject_catalog ssc
    on ssc.series_code = ser.code and ssc.subject_code = s.code
  where c.is_active
    and c.sector = 'general'
    and (
      (c.series_id is not null and ssc.subject_code is not null)
      or
      (c.series_id is null and lsc.is_compulsory)
      or
      (c.series_id is null and c.language_option is not null
       and s.code = any(regexp_split_to_array(c.language_option, '_')))
    )
    and (
      s.code not in ('allemand','espagnol','arabe','italien','chinois')
      or (c.language_option is not null
          and s.code = any(regexp_split_to_array(c.language_option, '_')))
    )
), dedup as (
  select class_id, subject_id,
         bool_or(is_compulsory) as is_compulsory,
         min(option_group) filter (where option_group is not null) as option_group,
         min(position) as position
  from expected
  group by class_id, subject_id
)
update public.class_subjects cs
set is_active = false
from public.school_classes c
where cs.class_id = c.id
  and c.is_active and c.sector = 'general'
  and cs.is_active
  and not exists (
    select 1 from dedup e
    where e.class_id = cs.class_id and e.subject_id = cs.subject_id
  );

with expected as (
  select distinct c.id as class_id, s.id as subject_id,
         coalesce(lsc.is_compulsory, true) as is_compulsory,
         lsc.option_group,
         coalesce(lsc.position, 0) as position
  from public.school_classes c
  join public.exam_levels el on el.id = c.exam_level_id
  join public.level_subject_catalog lsc on lsc.level_code = el.code
  join public.subjects s on s.code = lsc.subject_code
    and s.is_active and s.subsystem = c.subsystem and s.sector = c.sector
  left join public.series ser on ser.id = c.series_id
  left join public.series_subject_catalog ssc
    on ssc.series_code = ser.code and ssc.subject_code = s.code
  where c.is_active and c.sector = 'general'
    and (
      (c.series_id is not null and ssc.subject_code is not null)
      or (c.series_id is null and lsc.is_compulsory)
      or (c.series_id is null and c.language_option is not null
          and s.code = any(regexp_split_to_array(c.language_option, '_')))
    )
    and (
      s.code not in ('allemand','espagnol','arabe','italien','chinois')
      or (c.language_option is not null
          and s.code = any(regexp_split_to_array(c.language_option, '_')))
    )
), dedup as (
  select class_id, subject_id,
         bool_or(is_compulsory) as is_compulsory,
         min(option_group) filter (where option_group is not null) as option_group,
         min(position) as position
  from expected
  group by class_id, subject_id
)
insert into public.class_subjects
  (class_id, subject_id, is_compulsory, option_group, position, is_active)
select class_id, subject_id, is_compulsory, option_group, position, true
from dedup
on conflict (class_id, subject_id) do update
set is_compulsory = excluded.is_compulsory,
    option_group = excluded.option_group,
    position = excluded.position,
    is_active = true;

commit;
