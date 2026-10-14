-- Link teacher-authored manual QCMs to a chapter without changing existing assignment data.
alter table public.assignments
  add column if not exists chapter_id uuid references public.course_chapters(id) on delete set null;

create index if not exists assignments_chapter_class_subject_idx
  on public.assignments (chapter_id, class_id, subject_id, status);

comment on column public.assignments.chapter_id is
  'Optional course catalogue chapter selected by the teacher for a manually authored QCM.';
