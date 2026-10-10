-- Restore teacher access to their own published media even if a classroom
-- assignment was later deactivated. New/managed courses remain restricted to
-- the teacher's subsystem and sector; admins retain full access.
drop policy if exists "teachers retain own course management" on public.courses;
create policy "teachers retain own course management"
on public.courses
for all
to authenticated
using (
  public.is_admin()
  or (
    teacher_id = auth.uid()
    and exists (
      select 1
      from public.profiles p
      join public.school_classes sc on sc.id = courses.class_id
      where p.id = auth.uid()
        and p.role = 'teacher'
        and p.subsystem = sc.subsystem
        and p.sector = sc.sector
    )
  )
)
with check (
  public.is_admin()
  or (
    teacher_id = auth.uid()
    and exists (
      select 1
      from public.profiles p
      join public.school_classes sc on sc.id = courses.class_id
      where p.id = auth.uid()
        and p.role = 'teacher'
        and p.subsystem = sc.subsystem
        and p.sector = sc.sector
    )
  )
);

drop policy if exists "teachers retain own resource management" on public.course_resources;
create policy "teachers retain own resource management"
on public.course_resources
for all
to authenticated
using (
  public.is_admin()
  or exists (
    select 1
    from public.courses c
    join public.profiles p on p.id = auth.uid()
    join public.school_classes sc on sc.id = c.class_id
    where c.id = course_resources.course_id
      and c.teacher_id = auth.uid()
      and p.role = 'teacher'
      and p.subsystem = sc.subsystem
      and p.sector = sc.sector
  )
)
with check (
  public.is_admin()
  or exists (
    select 1
    from public.courses c
    join public.profiles p on p.id = auth.uid()
    join public.school_classes sc on sc.id = c.class_id
    where c.id = course_resources.course_id
      and c.teacher_id = auth.uid()
      and p.role = 'teacher'
      and p.subsystem = sc.subsystem
      and p.sector = sc.sector
  )
);

notify pgrst, 'reload schema';
