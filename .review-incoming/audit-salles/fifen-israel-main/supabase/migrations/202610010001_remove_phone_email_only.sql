-- Fise School : connexion et inscription par e-mail uniquement.
-- Supprime toute trace du numéro de téléphone dans la base.

-- 1. Le déclencheur de création de profil n'utilise plus le téléphone.
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
    id, first_name, last_name, email, role, preferred_language,
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

-- 2. Les profils existants sans e-mail reprennent l'e-mail du compte.
update public.profiles p
set email = u.email
from auth.users u
where u.id = p.id
  and (p.email is null or trim(p.email) = '')
  and u.email is not null;

-- 3. Un e-mail ne peut servir qu'à un seul profil.
do $$
begin
  create unique index if not exists profiles_email_unique_idx
    on public.profiles (lower(email))
    where email is not null;
exception when unique_violation then
  raise notice 'Des e-mails en double existent dans profiles : index unique non créé.';
end;
$$;

-- 4. Suppression de la colonne téléphone.
alter table public.profiles drop column if exists phone;
