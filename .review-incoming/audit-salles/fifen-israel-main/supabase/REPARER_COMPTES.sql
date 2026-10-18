-- ============================================================
-- Fise School : réparer les comptes depuis Supabase
-- À coller dans Supabase > SQL Editor, puis cliquer sur "Run".
-- Exécutez UN SEUL bloc à la fois (A, B ou C).
-- ============================================================


-- ============================================================
-- BLOC A : faire fonctionner le compte ADMINISTRATEUR
-- Remplacez l'e-mail ci-dessous par celui de votre compte admin
-- (le compte doit déjà exister dans Authentication > Users).
-- ============================================================
do $$
declare
  v_email text := lower('israelfifen544@gmail.com');   -- << CHANGER ICI
  v_id uuid;
begin
  select id into v_id from auth.users where lower(email) = v_email limit 1;
  if v_id is null then
    raise exception 'Aucun compte "%" dans Authentication > Users. Créez-le d''abord.', v_email;
  end if;

  alter table public.profiles disable trigger profiles_protect_role;

  -- Un seul administrateur est autorisé : les autres repassent élèves.
  update public.profiles set role = 'student'
  where role = 'admin' and id <> v_id;

  -- Le profil existe-t-il ? Sinon on le crée.
  insert into public.profiles (id, first_name, last_name, email, role, preferred_language)
  select v_id, 'Admin', 'Fise School', v_email, 'admin', 'fr'
  where not exists (select 1 from public.profiles where id = v_id);

  update public.profiles set role = 'admin', email = v_email where id = v_id;

  alter table public.profiles enable trigger profiles_protect_role;

  -- E-mail confirmé + rôle admin dans le jeton de connexion.
  update auth.users
  set email_confirmed_at = coalesce(email_confirmed_at, now()),
      raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
  where id = v_id;
end $$;


-- ============================================================
-- BLOC B : confirmer TOUS les e-mails déjà inscrits
-- (utile si "Confirm email" était activé pendant vos tests)
-- ============================================================
-- update auth.users set email_confirmed_at = now() where email_confirmed_at is null;


-- ============================================================
-- BLOC C : changer le rôle d'un compte de test (élève <-> enseignant)
-- Remplacez l'e-mail et le rôle ('student' ou 'teacher').
-- ============================================================
-- do $$
-- begin
--   alter table public.profiles disable trigger profiles_protect_role;
--   update public.profiles
--   set role = 'teacher'                                   -- << 'student' ou 'teacher'
--   where lower(email) = lower('fifenisrael561@gmail.com'); -- << CHANGER ICI
--   alter table public.profiles enable trigger profiles_protect_role;
-- end $$;
