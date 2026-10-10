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

  select p.role into v_role from public.profiles p where p.id = v_uid;
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
              and not (
                c.exam_level_id is not null
                and c.series_id is null
                and c.specialty_id is null
                and exists (
                  select 1
                  from public.school_classes specific
                  where specific.is_active
                    and specific.subsystem = c.subsystem
                    and specific.sector = c.sector
                    and specific.exam_level_id = c.exam_level_id
                    and (specific.series_id is not null or specific.specialty_id is not null)
                )
              )
          )
        )
    ) then
      raise exception 'Classroom is outside your allowed subsystem or sector, or is a generic duplicate';
    end if;

    if not public.is_admin() then
      update public.class_teachers
      set is_active = true
      where teacher_id = v_uid and class_id = v_class_id;

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
