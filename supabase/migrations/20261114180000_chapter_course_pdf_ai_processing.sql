-- AI extraction metadata for chapter courses only.
-- The original PDF, pages_json and content_blocks_* remain separate and untouched.
alter table public.chapter_content_items
  add column if not exists processing_status text not null default 'not_started',
  add column if not exists pending_source_pdf_path text,
  add column if not exists processing_error text,
  add column if not exists processed_at timestamptz,
  add column if not exists processing_metadata jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'chapter_content_processing_status_check'
      and conrelid = 'public.chapter_content_items'::regclass
  ) then
    alter table public.chapter_content_items
      add constraint chapter_content_processing_status_check
      check (processing_status in (
        'not_started', 'processing', 'review_required', 'ready', 'failed'
      ));
  end if;
end $$;

create index if not exists chapter_content_course_processing_status_idx
  on public.chapter_content_items (processing_status, updated_at desc)
  where content_type = 'course';
