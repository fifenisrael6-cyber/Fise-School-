-- Classify resources into chapter folders without changing the existing resource_type API.
-- Existing rows are backfilled from their current resource_type; readers keep working.
alter table public.course_resources
  add column if not exists folder_key text;

update public.course_resources
set folder_key = case lower(coalesce(resource_type, ''))
  when 'video' then 'videos'
  when 'audio' then 'audios'
  when 'exercise' then 'exercises'
  when 'worksheet' then 'exercises'
  when 'work' then 'exercises'
  when 'assignment' then 'exercises'
  when 'text' then 'lessons'
  when 'lesson' then 'lessons'
  else 'documents'
end
where folder_key is null or btrim(folder_key) = '';

alter table public.course_resources
  alter column folder_key set default 'documents';

alter table public.course_resources
  drop constraint if exists course_resources_folder_key_check;
alter table public.course_resources
  add constraint course_resources_folder_key_check
  check (folder_key in ('lessons', 'videos', 'audios', 'documents', 'exercises'));
