-- Fise School: publish teacher media immediately while retaining admin moderation.
-- The course_resources relation identifies media posts; official chapter/course catalogue is untouched.

alter table public.courses alter column status set default 'published';

update public.courses c
set status = 'published',
    published_at = coalesce(c.published_at, now()),
    updated_at = now()
where c.status = 'draft'
  and c.class_id is not null
  and exists (select 1 from public.course_resources r where r.course_id = c.id);

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
      and c.status = 'published'
      and c.class_id is not null
      and exists (select 1 from public.course_resources r where r.course_id = c.id)
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

drop policy if exists "teachers insert own assigned course media" on public.courses;
create policy "teachers insert own assigned course media"
on public.courses for insert to authenticated
with check (
  teacher_id = auth.uid() and class_id is not null
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher')
  and public.teacher_can_manage_class(class_id, auth.uid())
);

drop policy if exists "teachers update own assigned course media" on public.courses;
create policy "teachers update own assigned course media"
on public.courses for update to authenticated
using (
  teacher_id = auth.uid() and class_id is not null
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher')
  and public.teacher_can_manage_class(class_id, auth.uid())
)
with check (
  teacher_id = auth.uid() and class_id is not null
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher')
  and public.teacher_can_manage_class(class_id, auth.uid())
);

drop policy if exists "teachers delete own assigned course media" on public.courses;
create policy "teachers delete own assigned course media"
on public.courses for delete to authenticated
using (
  teacher_id = auth.uid() and class_id is not null
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher')
  and public.teacher_can_manage_class(class_id, auth.uid())
);

notify pgrst, 'reload schema';
