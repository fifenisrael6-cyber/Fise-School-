-- Unifier tous les codes d'invitation de groupe sous le préfixe FISE.
-- Les anciens codes GPR-/GRP- restent acceptés à la saisie pendant la transition.
create or replace function public.generate_group_invite_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_code text;
begin
  loop
    v_code := 'FISE-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (
      select 1 from public.message_groups where upper(invite_code) = v_code
    );
  end loop;
  return v_code;
end;
$$;

revoke all on function public.generate_group_invite_code() from public;

-- Normaliser les codes déjà enregistrés sans changer les six caractères uniques.
update public.message_groups
set invite_code = 'FISE-' || upper(regexp_replace(invite_code, '^(FISE|GPR|GRP)[ -]*', '', 'i'))
where invite_code ~* '^(FISE|GPR|GRP)[ -]*[A-F0-9]{6}$'
  and invite_code !~* '^FISE-[A-F0-9]{6}$';

create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_suffix text;
begin
  select role into v_role
  from public.profiles
  where id = auth.uid();

  if v_role is null then
    raise exception 'Profile not found';
  end if;

  -- Accepte FISE-XXXXXX, FISE XXXXXX et les anciens GPR/GRP-XXXXXX.
  v_suffix := upper(regexp_replace(trim(coalesce(p_code, '')), '^(FISE|GPR|GRP)[ -]*', '', 'i'));
  v_suffix := regexp_replace(v_suffix, '[^A-Z0-9]', '', 'g');

  if length(v_suffix) <> 6 then
    raise exception 'Invalid invitation code';
  end if;

  select * into v_group
  from public.message_groups
  where upper(regexp_replace(invite_code, '^(FISE|GPR|GRP)[ -]*', '', 'i')) = v_suffix
  limit 1;

  if not found then
    raise exception 'Invalid invitation code';
  end if;

  insert into public.message_group_members (group_id, user_id, role)
  values (
    v_group.id,
    auth.uid(),
    case when v_role = 'student' then 'student' else 'teacher' end
  )
  on conflict (group_id, user_id) do nothing;

  return v_group.id;
end;
$$;

revoke all on function public.join_message_group(text) from public;
grant execute on function public.join_message_group(text) to authenticated;
