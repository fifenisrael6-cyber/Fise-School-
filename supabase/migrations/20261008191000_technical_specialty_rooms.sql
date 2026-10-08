-- Generate specialty-specific rooms for active technical classes in the current school year.
insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id, exam_level_id, series_id, specialty_id)
select
  el.code || '_' || sp.code,
  el.level_name_fr || ' — ' || sp.name_fr,
  el.subsystem, el.sector, ay.id, el.id, null, sp.id
from public.exam_levels el
join public.academic_years ay on ay.is_current
join public.exam_level_specialties els on els.exam_level_id = el.id and els.active
join public.specialties sp on sp.id = els.specialty_id and sp.active
where el.active and el.sector = 'technical' and el.level_order >= 5
on conflict (name, academic_year_id) do update
set display_name = excluded.display_name,
    specialty_id = excluded.specialty_id,
    is_active = true,
    updated_at = now();
