-- Repair student classroom assignment from a valid teacher code.
-- This migration is intentionally additive: it does not move a student who
-- already belongs to another active classroom.

create or replace function public.join_teacher_access_code(p_code text)
returns table(teacher_id uuid, class_id uuid, access_code_id text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  v_teacher uuid;
  v_class uuid;
  v_code_id text;
  v_class_row public.school_classes%rowtype;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = v_user and p.role = 'student'
  ) then
    raise exception 'Only students can join a teacher space';
  end if;

  -- Accept FISE123, FISE-123 and the raw code body.
  if v_code like 'FISE-%' then
    v_code := substring(v_code from 6);
  elsif v_code like 'FISE%' then
    v_code := regexp_replace(v_code, '^FISE-?', '');
  elsif v_code like 'GRP-%' then
    v_code := substring(v_code from 5);
  end if;

  select t.id, t.teacher_id, t.class_id
    into v_code_id, v_teacher, v_class
  from public.teacher_access_codes t
  where upper(trim(t.code)) = upper(trim(v_code))
    and t.is_active = true
  order by t.created_at desc
  limit 1;

  if v_code_id is null or v_teacher is null or v_class is null then
    raise exception 'Invalid or inactive teacher access code';
  end if;

  select c.* into v_class_row
  from public.school_classes c
  where c.id = v_class and c.is_active = true;

  if not found then
    raise exception 'The classroom for this code is unavailable';
  end if;

  -- If an active membership exists, it must already be this classroom.
  if exists (
    select 1 from public.class_students cs
    where cs.student_id = v_user
      and cs.is_active = true
      and cs.class_id <> v_class
  ) then
    raise exception 'Student already assigned to another classroom';
  end if;

  -- Create the classroom membership when the student has none.
  if not exists (
    select 1 from public.class_students cs
    where cs.student_id = v_user
      and cs.class_id = v_class
      and cs.is_active = true
  ) then
    insert into public.class_students(class_id, student_id, joined_at, is_active)
    values (v_class, v_user, now(), true);
  end if;

  -- Synchronize profile labels/IDs so the home screen and course pages agree.
  update public.profiles p
  set subsystem = v_class_row.subsystem,
      sector = v_class_row.sector,
      exam_level_id = v_class_row.exam_level_id,
      series_id = v_class_row.series_id,
      specialty_id = v_class_row.specialty_id,
      class_name = v_class_row.display_name,
      language_option = v_class_row.language_option,
      updated_at = now()
  where p.id = v_user;

  insert into public.teacher_access_memberships(
    student_id, teacher_id, class_id, access_code_id
  )
  values (v_user, v_teacher, v_class, v_code_id)
  on conflict (student_id, teacher_id, class_id)
  do update set access_code_id = excluded.access_code_id;

  return query select v_teacher, v_class, v_code_id;
end;
$$;

revoke all on function public.join_teacher_access_code(text) from public, anon;
grant execute on function public.join_teacher_access_code(text) to authenticated;

-- Keep the old RPC signature for older app versions, but use the corrected
-- assignment flow instead of merely checking for a pre-existing membership.
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
  v_joined record;
begin
  select * into v_joined
  from public.join_teacher_access_code(p_code)
  limit 1;

  if not found then
    return false;
  end if;

  -- A non-null caller-supplied class must match the classroom in the code.
  if p_class_id is not null and v_joined.class_id <> p_class_id then
    return false;
  end if;

  return true;
exception
  when others then
    -- Preserve a boolean result for legacy callers; the new app uses the
    -- join RPC directly so it can show a localized, meaningful error.
    return false;
end;
$$;

revoke all on function public.validate_teacher_access_code(text, uuid) from public, anon;
grant execute on function public.validate_teacher_access_code(text, uuid) to authenticated;

-- Use the same corrected assignment routine when a student joins with a FISE
-- teacher code. Legacy GRP invitation codes remain supported.
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
  v_joined record;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select p.role into v_role
  from public.profiles p
  where p.id = auth.uid();

  if v_role is null then
    raise exception 'Profile not found';
  end if;

  if left(v_code, 4) = 'FISE' then
    if v_role = 'student' then
      select * into v_joined
      from public.join_teacher_access_code(p_code)
      limit 1;
      v_teacher_id := v_joined.teacher_id;
      v_class_id := v_joined.class_id;
    else
      if v_code like 'FISE-%' then
        v_code := substring(v_code from 6);
      else
        v_code := substring(v_code from 5);
      end if;

      select t.teacher_id, t.class_id
        into v_teacher_id, v_class_id
      from public.teacher_access_codes t
      where upper(trim(t.code)) = v_code
        and t.is_active = true
      order by t.created_at desc
      limit 1;

      if v_teacher_id is null or v_class_id is null then
        raise exception 'Invalid or inactive teacher access code';
      end if;

      if v_role = 'teacher'
         and v_teacher_id <> auth.uid()
         and not public.teacher_can_manage_class(v_class_id, auth.uid()) then
        raise exception 'Teacher is not assigned to this classroom';
      elsif v_role not in ('teacher', 'admin') then
        raise exception 'This account cannot join message groups';
      end if;
    end if;

    for v_group in
      select g.*
      from public.message_groups g
      where g.owner_id = v_teacher_id
        and (
          g.class_id = v_class_id
          or exists (
            select 1 from public.message_group_classrooms gc
            where gc.group_id = g.id and gc.class_id = v_class_id
          )
        )
      order by g.created_at, g.id
    loop
      insert into public.message_group_members(group_id, user_id, role)
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

    if v_first_group_id is null then
      raise exception 'No message group exists for this teacher and classroom yet';
    end if;

    return v_first_group_id;
  end if;

  select * into v_group
  from public.message_groups
  where invite_code = upper(trim(p_code))
  limit 1;

  if not found then
    raise exception 'Invalid invitation code';
  end if;

  if v_role = 'student' and v_group.class_id is not null
     and not public.is_student_in_class(v_group.class_id, auth.uid()) then
    raise exception 'This group is not assigned to your classroom';
  end if;

  if v_role = 'student' and v_group.class_id is null
     and not exists (
       select 1 from public.message_group_classrooms gc
       join public.class_students cs on cs.class_id = gc.class_id
       where gc.group_id = v_group.id
         and cs.student_id = auth.uid()
         and cs.is_active = true
     ) then
    raise exception 'This group is not assigned to your classroom';
  end if;

  insert into public.message_group_members(group_id, user_id, role)
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
