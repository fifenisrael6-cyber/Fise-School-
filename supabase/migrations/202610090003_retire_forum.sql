-- Fise School: retrait définitif de l'ancien forum.
-- Les écrans de messagerie et les groupes disposent désormais de leurs propres tables.
-- Cette migration supprime volontairement les anciennes discussions et leurs pièces jointes.

drop trigger if exists forum_topic_notification on public.forum_topics;
drop trigger if exists forum_post_notification on public.forum_posts;

drop function if exists public.notify_forum_post();
drop function if exists public.notify_forum_topic();
drop function if exists public.is_forum_member(uuid);

drop table if exists public.forum_posts cascade;
drop table if exists public.forum_topics cascade;

delete from storage.objects where bucket_id = 'forum-attachments';
delete from storage.buckets where id = 'forum-attachments';

delete from public.notifications where type = 'forum';

notify pgrst, 'reload schema';
