-- Respect classroom validation triggers: synchronize the profile before inserting
-- the class_students row, so subsystem/sector checks see the target classroom.
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

  if exists (
    select 1 from public.class_students cs
    where cs.student_id = v_user
      and cs.is_active = true
      and cs.class_id <> v_class
  ) then
    raise exception 'Student already assigned to another classroom';
  end if;

  -- Update first: class_students has BEFORE triggers validating profile fields.
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

  if not exists (
    select 1 from public.class_students cs
    where cs.student_id = v_user
      and cs.class_id = v_class
      and cs.is_active = true
  ) then
    insert into public.class_students(class_id, student_id, joined_at, is_active)
    values (v_class, v_user, now(), true);
  end if;

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
