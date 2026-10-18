-- Fise School: teachers may publish chapter media only.
-- Text lessons and chapter quizzes remain admin-managed.
-- A chapter's published media may be shared with another class only when
-- its subject, level, position and bilingual chapter titles match exactly.
-- This avoids sharing by subject name alone when the programme differs.
create or replace function public.student_can_access_chapter(p_chapter_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.course_chapters source_ch
    join public.curricula source_cu on source_cu.id = source_ch.curriculum_id
    where source_ch.id = p_chapter_id
      and source_ch.is_active
      and source_cu.is_active
      and exists (
        select 1
        from public.course_chapters matching_ch
        join public.curricula cu on cu.id = matching_ch.curriculum_id
        join public.class_students cs
          on cs.student_id = auth.uid() and cs.is_active
        join public.school_classes sc
          on sc.id = cs.class_id and sc.is_active
        join public.class_subjects csub
          on csub.class_id = sc.id
         and csub.subject_id = cu.subject_id
         and csub.is_active
        where matching_ch.is_active
          and cu.is_active
          and cu.subject_id = source_cu.subject_id
          and cu.subsystem = source_cu.subsystem
          and cu.sector = source_cu.sector
          and cu.exam_level_id is not distinct from source_cu.exam_level_id
          and matching_ch.position = source_ch.position
          and lower(trim(matching_ch.title_fr)) = lower(trim(source_ch.title_fr))
          and lower(trim(matching_ch.title_en)) = lower(trim(source_ch.title_en))
          and cu.subsystem = sc.subsystem
          and cu.sector = sc.sector
          and (cu.exam_level_id is null or cu.exam_level_id = sc.exam_level_id)
          and (cu.series_id is null or cu.series_id = sc.series_id)
          and (cu.specialty_id is null or cu.specialty_id = sc.specialty_id)
      )
  );
$function$;
revoke all on function public.student_can_access_chapter(uuid) from public;
grant execute on function public.student_can_access_chapter(uuid) to authenticated;

alter table public.chapter_content_items
  drop constraint if exists chapter_content_items_content_type_check;
alter table public.chapter_content_items
  add constraint chapter_content_items_content_type_check
  check (content_type in ('course','video','pdf','image','audio'));

alter table public.chapter_content_items
  drop constraint if exists chapter_content_source_valid;
alter table public.chapter_content_items
  add constraint chapter_content_source_valid check (
    (content_type = 'course' and (body_text_fr is not null or body_text_en is not null))
    or (content_type = 'video' and (external_url is not null or storage_path is not null))
    or (content_type in ('pdf','image','audio') and storage_path is not null)
  );

create or replace function public.teacher_can_upload_chapter_media(p_chapter_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.course_chapters ch
    join public.curricula cu on cu.id = ch.curriculum_id
    join public.class_subjects csub
      on csub.subject_id = cu.subject_id and csub.is_active
    join public.school_classes sc
      on sc.id = csub.class_id and sc.is_active
    join public.profiles p on p.id = auth.uid() and p.role = 'teacher'
    where ch.id = p_chapter_id
      and ch.is_active
      and cu.is_active
      and cu.subsystem = sc.subsystem
      and cu.sector = sc.sector
      and (cu.exam_level_id is null or cu.exam_level_id = sc.exam_level_id)
      and (cu.series_id is null or cu.series_id = sc.series_id)
      and (cu.specialty_id is null or cu.specialty_id = sc.specialty_id)
      and public.teacher_can_manage_class(sc.id, auth.uid())
  );
$function$;
revoke all on function public.teacher_can_upload_chapter_media(uuid) from public;
grant execute on function public.teacher_can_upload_chapter_media(uuid) to authenticated;

drop policy if exists "teachers read own chapter media" on public.chapter_content_items;
create policy "teachers read own chapter media"
on public.chapter_content_items for select to authenticated
using (
  content_type <> 'course'
  and created_by = auth.uid()
  and public.teacher_can_upload_chapter_media(chapter_id)
);

drop policy if exists "teachers upload chapter media only" on public.chapter_content_items;
create policy "teachers upload chapter media only"
on public.chapter_content_items for insert to authenticated
with check (
  content_type in ('video','pdf','image','audio')
  and created_by = auth.uid()
  and public.teacher_can_upload_chapter_media(chapter_id)
);

drop policy if exists "teachers update own chapter media only" on public.chapter_content_items;
create policy "teachers update own chapter media only"
on public.chapter_content_items for update to authenticated
using (
  content_type in ('video','pdf','image','audio')
  and created_by = auth.uid()
  and public.teacher_can_upload_chapter_media(chapter_id)
)
with check (
  content_type in ('video','pdf','image','audio')
  and created_by = auth.uid()
  and public.teacher_can_upload_chapter_media(chapter_id)
);

drop policy if exists "teachers delete own chapter media only" on public.chapter_content_items;
create policy "teachers delete own chapter media only"
on public.chapter_content_items for delete to authenticated
using (
  content_type in ('video','pdf','image','audio')
  and created_by = auth.uid()
  and public.teacher_can_upload_chapter_media(chapter_id)
);

-- Keep admin control of lesson text and course records; teacher-facing UI must not
-- be able to create or edit course/lesson text.
drop policy if exists "teachers manage assigned courses" on public.courses;
drop policy if exists "teachers manage own courses" on public.courses;
drop policy if exists "admins manage course records" on public.courses;
create policy "admins manage course records"
on public.courses for all to authenticated
using (public.is_admin() or public.is_catalog_admin())
with check (public.is_admin() or public.is_catalog_admin());

drop policy if exists "teachers manage own lessons" on public.lessons;
drop policy if exists "teachers manage assigned course lessons" on public.lessons;
drop policy if exists "admins manage lesson records" on public.lessons;
create policy "admins manage lesson records"
on public.lessons for all to authenticated
using (public.is_admin() or public.is_catalog_admin())
with check (public.is_admin() or public.is_catalog_admin());

-- Private chapter media storage: path starts with <chapter_uuid>/...
drop policy if exists "teachers upload assigned chapter media files" on storage.objects;
create policy "teachers upload assigned chapter media files"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chapter-content'
  and public.teacher_can_upload_chapter_media(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "teachers read assigned chapter media files" on storage.objects;
create policy "teachers read assigned chapter media files"
on storage.objects for select to authenticated
using (
  bucket_id = 'chapter-content'
  and owner_id = auth.uid()::text
  and public.teacher_can_upload_chapter_media(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "teachers update assigned chapter media files" on storage.objects;
create policy "teachers update assigned chapter media files"
on storage.objects for update to authenticated
using (
  bucket_id = 'chapter-content'
  and owner_id = auth.uid()::text
  and public.teacher_can_upload_chapter_media(((storage.foldername(name))[1])::uuid)
)
with check (
  bucket_id = 'chapter-content'
  and owner_id = auth.uid()::text
  and public.teacher_can_upload_chapter_media(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "teachers delete assigned chapter media files" on storage.objects;
create policy "teachers delete assigned chapter media files"
on storage.objects for delete to authenticated
using (
  bucket_id = 'chapter-content'
  and owner_id = auth.uid()::text
  and public.teacher_can_upload_chapter_media(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "students read published chapter media files" on storage.objects;
create policy "students read published chapter media files"
on storage.objects for select to authenticated
using (
  bucket_id = 'chapter-content'
  and exists (
    select 1
    from public.chapter_content_items ci
    where ci.storage_path = objects.name
      and ci.is_published
      and ci.content_type in ('video','pdf','image','audio')
      and public.student_can_access_chapter(ci.chapter_id)
  )
);
