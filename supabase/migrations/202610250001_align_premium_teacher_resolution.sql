-- Resolve Premium teacher commissions from the teacher vocation selected in the profile.
-- Keep the older teaching_stream column as a fallback for existing teacher profiles.
create or replace function public.resolve_premium_teachers(p_student_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_science uuid;
  v_literary uuid;
begin
  select ct.teacher_id into v_science
  from public.class_students cs
  join public.class_teachers ct on ct.class_id = cs.class_id and ct.is_active
  join public.profiles t on t.id = ct.teacher_id and t.role = 'teacher'
  where cs.student_id = p_student_id
    and cs.is_active
    and coalesce(nullif(t.teacher_vocation, ''), nullif(t.teaching_stream, '')) = 'scientific'
  order by ct.assigned_at desc
  limit 1;

  select ct.teacher_id into v_literary
  from public.class_students cs
  join public.class_teachers ct on ct.class_id = cs.class_id and ct.is_active
  join public.profiles t on t.id = ct.teacher_id and t.role = 'teacher'
  where cs.student_id = p_student_id
    and cs.is_active
    and coalesce(nullif(t.teacher_vocation, ''), nullif(t.teaching_stream, '')) = 'literary'
  order by ct.assigned_at desc
  limit 1;

  return jsonb_build_object(
    'science_teacher_id', v_science,
    'literary_teacher_id', v_literary
  );
end;
$$;
