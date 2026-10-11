-- Restore teacher visibility and management for their own course media.
-- Access is scoped to courses owned by the authenticated teacher; students and
-- unrelated teachers do not gain write access.
drop policy if exists "teachers retain own course management" on public.courses;
create policy "teachers retain own course management"
on public.courses for all to authenticated
using (
  public.is_admin()
  or (teacher_id = auth.uid() and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'teacher'
  ))
)
with check (
  public.is_admin()
  or (teacher_id = auth.uid() and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'teacher'
  ))
);

drop policy if exists "teachers retain own resource management" on public.course_resources;
create policy "teachers retain own resource management"
on public.course_resources for all to authenticated
using (
  public.is_admin()
  or exists (
    select 1 from public.courses c
    join public.profiles p on p.id = auth.uid()
    where c.id = course_resources.course_id
      and c.teacher_id = auth.uid()
      and p.role = 'teacher'
  )
)
with check (
  public.is_admin()
  or exists (
    select 1 from public.courses c
    join public.profiles p on p.id = auth.uid()
    where c.id = course_resources.course_id
      and c.teacher_id = auth.uid()
      and p.role = 'teacher'
  )
);

drop policy if exists "course members read course resources storage" on storage.objects;
drop policy if exists "course owners upload resources storage" on storage.objects;
drop policy if exists "course owners update resources storage" on storage.objects;
drop policy if exists "course owners delete resources storage" on storage.objects;

create policy "course members read course resources storage"
on storage.objects for select to authenticated
using (
  bucket_id = 'course-resources'
  and (
    public.is_admin()
    or public.is_course_student((storage.foldername(name))[1]::uuid)
    or exists (
      select 1 from public.courses c
      where c.id = (storage.foldername(name))[1]::uuid
        and c.teacher_id = auth.uid()
    )
  )
);

create policy "course owners upload resources storage"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'course-resources'
  and (
    public.is_admin()
    or exists (
      select 1 from public.courses c
      join public.profiles p on p.id = auth.uid()
      where c.id = (storage.foldername(name))[1]::uuid
        and c.teacher_id = auth.uid()
        and p.role = 'teacher'
    )
  )
);

create policy "course owners update resources storage"
on storage.objects for update to authenticated
using (
  bucket_id = 'course-resources'
  and (
    public.is_admin()
    or exists (
      select 1 from public.courses c
      where c.id = (storage.foldername(name))[1]::uuid
        and c.teacher_id = auth.uid()
    )
  )
)
with check (bucket_id = 'course-resources');

create policy "course owners delete resources storage"
on storage.objects for delete to authenticated
using (
  bucket_id = 'course-resources'
  and (
    public.is_admin()
    or exists (
      select 1 from public.courses c
      where c.id = (storage.foldername(name))[1]::uuid
        and c.teacher_id = auth.uid()
    )
  )
);

notify pgrst, 'reload schema';
