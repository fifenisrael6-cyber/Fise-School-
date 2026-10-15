-- Connecte la validation de code élève au code unique de l'enseignant.
create or replace function public.validate_teacher_access_code(
  p_code text,
  p_class_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  v_teacher uuid;
  v_code_id text;
  v_legacy_class uuid;
  v_group record;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = v_user;
  if v_role <> 'student' then raise exception 'Only students can validate teacher access codes'; end if;

  if not public.is_student_in_class(p_class_id, v_user) then
    return false;
  end if;

  v_code := regexp_replace(v_code, '^FISE-?', '');

  -- Code unique commun à tous les groupes de l'enseignant.
  select teacher_id into v_teacher
  from public.teacher_group_access_codes
  where upper(regexp_replace(code, '^FISE-', '')) = v_code
    and is_active = true
  limit 1;

  if v_teacher is not null then
    if not exists (
      select 1 from public.message_groups g
      where g.owner_id = v_teacher
        and (
          g.class_id = p_class_id
          or exists (
            select 1 from public.message_group_classrooms gc
            where gc.group_id = g.id and gc.class_id = p_class_id
          )
        )
    ) then
      return false;
    end if;

    for v_group in
      select distinct g.id
      from public.message_groups g
      where g.owner_id = v_teacher
        and (
          g.class_id = p_class_id
          or exists (
            select 1 from public.message_group_classrooms gc
            where gc.group_id = g.id and gc.class_id = p_class_id
          )
        )
    loop
      insert into public.message_group_members (group_id, user_id, role)
      values (v_group.id, v_user, 'student')
      on conflict (group_id, user_id) do nothing;
    end loop;

    insert into public.teacher_access_memberships(student_id, teacher_id, class_id, access_code_id)
    values (v_user, v_teacher, p_class_id, 'MASTER-' || v_teacher::text)
    on conflict (student_id, teacher_id, class_id)
    do update set access_code_id = excluded.access_code_id;

    return true;
  end if;

  -- Compatibilité avec les codes historiques par classe.
  select t.id, t.teacher_id, t.class_id::uuid
    into v_code_id, v_teacher, v_legacy_class
  from public.teacher_access_codes t
  where lower(trim(t.code)) = lower(v_code)
    and t.is_active = true
  order by t.created_at desc
  limit 1;

  if v_code_id is null or v_legacy_class is distinct from p_class_id then
    return false;
  end if;

  insert into public.teacher_access_memberships(student_id, teacher_id, class_id, access_code_id)
  values (v_user, v_teacher, p_class_id, v_code_id)
  on conflict (student_id, teacher_id, class_id)
  do update set access_code_id = excluded.access_code_id;

  return true;
end;
$$;

revoke all on function public.validate_teacher_access_code(text, uuid) from public, anon;
grant execute on function public.validate_teacher_access_code(text, uuid) to authenticated;
