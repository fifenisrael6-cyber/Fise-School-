-- Fise School
-- Forum attachments: images, PDF, video and audio files.
-- Files are stored in a private Supabase Storage bucket.

alter table public.forum_posts
  add column if not exists attachment_path text,
  add column if not exists attachment_name text,
  add column if not exists attachment_type text,
  add column if not exists attachment_size bigint;

create index if not exists forum_posts_attachment_idx
  on public.forum_posts (attachment_path)
  where attachment_path is not null;

insert into storage.buckets (id, name, public)
values ('forum-attachments', 'forum-attachments', false)
on conflict (id) do update
set public = false;

drop policy if exists "forum attachments are readable by class members"
  on storage.objects;

create policy "forum attachments are readable by class members"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'forum-attachments'
  and (
    public.is_forum_member(
      split_part(name, '/', 1)::uuid
    )
  )
);

drop policy if exists "forum attachments can be uploaded by members"
  on storage.objects;

create policy "forum attachments can be uploaded by members"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'forum-attachments'
  and (
    public.is_forum_member(
      split_part(name, '/', 1)::uuid
    )
  )
  and owner_id = auth.uid()::text
);

drop policy if exists "forum attachments can be deleted by owner"
  on storage.objects;

create policy "forum attachments can be deleted by owner"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'forum-attachments'
  and owner_id = auth.uid()::text
);