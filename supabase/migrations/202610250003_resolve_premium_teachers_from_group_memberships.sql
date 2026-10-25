-- Premium commissions follow the teacher actually linked to each active standard group
-- through the shared FISE code. No teacher code is entered during checkout.
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
  select m.teacher_id into v_science
  from public.student_group_memberships m
  where m.student_id = p_student_id
    and m.category = 'scientific'
    and m.access_type = 'standard'
    and m.status = 'active'
    and m.effective_from <= now()
    and (m.effective_until is null or m.effective_until > now())
  order by m.effective_from desc
  limit 1;

  select m.teacher_id into v_literary
  from public.student_group_memberships m
  where m.student_id = p_student_id
    and m.category = 'literary'
    and m.access_type = 'standard'
    and m.status = 'active'
    and m.effective_from <= now()
    and (m.effective_until is null or m.effective_until > now())
  order by m.effective_from desc
  limit 1;

  return jsonb_build_object(
    'science_teacher_id', v_science,
    'literary_teacher_id', v_literary
  );
end;
$$;

revoke all on function public.resolve_premium_teachers(uuid) from public, anon, authenticated;
grant execute on function public.resolve_premium_teachers(uuid) to service_role;
