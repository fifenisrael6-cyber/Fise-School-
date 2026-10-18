-- Fise School: structured chapter content (additive migration).
-- Reuses subjects, class_subjects, curricula and course_chapters already in production.
-- Does not alter existing courses, offline learning, messages, grades or branding.

create or replace function public.student_can_access_chapter(p_chapter_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.course_chapters ch
    join public.curricula cu on cu.id = ch.curriculum_id
    join public.class_students cs
      on cs.student_id = auth.uid() and cs.is_active
    join public.school_classes sc
      on sc.id = cs.class_id and sc.is_active
    join public.class_subjects csub
      on csub.class_id = sc.id
     and csub.subject_id = cu.subject_id
     and csub.is_active
    where ch.id = p_chapter_id
      and ch.is_active
      and cu.is_active
      and cu.subsystem = sc.subsystem
      and cu.sector = sc.sector
      and (cu.exam_level_id is null or cu.exam_level_id = sc.exam_level_id)
      and (cu.series_id is null or cu.series_id = sc.series_id)
      and (cu.specialty_id is null or cu.specialty_id = sc.specialty_id)
  );
$$;
revoke all on function public.student_can_access_chapter(uuid) from public;
grant execute on function public.student_can_access_chapter(uuid) to authenticated;

create table if not exists public.chapter_content_items (
  id uuid primary key default gen_random_uuid(),
  chapter_id uuid not null references public.course_chapters(id) on delete cascade,
  content_type text not null check (content_type in ('course', 'video', 'pdf')),
  title_fr text not null,
  title_en text not null,
  body_text_fr text,
  body_text_en text,
  external_url text,
  storage_path text,
  position integer not null default 0 check (position >= 0),
  is_published boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chapter_content_title_not_blank
    check (length(trim(title_fr)) > 0 and length(trim(title_en)) > 0),
  constraint chapter_content_source_valid check (
    (content_type = 'course' and (body_text_fr is not null or body_text_en is not null))
    or (content_type = 'video' and (external_url is not null or storage_path is not null))
    or (content_type = 'pdf' and storage_path is not null)
  )
);
create index if not exists chapter_content_items_visible_idx
  on public.chapter_content_items(chapter_id, is_published, position);

create table if not exists public.chapter_exercises (
  id uuid primary key default gen_random_uuid(),
  chapter_id uuid not null references public.course_chapters(id) on delete cascade,
  statement_fr text not null,
  statement_en text not null,
  difficulty text not null default 'medium'
    check (difficulty in ('easy', 'medium', 'hard')),
  position integer not null default 0 check (position >= 0),
  is_published boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chapter_exercise_statement_not_blank
    check (length(trim(statement_fr)) > 0 and length(trim(statement_en)) > 0)
);
create index if not exists chapter_exercises_visible_idx
  on public.chapter_exercises(chapter_id, is_published, position);

-- Corrections are deliberately separated from student-readable exercise statements.
create table if not exists public.chapter_exercise_corrections (
  exercise_id uuid primary key references public.chapter_exercises(id) on delete cascade,
  correction_fr text not null,
  correction_en text not null,
  explanation_fr text,
  explanation_en text,
  updated_at timestamptz not null default now()
);

create table if not exists public.chapter_quizzes (
  id uuid primary key default gen_random_uuid(),
  chapter_id uuid not null references public.course_chapters(id) on delete cascade,
  title_fr text not null,
  title_en text not null,
  description_fr text,
  description_en text,
  position integer not null default 0 check (position >= 0),
  is_published boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chapter_quiz_title_not_blank
    check (length(trim(title_fr)) > 0 and length(trim(title_en)) > 0)
);
create index if not exists chapter_quizzes_visible_idx
  on public.chapter_quizzes(chapter_id, is_published, position);

-- Questions/options are readable by students; the correct answer is not stored here.
create table if not exists public.chapter_quiz_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.chapter_quizzes(id) on delete cascade,
  prompt_fr text not null,
  prompt_en text not null,
  options_fr jsonb not null,
  options_en jsonb not null,
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now(),
  constraint chapter_quiz_options_are_arrays
    check (jsonb_typeof(options_fr) = 'array' and jsonb_typeof(options_en) = 'array'),
  constraint chapter_quiz_prompt_not_blank
    check (length(trim(prompt_fr)) > 0 and length(trim(prompt_en)) > 0)
);
create index if not exists chapter_quiz_questions_position_idx
  on public.chapter_quiz_questions(quiz_id, position);

-- Answer keys and explanations must never be directly readable by students.
create table if not exists public.chapter_quiz_answer_keys (
  question_id uuid primary key references public.chapter_quiz_questions(id) on delete cascade,
  correct_option_index integer not null check (correct_option_index >= 0),
  explanation_fr text,
  explanation_en text,
  updated_at timestamptz not null default now()
);

create table if not exists public.chapter_learning_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  chapter_id uuid not null references public.course_chapters(id) on delete cascade,
  course_read boolean not null default false,
  course_read_at timestamptz,
  last_opened_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(student_id, chapter_id),
  constraint chapter_read_timestamp_consistent
    check (not course_read or course_read_at is not null)
);

create table if not exists public.chapter_exercise_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  exercise_id uuid not null references public.chapter_exercises(id) on delete cascade,
  completed boolean not null default false,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(student_id, exercise_id),
  constraint exercise_completed_timestamp_consistent
    check (not completed or completed_at is not null)
);

create table if not exists public.chapter_quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  quiz_id uuid not null references public.chapter_quizzes(id) on delete cascade,
  attempt_no integer not null default 1 check (attempt_no > 0),
  score integer check (score between 0 and 100),
  answers jsonb not null default '{}'::jsonb,
  corrections jsonb,
  submitted_at timestamptz not null default now(),
  unique(student_id, quiz_id, attempt_no)
);
create index if not exists chapter_quiz_attempts_student_idx
  on public.chapter_quiz_attempts(student_id, submitted_at desc);

-- Only the admin account can create, edit, hide or delete the new content.
-- Students can read only published content for a curriculum attached to their class.
alter table public.chapter_content_items enable row level security;
alter table public.chapter_exercises enable row level security;
alter table public.chapter_exercise_corrections enable row level security;
alter table public.chapter_quizzes enable row level security;
alter table public.chapter_quiz_questions enable row level security;
alter table public.chapter_quiz_answer_keys enable row level security;
alter table public.chapter_learning_progress enable row level security;
alter table public.chapter_exercise_progress enable row level security;
alter table public.chapter_quiz_attempts enable row level security;

drop policy if exists "students read published chapter content" on public.chapter_content_items;
create policy "students read published chapter content"
on public.chapter_content_items for select to authenticated
using (is_published and public.student_can_access_chapter(chapter_id));
drop policy if exists "admins manage chapter content" on public.chapter_content_items;
create policy "admins manage chapter content"
on public.chapter_content_items for all to authenticated
using (public.is_catalog_admin()) with check (public.is_catalog_admin());

drop policy if exists "students read published chapter exercises" on public.chapter_exercises;
create policy "students read published chapter exercises"
on public.chapter_exercises for select to authenticated
using (is_published and public.student_can_access_chapter(chapter_id));
drop policy if exists "admins manage chapter exercises" on public.chapter_exercises;
create policy "admins manage chapter exercises"
on public.chapter_exercises for all to authenticated
using (public.is_catalog_admin()) with check (public.is_catalog_admin());

drop policy if exists "admins manage exercise corrections" on public.chapter_exercise_corrections;
create policy "admins manage exercise corrections"
on public.chapter_exercise_corrections for all to authenticated
using (public.is_catalog_admin()) with check (public.is_catalog_admin());

drop policy if exists "students read published chapter quizzes" on public.chapter_quizzes;
create policy "students read published chapter quizzes"
on public.chapter_quizzes for select to authenticated
using (is_published and public.student_can_access_chapter(chapter_id));
drop policy if exists "admins manage chapter quizzes" on public.chapter_quizzes;
create policy "admins manage chapter quizzes"
on public.chapter_quizzes for all to authenticated
using (public.is_catalog_admin()) with check (public.is_catalog_admin());

drop policy if exists "students read questions of accessible quizzes" on public.chapter_quiz_questions;
create policy "students read questions of accessible quizzes"
on public.chapter_quiz_questions for select to authenticated
using (exists (
  select 1 from public.chapter_quizzes q
  where q.id = quiz_id and q.is_published
    and public.student_can_access_chapter(q.chapter_id)
));
drop policy if exists "admins manage chapter quiz questions" on public.chapter_quiz_questions;
create policy "admins manage chapter quiz questions"
on public.chapter_quiz_questions for all to authenticated
using (public.is_catalog_admin()) with check (public.is_catalog_admin());

drop policy if exists "admins manage quiz answer keys" on public.chapter_quiz_answer_keys;
create policy "admins manage quiz answer keys"
on public.chapter_quiz_answer_keys for all to authenticated
using (public.is_catalog_admin()) with check (public.is_catalog_admin());

drop policy if exists "students manage own chapter progress" on public.chapter_learning_progress;
create policy "students manage own chapter progress"
on public.chapter_learning_progress for all to authenticated
using (student_id = auth.uid() and public.student_can_access_chapter(chapter_id))
with check (student_id = auth.uid() and public.student_can_access_chapter(chapter_id));
drop policy if exists "admins read chapter progress" on public.chapter_learning_progress;
create policy "admins read chapter progress"
on public.chapter_learning_progress for select to authenticated
using (public.is_catalog_admin());

drop policy if exists "students manage own exercise progress" on public.chapter_exercise_progress;
create policy "students manage own exercise progress"
on public.chapter_exercise_progress for all to authenticated
using (
  student_id = auth.uid()
  and exists (
    select 1 from public.chapter_exercises e
    where e.id = exercise_id and e.is_published
      and public.student_can_access_chapter(e.chapter_id)
  )
)
with check (
  student_id = auth.uid()
  and exists (
    select 1 from public.chapter_exercises e
    where e.id = exercise_id and e.is_published
      and public.student_can_access_chapter(e.chapter_id)
  )
);
drop policy if exists "admins read exercise progress" on public.chapter_exercise_progress;
create policy "admins read exercise progress"
on public.chapter_exercise_progress for select to authenticated
using (public.is_catalog_admin());

-- Scores/corrections are written later through a validated server-side quiz submission RPC.
-- Students can only read their own attempts; no direct client insert/update/delete policies.
drop policy if exists "students read own quiz attempts" on public.chapter_quiz_attempts;
create policy "students read own quiz attempts"
on public.chapter_quiz_attempts for select to authenticated
using (student_id = auth.uid());
drop policy if exists "admins read quiz attempts" on public.chapter_quiz_attempts;
create policy "admins read quiz attempts"
on public.chapter_quiz_attempts for select to authenticated
using (public.is_catalog_admin());

-- Correction reveal is an explicit RPC: correction rows themselves stay protected.
create or replace function public.get_chapter_exercise_correction(p_exercise_id uuid)
returns table(correction_fr text, correction_en text, explanation_fr text, explanation_en text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.chapter_exercises e
    where e.id = p_exercise_id
      and e.is_published
      and public.student_can_access_chapter(e.chapter_id)
  ) and not public.is_catalog_admin() then
    raise exception 'Not allowed';
  end if;

  return query
  select c.correction_fr, c.correction_en, c.explanation_fr, c.explanation_en
  from public.chapter_exercise_corrections c
  join public.chapter_exercises e on e.id = c.exercise_id
  where c.exercise_id = p_exercise_id and e.is_published;
end;
$$;
revoke all on function public.get_chapter_exercise_correction(uuid) from public;
grant execute on function public.get_chapter_exercise_correction(uuid) to authenticated;

-- updated_at triggers for the new editable content/progress tables.
drop trigger if exists chapter_content_items_updated_at on public.chapter_content_items;
create trigger chapter_content_items_updated_at before update on public.chapter_content_items
for each row execute function public.set_pedagogy_updated_at();
drop trigger if exists chapter_exercises_updated_at on public.chapter_exercises;
create trigger chapter_exercises_updated_at before update on public.chapter_exercises
for each row execute function public.set_pedagogy_updated_at();
drop trigger if exists chapter_quizzes_updated_at on public.chapter_quizzes;
create trigger chapter_quizzes_updated_at before update on public.chapter_quizzes
for each row execute function public.set_pedagogy_updated_at();
drop trigger if exists chapter_learning_progress_updated_at on public.chapter_learning_progress;
create trigger chapter_learning_progress_updated_at before update on public.chapter_learning_progress
for each row execute function public.set_pedagogy_updated_at();
drop trigger if exists chapter_exercise_progress_updated_at on public.chapter_exercise_progress;
create trigger chapter_exercise_progress_updated_at before update on public.chapter_exercise_progress
for each row execute function public.set_pedagogy_updated_at();
