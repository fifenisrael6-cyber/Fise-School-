-- Code unique par enseignant pour tous ses groupes et salles.
-- Migration additive : les anciennes tables/codes restent en place pour compatibilité.

create table if not exists public.teacher_group_access_codes (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null unique references auth.users(id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_active boolean not null default true,
  constraint teacher_group_access_codes_format
    check (code ~ '^FISE-[A-Z0-9]{6}$')
);

create index if not exists teacher_group_access_codes_code_idx
  on public.teacher_group_access_codes (upper(code));

alter table public.teacher_group_access_codes enable row level security;

drop policy if exists teacher_reads_own_group_access_code on public.teacher_group_access_codes;
create policy teacher_reads_own_group_access_code
  on public.teacher_group_access_codes for select to authenticated
  using (teacher_id = auth.uid());

-- L'enseignant choisit son code une seule fois. Les appels suivants renvoient
-- le code existant; un changement explicite se fait avec set_teacher_group_access_code.
create or replace function public.get_or_create_teacher_group_access_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_code text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = v_user;
  if v_role <> 'teacher' then raise exception 'Only teachers can manage this code'; end if;

  select code into v_code
  from public.teacher_group_access_codes
  where teacher_id = v_user and is_active = true;

  if v_code is not null then return v_code; end if;

  loop
    v_code := 'FISE-' || upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 6));
    exit when not exists (
      select 1 from public.teacher_group_access_codes where upper(code) = v_code
    );
  end loop;

  insert into public.teacher_group_access_codes (teacher_id, code)
  values (v_user, v_code)
  on conflict (teacher_id) do update
    set code = excluded.code, is_active = true, updated_at = now()
  returning code into v_code;

  return v_code;
end;
$$;

create or replace function public.set_teacher_group_access_code(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = v_user;
  if v_role <> 'teacher' then raise exception 'Only teachers can manage this code'; end if;

  v_code := regexp_replace(v_code, '^FISE', 'FISE-');
  if v_code !~ '^FISE-[A-Z0-9]{6}$' then
    raise exception 'Code must use format FISE-XXXXXX';
  end if;

  insert into public.teacher_group_access_codes (teacher_id, code, is_active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code, is_active = true, updated_at = now();

  return v_code;
exception
  when unique_violation then
    raise exception 'This FISE code is already used';
end;
$$;

-- Les élèves ne rejoignent que les groupes du professeur dont le code est fourni
-- ET dont la salle correspond à leur inscription active. Aucun choix de salle
-- côté client ne peut contourner cette vérification serveur.
create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  v_teacher_id uuid;
  v_student_class uuid;
  v_first_group_id uuid;
  v_suffix text;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if auth.uid() is null or v_role is null then raise exception 'Authentication required'; end if;

  -- Le code principal FISE de l'enseignant donne accès à ses groupes,
  -- mais uniquement dans la salle active de l'élève.
  v_code := regexp_replace(v_code, '^(FISE|GPR|GRP)-?', '');
  if length(v_code) = 6 then
    select teacher_id into v_teacher_id
    from public.teacher_group_access_codes
    where upper(regexp_replace(code, '^FISE-', '')) = v_code
      and is_active = true
    limit 1;

    if v_teacher_id is not null then
      if v_role = 'student' then
        select cs.class_id into v_student_class
        from public.class_students cs
        where cs.student_id = auth.uid() and cs.is_active = true
        order by cs.joined_at desc
        limit 1;

        if v_student_class is null then
          raise exception 'No active classroom is assigned to this student';
        end if;

        for v_group in
          select distinct g.*
          from public.message_groups g
          where g.owner_id = v_teacher_id
            and (
              g.class_id = v_student_class
              or exists (
                select 1 from public.message_group_classrooms gc
                where gc.group_id = g.id and gc.class_id = v_student_class
              )
            )
          order by g.created_at, g.id
        loop
          insert into public.message_group_members (group_id, user_id, role)
          values (v_group.id, auth.uid(), 'student')
          on conflict (group_id, user_id) do nothing;
          if v_first_group_id is null then v_first_group_id := v_group.id; end if;
        end loop;

        if v_first_group_id is null then
          raise exception 'No group exists for this teacher in your classroom';
        end if;
        return v_first_group_id;
      elsif v_role = 'teacher' then
        if v_teacher_id <> auth.uid() then raise exception 'This code belongs to another teacher'; end if;
        select id into v_first_group_id from public.message_groups
        where owner_id = auth.uid() order by created_at, id limit 1;
        if v_first_group_id is null then raise exception 'Create a group first'; end if;
        return v_first_group_id;
      elsif v_role <> 'admin' then
        raise exception 'This account cannot join message groups';
      end if;
    end if;
  end if;

  -- Compatibilité : les anciens codes de groupe restent utilisables.
  select * into v_group
  from public.message_groups
  where upper(regexp_replace(invite_code, '^(FISE|GPR|GRP)[ -]*', '', 'i')) =
        upper(regexp_replace(trim(coalesce(p_code, '')), '^(FISE|GPR|GRP)[ -]*', '', 'i'))
  limit 1;

  if not found then raise exception 'Invalid invitation code'; end if;

  if v_group.class_id is not null and v_role = 'student'
     and not public.is_student_in_class(v_group.class_id, auth.uid()) then
    raise exception 'This group is not assigned to your classroom';
  end if;

  insert into public.message_group_members (group_id, user_id, role)
  values (v_group.id, auth.uid(), case when v_role = 'student' then 'student' else 'teacher' end)
  on conflict (group_id, user_id) do nothing;

  return v_group.id;
end;
$$;

revoke all on function public.get_or_create_teacher_group_access_code() from public, anon;
grant execute on function public.get_or_create_teacher_group_access_code() to authenticated;
revoke all on function public.set_teacher_group_access_code(text) from public, anon;
grant execute on function public.set_teacher_group_access_code(text) to authenticated;
revoke all on function public.join_message_group(text) from public, anon;
grant execute on function public.join_message_group(text) to authenticated;
