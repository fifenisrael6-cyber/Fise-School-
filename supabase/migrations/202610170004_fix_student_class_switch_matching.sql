-- Allow authenticated students to select an available school classroom without
-- a teacher code. The account stays the same; the active class and school pathway
-- metadata are updated together by a server-side function.

create or replace function public.list_available_student_classrooms()
returns table (
  class_id uuid,
  class_name text,
  is_current boolean,
  subsystem text,
  sector text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_subsystem text;
  v_current uuid;
  v_current_year uuid;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  select p.role, p.subsystem::text
    into v_role, v_subsystem
  from public.profiles p
  where p.id = v_user;

  if v_role <> 'student' then
    raise exception 'Only students can change classroom';
  end if;

  select cs.class_id
    into v_current
  from public.class_students cs
  where cs.student_id = v_user and cs.is_active
  order by cs.joined_at desc
  limit 1;

  select ay.id
    into v_current_year
  from public.academic_years ay
  where ay.is_current
  limit 1;

  return query
  select sc.id,
         coalesce(sc.display_name, sc.name),
         sc.id = v_current,
         sc.subsystem::text,
         sc.sector::text
  from public.school_classes sc
  where sc.is_active
    and (nullif(trim(v_subsystem), '') is null or lower(trim(sc.subsystem::text)) = lower(trim(v_subsystem)))
    and (
      v_current_year is null
      or sc.academic_year_id = v_current_year
      or sc.id = v_current
    )
  order by (sc.id = v_current) desc, coalesce(sc.display_name, sc.name);
end;
$$;

create or replace function public.switch_student_class_without_code(p_class_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_subsystem text;
  v_current uuid;
  v_current_year uuid;
  v_class public.school_classes%rowtype;
  v_exam_id uuid;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  select p.role, p.subsystem::text
    into v_role, v_subsystem
  from public.profiles p
  where p.id = v_user;

  if v_role <> 'student' then
    raise exception 'Only students can change classroom';
  end if;

  select ay.id
    into v_current_year
  from public.academic_years ay
  where ay.is_current
  limit 1;

  select sc.*
    into v_class
  from public.school_classes sc
  where sc.id = p_class_id
    and sc.is_active
    and (nullif(trim(v_subsystem), '') is null or lower(trim(sc.subsystem::text)) = lower(trim(v_subsystem)))
    and (
      v_current_year is null
      or sc.academic_year_id = v_current_year
      or exists (
        select 1 from public.class_students existing
        where existing.student_id = v_user
          and existing.class_id = sc.id
          and existing.is_active
      )
    );

  if not found then
    raise exception 'Selected classroom is unavailable or outside your school subsystem';
  end if;

  select cs.class_id
    into v_current
  from public.class_students cs
  where cs.student_id = v_user and cs.is_active
  order by cs.joined_at desc
  limit 1;

  if v_current is distinct from p_class_id then
    -- Deactivate the old active membership before inserting the new one.
    update public.class_students
       set is_active = false
     where student_id = v_user and is_active = true;

    insert into public.class_students(class_id, student_id, joined_at, is_active)
    values (p_class_id, v_user, now(), true)
    on conflict (class_id, student_id) where is_active
    do update set joined_at = excluded.joined_at, is_active = true;

    select el.exam_id
      into v_exam_id
    from public.exam_levels el
    where el.id = v_class.exam_level_id;

    -- Update the complete school pathway, not just the visible class label.
    -- The account ID and personal data are intentionally unchanged.
    update public.profiles
       set class_name = coalesce(v_class.display_name, v_class.name),
           subsystem = v_class.subsystem,
           sector = v_class.sector,
           exam_level_id = v_class.exam_level_id,
           exam_id = v_exam_id,
           series_id = v_class.series_id,
           specialty_id = v_class.specialty_id
     where id = v_user;
  end if;

  return p_class_id;
end;
$$;

revoke all on function public.list_available_student_classrooms() from public, anon;
grant execute on function public.list_available_student_classrooms() to authenticated;
revoke all on function public.switch_student_class_without_code(uuid) from public, anon;
grant execute on function public.switch_student_class_without_code(uuid) to authenticated;
