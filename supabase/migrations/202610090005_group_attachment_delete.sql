-- Permet au propriétaire du groupe d'effacer une pièce jointe attachée à un
-- message qu'il est autorisé à supprimer. Le service nettoie le fichier avant
-- de supprimer la ligne du message, afin que la politique puisse vérifier le lien.
drop policy if exists "group message owners delete attachments" on storage.objects;
create policy "group message owners delete attachments"
on storage.objects for delete to authenticated
using (
  bucket_id = 'group-message-attachments'
  and (
    owner_id = (select auth.uid())::text
    or exists (
      select 1
      from public.message_group_messages m
      join public.message_groups g on g.id = m.group_id
      where m.attachment_path = name
        and g.owner_id = (select auth.uid())
    )
  )
);
