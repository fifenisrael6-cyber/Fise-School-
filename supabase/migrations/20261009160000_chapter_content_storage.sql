-- Private storage policies for PDFs and videos attached to published chapters.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chapter-content', 'chapter-content', false, 52428800, array['application/pdf','video/mp4','video/webm'])
on conflict (id) do update set public = false, file_size_limit = 52428800,
  allowed_mime_types = array['application/pdf','video/mp4','video/webm'];

drop policy if exists "admins upload chapter content files" on storage.objects;
create policy "admins upload chapter content files" on storage.objects
for insert to authenticated
with check (bucket_id = 'chapter-content' and public.is_catalog_admin());

drop policy if exists "admins update chapter content files" on storage.objects;
create policy "admins update chapter content files" on storage.objects
for update to authenticated
using (bucket_id = 'chapter-content' and public.is_catalog_admin())
with check (bucket_id = 'chapter-content' and public.is_catalog_admin());

drop policy if exists "admins delete chapter content files" on storage.objects;
create policy "admins delete chapter content files" on storage.objects
for delete to authenticated
using (bucket_id = 'chapter-content' and public.is_catalog_admin());

drop policy if exists "read published chapter content files" on storage.objects;
create policy "read published chapter content files" on storage.objects
for select to authenticated
using (
  bucket_id = 'chapter-content'
  and (
    public.is_catalog_admin()
    or exists (
      select 1 from public.chapter_content_items c
      where c.storage_path = storage.objects.name
        and c.is_published
        and public.student_can_access_chapter(c.chapter_id)
    )
  )
);
