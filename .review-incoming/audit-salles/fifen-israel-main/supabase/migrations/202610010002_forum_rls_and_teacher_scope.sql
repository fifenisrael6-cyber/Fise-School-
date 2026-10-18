-- Fise School: final forum authorization hardening.
-- This is a new migration so previously applied migrations keep their checksums.

create or replace function public.is_forum_member(target_class_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_admin()
    or exists (
      select 1 from public.class_students cs
      where cs.class_id = target_class_id
        and cs.student_id = auth.uid()
        and cs.is_active = true
    )
    or exists (
      select 1 from public.class_teachers ct
      where ct.class_id = target_class_id
        and ct.teacher_id = auth.uid()
        and ct.is_active = true
    );
$$;

revoke all on function public.is_forum_member(uuid) from public;
grant execute on function public.is_forum_member(uuid) to authenticated;

drop policy if exists "forum topics authenticated read" on public.forum_topics;
drop policy if exists "forum topics authenticated insert" on public.forum_topics;
drop policy if exists "forum topics authenticated update" on public.forum_topics;
drop policy if exists "forum topics authenticated delete" on public.forum_topics;
drop policy if exists "forum topics members read" on public.forum_topics;
drop policy if exists "forum topics teachers create" on public.forum_topics;
drop policy if exists "forum topics teachers update" on public.forum_topics;
drop policy if exists "forum topics teachers delete" on public.forum_topics;

create policy "forum topics members read"
on public.forum_topics
for select to authenticated
using (public.is_forum_member(class_id));

create policy "forum topics teachers create"
on public.forum_topics
for insert to authenticated
with check (
  creator_id = auth.uid()
  and (
    public.is_admin()
    or public.teacher_can_manage_class(class_id, auth.uid())
  )
);

create policy "forum topics teachers update"
on public.forum_topics
for update to authenticated
using (
  public.is_admin()
  or public.teacher_can_manage_class(class_id, auth.uid())
)
with check (
  public.is_admin()
  or public.teacher_can_manage_class(class_id, auth.uid())
);

create policy "forum topics teachers delete"
on public.forum_topics
for delete to authenticated
using (
  public.is_admin()
  or public.teacher_can_manage_class(class_id, auth.uid())
);


drop policy if exists "forum posts authenticated read" on public.forum_posts;
drop policy if exists "forum posts authenticated insert" on public.forum_posts;
drop policy if exists "forum posts authenticated update" on public.forum_posts;
drop policy if exists "forum posts authenticated delete" on public.forum_posts;
drop policy if exists "forum posts members read" on public.forum_posts;
drop policy if exists "forum posts members create" on public.forum_posts;
drop policy if exists "forum posts authors update" on public.forum_posts;
drop policy if exists "forum posts authors delete" on public.forum_posts;

create policy "forum posts members read"
on public.forum_posts
for select to authenticated
using (
  exists (
    select 1 from public.forum_topics t
    where t.id = forum_posts.topic_id
      and public.is_forum_member(t.class_id)
  )
);

create policy "forum posts members create"
on public.forum_posts
for insert to authenticated
with check (
  author_id = auth.uid()
  and exists (
    select 1
    from public.forum_topics t
    where t.id = forum_posts.topic_id
      and public.is_forum_member(t.class_id)
      and (
        not t.is_locked
        or public.is_admin()
        or public.teacher_can_manage_class(t.class_id, auth.uid())
      )
  )
);

create policy "forum posts authors update"
on public.forum_posts
for update to authenticated
using (
  author_id = auth.uid()
  or public.is_admin()
  or exists (
    select 1 from public.forum_topics t
    where t.id = forum_posts.topic_id
      and public.teacher_can_manage_class(t.class_id, auth.uid())
  )
)
with check (
  author_id = auth.uid()
  or public.is_admin()
  or exists (
    select 1 from public.forum_topics t
    where t.id = forum_posts.topic_id
      and public.teacher_can_manage_class(t.class_id, auth.uid())
  )
);

create policy "forum posts authors delete"
on public.forum_posts
for delete to authenticated
using (
  author_id = auth.uid()
  or public.is_admin()
  or exists (
    select 1 from public.forum_topics t
    where t.id = forum_posts.topic_id
      and public.teacher_can_manage_class(t.class_id, auth.uid())
  )
);

-- Keep storage aligned with table membership. Administrators can manage all forum files.
drop policy if exists "forum attachments are readable by class members" on storage.objects;
create policy "forum attachments are readable by class members"
on storage.objects for select to authenticated
using (
  bucket_id = 'forum-attachments'
  and public.is_forum_member(split_part(name, '/', 1)::uuid)
);

drop policy if exists "forum attachments can be uploaded by members" on storage.objects;
create policy "forum attachments can be uploaded by members"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'forum-attachments'
  and public.is_forum_member(split_part(name, '/', 1)::uuid)
  and owner_id = auth.uid()::text
);

drop policy if exists "forum attachments can be deleted by owner" on storage.objects;
create policy "forum attachments can be deleted by owner"
on storage.objects for delete to authenticated
using (
  bucket_id = 'forum-attachments'
  and (
    owner_id = auth.uid()::text
    or public.is_admin()
  )
);
