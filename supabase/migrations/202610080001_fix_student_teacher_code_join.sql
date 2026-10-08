-- Fix student teacher-code joining.
-- A valid teacher code now adds the student to the code's classroom.
-- This is what the Cours page uses to find the student's subjects.

create or replace function public.join_class_with_teacher_access_code(
  p_code text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := auth.uid();
  v_class_id uuid;
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

  select t.class_id
    into v_class_id
  from public.teacher_access_codes t
  join public.school_classes c on c.id = t.class_id
  where lower(t.code) = lower(
    case
      when lower(trim(p_code)) like 'fise%'
        then substring(trim(p_code) from 5)
      else trim(p_code)
    end
  )
    and t.is_active
    and c.is_active
  limit 1;

  if v_class_id is null then
    raise exception 'Invalid or inactive teacher access code';
  end if;

  insert into public.class_students (
    class_id,
    student_id,
    joined_at,
    is_active
  )
  values (
    v_class_id,
    v_student,
    now(),
    true
  )
  on conflict (class_id, student_id) where is_active
  do update set
    is_active = true,
    joined_at = now();

  return v_class_id;
end;
$$;

revoke all
on function public.join_class_with_teacher_access_code(text)
from public;

grant execute
on function public.join_class_with_teacher_access_code(text)
to authenticated;
