-- A student must have validated the teacher's shared FISE code before group RLS allows access.
create or replace function public.is_message_group_member(p_group_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.message_group_members m
    join public.message_groups g on g.id = m.group_id
    join public.profiles p on p.id = m.user_id
    where m.group_id = p_group_id and m.user_id = auth.uid()
      and (
        p.role <> 'student'
        or exists (
          select 1 from public.teacher_fise_code_memberships fm
          where fm.student_id = m.user_id and fm.teacher_id = g.owner_id
            and (
              fm.class_id = g.class_id
              or exists (select 1 from public.message_group_classrooms gc
                where gc.group_id = g.id and gc.class_id = fm.class_id)
            )
        )
      )
  );
$$;

create or replace function public.join_message_group(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_code text;
  v_teacher_id uuid;
  v_shared_code text;
  v_student_class uuid;
  v_first_group_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null then raise exception 'Profile not found'; end if;
  v_code := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));

  if v_code ~ '^(FISE|GPR|GRP)-?[A-Z0-9]{6}$' then
    v_code := regexp_replace(v_code, '^(FISE|GPR|GRP)-?', '');
    select c.teacher_id, c.code into v_teacher_id, v_shared_code
    from public.teacher_group_access_codes c
    where upper(regexp_replace(c.code, '^FISE-', '')) = v_code and c.is_active = true
    limit 1;
    if v_teacher_id is not null then
      if v_role = 'student' then
        select cs.class_id into v_student_class from public.class_students cs
        where cs.student_id = auth.uid() and cs.is_active = true
        order by cs.joined_at desc limit 1;
        if v_student_class is null then raise exception 'No active classroom is assigned to this student'; end if;
        insert into public.teacher_fise_code_memberships (student_id, teacher_id, class_id, code, joined_at)
        values (auth.uid(), v_teacher_id, v_student_class, v_shared_code, now())
        on conflict (student_id, teacher_id, class_id)
        do update set code = excluded.code, joined_at = now();
        for v_group in
          select distinct g.* from public.message_groups g
          where g.owner_id = v_teacher_id and (
            g.class_id = v_student_class or exists (
              select 1 from public.message_group_classrooms gc
              where gc.group_id = g.id and gc.class_id = v_student_class
            )
          ) order by g.created_at, g.id
        loop
          insert into public.message_group_members(group_id, user_id, role)
          values (v_group.id, auth.uid(), 'student') on conflict (group_id, user_id) do nothing;
          if v_first_group_id is null then v_first_group_id := v_group.id; end if;
        end loop;
        return v_first_group_id;
      elsif v_role = 'teacher' then
        if v_teacher_id <> auth.uid() then raise exception 'This code belongs to another teacher'; end if;
        select id into v_first_group_id from public.message_groups where owner_id = auth.uid()
        order by created_at, id limit 1;
        return v_first_group_id;
      elsif v_role <> 'admin' then
        raise exception 'This account cannot join message groups';
      end if;
    end if;
  end if;

  -- Legacy group codes no longer grant students access. The shared FISE code is required.
  select * into v_group from public.message_groups g
  where upper(regexp_replace(g.invite_code, '^(FISE|GPR|GRP)[ -]*', '', 'i')) =
        upper(regexp_replace(trim(coalesce(p_code, '')), '^(FISE|GPR|GRP)[ -]*', '', 'i'))
  limit 1;
  if not found then raise exception 'Invalid invitation code'; end if;
  if v_role = 'student' then
    raise exception 'Use the teacher shared FISE code to access groups and evaluations';
  end if;
  insert into public.message_group_members(group_id, user_id, role)
  values (v_group.id, auth.uid(), 'teacher') on conflict (group_id, user_id) do nothing;
  return v_group.id;
end;
$$;

revoke all on function public.is_message_group_member(uuid) from public, anon;
grant execute on function public.is_message_group_member(uuid) to authenticated;
revoke all on function public.join_message_group(text) from public, anon;
grant execute on function public.join_message_group(text) to authenticated;
notify pgrst, 'reload schema';
