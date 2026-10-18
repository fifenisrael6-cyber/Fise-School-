-- Fise School: explicitly require a valid Supabase session for teacher chapter-media writes.
-- Teachers may upload media only; written courses/lessons remain admin-managed.
drop policy if exists "teachers upload chapter media only" on public.chapter_content_items;
create policy "teachers upload chapter media only"
on public.chapter_content_items for insert to authenticated
with check (
  (select auth.uid()) is not null
  and content_type in ('video','pdf','image','audio')
  and created_by = (select auth.uid())
  and public.teacher_can_upload_chapter_media(chapter_id)
);

drop policy if exists "teachers update own chapter media only" on public.chapter_content_items;
create policy "teachers update own chapter media only"
on public.chapter_content_items for update to authenticated
using (
  (select auth.uid()) is not null
  and content_type in ('video','pdf','image','audio')
  and created_by = (select auth.uid())
  and public.teacher_can_upload_chapter_media(chapter_id)
)
with check (
  (select auth.uid()) is not null
  and content_type in ('video','pdf','image','audio')
  and created_by = (select auth.uid())
  and public.teacher_can_upload_chapter_media(chapter_id)
);

drop policy if exists "teachers delete own chapter media only" on public.chapter_content_items;
create policy "teachers delete own chapter media only"
on public.chapter_content_items for delete to authenticated
using (
  (select auth.uid()) is not null
  and content_type in ('video','pdf','image','audio')
  and created_by = (select auth.uid())
  and public.teacher_can_upload_chapter_media(chapter_id)
);

drop policy if exists "teachers upload assigned chapter media files" on storage.objects;
create policy "teachers upload assigned chapter media files"
on storage.objects for insert to authenticated
with check (
  (select auth.uid()) is not null
  and bucket_id = 'chapter-content'
  and public.teacher_can_upload_chapter_media(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "teachers update assigned chapter media files" on storage.objects;
create policy "teachers update assigned chapter media files"
on storage.objects for update to authenticated
using (
  (select auth.uid()) is not null
  and bucket_id = 'chapter-content'
  and owner_id = (select auth.uid())::text
  and public.teacher_can_upload_chapter_media(((storage.foldername(name))[1])::uuid)
)
with check (
  (select auth.uid()) is not null
  and bucket_id = 'chapter-content'
  and owner_id = (select auth.uid())::text
  and public.teacher_can_upload_chapter_media(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "teachers delete assigned chapter media files" on storage.objects;
create policy "teachers delete assigned chapter media files"
on storage.objects for delete to authenticated
using (
  (select auth.uid()) is not null
  and bucket_id = 'chapter-content'
  and owner_id = (select auth.uid())::text
  and public.teacher_can_upload_chapter_media(((storage.foldername(name))[1])::uuid)
);

-- Keep public.courses writes restricted to administrators. Teacher media is
-- stored in chapter_content_items, not in public.courses.
