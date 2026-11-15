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

update public.lessons
set pages_json = jsonb_build_array(jsonb_build_object(
  'id', 'legacy-lesson-page-1',
  'position', 1,
  'blocks', jsonb_build_array(
    case when nullif(trim(coalesce(objectives_fr, objectives_en, '')), '') is not null
      then jsonb_build_object('type','section','text_fr','Objectifs','text_en','Objectives')
      else null end,
    case when nullif(trim(coalesce(objectives_fr, objectives_en, '')), '') is not null
      then jsonb_build_object('type','text','text_fr',coalesce(objectives_fr,''),'text_en',coalesce(objectives_en,objectives_fr,'')) else null end,
    case when nullif(trim(coalesce(content_fr, content_en, '')), '') is not null
      then jsonb_build_object('type','section','text_fr','Contenu du cours','text_en','Course content')
      else null end,
    case when nullif(trim(coalesce(content_fr, content_en, '')), '') is not null
      then jsonb_build_object('type','text','text_fr',coalesce(content_fr,''),'text_en',coalesce(content_en,content_fr,'')) else null end,
    case when nullif(trim(coalesce(examples_fr, examples_en, '')), '') is not null
      then jsonb_build_object('type','section','text_fr','Exemples','text_en','Examples')
      else null end,
    case when nullif(trim(coalesce(examples_fr, examples_en, '')), '') is not null
      then jsonb_build_object('type','text','text_fr',coalesce(examples_fr,''),'text_en',coalesce(examples_en,examples_fr,'')) else null end,
    case when nullif(trim(coalesce(summary_fr, summary_en, '')), '') is not null
      then jsonb_build_object('type','section','text_fr','Résumé','text_en','Summary')
      else null end,
    case when nullif(trim(coalesce(summary_fr, summary_en, '')), '') is not null
      then jsonb_build_object('type','text','text_fr',coalesce(summary_fr,''),'text_en',coalesce(summary_en,summary_fr,'')) else null end
  ) - null
))
where jsonb_array_length(pages_json) = 0
  and (
    nullif(trim(coalesce(objectives_fr, objectives_en, '')), '') is not null
    or nullif(trim(coalesce(content_fr, content_en, '')), '') is not null
    or nullif(trim(coalesce(examples_fr, examples_en, '')), '') is not null
    or nullif(trim(coalesce(summary_fr, summary_en, '')), '') is not null
  );

comment on column public.lessons.pages_json is
  'Ordered responsive student lesson pages; each page contains typed content blocks.';

commit;
