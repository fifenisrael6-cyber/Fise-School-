-- Explicit student classroom transfer using the teacher's shared FISE code.
-- The code never silently changes a student's classroom; switching is a separate,
-- user-confirmed action. Only classrooms actually assigned to that teacher's groups
-- are offered. Existing courses, files, payments and other modules are not modified.

create or replace function public.list_teacher_classrooms_for_student(p_code text)
returns table(class_id uuid, class_name text, is_current boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_suffix text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  v_teacher uuid;
  v_current uuid;
  v_subsystem text;
  v_sector text;
  v_exam_level uuid;
  v_series uuid;
  v_specialty uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select p.role, p.subsystem::text, p.sector::text, p.exam_level_id, p.series_id, p.specialty_id
    into v_role, v_subsystem, v_sector, v_exam_level, v_series, v_specialty
  from public.profiles p where p.id = v_user;
  if v_role <> 'student' then raise exception 'Only students can change classroom'; end if;

  v_suffix := regexp_replace(v_suffix, '^(FISE|GPR|GRP)-?', '', 'i');
  v_suffix := regexp_replace(v_suffix, '[^A-Z0-9]', '', 'g');
  if length(v_suffix) <> 6 then return; end if;

  select c.teacher_id into v_teacher
  from public.teacher_group_access_codes c
  where upper(regexp_replace(c.code, '^FISE-', '', 'i')) = v_suffix
    and c.is_active = true
  limit 1;
  if v_teacher is null then
    select c.teacher_id into v_teacher
    from public.teacher_access_codes c
    where upper(regexp_replace(trim(c.code), '^(FISE|GPR|GRP)-?', '', 'i')) = v_suffix
      and c.is_active = true
    order by c.created_at desc limit 1;
  end if;
  if v_teacher is null then return; end if;

  select cs.class_id into v_current
  from public.class_students cs
  where cs.student_id = v_user and cs.is_active
  order by cs.joined_at desc limit 1;

  return query
  select distinct sc.id, coalesce(sc.display_name, sc.name), sc.id = v_current
  from public.message_groups g
  join public.school_classes sc on sc.is_active and (
    sc.id = g.class_id or exists (
      select 1 from public.message_group_classrooms gc
      where gc.group_id = g.id and gc.class_id = sc.id
    )
  )
  where g.owner_id = v_teacher
    and sc.subsystem::text is not distinct from v_subsystem
    and sc.sector::text is not distinct from v_sector
    and (v_exam_level is null or sc.exam_level_id = v_exam_level)
    and (sc.series_id is null or sc.series_id is not distinct from v_series)
    and (sc.specialty_id is null or sc.specialty_id is not distinct from v_specialty)
  order by 2;
end;
$$;

create or replace function public.switch_student_class_with_teacher_code(
  p_code text,
  p_class_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_suffix text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  v_teacher uuid;
  v_class public.school_classes%rowtype;
  v_current uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select p.role into v_role from public.profiles p where p.id = v_user;
  if v_role <> 'student' then raise exception 'Only students can change classroom'; end if;

  v_suffix := regexp_replace(v_suffix, '^(FISE|GPR|GRP)-?', '', 'i');
  v_suffix := regexp_replace(v_suffix, '[^A-Z0-9]', '', 'g');
  if length(v_suffix) <> 6 then raise exception 'Invalid teacher code'; end if;

  select c.teacher_id into v_teacher
  from public.teacher_group_access_codes c
  where upper(regexp_replace(c.code, '^FISE-', '', 'i')) = v_suffix
    and c.is_active = true
  limit 1;
  if v_teacher is null then
    select c.teacher_id into v_teacher
    from public.teacher_access_codes c
    where upper(regexp_replace(trim(c.code), '^(FISE|GPR|GRP)-?', '', 'i')) = v_suffix
      and c.is_active = true
    order by c.created_at desc limit 1;
  end if;
  if v_teacher is null then raise exception 'Invalid or inactive teacher code'; end if;

  select * into v_class
  from public.school_classes sc
  where sc.id = p_class_id and sc.is_active
    and exists (
      select 1 from public.message_groups g
      where g.owner_id = v_teacher
        and (
          g.class_id = sc.id
          or exists (
            select 1 from public.message_group_classrooms gc
            where gc.group_id = g.id and gc.class_id = sc.id
          )
        )
    )
    and exists (
      select 1 from public.profiles p
      where p.id = v_user
        and p.subsystem::text is not distinct from sc.subsystem::text
        and p.sector::text is not distinct from sc.sector::text
        and (p.exam_level_id is null or p.exam_level_id = sc.exam_level_id)
        and (sc.series_id is null or sc.series_id is not distinct from p.series_id)
        and (sc.specialty_id is null or sc.specialty_id is not distinct from p.specialty_id)
    );
  if not found then
    raise exception 'This classroom is unavailable or incompatible with your profile';
  end if;

  select cs.class_id into v_current
  from public.class_students cs
  where cs.student_id = v_user and cs.is_active
  order by cs.joined_at desc limit 1;

  if v_current is distinct from p_class_id then
    -- Deactivate first so the one-active-class-per-academic-year trigger is respected.
    update public.class_students
      set is_active = false
      where student_id = v_user and is_active = true;

    insert into public.class_students(class_id, student_id, joined_at, is_active)
    values (p_class_id, v_user, now(), true)
    on conflict (class_id, student_id) where is_active
    do update set joined_at = excluded.joined_at, is_active = true;

    update public.profiles
      set class_name = coalesce(v_class.display_name, v_class.name)
      where id = v_user;
  end if;

  return p_class_id;
end;
$$;

revoke all on function public.list_teacher_classrooms_for_student(text) from public, anon;
grant execute on function public.list_teacher_classrooms_for_student(text) to authenticated;
revoke all on function public.switch_student_class_with_teacher_code(text, uuid) from public, anon;
grant execute on function public.switch_student_class_with_teacher_code(text, uuid) to authenticated;
