-- Teacher-targeted classroom selection for QCMs and message groups.
-- Only active classrooms matching the teacher profile's subsystem AND sector
-- are returned/authorized. Admins may see all active classrooms.
create or replace function public.list_compatible_teacher_classes()
returns table (id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select c.id
  from public.school_classes c
  where c.is_active
    and (
      public.is_admin()
      or exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.role = 'teacher'
          and p.subsystem is not null
          and p.sector is not null
          and p.subsystem = c.subsystem
          and p.sector = c.sector
      )
    )
  order by c.display_name;
$$;

revoke all on function public.list_compatible_teacher_classes() from public, anon;
grant execute on function public.list_compatible_teacher_classes() to authenticated;

-- Activate only explicitly selected, compatible teacher/class assignments.
-- Existing assignments are preserved; selecting a target never deactivates
-- other classes or removes existing teaching access.
create or replace function public.teacher_authorize_compatible_classes(p_class_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_class_id uuid;
  v_count integer := 0;
  v_role text;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select p.role into v_role
  from public.profiles p
  where p.id = v_uid;

  if v_role is null or v_role not in ('teacher', 'admin') then
    raise exception 'Only teachers and admins can target classrooms';
  end if;

  if coalesce(cardinality(p_class_ids), 0) = 0 then
    raise exception 'Select at least one classroom';
  end if;

  foreach v_class_id in array p_class_ids loop
    if not exists (
      select 1
      from public.school_classes c
      where c.id = v_class_id
        and c.is_active
        and (
          public.is_admin()
          or exists (
            select 1
            from public.profiles p
            where p.id = v_uid
              and p.role = 'teacher'
              and p.subsystem is not null
              and p.sector is not null
              and p.subsystem = c.subsystem
              and p.sector = c.sector
          )
        )
    ) then
      raise exception 'Classroom is outside your allowed subsystem or sector';
    end if;

    if not public.is_admin() then
      update public.class_teachers
      set is_active = true
      where teacher_id = v_uid
        and class_id = v_class_id;

      if not found then
        insert into public.class_teachers (class_id, teacher_id, is_active)
        values (v_class_id, v_uid, true);
      end if;
    end if;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.teacher_authorize_compatible_classes(uuid[]) from public, anon;
grant execute on function public.teacher_authorize_compatible_classes(uuid[]) to authenticated;


-- QCMs built directly by the teacher are standalone assignments and do not
-- require a course row. Course-linked assignments retain the stricter checks.
create or replace function public.validate_assignment_context()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_course public.courses%rowtype;
begin
  if new.course_id is null then
    if new.lesson_id is not null then
      raise exception 'A lesson-linked assignment must reference a course';
    end if;

    if not public.is_admin()
       and not public.teacher_can_manage_class(new.class_id, new.teacher_id) then
      raise exception 'Teacher is not assigned to the selected class';
    end if;

    if new.subject_id is null then
      raise exception 'Assignment subject is required when no course is selected';
    end if;

    if not exists (
      select 1
      from public.class_subjects cs
      where cs.class_id = new.class_id
        and cs.subject_id = new.subject_id
        and cs.is_active
    ) then
      raise exception 'The selected subject is not assigned to this classroom';
    end if;

    return new;
  end if;

  select * into v_course
  from public.courses
  where id = new.course_id;

  if not found or v_course.status = 'archived' then
    raise exception 'Assignment course is not available';
  end if;

  if new.class_id is distinct from v_course.class_id then
    raise exception 'Assignment class must match the course class';
  end if;

  if new.teacher_id is distinct from v_course.teacher_id and not public.is_admin() then
    raise exception 'Assignment teacher must own the selected course';
  end if;

  if not public.is_admin()
     and not public.teacher_can_manage_class(new.class_id, new.teacher_id) then
    raise exception 'Teacher is not assigned to the selected class';
  end if;

  if new.lesson_id is not null and not exists (
    select 1 from public.lessons l
    where l.id = new.lesson_id
      and l.course_id = new.course_id
  ) then
    raise exception 'Assignment lesson must belong to the selected course';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_assignment_context() from public;
grant execute on function public.validate_assignment_context() to authenticated;
