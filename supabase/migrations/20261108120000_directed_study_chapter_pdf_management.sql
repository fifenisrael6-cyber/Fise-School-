-- Add chapter-level metadata for directed-study PDFs without replacing existing course links.
-- Existing rows are backfilled from their linked course; all changes are additive.
alter table public.directed_studies
  add column if not exists chapter_id uuid references public.course_chapters(id) on delete set null;

update public.directed_studies td
set chapter_id = c.chapter_id
from public.courses c
where td.course_id = c.id
  and td.chapter_id is null
  and c.chapter_id is not null;

create index if not exists directed_studies_chapter_idx
  on public.directed_studies(chapter_id, status, created_at desc);

-- Administrators can upload and remove files through the management screen.
-- Students still use the existing enrollment-scoped read policy.
drop policy if exists "admins upload directed study files" on storage.objects;
create policy "admins upload directed study files"
on storage.objects for insert to authenticated
with check (bucket_id = 'directed-study-files' and public.is_admin());

drop policy if exists "admins update directed study files" on storage.objects;
create policy "admins update directed study files"
on storage.objects for update to authenticated
using (bucket_id = 'directed-study-files' and public.is_admin())
with check (bucket_id = 'directed-study-files' and public.is_admin());

drop policy if exists "admins delete directed study files" on storage.objects;
create policy "admins delete directed study files"
on storage.objects for delete to authenticated
using (bucket_id = 'directed-study-files' and public.is_admin());
