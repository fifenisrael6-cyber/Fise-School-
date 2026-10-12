-- Expose teacher-shared media to active students in the associated classroom.
-- This is additive: existing course/resource/storage policies are preserved.
-- Teacher media stay draft; official course publication remains administrator-only.

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
     and cs.is_active = true
    where c.id = target_course_id
      and c.status = 'draft'
      and c.class_id is not null
      and exists (
        select 1 from public.course_resources r where r.course_id = c.id
      )
  );
$$;

revoke all on function public.is_course_media_student(uuid) from public;
grant execute on function public.is_course_media_student(uuid) to authenticated;

drop policy if exists "students read shared teacher media courses" on public.courses;
create policy "students read shared teacher media courses"
on public.courses for select to authenticated
using (public.is_course_media_student(id));

drop policy if exists "students read shared teacher media resources" on public.course_resources;
create policy "students read shared teacher media resources"
on public.course_resources for select to authenticated
using (public.is_course_media_student(course_id));

drop policy if exists "students read shared teacher media storage" on storage.objects;
create policy "students read shared teacher media storage"
on storage.objects for select to authenticated
using (
  bucket_id = 'course-resources'
  and public.is_course_media_student((storage.foldername(name))[1]::uuid)
);

notify pgrst, 'reload schema';
