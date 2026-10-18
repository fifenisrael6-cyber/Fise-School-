-- Fise School: toutes les classes (pas seulement les classes d'examen), pour les
-- sous-systèmes francophone et anglophone, enseignement général et technique.
-- L'élève choisit sa classe lui-même à l'inscription.
--
-- Une classe sans examen (6ème, Form 1, ...) a exam_id = null.
-- Les migrations précédentes ne sont pas modifiées.

alter table public.exam_levels
  alter column exam_id drop not null;

alter table public.exam_levels
  add column if not exists is_exam_class boolean not null default false,
  add column if not exists level_order integer not null default 0,
  add column if not exists curriculum_fr text,
  add column if not exists curriculum_en text;

update public.exam_levels set is_exam_class = true where exam_id is not null;

-- Programmes officiels (modifiables par l'administration si besoin) :
--   francophone : programme du ministère (MINESEC pour le secondaire)
--   anglophone  : programme du sous-système anglophone (GCE Board pour les examens)
update public.exam_levels set
  curriculum_fr = case subsystem
    when 'francophone' then 'Programme officiel du MINESEC (sous-système francophone)'
    else 'Programme du sous-système anglophone (GCE Board)'
  end,
  curriculum_en = case subsystem
    when 'francophone' then 'Official MINESEC curriculum (francophone sub-system)'
    else 'Anglophone sub-system curriculum (GCE Board)'
  end
where curriculum_fr is null or curriculum_en is null;

-- Nouvelles classes (sans examen). Les classes d'examen existantes sont conservées.
insert into public.exam_levels
  (code, subsystem, sector, level_name_fr, level_name_en, exam_id,
   verification_status, is_exam_class, level_order)
values
  -- Francophone général
  ('fr_general_sixieme',   'francophone', 'general',   'Sixième (6ème)',    'Sixième (6ème)',    null, 'verified', false, 1),
  ('fr_general_cinquieme', 'francophone', 'general',   'Cinquième (5ème)',  'Cinquième (5ème)',  null, 'verified', false, 2),
  ('fr_general_quatrieme', 'francophone', 'general',   'Quatrième (4ème)',  'Quatrième (4ème)',  null, 'verified', false, 3),
  ('fr_general_seconde',   'francophone', 'general',   'Seconde (2nde)',    'Seconde (2nde)',    null, 'verified', false, 5),
  -- Francophone technique
  ('fr_technical_sixieme',   'francophone', 'technical', 'Sixième technique',   'Technical Sixième',   null, 'pending_official_confirmation', false, 1),
  ('fr_technical_cinquieme', 'francophone', 'technical', 'Cinquième technique', 'Technical Cinquième', null, 'pending_official_confirmation', false, 2),
  ('fr_technical_quatrieme', 'francophone', 'technical', 'Quatrième technique', 'Technical Quatrième', null, 'pending_official_confirmation', false, 3),
  ('fr_technical_troisieme', 'francophone', 'technical', 'Troisième technique', 'Technical Troisième', null, 'pending_official_confirmation', false, 4),
  ('fr_technical_seconde',   'francophone', 'technical', 'Seconde technique',   'Technical Seconde',   null, 'pending_official_confirmation', false, 5),
  -- Anglophone général
  ('en_general_form_1',       'anglophone', 'general',   'Form 1',       'Form 1',       null, 'verified', false, 1),
  ('en_general_form_2',       'anglophone', 'general',   'Form 2',       'Form 2',       null, 'verified', false, 2),
  ('en_general_form_3',       'anglophone', 'general',   'Form 3',       'Form 3',       null, 'verified', false, 3),
  ('en_general_form_4',       'anglophone', 'general',   'Form 4',       'Form 4',       null, 'verified', false, 4),
  ('en_general_lower_sixth',  'anglophone', 'general',   'Lower Sixth',  'Lower Sixth',  null, 'verified', false, 6),
  -- Anglophone technique
  ('en_technical_form_1',      'anglophone', 'technical', 'Form 1',      'Form 1',      null, 'verified', false, 1),
  ('en_technical_form_2',      'anglophone', 'technical', 'Form 2',      'Form 2',      null, 'verified', false, 2),
  ('en_technical_form_3',      'anglophone', 'technical', 'Form 3',      'Form 3',      null, 'verified', false, 3),
  ('en_technical_form_4',      'anglophone', 'technical', 'Form 4',      'Form 4',      null, 'verified', false, 4),
  ('en_technical_lower_sixth', 'anglophone', 'technical', 'Lower Sixth', 'Lower Sixth', null, 'verified', false, 6)
on conflict (code) do update set
  level_name_fr = excluded.level_name_fr,
  level_name_en = excluded.level_name_en,
  verification_status = excluded.verification_status,
  is_exam_class = excluded.is_exam_class,
  level_order = excluded.level_order,
  updated_at = now();

-- Ordre d'affichage des classes d'examen déjà présentes.
update public.exam_levels set level_order = v.ord
from (values
  ('fr_general_troisieme', 4),
  ('fr_general_premiere', 6),
  ('fr_general_terminale', 7),
  ('fr_technical_cap', 4),
  ('fr_technical_premiere', 6),
  ('fr_technical_terminale', 7),
  ('fr_technical_brevet_technicien', 7),
  ('en_general_form_5', 5),
  ('en_general_upper_sixth', 7),
  ('en_technical_form_5', 5),
  ('en_technical_upper_sixth', 7)
) as v(code, ord)
where exam_levels.code = v.code;

-- Programmes pour les lignes qui viennent d'être insérées.
update public.exam_levels set
  curriculum_fr = case subsystem
    when 'francophone' then 'Programme officiel du MINESEC (sous-système francophone)'
    else 'Programme du sous-système anglophone (GCE Board)'
  end,
  curriculum_en = case subsystem
    when 'francophone' then 'Official MINESEC curriculum (francophone sub-system)'
    else 'Anglophone sub-system curriculum (GCE Board)'
  end
where curriculum_fr is null or curriculum_en is null;

-- Examens et classes officiels du général francophone : confirmés.
update public.exams set verification_status = 'verified'
where code in ('bepc', 'probatoire', 'baccalaureat');
update public.exam_levels set verification_status = 'verified'
where code in ('fr_general_troisieme', 'fr_general_premiere', 'fr_general_terminale');

create index if not exists exam_levels_order_idx
  on public.exam_levels (subsystem, sector, level_order);

-- Le profil n'exige un examen que si la classe en a un : la validation existante
-- (validate_profile_catalog_links) ne vérifie exam_id que lorsqu'il est renseigné,
-- donc une classe sans examen (exam_id null) est acceptée telle quelle.

-- L'inscription se fait avec le téléphone : l'e-mail (facultatif) est transmis dans
-- les métadonnées et repris dans le profil.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  requested_role text := metadata ->> 'role';
  requested_subsystem text := metadata ->> 'subsystem';
  requested_sector text := metadata ->> 'sector';
  profile_email text := coalesce(new.email, nullif(trim(metadata ->> 'email'), ''));
  uuid_pattern constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$';
begin
  insert into public.profiles (
    id, first_name, last_name, phone, email, role, preferred_language,
    subsystem, sector, exam_level_id, exam_id, series_id, specialty_id,
    class_name, exam_level_label, exam_label, track_label
  )
  values (
    new.id,
    coalesce(
      nullif(trim(metadata ->> 'first_name'), ''),
      nullif(split_part(coalesce(profile_email, ''), '@', 1), ''),
      'Utilisateur'
    ),
    coalesce(nullif(trim(metadata ->> 'last_name'), ''), 'Fise'),
    new.phone,
    profile_email,
    case when requested_role in ('student', 'teacher')
      then requested_role else 'student' end,
    case when metadata ->> 'preferred_language' in ('fr', 'en')
      then metadata ->> 'preferred_language' else 'fr' end,
    case when requested_subsystem in ('francophone', 'anglophone')
      then requested_subsystem::public.catalog_subsystem else null end,
    case when requested_sector in ('general', 'technical')
      then requested_sector::public.catalog_sector else null end,
    case when metadata ->> 'exam_level_id' ~ uuid_pattern
      then (metadata ->> 'exam_level_id')::uuid else null end,
    case when metadata ->> 'exam_id' ~ uuid_pattern
      then (metadata ->> 'exam_id')::uuid else null end,
    case when metadata ->> 'series_id' ~ uuid_pattern
      then (metadata ->> 'series_id')::uuid else null end,
    case when metadata ->> 'specialty_id' ~ uuid_pattern
      then (metadata ->> 'specialty_id')::uuid else null end,
    nullif(trim(metadata ->> 'class_name'), ''),
    nullif(trim(metadata ->> 'exam_level'), ''),
    nullif(trim(metadata ->> 'exam'), ''),
    nullif(trim(metadata ->> 'track'), '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;
