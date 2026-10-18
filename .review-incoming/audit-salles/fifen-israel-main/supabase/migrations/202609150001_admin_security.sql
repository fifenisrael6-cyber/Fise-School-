-- Fise School
-- Sécurité renforcée du compte administrateur.

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- L'administrateur peut lire les profils.
drop policy if exists "admins_can_read_profiles" on public.profiles;

create policy "admins_can_read_profiles"
on public.profiles
for select
to authenticated
using (
  id = auth.uid()
  or public.is_admin()
);

-- Un utilisateur peut uniquement lire son propre profil.
drop policy if exists "users_can_read_own_profile" on public.profiles;

create policy "users_can_read_own_profile"
on public.profiles
for select
to authenticated
using (
  id = auth.uid()
);

-- L'utilisateur ne peut jamais modifier son propre rôle.
create or replace function public.prevent_self_admin_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() = old.id
     and new.role is distinct from old.role
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
  then
    raise exception 'Users cannot change their own role';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_prevent_self_admin_escalation
on public.profiles;

create trigger profiles_prevent_self_admin_escalation
before update on public.profiles
for each row
execute function public.prevent_self_admin_escalation();