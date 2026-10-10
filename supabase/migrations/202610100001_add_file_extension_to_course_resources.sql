-- Keep course_resources aligned with the Flutter ResourceService payload.
-- Existing rows remain valid; older resources may not have a known extension.
alter table public.course_resources
  add column if not exists file_extension text;

comment on column public.course_resources.file_extension is
  'Lowercase file extension without a leading dot, when known.';

-- Refresh PostgREST metadata so clients can use the new column immediately.
notify pgrst, 'reload schema';
