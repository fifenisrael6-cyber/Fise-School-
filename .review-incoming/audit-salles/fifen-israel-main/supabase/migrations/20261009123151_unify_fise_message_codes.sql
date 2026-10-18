-- Fise School: unifier le format des codes de groupe et d'accès enseignant.
-- Les codes existants conservent leur suffixe; seul le préfixe change.
update public.message_groups
set invite_code = 'FISE-' || substring(invite_code from 5)
where invite_code like 'GRP-%';

-- Pour les groupes liés à une classe, le code enseignant privé utilise le même suffixe.
update public.teacher_access_codes tac
set code = substring(g.invite_code from 6),
    updated_at = now()
from public.message_groups g
where g.owner_id = tac.teacher_id
  and g.class_id is not null
  and tac.class_id = g.class_id::text
  and g.invite_code like 'FISE-%';

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
    exit when not exists (select 1 from public.message_groups where invite_code = v_code);
  end loop;
  return v_code;
end;
$$;

create or replace function public.sync_group_code_to_teacher_access(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.message_groups%rowtype;
  v_suffix text;
begin
  select * into v_group
  from public.message_groups
  where id = p_group_id and owner_id = auth.uid();

  if not found or v_group.class_id is null then
    return;
  end if;

  v_suffix := substring(v_group.invite_code from 6);

  insert into public.teacher_access_codes
    (id, teacher_id, code, class_id, created_at, updated_at, is_active)
  values
    (v_group.owner_id::text || '_' || v_group.class_id::text || '_' || extract(epoch from now())::bigint::text,
     v_group.owner_id, v_suffix, v_group.class_id::text, now(), now(), true)
  on conflict (teacher_id, class_id)
  do update set code = excluded.code, updated_at = now(), is_active = true;
end;
$$;

revoke all on function public.sync_group_code_to_teacher_access(uuid) from public;

create or replace function public.create_message_group(p_name text, p_class_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role in ('teacher', 'admin')) then
    raise exception 'Only a teacher can create a group';
  end if;

  if p_class_id is not null and not public.teacher_can_manage_class(p_class_id, auth.uid()) then
    raise exception 'Teacher is not assigned to this class';
  end if;

  insert into public.message_groups (class_id, name, owner_id, invite_code)
  values (p_class_id, trim(p_name), auth.uid(), public.generate_group_invite_code())
  returning id into v_id;

  insert into public.message_group_members (group_id, user_id, role)
  values (v_id, auth.uid(), 'teacher');

  perform public.sync_group_code_to_teacher_access(v_id);
  return v_id;
end;
$$;

create or replace function public.regenerate_message_group_code(p_group_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if not exists (
    select 1 from public.message_groups where id = p_group_id and owner_id = auth.uid()
  ) then
    raise exception 'Only the group owner can change the invitation code';
  end if;

  v_code := public.generate_group_invite_code();
  update public.message_groups set invite_code = v_code where id = p_group_id;
  perform public.sync_group_code_to_teacher_access(p_group_id);
  return v_code;
end;
$$;

create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_code text;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null then
    raise exception 'Profile not found';
  end if;

  v_code := upper(trim(p_code));
  if v_code like 'GRP-%' then
    v_code := 'FISE-' || substring(v_code from 5);
  elsif v_code not like 'FISE-%' then
    v_code := 'FISE-' || regexp_replace(v_code, '^FISE', '');
  end if;

  select * into v_group
  from public.message_groups
  where invite_code = v_code;

  if not found then
    raise exception 'Invalid invitation code';
  end if;

  insert into public.message_group_members (group_id, user_id, role)
  values (v_group.id, auth.uid(), case when v_role = 'student' then 'student' else 'teacher' end)
  on conflict (group_id, user_id) do nothing;

  return v_group.id;
end;
$$;
