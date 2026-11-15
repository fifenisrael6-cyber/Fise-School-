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
      (1, case when nullif(trim(coalesce(lesson.objectives_fr, lesson.objectives_en, '')), '') is not null
        then jsonb_build_object('type','section','text_fr','Objectifs','text_en','Objectives') end),
      (2, case when nullif(trim(coalesce(lesson.objectives_fr, lesson.objectives_en, '')), '') is not null
        then jsonb_build_object('type','text','text_fr',coalesce(lesson.objectives_fr,''),'text_en',coalesce(lesson.objectives_en,lesson.objectives_fr,'')) end),
      (3, case when nullif(trim(coalesce(lesson.content_fr, lesson.content_en, '')), '') is not null
        then jsonb_build_object('type','section','text_fr','Contenu du cours','text_en','Course content') end),
      (4, case when nullif(trim(coalesce(lesson.content_fr, lesson.content_en, '')), '') is not null
        then jsonb_build_object('type','text','text_fr',coalesce(lesson.content_fr,''),'text_en',coalesce(lesson.content_en,lesson.content_fr,'')) end),
      (5, case when nullif(trim(coalesce(lesson.examples_fr, lesson.examples_en, '')), '') is not null
        then jsonb_build_object('type','section','text_fr','Exemples','text_en','Examples') end),
      (6, case when nullif(trim(coalesce(lesson.examples_fr, lesson.examples_en, '')), '') is not null
        then jsonb_build_object('type','text','text_fr',coalesce(lesson.examples_fr,''),'text_en',coalesce(lesson.examples_en,lesson.examples_fr,'')) end),
      (7, case when nullif(trim(coalesce(lesson.summary_fr, lesson.summary_en, '')), '') is not null
        then jsonb_build_object('type','section','text_fr','Résumé','text_en','Summary') end),
      (8, case when nullif(trim(coalesce(lesson.summary_fr, lesson.summary_en, '')), '') is not null
        then jsonb_build_object('type','text','text_fr',coalesce(lesson.summary_fr,''),'text_en',coalesce(lesson.summary_en,lesson.summary_fr,'')) end)
    ) as blocks(ord, block)
    where block is not null
  )
))
where jsonb_array_length(lesson.pages_json) = 0
  and (
    nullif(trim(coalesce(lesson.objectives_fr, lesson.objectives_en, '')), '') is not null
    or nullif(trim(coalesce(lesson.content_fr, lesson.content_en, '')), '') is not null
    or nullif(trim(coalesce(lesson.examples_fr, lesson.examples_en, '')), '') is not null
    or nullif(trim(coalesce(lesson.summary_fr, lesson.summary_en, '')), '') is not null
  );

comment on column public.lessons.pages_json is
  'Ordered responsive student lesson pages; each page contains typed content blocks.';

commit;
