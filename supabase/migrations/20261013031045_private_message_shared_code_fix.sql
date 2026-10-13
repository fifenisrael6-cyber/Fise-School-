-- Private chat unlock must share the teacher code with group chat without
-- invoking join_teacher_access_code(), which is a class-enrolment flow.
create or replace function public.unlock_teacher_private_messages(p_code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student uuid := (select auth.uid());
  v_code text := upper(trim(coalesce(p_code, '')));
  v_teacher uuid;
  v_class uuid;
  v_code_id text;
begin
  if v_student is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = v_student and role = 'student'
  ) then
    raise exception 'Only students can unlock a teacher';
  end if;

  -- Accept the same code variants used in the UI: FISE-ABC, FISEABC or ABC.
  v_code := regexp_replace(v_code, '^FISE-?', '');

  select t.id, t.teacher_id, t.class_id::uuid
    into v_code_id, v_teacher, v_class
  from public.teacher_access_codes t
  where upper(trim(t.code)) = v_code
    and t.is_active = true
  order by t.created_at desc
  limit 1;

  if v_code_id is null or v_teacher is null or v_class is null then
    return false;
  end if;

  -- Private access is allowed only when the student already belongs to
  -- the code's classroom; do not change the student's school registration.
  if not exists (
    select 1 from public.class_students cs
    where cs.student_id = v_student
      and cs.class_id = v_class
      and cs.is_active = true
  ) then
    return false;
  end if;

  insert into public.teacher_access_memberships
    (student_id, teacher_id, class_id, access_code_id)
  values (v_student, v_teacher, v_class, v_code_id)
  on conflict (student_id, teacher_id, class_id)
  do update set access_code_id = excluded.access_code_id;

  return true;
end;
$$;

revoke all on function public.unlock_teacher_private_messages(text) from public, anon;
grant execute on function public.unlock_teacher_private_messages(text) to authenticated;
