-- Align representative second-cycle general mappings with the official MINESEC
-- baccalaureate subject tables (series A4/A5 and C/D).
-- Official references:
-- https://www.minesec.gov.cm/web/index.php/fr/decisions-fr/item/download/1684_ffdd496c6cda71f8514e848ed0a9da1a
-- https://www.minesec.gov.cm/web/index.php/fr/decisions-fr/item/download/1685_de779e22e38c5da348fab7cbaed22ab8

-- C and D list Literature/Culture générale and do not list Geography as a written exam in this decree.
update public.class_subjects cs
set is_active = false
from public.school_classes c
join public.exam_levels el on el.id = c.exam_level_id
join public.series sr on sr.id = c.series_id
join public.subjects s on true
where cs.class_id = c.id
  and s.id = cs.subject_id
  and cs.is_active
  and el.level_order >= 5
  and c.subsystem = 'francophone'
  and c.sector = 'general'
  and sr.code in ('c','d')
  and s.code = 'geographie';

update public.class_subjects cs
set is_active = true
from public.school_classes c
join public.exam_levels el on el.id = c.exam_level_id
join public.series sr on sr.id = c.series_id
join public.subjects s on true
where cs.class_id = c.id
  and s.id = cs.subject_id
  and el.level_order >= 5
  and c.subsystem = 'francophone'
  and c.sector = 'general'
  and sr.code in ('c','d')
  and s.code = 'litterature'
  and s.is_active;

insert into public.class_subjects (class_id, subject_id, is_compulsory, option_group, position, is_active)
select c.id, s.id, true, null,
       coalesce((select max(cs2.position) + 1 from public.class_subjects cs2 where cs2.class_id = c.id), 0),
       true
from public.school_classes c
join public.exam_levels el on el.id = c.exam_level_id
join public.series sr on sr.id = c.series_id
join public.subjects s on s.code = 'litterature' and s.is_active
where el.level_order >= 5
  and c.subsystem = 'francophone'
  and c.sector = 'general'
  and sr.code in ('c','d')
  and not exists (
    select 1 from public.class_subjects cs
    where cs.class_id = c.id and cs.subject_id = s.id
  );

-- A4/A5 use a general Sciences subject; separate Physics/Chemistry/SVT
-- are not listed as separate baccalaureate exam subjects in these series tables.
update public.class_subjects cs
set is_active = false
from public.school_classes c
join public.exam_levels el on el.id = c.exam_level_id
join public.series sr on sr.id = c.series_id
join public.subjects s on true
where cs.class_id = c.id
  and s.id = cs.subject_id
  and cs.is_active
  and el.level_order >= 5
  and c.subsystem = 'francophone'
  and c.sector = 'general'
  and sr.code in ('a4','a5')
  and s.code in ('chimie','physique','svt');

insert into public.class_subjects (class_id, subject_id, is_compulsory, option_group, position, is_active)
select c.id, s.id, true, null,
       coalesce((select max(cs2.position) + 1 from public.class_subjects cs2 where cs2.class_id = c.id), 0)
         + row_number() over (partition by c.id order by s.code) - 1,
       true
from public.school_classes c
join public.exam_levels el on el.id = c.exam_level_id
join public.series sr on sr.id = c.series_id
join public.subjects s on s.code in ('sciences','langues_nationales','education_artistique') and s.is_active
where el.level_order >= 5
  and c.subsystem = 'francophone'
  and c.sector = 'general'
  and sr.code in ('a4','a5')
  and not exists (
    select 1 from public.class_subjects cs
    where cs.class_id = c.id and cs.subject_id = s.id
  );

update public.class_subjects cs
set is_active = true
from public.school_classes c
join public.exam_levels el on el.id = c.exam_level_id
join public.series sr on sr.id = c.series_id
join public.subjects s on true
where cs.class_id = c.id
  and s.id = cs.subject_id
  and el.level_order >= 5
  and c.subsystem = 'francophone'
  and c.sector = 'general'
  and sr.code in ('a4','a5')
  and s.code in ('sciences','langues_nationales','education_artistique')
  and s.is_active;
