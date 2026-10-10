-- Repair FISE- normalization for student class and group access.
-- Existing records keep only the suffix (for example MATHS6A) in code.
-- Accept either the suffix or the full FISE-... value from the app.

create or replace function public.join_class_with_teacher_access_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := auth.uid();
  v_class_id uuid;
  v_code text := regexp_replace(upper(trim(coalesce(p_code, ''))), '^FISE-', '');
begin
  if v_student is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = v_student and role = 'student'
  ) then
    raise exception 'Only a student can join a class with this code';
  end if;

  if length(v_code) < 3 or v_code ~ '\s' or v_code !~ '^[A-Z0-9-]+$' then
    raise exception 'Invalid teacher access code format';
  end if;

  select t.class_id
    into v_class_id
  from public.teacher_access_codes t
  join public.school_classes c on c.id = t.class_id
  where regexp_replace(upper(trim(t.code)), '^FISE-', '') = v_code
    and t.is_active = true
    and c.is_active = true
  order by t.created_at desc
  limit 1;

  if v_class_id is null then
    raise exception 'Invalid or inactive teacher access code';
  end if;

  insert into public.class_students (class_id, student_id, joined_at, is_active)
  values (v_class_id, v_student, now(), true)
  on conflict (class_id, student_id) where is_active
  do update set is_active = true, joined_at = now();

  return v_class_id;
end;
$$;

revoke all on function public.join_class_with_teacher_access_code(text) from public, anon;
grant execute on function public.join_class_with_teacher_access_code(text) to authenticated;

create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_code text := upper(trim(coalesce(p_code, '')));
  v_teacher_id uuid;
  v_class_id uuid;
  v_first_group_id uuid;
begin
  select role into v_role
  from public.profiles
  where id = auth.uid();

  if v_role is null then
    raise exception 'Profile not found';
  end if;

  if left(v_code, 5) = 'FISE-' then
    v_code := substring(v_code from 6);

    select t.teacher_id, t.class_id
      into v_teacher_id, v_class_id
    from public.teacher_access_codes t
    where regexp_replace(upper(trim(t.code)), '^FISE-', '') = v_code
      and t.is_active = true
    order by t.created_at desc
    limit 1;

    if v_teacher_id is null or v_class_id is null then
      raise exception 'Invalid teacher access code';
    end if;

    if v_role = 'student' then
      if not public.is_student_in_class(v_class_id, auth.uid()) then
        raise exception 'This code is not valid for your classroom';
      end if;
    elsif v_role = 'teacher' then
      if v_teacher_id <> auth.uid()
         and not public.teacher_can_manage_class(v_class_id, auth.uid()) then
        raise exception 'Teacher is not assigned to this classroom';
      end if;
    elsif v_role <> 'admin' then
      raise exception 'This account cannot join message groups';
    end if;

    for v_group in
      select g.*
      from public.message_groups g
      where g.owner_id = v_teacher_id
        and g.class_id = v_class_id
      order by g.created_at, g.id
    loop
      insert into public.message_group_members (group_id, user_id, role)
      values (
        v_group.id,
        auth.uid(),
        case when v_role = 'student' then 'student' else 'teacher' end
      )
      on conflict (group_id, user_id) do nothing;

      if v_first_group_id is null then
        v_first_group_id := v_group.id;
      end if;
    end loop;

    -- A valid code still grants private-message access when no group exists yet.
    return v_first_group_id;
  end if;

  -- Backward compatibility for existing GRP- invitation codes.
  select * into v_group
  from public.message_groups
  where invite_code = upper(trim(p_code))
  limit 1;

  if not found then
    raise exception 'Invalid invitation code';
  end if;

  if v_group.class_id is not null and v_role = 'student'
     and not public.is_student_in_class(v_group.class_id, auth.uid()) then
    raise exception 'This group is not assigned to your classroom';
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

revoke all on function public.join_message_group(text) from public, anon;
grant execute on function public.join_message_group(text) to authenticated;

notify pgrst, 'reload schema';
