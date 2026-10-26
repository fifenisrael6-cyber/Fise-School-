-- Fise School: normalize classroom options to the four MINESEC pathways.
-- Non-destructive: preserve historic rooms and occupied classrooms; retire unused duplicates.
-- Official references:
-- https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone
-- https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone

-- 1) The francophone general second cycle must not offer technical-only or duplicate series.
update public.exam_level_series els
set active = false
from public.exam_levels el, public.series s
where els.exam_level_id = el.id
  and els.series_id = s.id
  and el.subsystem = 'francophone'
  and el.sector = 'general'
  and el.active
  and s.code in ('abi', 'e', 'sh')
  and els.active;

-- 2) Add the MINESEC anglophone GCE Advanced Level series as distinct catalog
-- codes, because A1-A5 already mean different series in the francophone subsystem.
insert into public.series (code, name_fr, name_en, verification_status, source_url, active)
values
  ('en_a1', 'A1 — Français, littérature et histoire', 'A1 — French, Literature and History', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true),
  ('en_a2', 'A2 — Géographie, économie et histoire', 'A2 — Geography, Economics and History', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true),
  ('en_a3', 'A3 — Littérature, histoire et économie', 'A3 — Literature, History and Economics', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true),
  ('en_a4', 'A4 — Géographie, économie et mathématiques', 'A4 — Geography, Economics and Mathematics', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true),
  ('en_a5', 'A5 — Littérature, philosophie et mathématiques', 'A5 — Literature, Philosophy and Mathematics', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true),
  ('en_a6', 'A6 — Littérature, français et langue étrangère', 'A6 — Literature, French and one Foreign Language', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true),
  ('en_a7', 'A7 — Littérature, cinématographie et informatique', 'A7 — Literature, Cinematography and Computer Science', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true),
  ('en_a8', 'A8 — Arts, artisanat et cultures nationales', 'A8 — Arts and Craft and National Language and Culture', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true),
  ('en_s1', 'S1 — Chimie, physique et mathématiques', 'S1 — Chemistry, Physics and Mathematics', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true),
  ('en_s2', 'S2 — Chimie, physique et biologie', 'S2 — Chemistry, Physics and Biology', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true),
  ('en_s3', 'S3 — Biologie, chimie et physique', 'S3 — Biology, Chemistry and Physics', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true),
  ('en_s4', 'S4 — Biologie, chimie et géologie/géographie', 'S4 — Biology, Chemistry and Geology/Geography', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-anglophone', true)
on conflict (code) do update
set name_fr = excluded.name_fr,
    name_en = excluded.name_en,
    verification_status = 'verified',
    source_url = excluded.source_url,
    active = true,
    updated_at = now();

-- Retire les anciennes catégories trop larges Arts/Science du niveau terminal
-- anglophone, puis associe les 12 séries MINESEC à Upper Sixth.
update public.exam_level_series els
set active = false
from public.exam_levels el, public.series s
where els.exam_level_id = el.id
  and els.series_id = s.id
  and el.code = 'en_general_upper_sixth'
  and s.code in ('gce_arts', 'gce_science')
  and els.active;

insert into public.exam_level_series (exam_level_id, series_id, verification_status, active)
select el.id, s.id, 'verified', true
from public.exam_levels el
cross join public.series s
where el.code = 'en_general_upper_sixth'
  and el.subsystem = 'anglophone'
  and el.sector = 'general'
  and el.active
  and s.code in ('en_a1','en_a2','en_a3','en_a4','en_a5','en_a6','en_a7','en_a8','en_s1','en_s2','en_s3','en_s4')
on conflict (exam_level_id, series_id) do update
set active = true, verification_status = 'verified';

-- Create one separate Upper Sixth classroom per official series for the current year.
insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id, exam_level_id, series_id, specialty_id, language_option, is_active)
select
  el.code || '_' || s.code,
  el.level_name_en || ' — ' || s.name_en,
  el.subsystem, el.sector, ay.id, el.id, s.id, null, null, true
from public.exam_levels el
join public.academic_years ay on ay.is_current
join public.exam_level_series els on els.exam_level_id = el.id and els.active
join public.series s on s.id = els.series_id and s.active
where el.code = 'en_general_upper_sixth'
  and s.code in ('en_a1','en_a2','en_a3','en_a4','en_a5','en_a6','en_a7','en_a8','en_s1','en_s2','en_s3','en_s4')
on conflict (name, academic_year_id) do update
set display_name = excluded.display_name,
    series_id = excluded.series_id,
    is_active = true,
    updated_at = now();

-- 3) Retire duplicate technical rooms whose display language belongs to the
-- other subsystem. Keep the localized canonical room and preserve any room
-- that still has students or has been selected by a teacher.
update public.school_classes c
set is_active = false, updated_at = now()
from public.academic_years ay
where ay.id = c.academic_year_id
  and ay.is_current
  and c.is_active
  and c.sector = 'technical'
  and c.specialty_id is not null
  and not exists (
    select 1 from public.class_students cs
    where cs.class_id = c.id and cs.is_active
  )
  and not exists (
    select 1 from public.teacher_followed_classes tfc
    where tfc.class_id = c.id
  )
  and exists (
    select 1
    from public.school_classes d
    where d.id <> c.id
      and d.academic_year_id = c.academic_year_id
      and d.exam_level_id = c.exam_level_id
      and d.subsystem = c.subsystem
      and d.sector = c.sector
      and d.specialty_id = c.specialty_id
      and d.series_id is not distinct from c.series_id
      and d.language_option is not distinct from c.language_option
      and d.is_active
      and (
        (c.subsystem = 'anglophone'
          and position('_specialty_' in d.name) > 0
          and position('_specialty_' in c.name) = 0)
        or
        (c.subsystem = 'francophone'
          and position('_specialty_' in d.name) = 0
          and position('_specialty_' in c.name) > 0)
      )
  );

-- Retire old broad GCE Arts/Science terminal rooms and unused generic final rooms.
-- An occupied legacy francophone Terminale is intentionally preserved until its
-- student has an explicitly selected series; the room is hidden from future choices below.
update public.school_classes c
set is_active = false, updated_at = now()
from public.academic_years ay
where ay.id = c.academic_year_id
  and ay.is_current
  and c.is_active
  and (
    c.series_id in (select id from public.series where code in ('gce_arts','gce_science'))
    or c.name in ('en_general_upper_sixth', 'en_technical_upper_sixth', 'fr_technical_terminale')
  )
  and not exists (select 1 from public.class_students cs where cs.class_id = c.id and cs.is_active)
  and not exists (select 1 from public.teacher_followed_classes tfc where tfc.class_id = c.id);

-- Retire unused generic francophone general Terminale only if no active student
-- remains attached to it.
update public.school_classes c
set is_active = false, updated_at = now()
from public.academic_years ay
where ay.id = c.academic_year_id
  and ay.is_current
  and c.name = 'fr_general_terminale'
  and c.is_active
  and not exists (select 1 from public.class_students cs where cs.class_id = c.id and cs.is_active)
  and not exists (select 1 from public.teacher_followed_classes tfc where tfc.class_id = c.id);

-- 4) The server is the source of truth for room-change choices. A student must
-- have a known subsystem AND sector; never fall back to all four pathways.
-- Combined language-option rooms (e.g. A5 — German + Spanish) remain in the
-- registration catalog because A5 officially requires two modern languages,
-- but are not offered as separate classrooms in the room-change screen.
create or replace function public.list_student_available_classes()
returns table (
  class_id uuid,
  class_name text,
  subsystem text,
  sector text,
  exam_level_id uuid,
  exam_id uuid,
  series_id uuid,
  specialty_id uuid,
  level_order integer,
  language_option text,
  academic_year_id uuid,
  exam_level_label text,
  exam_label text,
  track_label text,
  relation text,
  recommended boolean
)
language plpgsql
stable
security definer
set search_path = public
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
  if v_user_id is null then
    raise exception 'Authentication is required';
  end if;

  select * into v_profile from public.profiles
  where id = v_user_id and role = 'student';
  if not found then
    raise exception 'Only student accounts can change classroom';
  end if;

  select sc.* into v_current
  from public.class_students cs
  join public.school_classes sc on sc.id = cs.class_id
  join public.academic_years ay on ay.id = sc.academic_year_id
  where cs.student_id = v_user_id
    and cs.is_active
    and sc.is_active
    and ay.is_current
  order by cs.joined_at desc
  limit 1;

  if v_current.id is not null then
    select el.level_order into v_current_order
    from public.exam_levels el where el.id = v_current.exam_level_id;
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

  if v_subsystem not in ('francophone', 'anglophone')
     or v_sector not in ('general', 'technical') then
    raise exception 'Student subsystem and sector must be set before changing classroom';
  end if;

  return query
  select dest.id, dest.display_name, dest.subsystem::text, dest.sector::text,
    dest.exam_level_id, level.exam_id, dest.series_id, dest.specialty_id,
    level.level_order, dest.language_option, dest.academic_year_id,
    case when v_profile.preferred_language = 'en' then level.level_name_en else level.level_name_fr end,
    case when v_profile.preferred_language = 'en' then exam.name_en else exam.name_fr end,
    case when v_profile.preferred_language = 'en'
      then coalesce(series.name_en, specialty.name_en)
      else coalesce(series.name_fr, specialty.name_fr) end,
    case
      when level.level_order = v_current_order + 1 then 'next'
      when level.level_order = v_current_order then 'same'
      when level.level_order < v_current_order then 'previous'
      else 'other'
    end,
    (v_current_order is not null
      and level.level_order = v_current_order + 1
      and (v_series is null or dest.series_id = v_series)
      and (v_specialty is null or dest.specialty_id = v_specialty))
  from public.school_classes dest
  join public.academic_years ay on ay.id = dest.academic_year_id
  join public.exam_levels level on level.id = dest.exam_level_id and level.active
  left join public.exams exam on exam.id = level.exam_id
  left join public.series series on series.id = dest.series_id
  left join public.specialties specialty on specialty.id = dest.specialty_id
  where dest.is_active
    and ay.is_current
    and dest.academic_year_id = v_year
    and dest.id is distinct from v_current.id
    and dest.subsystem::text = v_subsystem
    and dest.sector::text = v_sector
    and position('_' in coalesce(dest.language_option, '')) = 0
    and exists (
      select 1 from public.teacher_followed_classes tfc
      where tfc.class_id = dest.id
    )
    and not (
      dest.series_id is null and dest.specialty_id is null
      and exists (
        select 1 from public.school_classes specific
        where specific.is_active
          and specific.id <> dest.id
          and specific.academic_year_id = dest.academic_year_id
          and specific.exam_level_id = dest.exam_level_id
          and specific.subsystem = dest.subsystem
          and specific.sector = dest.sector
          and (specific.series_id is not null or specific.specialty_id is not null)
      )
    )
  order by 16 desc, level.level_order, dest.display_name;
end;
$function$;

revoke all on function public.list_student_available_classes() from public, anon;
grant execute on function public.list_student_available_classes() to authenticated;
notify pgrst, 'reload schema';
