-- Share one published lesson/media item across equivalent chapters in different series.
-- Additive only: keeps existing content rows and preserves RLS.

create table if not exists public.chapter_content_item_chapters (
  content_item_id uuid not null references public.chapter_content_items(id) on delete cascade,
  chapter_id uuid not null references public.course_chapters(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (content_item_id, chapter_id)
);

create index if not exists chapter_content_item_chapters_chapter_idx
  on public.chapter_content_item_chapters(chapter_id, content_item_id);

alter table public.chapter_content_item_chapters enable row level security;

drop policy if exists "students read linked published chapter content" on public.chapter_content_item_chapters;
create policy "students read linked published chapter content"
on public.chapter_content_item_chapters for select to authenticated
using (
  exists (
    select 1
    from public.chapter_content_items i
    where i.id = content_item_id
      and i.is_published
  )
  and public.student_can_access_chapter(chapter_id)
);

drop policy if exists "admins manage chapter content links" on public.chapter_content_item_chapters;
create policy "admins manage chapter content links"
on public.chapter_content_item_chapters for all to authenticated
using (public.is_catalog_admin())
with check (public.is_catalog_admin());

create or replace function public.student_can_access_chapter_content(p_content_item_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.chapter_content_items i
    where i.id = p_content_item_id
      and i.is_published
      and public.student_can_access_chapter(i.chapter_id)
  )
  or exists (
    select 1
    from public.chapter_content_item_chapters l
    join public.chapter_content_items i on i.id = l.content_item_id
    where l.content_item_id = p_content_item_id
      and i.is_published
      and public.student_can_access_chapter(l.chapter_id)
  );
$$;

revoke all on function public.student_can_access_chapter_content(uuid) from public;
grant execute on function public.student_can_access_chapter_content(uuid) to authenticated;

drop policy if exists "students read published chapter content" on public.chapter_content_items;
create policy "students read published chapter content"
on public.chapter_content_items for select to authenticated
using (is_published and public.student_can_access_chapter_content(id));

create or replace function public.sync_chapter_content_item_links()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.chapter_content_item_chapters
  where content_item_id = new.id;

  insert into public.chapter_content_item_chapters(content_item_id, chapter_id)
  select new.id, ch.id
  from public.course_chapters source_ch
  join public.curricula source_cu on source_cu.id = source_ch.curriculum_id
  join public.course_chapters ch
    on lower(regexp_replace(trim(ch.title_fr), '\s+', ' ', 'g'))
     = lower(regexp_replace(trim(source_ch.title_fr), '\s+', ' ', 'g'))
  join public.curricula cu on cu.id = ch.curriculum_id
  where source_ch.id = new.chapter_id
    and source_ch.is_active and ch.is_active
    and cu.is_active and source_cu.is_active
    and cu.subject_id = source_cu.subject_id
    and cu.exam_level_id is not distinct from source_cu.exam_level_id
    and cu.subsystem = source_cu.subsystem
    and cu.sector = source_cu.sector
    and cu.specialty_id is not distinct from source_cu.specialty_id
    and cu.teaching_stream is not distinct from source_cu.teaching_stream
  on conflict (content_item_id, chapter_id) do nothing;

  insert into public.chapter_content_item_chapters(content_item_id, chapter_id)
  values (new.id, new.chapter_id)
  on conflict (content_item_id, chapter_id) do nothing;

  return new;
end;
$$;

drop trigger if exists chapter_content_item_links_sync on public.chapter_content_items;
create trigger chapter_content_item_links_sync
after insert or update of chapter_id, title_fr, is_published
on public.chapter_content_items
for each row execute function public.sync_chapter_content_item_links();

insert into public.chapter_content_item_chapters(content_item_id, chapter_id)
select i.id, ch.id
from public.chapter_content_items i
join public.course_chapters source_ch on source_ch.id = i.chapter_id
join public.curricula source_cu on source_cu.id = source_ch.curriculum_id
join public.course_chapters ch
  on lower(regexp_replace(trim(ch.title_fr), '\s+', ' ', 'g'))
   = lower(regexp_replace(trim(source_ch.title_fr), '\s+', ' ', 'g'))
join public.curricula cu on cu.id = ch.curriculum_id
where source_cu.is_active and cu.is_active
  and source_ch.is_active and ch.is_active
  and cu.subject_id = source_cu.subject_id
  and cu.exam_level_id is not distinct from source_cu.exam_level_id
  and cu.subsystem = source_cu.subsystem
  and cu.sector = source_cu.sector
  and cu.specialty_id is not distinct from source_cu.specialty_id
  and cu.teaching_stream is not distinct from source_cu.teaching_stream
on conflict (content_item_id, chapter_id) do nothing;

insert into public.chapter_content_item_chapters(content_item_id, chapter_id)
select id, chapter_id from public.chapter_content_items
on conflict (content_item_id, chapter_id) do nothing;

grant select on public.chapter_content_item_chapters to authenticated;
