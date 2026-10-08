-- Assign only the subjects listed for each level/series/language in the curriculum catalog.
-- This deliberately avoids assigning every subject from a subsystem or sector to every classroom.
with expected_raw as (
  select c.id as class_id, s.id as subject_id,
         lsc.is_compulsory, lsc.option_group, lsc.position
  from public.school_classes c
  join public.exam_levels el on el.id = c.exam_level_id
  join public.level_subject_catalog lsc on lsc.level_code = el.code
  join public.subjects s on s.code = lsc.subject_code
    and s.subsystem = c.subsystem and s.sector = c.sector and s.is_active
  where c.is_active
    and (
      c.language_option is null
      or s.code not in ('allemand','espagnol','arabe','italien','chinois')
      or s.code = any(regexp_split_to_array(c.language_option, '_'))
    )
  union
  select c.id, s.id, false, 'Spécialité de série',
         200 + row_number() over (partition by c.id order by s.code)::integer
  from public.school_classes c
  join public.series ser on ser.id = c.series_id
  join public.series_subject_catalog ssc on ssc.series_code = ser.code
  join public.subjects s on s.code = ssc.subject_code
    and s.subsystem = c.subsystem and s.sector = c.sector and s.is_active
  where c.is_active
    and (
      s.code not in ('allemand','espagnol','arabe','italien','chinois')
      or s.code = any(regexp_split_to_array(coalesce(c.language_option,''), '_'))
    )
  union
  select c.id, s.id, false, 'Option linguistique', 400
  from public.school_classes c
  join public.subjects s on s.code = any(regexp_split_to_array(coalesce(c.language_option,''), '_'))
    and s.subsystem = c.subsystem and s.sector = c.sector and s.is_active
  where c.is_active and c.language_option is not null
),
expected as (
  select class_id, subject_id,
         bool_or(coalesce(is_compulsory,false)) as is_compulsory,
         min(option_group) filter(where option_group is not null) as option_group,
         min(position) as position
  from expected_raw
  group by class_id, subject_id
)
update public.class_subjects cs
set is_active = false
where cs.is_active
  and exists (select 1 from public.school_classes c where c.id=cs.class_id and c.is_active)
  and not exists (select 1 from expected e where e.class_id=cs.class_id and e.subject_id=cs.subject_id);

with expected_raw as (
  select c.id as class_id, s.id as subject_id,
         lsc.is_compulsory, lsc.option_group, lsc.position
  from public.school_classes c
  join public.exam_levels el on el.id = c.exam_level_id
  join public.level_subject_catalog lsc on lsc.level_code = el.code
  join public.subjects s on s.code = lsc.subject_code
    and s.subsystem = c.subsystem and s.sector = c.sector and s.is_active
  where c.is_active
    and (
      c.language_option is null
      or s.code not in ('allemand','espagnol','arabe','italien','chinois')
      or s.code = any(regexp_split_to_array(c.language_option, '_'))
    )
  union
  select c.id, s.id, false, 'Spécialité de série',
         200 + row_number() over (partition by c.id order by s.code)::integer
  from public.school_classes c
  join public.series ser on ser.id = c.series_id
  join public.series_subject_catalog ssc on ssc.series_code = ser.code
  join public.subjects s on s.code = ssc.subject_code
    and s.subsystem = c.subsystem and s.sector = c.sector and s.is_active
  where c.is_active
    and (
      s.code not in ('allemand','espagnol','arabe','italien','chinois')
      or s.code = any(regexp_split_to_array(coalesce(c.language_option,''), '_'))
    )
  union
  select c.id, s.id, false, 'Option linguistique', 400
  from public.school_classes c
  join public.subjects s on s.code = any(regexp_split_to_array(coalesce(c.language_option,''), '_'))
    and s.subsystem = c.subsystem and s.sector = c.sector and s.is_active
  where c.is_active and c.language_option is not null
),
expected as (
  select class_id, subject_id,
         bool_or(coalesce(is_compulsory,false)) as is_compulsory,
         min(option_group) filter(where option_group is not null) as option_group,
         min(position) as position
  from expected_raw
  group by class_id, subject_id
)
insert into public.class_subjects(class_id, subject_id, is_compulsory, option_group, position, is_active)
select class_id, subject_id, is_compulsory, option_group, position, true
from expected
on conflict (class_id, subject_id) do update
set is_compulsory=excluded.is_compulsory,
    option_group=excluded.option_group,
    position=excluded.position,
    is_active=true;
