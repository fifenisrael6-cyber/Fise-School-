-- Fise School: message deletion controls.
-- Users can delete only messages they sent; group membership is rechecked server-side.
drop policy if exists "senders delete own private messages" on public.private_messages;
create policy "senders delete own private messages"
on public.private_messages for delete to authenticated
using (sender_id = (select auth.uid()));

drop policy if exists "senders delete own group messages" on public.message_group_messages;
create policy "senders delete own group messages"
on public.message_group_messages for delete to authenticated
using (
  sender_id = (select auth.uid())
  and public.is_message_group_member(group_id)
);

-- Make the storage cleanup permission explicit for group attachments.
drop policy if exists "members delete own group attachments" on storage.objects;
create policy "members delete own group attachments"
on storage.objects for delete to authenticated
using (
  bucket_id = 'group-message-attachments'
  and exists (
    select 1
    from public.message_group_messages m
    where m.attachment_path = name
      and m.sender_id = (select auth.uid())
      and public.is_message_group_member(m.group_id)
  )
);
