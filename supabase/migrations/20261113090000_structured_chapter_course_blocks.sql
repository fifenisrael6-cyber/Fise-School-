-- Structured lesson blocks are added alongside the legacy text/pages fields.
-- This is additive: existing roles, RLS policies, chapter links and course records
-- remain unchanged. Existing readers can continue using body_text/pages_json.

alter table public.chapter_content_items
  add column if not exists content_blocks_fr jsonb not null default '[]'::jsonb,
  add column if not exists content_blocks_en jsonb not null default '[]'::jsonb;

alter table public.chapter_content_items
  drop constraint if exists chapter_content_blocks_fr_array,
  add constraint chapter_content_blocks_fr_array
    check (jsonb_typeof(content_blocks_fr) = 'array'),
  drop constraint if exists chapter_content_blocks_en_array,
  add constraint chapter_content_blocks_en_array
    check (jsonb_typeof(content_blocks_en) = 'array');

-- Preserve all previously published lessons as one TEXT block until an editor
-- or the importer rewrites them into ordered TEXT / FORMULA / DIAGRAM blocks.
update public.chapter_content_items
set content_blocks_fr = jsonb_build_array(
      jsonb_build_object('type', 'TEXT', 'text', body_text_fr)
    )
where jsonb_array_length(content_blocks_fr) = 0
  and nullif(trim(body_text_fr), '') is not null;

update public.chapter_content_items
set content_blocks_en = jsonb_build_array(
      jsonb_build_object('type', 'TEXT', 'text', body_text_en)
    )
where jsonb_array_length(content_blocks_en) = 0
  and nullif(trim(body_text_en), '') is not null;

comment on column public.chapter_content_items.content_blocks_fr is
  'Ordered French lesson blocks: TEXT {text}, FORMULA {latex}, DIAGRAM {storage_path, caption}.';
comment on column public.chapter_content_items.content_blocks_en is
  'Ordered English lesson blocks: TEXT {text}, FORMULA {latex}, DIAGRAM {storage_path, caption}.';
