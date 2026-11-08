-- Publish official chapter content changes to Supabase Realtime.
-- Idempotent: safe when either table is already in supabase_realtime.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'chapter_content_items'
    ) then
      alter publication supabase_realtime add table public.chapter_content_items;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'course_chapters'
    ) then
      alter publication supabase_realtime add table public.course_chapters;
    end if;

    if to_regclass('public.chapter_content_item_chapters') is not null
      and not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'chapter_content_item_chapters'
      ) then
      alter publication supabase_realtime add table public.chapter_content_item_chapters;
    end if;
  end if;
end
$$;
