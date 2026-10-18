-- Admins can manage all course resource files in Storage.
-- Teachers can manage files only for courses they own and classes they are assigned to.

drop policy if exists "course members read course resources storage" on storage.objects;
drop policy if exists "course owners upload resources storage" on storage.objects;
drop policy if exists "course owners update resources storage" on storage.objects;
drop policy if exists "course owners delete resources storage" on storage.objects;

create policy "course members read course resources storage"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'course-resources'
  and (
    public.is_admin()
    or public.is_course_student((storage.foldername(name))[1]::uuid)
    or exists (
      select 1
      from public.courses c
      where c.id = (storage.foldername(name))[1]::uuid
        and c.teacher_id = auth.uid()
        and public.teacher_can_manage_class(c.class_id, auth.uid())
    )
  )
);

create policy "course owners upload resources storage"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'course-resources'
  and (
    public.is_admin()
    or exists (
      select 1
      from public.courses c
      where c.id = (storage.foldername(name))[1]::uuid
        and c.teacher_id = auth.uid()
        and public.teacher_can_manage_class(c.class_id, auth.uid())
    )
  )
);

create policy "course owners update resources storage"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'course-resources'
  and (
    public.is_admin()
    or exists (
      select 1
      from public.courses c
      where c.id = (storage.foldername(name))[1]::uuid
        and c.teacher_id = auth.uid()
        and public.teacher_can_manage_class(c.class_id, auth.uid())
    )
  )
)
with check (
  bucket_id = 'course-resources'
);

create policy "course owners delete resources storage"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'course-resources'
  and (
    public.is_admin()
    or exists (
      select 1
      from public.courses c
      where c.id = (storage.foldername(name))[1]::uuid
        and c.teacher_id = auth.uid()
        and public.teacher_can_manage_class(c.class_id, auth.uid())
    )
  )
);
