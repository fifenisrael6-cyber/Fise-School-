-- Sélection explicite d'un groupe/salle avec le code maître FISE de l'enseignant.
-- Migration additive : les tables de groupes, paiements et codes historiques restent intactes.

create or replace function public.list_teacher_groups_by_code(p_code text)
returns table (group_id uuid, group_name text, class_id uuid, class_name text)
language plpgsql security definer set search_path = public
as $$
declare
  v_role text;
  v_input text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  v_suffix text;
  v_teacher_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.role into v_role from public.profiles p where p.id = auth.uid();
  if v_role not in ('student', 'teacher', 'admin') then
    raise exception 'This account cannot access teacher groups';
  end if;

  v_suffix := regexp_replace(v_input, '^(FISE|GPR|GRP)-?', '', 'i');
  if length(v_suffix) <> 6 then return; end if;

  select c.teacher_id into v_teacher_id
  from public.teacher_group_access_codes c
  where upper(regexp_replace(c.code, '^FISE-', '', 'i')) = v_suffix
    and c.is_active limit 1;

  if v_teacher_id is null then
    select c.teacher_id into v_teacher_id
    from public.teacher_access_codes c
    where upper(regexp_replace(trim(c.code), '^(FISE|GPR|GRP)-?', '', 'i')) = v_suffix
      and c.is_active order by c.created_at desc limit 1;
  end if;
  if v_teacher_id is null then return; end if;

  return query
  select distinct g.id, g.name, sc.id, sc.display_name
  from public.message_groups g
  join public.message_group_classrooms gc on gc.group_id = g.id
  join public.school_classes sc on sc.id = gc.class_id
  where g.owner_id = v_teacher_id and sc.is_active
  order by g.name, sc.display_name;
end;
$$;

create or replace function public.join_teacher_group_by_code(
  p_code text, p_group_id uuid, p_class_id uuid
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_role text;
  v_input text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  v_suffix text;
  v_teacher_id uuid;
  v_student_class_id uuid;
  v_group_owner uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.role into v_role from public.profiles p where p.id = auth.uid();
  if v_role <> 'student' then
    raise exception 'Only students can join a teacher group through this code';
  end if;

  v_suffix := regexp_replace(v_input, '^(FISE|GPR|GRP)-?', '', 'i');
  if length(v_suffix) <> 6 then raise exception 'Invalid teacher code'; end if;

  select c.teacher_id into v_teacher_id
  from public.teacher_group_access_codes c
  where upper(regexp_replace(c.code, '^FISE-', '', 'i')) = v_suffix
    and c.is_active limit 1;

  if v_teacher_id is null then
    select c.teacher_id into v_teacher_id
    from public.teacher_access_codes c
    where upper(regexp_replace(trim(c.code), '^(FISE|GPR|GRP)-?', '', 'i')) = v_suffix
      and c.is_active order by c.created_at desc limit 1;
  end if;
  if v_teacher_id is null then raise exception 'Invalid teacher code'; end if;

  select cs.class_id into v_student_class_id
  from public.class_students cs
  where cs.student_id = auth.uid() and cs.is_active
  order by cs.joined_at desc limit 1;

  if v_student_class_id is null or v_student_class_id <> p_class_id then
    raise exception 'Selected classroom does not match the student classroom';
  end if;

  select g.owner_id into v_group_owner
  from public.message_groups g
  where g.id = p_group_id and g.owner_id = v_teacher_id
    and (g.class_id = p_class_id or exists (
      select 1 from public.message_group_classrooms gc
      where gc.group_id = g.id and gc.class_id = p_class_id
    ))
  limit 1;
  if v_group_owner is null then
    raise exception 'Selected group is not available for this classroom';
  end if;

  insert into public.message_group_members (group_id, user_id, role)
  values (p_group_id, auth.uid(), 'student')
  on conflict (group_id, user_id) do nothing;
  return p_group_id;
end;
$$;

revoke all on function public.list_teacher_groups_by_code(text) from public, anon;
grant execute on function public.list_teacher_groups_by_code(text) to authenticated;
revoke all on function public.join_teacher_group_by_code(text, uuid, uuid) from public, anon;
grant execute on function public.join_teacher_group_by_code(text, uuid, uuid) to authenticated;
