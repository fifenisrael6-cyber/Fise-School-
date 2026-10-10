-- Automatic quizzes generated from published lesson content.
-- Correct answers remain server-only and are returned only after submission.
create table if not exists public.course_generated_quizzes (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  source_hash text not null,
  language text not null check (language in ('fr','en')),
  title text not null,
  created_at timestamptz not null default now(),
  unique (lesson_id, source_hash, language)
);

create table if not exists public.course_generated_quiz_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.course_generated_quizzes(id) on delete cascade,
  position integer not null check (position > 0),
  prompt text not null,
  options jsonb not null check (jsonb_typeof(options) = 'array' and jsonb_array_length(options) between 2 and 4),
  created_at timestamptz not null default now(),
  unique (quiz_id, position)
);

create table if not exists public.course_generated_quiz_answers (
  question_id uuid primary key references public.course_generated_quiz_questions(id) on delete cascade,
  correct_index integer not null check (correct_index between 0 and 3),
  explanation text not null default ''
);

create table if not exists public.course_generated_quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.course_generated_quizzes(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  score integer not null check (score >= 0),
  total integer not null check (total > 0 and score <= total),
  answers jsonb not null default '{}'::jsonb,
  submitted_at timestamptz not null default now()
);

create index if not exists course_generated_quizzes_course_idx
  on public.course_generated_quizzes(course_id, lesson_id, language);
create index if not exists course_generated_quiz_questions_quiz_idx
  on public.course_generated_quiz_questions(quiz_id, position);
create index if not exists course_generated_quiz_attempts_student_idx
  on public.course_generated_quiz_attempts(student_id, submitted_at desc);

alter table public.course_generated_quizzes enable row level security;
alter table public.course_generated_quiz_questions enable row level security;
alter table public.course_generated_quiz_answers enable row level security;
alter table public.course_generated_quiz_attempts enable row level security;

drop policy if exists "students read generated quizzes for visible published lessons" on public.course_generated_quizzes;
create policy "students read generated quizzes for visible published lessons"
on public.course_generated_quizzes for select to authenticated
using (
  exists (
    select 1 from public.lessons l
    join public.courses c on c.id = l.course_id
    where l.id = course_generated_quizzes.lesson_id
      and l.is_published
      and c.status = 'published'
  )
);

drop policy if exists "students read questions for visible generated quizzes" on public.course_generated_quiz_questions;
create policy "students read questions for visible generated quizzes"
on public.course_generated_quiz_questions for select to authenticated
using (
  exists (
    select 1 from public.course_generated_quizzes q
    where q.id = course_generated_quiz_questions.quiz_id
  )
);

drop policy if exists "students read their generated quiz attempts" on public.course_generated_quiz_attempts;
create policy "students read their generated quiz attempts"
on public.course_generated_quiz_attempts for select to authenticated
using (student_id = (select auth.uid()));

-- Do not expose answer keys or direct writes through the Data API.
revoke all on public.course_generated_quiz_answers from anon, authenticated;
revoke insert, update, delete on public.course_generated_quizzes from anon, authenticated;
revoke insert, update, delete on public.course_generated_quiz_questions from anon, authenticated;
revoke insert, update, delete on public.course_generated_quiz_attempts from anon, authenticated;
grant select on public.course_generated_quizzes, public.course_generated_quiz_questions,
  public.course_generated_quiz_attempts to authenticated;
