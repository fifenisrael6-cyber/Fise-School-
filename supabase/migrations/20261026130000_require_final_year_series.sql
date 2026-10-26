-- Final safeguards for official final-year series/specialties.
-- Retire broad Arts/Science labels from non-final anglophone classes; official
-- A1-A8 and S1-S4 series are modeled separately for Upper Sixth.
update public.exam_level_series els
set active = false
from public.exam_levels el, public.series s
where els.exam_level_id = el.id
  and els.series_id = s.id
  and el.subsystem = 'anglophone'
  and el.sector = 'general'
  and el.code in ('en_general_form_5', 'en_general_lower_sixth')
  and s.code in ('gce_arts', 'gce_science')
  and els.active;

-- Prevent future active Terminale/Upper Sixth classrooms from being created
-- without a series (general) or specialty (technical). Existing occupied legacy
-- rooms are left intact for their current students and hidden from choice lists.
create or replace function public.enforce_final_level_track_room()
returns trigger
language plpgsql
set search_path = public
as $function$
declare
  v_level_order integer;
  v_sector text;
begin
  if not new.is_active or new.exam_level_id is null then
    return new;
  end if;

  select el.level_order, el.sector::text
    into v_level_order, v_sector
  from public.exam_levels el
  where el.id = new.exam_level_id and el.active;

  if v_level_order = 7 and v_sector = 'general' and new.series_id is null then
    raise exception 'A final-year general classroom must have an official series';
  end if;

  if v_level_order = 7 and v_sector = 'technical' and new.specialty_id is null then
    raise exception 'A final-year technical classroom must have an official specialty';
  end if;

  return new;
end;
$function$;

drop trigger if exists school_classes_require_final_track on public.school_classes;
create trigger school_classes_require_final_track
before insert or update of exam_level_id, series_id, specialty_id, is_active
on public.school_classes
for each row execute function public.enforce_final_level_track_room();
