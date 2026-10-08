-- Retire the legacy Forum feature. Historical migrations are kept for migration-chain integrity.
do $$
begin
  if to_regclass('public.forum_posts') is not null then
    execute 'drop trigger if exists forum_post_notification on public.forum_posts';
  end if;
end $$;

delete from storage.objects where bucket_id = 'forum-attachments';
delete from storage.buckets where id = 'forum-attachments';

drop table if exists public.forum_posts cascade;
drop table if exists public.forum_topics cascade;
drop function if exists public.is_forum_member(uuid);
