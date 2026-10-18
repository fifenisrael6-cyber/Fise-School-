-- Désigne le compte administrateur unique de Fise School.

update public.profiles
set
  role = 'admin',
  updated_at = now()
where id = '108dd782-9707-4fd7-b104-0103a0718faa'::uuid;

-- The administrator may be created after the schema is deployed.  Do not
-- abort a fresh installation merely because this account does not yet exist.
