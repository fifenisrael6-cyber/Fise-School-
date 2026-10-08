-- Deactivate obviously incompatible subjects in general-class assignments.
-- The active classroom mapping remains the sole source for student subject lists.

update public.class_subjects cs
set is_active = false
from public.school_classes c
join public.exam_levels el on el.id = c.exam_level_id
left join public.series sr on sr.id = c.series_id
join public.subjects s on s.id = cs.subject_id
where cs.class_id = c.id
  and cs.is_active
  and c.sector = 'general'
  and s.sector = 'general'
  and (
    -- Language-option rooms may contain only the language(s) selected for that room.
    (
      c.language_option is not null
      and s.code in ('allemand','arabe','chinois','espagnol','italien')
      and not (s.code = any(string_to_array(c.language_option, '_')))
    )
    -- First-cycle classes do not take second-cycle series-specific subjects.
    or (
      el.level_order < 5
      and s.code in ('latin','grec','philosophie','litterature',
                     'arts_cinematographiques','commerce_fr','comptabilite_fr')
    )
    -- Second-cycle language/Latin/Greek subjects must agree with the chosen series.
    or (
      el.level_order >= 5
      and sr.code is not null
      and s.code in ('latin','grec')
      and (
        (sr.code in ('a1') and false)
        or (sr.code in ('a2','a3') and s.code = 'grec')
        or (sr.code not in ('a1','a2','a3') )
      )
    )
    -- Commercial/accounting subjects are not general-series subjects.
    or (
      el.level_order >= 5
      and sr.code is not null
      and s.code in ('commerce_fr','comptabilite_fr')
    )
    -- Cinema studies belong to the AC series, not science, bilingual or language series.
    or (
      el.level_order >= 5
      and sr.code is not null
      and sr.code <> 'ac'
      and s.code = 'arts_cinematographiques'
    )
    -- Literature is not a subject assignment for the C/D/TI science and technology series.
    or (
      el.level_order >= 5
      and sr.code in ('c','d','ti')
      and s.code = 'litterature'
    )
  );

-- Ensure every selected language-option room retains the selected language rows.
-- (No rows are added here; missing official assignments are not guessed.)