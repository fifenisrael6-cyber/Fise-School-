-- Restore second-cycle francophone series links, create missing language-option rooms,
-- and ensure students see the curriculum for their exact series rather than every
-- optional subject listed for the Terminale level.
begin;

-- Re-activate only the known francophone general series for second-cycle levels.
insert into public.exam_level_series (exam_level_id, series_id, verification_status, active)
select el.id, s.id, 'verified', true
from public.exam_levels el
join public.series s on lower(s.code) in ('a1','a2','a3','a4','a5','ac','c','d','ti','bil')
where el.subsystem = 'francophone'
  and el.sector = 'general'
  and el.level_order >= 5
  and el.active
  and s.active
on conflict (exam_level_id, series_id) do update
set active = true, verification_status = 'verified';

-- The student-facing Cours page reads class_subjects, so narrow second-cycle
-- general rooms to common core + the subjects attached to the selected series.
with expected as (
  select c.id class_id, s.id subject_id,
         coalesce(lsc.is_compulsory, true) is_compulsory,
         lsc.option_group,
         coalesce(lsc.position, 0) position
  from public.school_classes c
  join public.exam_levels el on el.id = c.exam_level_id
  join public.subjects s
    on s.subsystem = c.subsystem and s.sector = c.sector and s.is_active
  left join public.level_subject_catalog lsc
    on lsc.level_code = el.code and lsc.subject_code = s.code
  left join public.series ser on ser.id = c.series_id
  left join public.series_subject_catalog ssc
    on ssc.series_code = ser.code and ssc.subject_code = s.code
  where c.is_active
    and c.subsystem = 'francophone'
    and c.sector = 'general'
    and el.level_order >= 5
    and c.series_id is not null
    and (
      -- Common subjects retained for every general series.
      s.code in ('francais','anglais','education_civique','eps')
      -- Series-specific subjects come from the explicit catalogue.
      or ssc.subject_code is not null
      -- Language options are retained only when chosen for this classroom.
      or (
        c.language_option is not null
        and s.code = any(regexp_split_to_array(c.language_option, '_'))
        and s.code in ('allemand','espagnol','arabe','italien','chinois')
      )
    )
), dedup as (
  select class_id, subject_id,
         bool_or(is_compulsory) is_compulsory,
         min(option_group) filter (where option_group is not null) option_group,
         min(position) position
  from expected
  group by class_id, subject_id
)
update public.class_subjects cs
set is_active = false
from public.school_classes c
join public.exam_levels el on el.id = c.exam_level_id
where cs.class_id = c.id
  and c.is_active
  and c.subsystem = 'francophone'
  and c.sector = 'general'
  and el.level_order >= 5
  and c.series_id is not null
  and cs.is_active
  and not exists (
    select 1 from dedup e
    where e.class_id = cs.class_id and e.subject_id = cs.subject_id
  );

with expected as (
  select c.id class_id, s.id subject_id,
         coalesce(lsc.is_compulsory, true) is_compulsory,
         lsc.option_group,
         coalesce(lsc.position, 0) position
  from public.school_classes c
  join public.exam_levels el on el.id = c.exam_level_id
  join public.subjects s
    on s.subsystem = c.subsystem and s.sector = c.sector and s.is_active
  left join public.level_subject_catalog lsc
    on lsc.level_code = el.code and lsc.subject_code = s.code
  left join public.series ser on ser.id = c.series_id
  left join public.series_subject_catalog ssc
    on ssc.series_code = ser.code and ssc.subject_code = s.code
  where c.is_active
    and c.subsystem = 'francophone'
    and c.sector = 'general'
    and el.level_order >= 5
    and c.series_id is not null
    and (
      s.code in ('francais','anglais','education_civique','eps')
      or ssc.subject_code is not null
      or (
        c.language_option is not null
        and s.code = any(regexp_split_to_array(c.language_option, '_'))
        and s.code in ('allemand','espagnol','arabe','italien','chinois')
      )
    )
), dedup as (
  select class_id, subject_id,
         bool_or(is_compulsory) is_compulsory,
         min(option_group) filter (where option_group is not null) option_group,
         min(position) position
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

-- AuthPage sends level/series/specialty/language metadata. Resolve the exact
-- classroom server-side so registration does not fail because class_id was omitted.
create or replace function public.sync_signup_language_option()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  requested_role text := coalesce(metadata ->> 'role', 'student');
  requested_class_id uuid;
  requested_option text := nullif(trim(metadata ->> 'language_option'), '');
  selected_class public.school_classes%rowtype;
begin
  if requested_role <> 'student' then
    return new;
  end if;

  if coalesce(metadata ->> 'class_id', '') ~ '^[0-9a-fA-F-]{36}$' then
    requested_class_id := (metadata ->> 'class_id')::uuid;
  end if;

  if requested_class_id is not null then
    select c.* into selected_class
    from public.school_classes c
    where c.id = requested_class_id
      and c.is_active
      and c.language_option is not distinct from requested_option
      and c.exam_level_id::text is not distinct from nullif(metadata ->> 'exam_level_id', '')
      and c.series_id::text is not distinct from nullif(metadata ->> 'series_id', '')
      and c.specialty_id::text is not distinct from nullif(metadata ->> 'specialty_id', '')
      and c.subsystem::text is not distinct from nullif(metadata ->> 'subsystem', '')
      and c.sector::text is not distinct from nullif(metadata ->> 'sector', '');
  else
    select c.* into selected_class
    from public.school_classes c
    where c.is_active
      and c.exam_level_id::text is not distinct from nullif(metadata ->> 'exam_level_id', '')
      and c.series_id::text is not distinct from nullif(metadata ->> 'series_id', '')
      and c.specialty_id::text is not distinct from nullif(metadata ->> 'specialty_id', '')
      and c.subsystem::text is not distinct from nullif(metadata ->> 'subsystem', '')
      and c.sector::text is not distinct from nullif(metadata ->> 'sector', '')
      and c.language_option is not distinct from requested_option
    order by c.display_name
    limit 1;
  end if;

  if selected_class.id is null then
    raise exception 'Aucune salle ne correspond au niveau, à la série/filière et à la langue sélectionnés. Vérifier le catalogue des classes.';
  end if;

  update public.profiles
  set subsystem = selected_class.subsystem,
      sector = selected_class.sector,
      exam_level_id = selected_class.exam_level_id,
      series_id = selected_class.series_id,
      specialty_id = selected_class.specialty_id,
      class_name = selected_class.display_name,
      exam_level_label = nullif(metadata ->> 'exam_level', ''),
      exam_label = nullif(metadata ->> 'exam', ''),
      track_label = nullif(metadata ->> 'track', ''),
      language_option = requested_option,
      updated_at = now()
  where id = new.id;

  insert into public.class_students (class_id, student_id, is_active)
  select selected_class.id, new.id, true
  where not exists (
    select 1 from public.class_students cs
    where cs.class_id = selected_class.id
      and cs.student_id = new.id
      and cs.is_active
  );

  return new;
end;
$$;

drop trigger if exists zz_sync_signup_language_option on auth.users;
create trigger zz_sync_signup_language_option
after insert on auth.users
for each row execute function public.sync_signup_language_option();

commit;
