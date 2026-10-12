-- Teacher-owned media management for the official course hierarchy.
-- Teachers may manage only resources they uploaded, and only inside classes
-- they are assigned to. Course/chapter/lesson publication remains unchanged.
alter table public.course_resources
  add column if not exists uploaded_by uuid references public.profiles(id) on delete set null;

-- Attribute legacy resources to the existing course owner where possible.
-- New uploads explicitly set uploaded_by to auth.uid() in the Flutter service.
update public.course_resources r
set uploaded_by = c.teacher_id
from public.courses c
where r.course_id = c.id
  and r.uploaded_by is null;

create index if not exists course_resources_uploaded_by_idx
  on public.course_resources(uploaded_by, created_at desc);

-- Resource metadata: students can read published resources for their class;
-- assigned teachers can read the resource list, but can mutate only their own
-- uploads. Administrators retain moderation access.
drop policy if exists "course members read resources" on public.course_resources;
drop policy if exists "assigned course owners manage resources" on public.course_resources;
drop policy if exists "course owners manage resources" on public.course_resources;
drop policy if exists "course participants read resources" on public.course_resources;
drop policy if exists "uploader or admin inserts resources" on public.course_resources;
drop policy if exists "uploader or admin updates resources" on public.course_resources;
drop policy if exists "uploader or admin deletes resources" on public.course_resources;

create policy "course participants read resources"
on public.course_resources
for select
to authenticated
using (
  public.is_catalog_admin()
  or public.is_course_student(course_id)
  or exists (
    select 1
    from public.courses c
    where c.id = course_resources.course_id
      and c.class_id is not null
      and public.teacher_can_manage_class(c.class_id, auth.uid())
  )
);

create policy "uploader or admin inserts resources"
on public.course_resources
for insert
to authenticated
with check (
  public.is_catalog_admin()
  or (
    uploaded_by = auth.uid()
    and exists (
      select 1
      from public.courses c
      where c.id = course_resources.course_id
        and c.class_id is not null
        and public.teacher_can_manage_class(c.class_id, auth.uid())
    )
  )
);

create policy "uploader or admin updates resources"
on public.course_resources
for update
to authenticated
using (
  public.is_catalog_admin()
  or (
    uploaded_by = auth.uid()
    and exists (
      select 1
      from public.courses c
      where c.id = course_resources.course_id
        and c.class_id is not null
        and public.teacher_can_manage_class(c.class_id, auth.uid())
    )
  )
)
with check (
  public.is_catalog_admin()
  or (
    uploaded_by = auth.uid()
    and exists (
      select 1
      from public.courses c
      where c.id = course_resources.course_id
        and c.class_id is not null
        and public.teacher_can_manage_class(c.class_id, auth.uid())
    )
  )
);

create policy "uploader or admin deletes resources"
on public.course_resources
for delete
to authenticated
using (
  public.is_catalog_admin()
  or (
    uploaded_by = auth.uid()
    and exists (
      select 1
      from public.courses c
      where c.id = course_resources.course_id
        and c.class_id is not null
        and public.teacher_can_manage_class(c.class_id, auth.uid())
    )
  )
);

-- Private Storage objects use the course UUID as their first path segment.
-- Keep the existing bucket and allow assigned teachers to upload/delete their
-- own resource files even when the official course itself belongs to admin.
drop policy if exists "course members read course resources storage" on storage.objects;
drop policy if exists "course owners upload resources storage" on storage.objects;
drop policy if exists "course owners update resources storage" on storage.objects;
drop policy if exists "course owners delete resources storage" on storage.objects;
drop policy if exists "course participants read resource files" on storage.objects;
drop policy if exists "assigned teachers upload resource files" on storage.objects;
drop policy if exists "assigned teachers delete resource files" on storage.objects;

create policy "course participants read resource files"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'course-resources'
  and (
    public.is_catalog_admin()
    or public.is_course_student(((storage.foldername(name))[1])::uuid)
    or exists (
      select 1
      from public.courses c
      where c.id = ((storage.foldername(name))[1])::uuid
        and c.class_id is not null
        and public.teacher_can_manage_class(c.class_id, auth.uid())
    )
  )
);

create policy "assigned teachers upload resource files"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'course-resources'
  and (
    public.is_catalog_admin()
    or exists (
      select 1
      from public.courses c
      where c.id = ((storage.foldername(name))[1])::uuid
        and c.class_id is not null
        and public.teacher_can_manage_class(c.class_id, auth.uid())
    )
  )
);

create policy "assigned teachers delete resource files"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'course-resources'
  and (
    public.is_catalog_admin()
    or exists (
      select 1
      from public.courses c
      where c.id = ((storage.foldername(name))[1])::uuid
        and c.class_id is not null
        and public.teacher_can_manage_class(c.class_id, auth.uid())
    )
  )
);

notify pgrst, 'reload schema';
