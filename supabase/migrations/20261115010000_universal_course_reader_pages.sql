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

comment on column public.courses.pages_json is
  'Ordered responsive course pages; each page contains typed content blocks.';
comment on column public.chapter_content_items.pages_json is
  'Ordered responsive lesson pages; each page contains typed content blocks.';

commit;
