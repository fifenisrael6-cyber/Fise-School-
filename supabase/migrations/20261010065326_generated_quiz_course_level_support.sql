-- Support automatic quizzes directly from a published course when it has no lesson rows.
alter table public.course_generated_quizzes
  alter column lesson_id drop not null;

alter table public.course_generated_quizzes
  drop constraint if exists course_generated_quizzes_lesson_id_source_hash_language_key;

create unique index if not exists course_generated_quizzes_source_unique
  on public.course_generated_quizzes (
    course_id,
    (coalesce(lesson_id, '00000000-0000-0000-0000-000000000000'::uuid)),
    source_hash,
    language
  );

drop policy if exists "students read generated quizzes for visible published lessons" on public.course_generated_quizzes;
create policy "students read generated quizzes for visible published lessons"
on public.course_generated_quizzes for select to authenticated
using (
  exists (
    select 1
    from public.courses c
    where c.id = course_generated_quizzes.course_id
      and c.status = 'published'
      and (
        (course_generated_quizzes.lesson_id is null and is_course_student(c.id))
        or exists (
          select 1 from public.lessons l
          where l.id = course_generated_quizzes.lesson_id
            and l.course_id = c.id
            and l.is_published
            and is_lesson_student(l.id)
        )
      )
  )
);

drop policy if exists "students read questions for visible generated quizzes" on public.course_generated_quiz_questions;
create policy "students read questions for visible generated quizzes"
on public.course_generated_quiz_questions for select to authenticated
using (
  exists (
    select 1
    from public.course_generated_quizzes q
    join public.courses c on c.id = q.course_id
    where q.id = course_generated_quiz_questions.quiz_id
      and c.status = 'published'
      and (
        (q.lesson_id is null and is_course_student(c.id))
        or exists (
          select 1 from public.lessons l
          where l.id = q.lesson_id
            and l.course_id = c.id
            and l.is_published
            and is_lesson_student(l.id)
        )
      )
  )
);
