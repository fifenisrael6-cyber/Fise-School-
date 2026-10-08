-- Remove optional foreign-language subjects from general rooms without a language choice.
-- Keep only the selected language(s) in option-specific rooms.
update public.class_subjects cs
set is_active = false
from public.school_classes c
join public.exam_levels el on el.id = c.exam_level_id
left join public.series sr on sr.id = c.series_id
join public.subjects s on true
where cs.class_id = c.id
  and s.id = cs.subject_id
  and cs.is_active
  and c.sector = 'general'
  and s.sector = 'general'
  and s.code in ('allemand','arabe','chinois','espagnol','italien')
  and (
    (c.language_option is null and el.level_order >= 5 and sr.code is not null)
    or (c.language_option is null and el.level_order < 5 and c.display_name not like '%Troisième%')
    or (c.language_option is not null and not (s.code = any(string_to_array(c.language_option, '_'))))
  );

-- ESF and standalone chemistry/physics entries are not part of the first-cycle general base list;
-- PCT remains the integrated science subject there.
update public.class_subjects cs
set is_active = false
from public.school_classes c
join public.exam_levels el on el.id = c.exam_level_id
join public.subjects s on true
where cs.class_id = c.id
  and s.id = cs.subject_id
  and cs.is_active
  and c.sector = 'general'
  and s.sector = 'general'
  and el.level_order < 5
  and s.code in ('esf','chimie','physique');