-- Teachers can see only published AI-generated chapter quizzes for compatible chapters.
-- Correct-answer keys are intentionally not included in these policies.
drop policy if exists "teachers read published AI chapter quizzes" on public.chapter_quizzes;
create policy "teachers read published AI chapter quizzes"
on public.chapter_quizzes for select to authenticated
using (
  is_published
  and created_by is null
  and public.teacher_can_upload_chapter_media(chapter_id)
);

drop policy if exists "teachers read questions of generated AI chapter quizzes" on public.chapter_quiz_questions;
create policy "teachers read questions of generated AI chapter quizzes"
on public.chapter_quiz_questions for select to authenticated
using (
  exists (
    select 1 from public.chapter_quizzes q
    where q.id = chapter_quiz_questions.quiz_id
      and q.is_published
      and q.created_by is null
      and public.teacher_can_upload_chapter_media(q.chapter_id)
  )
);
