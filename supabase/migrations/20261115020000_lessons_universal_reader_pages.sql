-- Extend the common responsive page contract to individual lessons.
-- Additive only: original lesson text and existing RLS policies remain unchanged.
begin;

alter table public.lessons
  add column if not exists pages_json jsonb not null default '[]'::jsonb;

alter table public.lessons
  drop constraint if exists lessons_pages_json_array_check;

alter table public.lessons
  add constraint lessons_pages_json_array_check
  check (jsonb_typeof(pages_json) = 'array');

update public.lessons as lesson
set pages_json = jsonb_build_array(jsonb_build_object(
  'id', 'legacy-lesson-page-1',
  'position', 1,
  'blocks', (
    select coalesce(jsonb_agg(block order by ord), '[]'::jsonb)
    from (values
      (1, case when nullif(trim(coalesce(nullif(trim(lesson.objectives_fr), ''), lesson.objectives_en, '')), '') is not null
        then jsonb_build_object('type','section','text_fr','Objectifs','text_en','Objectives') end),
      (2, case when nullif(trim(coalesce(nullif(trim(lesson.objectives_fr), ''), lesson.objectives_en, '')), '') is not null
        then jsonb_build_object('type','text','text_fr',coalesce(lesson.objectives_fr,''),'text_en',coalesce(lesson.objectives_en,lesson.objectives_fr,'')) end),
      (3, case when nullif(trim(coalesce(nullif(trim(lesson.content_fr), ''), lesson.content_en, '')), '') is not null
        then jsonb_build_object('type','section','text_fr','Contenu du cours','text_en','Course content') end),
      (4, case when nullif(trim(coalesce(nullif(trim(lesson.content_fr), ''), lesson.content_en, '')), '') is not null
        then jsonb_build_object('type','text','text_fr',coalesce(lesson.content_fr,''),'text_en',coalesce(lesson.content_en,lesson.content_fr,'')) end),
      (5, case when nullif(trim(coalesce(nullif(trim(lesson.examples_fr), ''), lesson.examples_en, '')), '') is not null
        then jsonb_build_object('type','section','text_fr','Exemples','text_en','Examples') end),
      (6, case when nullif(trim(coalesce(nullif(trim(lesson.examples_fr), ''), lesson.examples_en, '')), '') is not null
        then jsonb_build_object('type','text','text_fr',coalesce(lesson.examples_fr,''),'text_en',coalesce(lesson.examples_en,lesson.examples_fr,'')) end),
      (7, case when nullif(trim(coalesce(nullif(trim(lesson.summary_fr), ''), lesson.summary_en, '')), '') is not null
        then jsonb_build_object('type','section','text_fr','Résumé','text_en','Summary') end),
      (8, case when nullif(trim(coalesce(nullif(trim(lesson.summary_fr), ''), lesson.summary_en, '')), '') is not null
        then jsonb_build_object('type','text','text_fr',coalesce(lesson.summary_fr,''),'text_en',coalesce(lesson.summary_en,lesson.summary_fr,'')) end)
    ) as blocks(ord, block)
    where block is not null
  )
))
where jsonb_array_length(lesson.pages_json) = 0
  and (
    nullif(trim(coalesce(nullif(trim(lesson.objectives_fr), ''), lesson.objectives_en, '')), '') is not null
    or nullif(trim(coalesce(nullif(trim(lesson.content_fr), ''), lesson.content_en, '')), '') is not null
    or nullif(trim(coalesce(nullif(trim(lesson.examples_fr), ''), lesson.examples_en, '')), '') is not null
    or nullif(trim(coalesce(nullif(trim(lesson.summary_fr), ''), lesson.summary_en, '')), '') is not null
  );

comment on column public.lessons.pages_json is
  'Ordered responsive student lesson pages; each page contains typed content blocks.';

-- New lesson publications and legacy text edits keep the same canonical
-- page representation. Explicitly authored pages are never overwritten.
create or replace function public.ensure_lesson_reader_pages()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  should_sync boolean := false;
begin
  if tg_op = 'INSERT' then
    should_sync := coalesce(jsonb_array_length(new.pages_json), 0) = 0;
  else
    should_sync := coalesce(jsonb_array_length(new.pages_json), 0) = 0
      or (new.pages_json is not distinct from old.pages_json
          and (new.objectives_fr is distinct from old.objectives_fr
            or new.objectives_en is distinct from old.objectives_en
            or new.content_fr is distinct from old.content_fr
            or new.content_en is distinct from old.content_en
            or new.examples_fr is distinct from old.examples_fr
            or new.examples_en is distinct from old.examples_en
            or new.summary_fr is distinct from old.summary_fr
            or new.summary_en is distinct from old.summary_en));
  end if;

  if should_sync then
    new.pages_json := jsonb_build_array(jsonb_build_object(
      'id', 'legacy-lesson-page-1',
      'position', 1,
      'blocks', (
        select coalesce(jsonb_agg(v.block order by v.ord)
          filter (where v.block is not null), '[]'::jsonb)
        from (values
          (1, case when nullif(trim(coalesce(nullif(trim(new.objectives_fr), ''), new.objectives_en, '')), '') is not null
            then jsonb_build_object('type','section','text_fr','Objectifs','text_en','Objectives') end),
          (2, case when nullif(trim(coalesce(nullif(trim(new.objectives_fr), ''), new.objectives_en, '')), '') is not null
            then jsonb_build_object('type','text','text_fr',coalesce(new.objectives_fr,''),'text_en',coalesce(new.objectives_en,new.objectives_fr,'')) end),
          (3, case when nullif(trim(coalesce(nullif(trim(new.content_fr), ''), new.content_en, '')), '') is not null
            then jsonb_build_object('type','section','text_fr','Contenu du cours','text_en','Course content') end),
          (4, case when nullif(trim(coalesce(nullif(trim(new.content_fr), ''), new.content_en, '')), '') is not null
            then jsonb_build_object('type','text','text_fr',coalesce(new.content_fr,''),'text_en',coalesce(new.content_en,new.content_fr,'')) end),
          (5, case when nullif(trim(coalesce(nullif(trim(new.examples_fr), ''), new.examples_en, '')), '') is not null
            then jsonb_build_object('type','section','text_fr','Exemples','text_en','Examples') end),
          (6, case when nullif(trim(coalesce(nullif(trim(new.examples_fr), ''), new.examples_en, '')), '') is not null
            then jsonb_build_object('type','text','text_fr',coalesce(new.examples_fr,''),'text_en',coalesce(new.examples_en,new.examples_fr,'')) end),
          (7, case when nullif(trim(coalesce(nullif(trim(new.summary_fr), ''), new.summary_en, '')), '') is not null
            then jsonb_build_object('type','section','text_fr','Résumé','text_en','Summary') end),
          (8, case when nullif(trim(coalesce(nullif(trim(new.summary_fr), ''), new.summary_en, '')), '') is not null
            then jsonb_build_object('type','text','text_fr',coalesce(new.summary_fr,''),'text_en',coalesce(new.summary_en,new.summary_fr,'')) end)
        ) as v(ord, block)
      )
    ));
  end if;
  return new;
end;
$$;

drop trigger if exists lessons_ensure_reader_pages on public.lessons;
create trigger lessons_ensure_reader_pages
before insert or update of objectives_fr, objectives_en, content_fr, content_en,
  examples_fr, examples_en, summary_fr, summary_en, pages_json
on public.lessons
for each row execute function public.ensure_lesson_reader_pages();

commit;
