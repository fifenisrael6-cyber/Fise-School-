-- Recover teacher media posts whose file uploads succeeded but whose final
-- publish step was interrupted. Only publish posts with persisted resources,
-- an active classroom, and a teacher whose current subsystem/sector matches it.
update public.courses co
set status = 'published',
    published_at = coalesce(co.published_at, now()),
    updated_at = now()
from public.profiles p
join public.school_classes c
  on c.is_active = true
 and c.subsystem = p.subsystem
 and c.sector = p.sector
where co.teacher_id = p.id
  and co.class_id = c.id
  and p.role = 'teacher'
  and p.subsystem is not null
  and p.sector is not null
  and co.status = 'draft'
  and exists (
    select 1
    from public.course_resources r
    where r.course_id = co.id
  );

notify pgrst, 'reload schema';
