-- Admin pedagogical publishing and bulk classroom catalogue management.
-- The subject catalogue is based on the official MINESEC programme structure;
-- administrators remain able to adjust a room's subjects when a class/series
-- has a specific option.

create or replace function public.admin_apply_base_subject_catalog()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator can apply the classroom catalogue';
  end if;

  insert into public.class_subjects (class_id, subject_id, is_compulsory, option_group, position, is_active)
  select c.id, s.id, true, null, row_number() over (partition by c.id order by s.code) - 1, true
  from public.school_classes c
  join public.subjects s
    on s.is_active
   and s.subsystem = c.subsystem
   and s.sector = c.sector
  where c.is_active
    and (
      (c.subsystem = 'francophone' and c.sector = 'general' and s.code in
        ('francais','anglais','mathematiques','histoire','geographie','education_civique'))
      or
      (c.subsystem = 'anglophone' and c.sector = 'general' and s.code in
        ('english_language','french_language','mathematics_en','history_en','geography_en','citizenship_en'))
      or
      (c.subsystem = 'francophone' and c.sector = 'technical' and s.code in
        ('technical_math','technical_science','dessin_technique','technologie','entrepreneuriat','technical_english'))
      or
      (c.subsystem = 'anglophone' and c.sector = 'technical' and s.code in
        ('technical_french','technical_communication','technical_math_en','technical_science_en','workshop_practice'))
    )
  on conflict (class_id, subject_id) do update set
    is_active = true;

  get diagnostics affected = row_count;
  return affected;
end;
$$;

revoke all on function public.admin_apply_base_subject_catalog() from public;
grant execute on function public.admin_apply_base_subject_catalog() to authenticated;

-- Admins may create courses using their own profile as the audit owner.
-- The existing course model keeps teacher_id for backward compatibility.
-- validate_teacher_course_scope already permits admins to bypass teacher scope.
