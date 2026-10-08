-- Complete signup placement: distinguish the student's class, series/specialty and language option.
-- MINESEC curriculum reference: https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone

alter table public.profiles add column if not exists language_option text;
alter table public.school_classes add column if not exists language_option text;

-- Series are a second-cycle choice; 3e takes a language option, not a baccalaureate series.
update public.exam_level_series els
set active = false
from public.exam_levels el
where el.id = els.exam_level_id
  and el.sector = 'general'
  and el.level_order < 5
  and els.active;

-- Ensure official francophone series are linked to Seconde, Première and Terminale.
insert into public.exam_level_series (exam_level_id, series_id, verification_status, active)
select el.id, s.id, 'verified', true
from public.exam_levels el
join public.series s on s.code in ('a1','a2','a3','a4','a5','ac','c','d','ti','bil')
where el.subsystem = 'francophone'
  and el.sector = 'general'
  and el.level_order >= 5
on conflict (exam_level_id, series_id) do update
set active = true, verification_status = 'verified';

-- Language options used in 3e and in language-based second-cycle series.
with language_options(code, label_fr, label_en) as (
  values
    ('allemand', 'Allemand', 'German'),
    ('espagnol', 'Espagnol', 'Spanish'),
    ('arabe', 'Arabe', 'Arabic'),
    ('italien', 'Italien', 'Italian'),
    ('chinois', 'Chinois', 'Chinese')
)
insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id, exam_level_id, series_id, specialty_id, language_option)
select
  el.code || '_lang_' || lo.code,
  el.level_name_fr || ' — ' || lo.label_fr,
  el.subsystem, el.sector, ay.id, el.id, null, null, lo.code
from public.exam_levels el
join public.academic_years ay on ay.is_current
cross join language_options lo
where el.code = 'fr_general_troisieme'
  and el.active
on conflict (name, academic_year_id) do update
set display_name = excluded.display_name,
    language_option = excluded.language_option,
    is_active = true,
    updated_at = now();

-- A2/A4: language II. A5: language II + language III (ordered pair).
with language_options(code, label_fr) as (
  values
    ('allemand', 'Allemand'),
    ('espagnol', 'Espagnol'),
    ('arabe', 'Arabe'),
    ('italien', 'Italien'),
    ('chinois', 'Chinois')
),
second_cycle as (
  select el.*, ay.id as year_id, s.id as series_id, s.code as series_code, s.name_fr as series_name
  from public.exam_levels el
  join public.academic_years ay on ay.is_current
  join public.exam_level_series els on els.exam_level_id = el.id and els.active
  join public.series s on s.id = els.series_id and s.active
  where el.subsystem = 'francophone'
    and el.sector = 'general'
    and el.level_order >= 5
    and el.active
)
insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id, exam_level_id, series_id, specialty_id, language_option)
select
  sc.code || '_' || sc.series_code || '_lang_' || lo.code,
  sc.level_name_fr || ' — ' || sc.series_name || ' — ' || lo.label_fr,
  sc.subsystem, sc.sector, sc.year_id, sc.id, sc.series_id, null, lo.code
from second_cycle sc
cross join language_options lo
where sc.series_code in ('a2','a4')
on conflict (name, academic_year_id) do update
set display_name = excluded.display_name,
    series_id = excluded.series_id,
    language_option = excluded.language_option,
    is_active = true,
    updated_at = now();

with language_options(code, label_fr) as (
  values
    ('allemand', 'Allemand'),
    ('espagnol', 'Espagnol'),
    ('arabe', 'Arabe'),
    ('italien', 'Italien'),
    ('chinois', 'Chinois')
),
second_cycle as (
  select el.*, ay.id as year_id, s.id as series_id, s.code as series_code, s.name_fr as series_name
  from public.exam_levels el
  join public.academic_years ay on ay.is_current
  join public.exam_level_series els on els.exam_level_id = el.id and els.active
  join public.series s on s.id = els.series_id and s.active
  where el.subsystem = 'francophone'
    and el.sector = 'general'
    and el.level_order >= 5
    and el.active
)
insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id, exam_level_id, series_id, specialty_id, language_option)
select
  sc.code || '_a5_' || lo2.code || '_' || lo3.code,
  sc.level_name_fr || ' — A5 — ' || lo2.label_fr || ' + ' || lo3.label_fr,
  sc.subsystem, sc.sector, sc.year_id, sc.id, sc.series_id, null,
  lo2.code || '_' || lo3.code
from second_cycle sc
cross join language_options lo2
cross join language_options lo3
where sc.series_code = 'a5'
  and lo2.code <> lo3.code
on conflict (name, academic_year_id) do update
set display_name = excluded.display_name,
    series_id = excluded.series_id,
    language_option = excluded.language_option,
    is_active = true,
    updated_at = now();

-- One dedicated room per remaining francophone general series and English Arts/Science group.
insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id, exam_level_id, series_id, specialty_id)
select
  el.code || '_' || s.code,
  el.level_name_fr || ' — ' || s.name_fr,
  el.subsystem, el.sector, ay.id, el.id, s.id, null
from public.exam_levels el
join public.academic_years ay on ay.is_current
join public.exam_level_series els on els.exam_level_id = el.id and els.active
join public.series s on s.id = els.series_id and s.active
where el.active
  and el.sector = 'general'
  and el.level_order >= 5
  and (
    (el.subsystem = 'francophone' and s.code not in ('a2','a4','a5'))
    or el.subsystem = 'anglophone'
  )
on conflict (name, academic_year_id) do update
set display_name = excluded.display_name,
    series_id = excluded.series_id,
    is_active = true,
    updated_at = now();

-- Keep option metadata in sync with the exact room chosen during signup.
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
begin
  if requested_role <> 'student' then
    return new;
  end if;

  if metadata ->> 'class_id' ~ '^[0-9a-fA-F-]{36}$' then
    requested_class_id := (metadata ->> 'class_id')::uuid;
  end if;

  if requested_class_id is null then
    raise exception 'A student must select a classroom matching the chosen class and option';
  end if;

  if not exists (
    select 1 from public.school_classes c
    where c.id = requested_class_id
      and c.is_active
      and c.language_option is not distinct from requested_option
      and c.exam_level_id is not distinct from nullif(metadata ->> 'exam_level_id','')::uuid
      and c.series_id is not distinct from nullif(metadata ->> 'series_id','')::uuid
      and c.specialty_id is not distinct from nullif(metadata ->> 'specialty_id','')::uuid
  ) then
    raise exception 'Selected classroom does not match the chosen language option';
  end if;

  update public.profiles
  set language_option = requested_option
  where id = new.id;

  return new;
end;
$$;

drop trigger if exists zz_sync_signup_language_option on auth.users;
create trigger zz_sync_signup_language_option
after insert on auth.users
for each row execute function public.sync_signup_language_option();
