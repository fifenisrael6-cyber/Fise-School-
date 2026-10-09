-- The forum UI has been removed; retire its database objects as requested.
-- Keep the empty private storage bucket until it can be removed through the Storage API.
drop policy if exists "forum attachments are readable by class members" on storage.objects;
drop policy if exists "forum attachments can be uploaded by members" on storage.objects;
drop policy if exists "forum attachments can be deleted by owner" on storage.objects;

do $$
declare r record;
begin
  for r in
    select p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('notify_forum_post', 'notify_forum_topic', 'is_forum_member')
  loop
    execute format('drop function if exists public.%I(%s) cascade', r.proname, r.args);
  end loop;
end;
$$;

drop table if exists public.forum_posts cascade;
drop table if exists public.forum_topics cascade;
drop table if exists public.class_forum_messages cascade;
drop table if exists public.class_forums cascade;