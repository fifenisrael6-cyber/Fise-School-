-- Historical recovery attempt retained to keep Supabase migration history in sync.
-- This predicate is context-sensitive because teacher_can_manage_class checks auth.uid().
-- The following migration performs the durable recovery using stored teacher/class
-- compatibility instead, so this migration intentionally does not change data.
update public.courses c
set status = 'published',
    published_at = coalesce(c.published_at, now()),
    updated_at = now()
where c.status = 'draft'
  and c.class_id is not null
  and exists (
    select 1 from public.course_resources r
    where r.course_id = c.id
  )
  and exists (
    select 1 from public.profiles p
    where p.id = c.teacher_id and p.role = 'teacher'
  )
  and public.teacher_can_manage_class(c.class_id, c.teacher_id);

notify pgrst, 'reload schema';
