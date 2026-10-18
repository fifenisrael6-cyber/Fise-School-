-- Final hardening for storage object updates and pedagogical attachments.
-- This migration only changes policies/functions; it does not rewrite previous migrations.

-- A course-resource object may not be moved by an owner into another course's folder.
drop policy if exists "course owners update resources storage" on storage.objects;
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

-- Private-message attachments cannot be moved outside the sender's folder.
drop policy if exists "private message attachments sender upload" on storage.objects;
create policy "private message attachments sender upload"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'private-message-attachments'
  and owner_id = auth.uid()::text
  and split_part(name, '/', 1) = auth.uid()::text
);
