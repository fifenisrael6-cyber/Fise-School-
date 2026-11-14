-- Universal student course reader content contract.
-- Additive/idempotent migration: keeps all original text, source files, IDs,
-- publication states and existing RLS policies. No policy is disabled or weakened.

begin;

alter table public.courses
  add column if not exists pages_json jsonb not null default '[]'::jsonb;

alter table public.courses
  drop constraint if exists courses_pages_json_array_check;

alter table public.courses
  add constraint courses_pages_json_array_check
  check (jsonb_typeof(pages_json) = 'array');

alter table public.chapter_content_items
  add column if not exists pages_json jsonb not null default '[]'::jsonb;

alter table public.chapter_content_items
  drop constraint if exists chapter_content_pages_json_array_check;

alter table public.chapter_content_items
  add constraint chapter_content_pages_json_array_check
  check (jsonb_typeof(pages_json) = 'array');

-- Backfill the legacy courses catalogue. Existing page structures are never
-- overwritten; rows without page data become one responsive TEXT page.
update public.courses
set pages_json = jsonb_build_array(
  jsonb_build_object(
    'id', 'legacy-page-1',
    'position', 1,
    'blocks', jsonb_build_array(
      jsonb_build_object(
        'type', 'text',
        'text_fr', coalesce(content_fr, ''),
        'text_en', coalesce(content_en, content_fr, '')
      )
    )
  )
)
where jsonb_array_length(pages_json) = 0
  and (
    nullif(trim(coalesce(content_fr, '')), '') is not null
    or nullif(trim(coalesce(content_en, '')), '') is not null
  );

-- Backfill chapter lessons only when the structured page list is empty.
-- Keep the legacy body_text columns intact for old app versions and audit.
update public.chapter_content_items
set pages_json = jsonb_build_array(
  jsonb_build_object(
    'id', 'legacy-page-1',
    'position', 1,
    'blocks', jsonb_build_array(
      jsonb_build_object(
        'type', 'text',
        'text_fr', coalesce(body_text_fr, ''),
        'text_en', coalesce(body_text_en, body_text_fr, '')
      )
    )
  )
)
where content_type = 'course'
  and jsonb_array_length(pages_json) = 0
  and (
    nullif(trim(coalesce(body_text_fr, '')), '') is not null
    or nullif(trim(coalesce(body_text_en, '')), '') is not null
  );

create index if not exists courses_pages_json_published_idx
  on public.courses (updated_at desc)
  where status = 'published';

create index if not exists chapter_content_pages_json_published_idx
  on public.chapter_content_items (updated_at desc)
  where content_type = 'course' and is_published = true;

-- Keep future legacy/admin text publications in the same page contract.
-- Explicit rich pages always win; plain-text forms are wrapped in one TEXT block.
create or replace function public.ensure_course_reader_pages()
returns trigger
language plpgsql
set search_path = public
as $
begin
  if (tg_table_name = 'courses') then
    if coalesce(jsonb_array_length(new.pages_json), 0) = 0
       or (tg_op = 'UPDATE'
           and new.pages_json is not distinct from old.pages_json
           and (new.content_fr is distinct from old.content_fr
                or new.content_en is distinct from old.content_en)) then
      if nullif(trim(coalesce(new.content_fr, '')), '') is not null
         or nullif(trim(coalesce(new.content_en, '')), '') is not null then
        new.pages_json := jsonb_build_array(jsonb_build_object(
          'id', 'legacy-page-1',
          'position', 1,
          'blocks', jsonb_build_array(jsonb_build_object(
            'type', 'text',
            'text_fr', coalesce(new.content_fr, ''),
            'text_en', coalesce(new.content_en, new.content_fr, '')
          ))
        ));
      end if;
    end if;
  elsif (tg_table_name = 'chapter_content_items') then
    if coalesce(jsonb_array_length(new.pages_json), 0) = 0
       or (tg_op = 'UPDATE'
           and new.pages_json is not distinct from old.pages_json
           and (new.body_text_fr is distinct from old.body_text_fr
                or new.body_text_en is distinct from old.body_text_en)) then
      if nullif(trim(coalesce(new.body_text_fr, '')), '') is not null
         or nullif(trim(coalesce(new.body_text_en, '')), '') is not null then
        new.pages_json := jsonb_build_array(jsonb_build_object(
          'id', 'legacy-page-1',
          'position', 1,
          'blocks', jsonb_build_array(jsonb_build_object(
            'type', 'text',
            'text_fr', coalesce(new.body_text_fr, ''),
            'text_en', coalesce(new.body_text_en, new.body_text_fr, '')
          ))
        ));
      end if;
    end if;
  end if;
  return new;
end;
$;

drop trigger if exists courses_ensure_reader_pages on public.courses;
create trigger courses_ensure_reader_pages
before insert or update of content_fr, content_en, pages_json
on public.courses
for each row execute function public.ensure_course_reader_pages();

drop trigger if exists chapter_items_ensure_reader_pages on public.chapter_content_items;
create trigger chapter_items_ensure_reader_pages
before insert or update of body_text_fr, body_text_en, pages_json
on public.chapter_content_items
for each row execute function public.ensure_course_reader_pages();

comment on column public.courses.pages_json is
  'Ordered responsive course pages; each page contains typed content blocks.';
comment on column public.chapter_content_items.pages_json is
  'Ordered responsive lesson pages; each page contains typed content blocks.';

commit;
