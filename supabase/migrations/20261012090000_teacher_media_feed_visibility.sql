-- Make teacher-shared media visible without publishing an official course.
-- Teacher media use the existing required curriculum/chapter links; identify them by draft status and attached resources.
-- Official courses/lessons remain administrator-published.

create or replace function public.is_course_media_student(target_course_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.courses c
    join public.class_students cs
      on cs.class_id = c.class_id
     and cs.student_id = auth.uid()
     and cs.is_active
    where c.id = target_course_id
      and c.status = 'draft'
      and c.class_id is not null
      and exists (
        select 1
        from public.course_resources r
        where r.course_id = c.id
      )
  );
$$;

revoke all on function public.is_course_media_student(uuid) from public;
grant execute on function public.is_course_media_student(uuid) to authenticated;

drop policy if exists "students read shared teacher media courses" on public.courses;
create policy "students read shared teacher media courses"
on public.courses
for select
to authenticated
using (public.is_course_media_student(id));

drop policy if exists "course members read resources" on public.course_resources;
create policy "course members read resources"
on public.course_resources
for select
to authenticated
using (
  public.is_course_student(course_id)
  or public.is_course_media_student(course_id)
  or exists (
    select 1
    from public.courses c
    where c.id = course_resources.course_id
      and (c.teacher_id = auth.uid() or public.is_catalog_admin())
  )
);

drop policy if exists "course members read course resources storage" on storage.objects;
create policy "course members read course resources storage"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'course-resources'
  and (
    public.is_admin()
    or public.is_course_student((storage.foldername(name))[1]::uuid)
    or public.is_course_media_student((storage.foldername(name))[1]::uuid)
    or exists (
      select 1
      from public.courses c
      where c.id = (storage.foldername(name))[1]::uuid
        and c.teacher_id = auth.uid()
    )
  )
);

notify pgrst, 'reload schema';
