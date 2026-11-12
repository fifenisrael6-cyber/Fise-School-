-- Preserve explicitly selected classroom links when an administrator publishes
-- or edits a shared chapter content item.
--
-- The previous trigger deleted every link on UPDATE OF is_published. That
-- erased links created by import-chapter-pdf for other selected classrooms,
-- so students in those classrooms could no longer read the published lesson.
--
-- Keep link synchronization additive: discover equivalent chapter folders and
-- ensure the source chapter is linked, but never delete explicit classroom links.
-- Publication status is enforced by the content-item RLS policy, not by links.

create or replace function public.sync_chapter_content_item_links()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.chapter_content_item_chapters(content_item_id, chapter_id)
  select new.id, ch.id
  from public.course_chapters source_ch
  join public.curricula source_cu on source_cu.id = source_ch.curriculum_id
  join public.course_chapters ch
    on lower(regexp_replace(trim(ch.title_fr), '\\s+', ' ', 'g'))
     = lower(regexp_replace(trim(source_ch.title_fr), '\\s+', ' ', 'g'))
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

-- Do not run link synchronization when is_published changes. The old trigger
-- included that column and wiped manually selected target classroom links.
drop trigger if exists chapter_content_item_links_sync on public.chapter_content_items;
create trigger chapter_content_item_links_sync
after insert or update of chapter_id, title_fr
on public.chapter_content_items
for each row execute function public.sync_chapter_content_item_links();

-- Backfill missing source/equivalent links without deleting existing manual links.
insert into public.chapter_content_item_chapters(content_item_id, chapter_id)
select i.id, ch.id
from public.chapter_content_items i
join public.course_chapters source_ch on source_ch.id = i.chapter_id
join public.curricula source_cu on source_cu.id = source_ch.curriculum_id
join public.course_chapters ch
  on lower(regexp_replace(trim(ch.title_fr), '\\s+', ' ', 'g'))
   = lower(regexp_replace(trim(source_ch.title_fr), '\\s+', ' ', 'g'))
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
