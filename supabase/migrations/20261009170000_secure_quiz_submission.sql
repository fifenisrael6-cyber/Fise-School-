-- Secure quiz scoring: answer keys are never directly readable by students.
create or replace function public.submit_chapter_quiz(p_quiz_id uuid, p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_chapter uuid;
  v_total integer;
  v_correct integer;
  v_attempt integer;
  v_attempt_id uuid;
  v_review jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(p_answers) <> 'object' then raise exception 'Answers must be an object'; end if;

  select chapter_id into v_chapter
  from public.chapter_quizzes
  where id = p_quiz_id and is_published;
  if v_chapter is null or not public.student_can_access_chapter(v_chapter) then
    raise exception 'Quiz is not available to this student';
  end if;

  select count(*) into v_total
  from public.chapter_quiz_questions where quiz_id = p_quiz_id;
  if v_total = 0 then raise exception 'Quiz has no questions'; end if;
  if (select count(*) from jsonb_object_keys(p_answers)) <> v_total then
    raise exception 'Answer every question before submitting';
  end if;

  if exists (
    select 1
    from jsonb_each(p_answers) a
    left join public.chapter_quiz_questions q
      on q.id = a.key::uuid and q.quiz_id = p_quiz_id
    where q.id is null
       or jsonb_typeof(a.value) <> 'number'
       or (a.value::text)::integer < 0
       or (a.value::text)::integer >= jsonb_array_length(q.options_fr)
  ) then raise exception 'One or more answers are invalid'; end if;

  select count(*) into v_correct
  from public.chapter_quiz_questions q
  join public.chapter_quiz_answer_keys k on k.question_id = q.id
  join jsonb_each(p_answers) a on a.key::uuid = q.id
  where q.quiz_id = p_quiz_id and (a.value::text)::integer = k.correct_option_index;

  perform pg_advisory_xact_lock(hashtext(v_uid::text || p_quiz_id::text));
  select coalesce(max(attempt_no), 0) + 1 into v_attempt
  from public.chapter_quiz_attempts
  where student_id = v_uid and quiz_id = p_quiz_id;

  insert into public.chapter_quiz_attempts(student_id, quiz_id, attempt_no, score, answers, submitted_at)
  values (v_uid, p_quiz_id, v_attempt, round((coalesce(v_correct,0)::numeric / v_total) * 100)::integer, p_answers, now())
  returning id into v_attempt_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'question_id', q.id,
    'selected_option_index', (p_answers ->> q.id::text)::integer,
    'correct_option_index', k.correct_option_index,
    'is_correct', ((p_answers ->> q.id::text)::integer = k.correct_option_index),
    'explanation_fr', k.explanation_fr,
    'explanation_en', k.explanation_en
  ) order by q.position), '[]'::jsonb)
  into v_review
  from public.chapter_quiz_questions q
  join public.chapter_quiz_answer_keys k on k.question_id = q.id
  where q.quiz_id = p_quiz_id;

  update public.chapter_quiz_attempts set corrections = v_review where id = v_attempt_id;
  return jsonb_build_object(
    'attempt_id', v_attempt_id,
    'attempt_no', v_attempt,
    'score', round((coalesce(v_correct,0)::numeric / v_total) * 100)::integer,
    'correct_answers', coalesce(v_correct,0),
    'total_questions', v_total,
    'review', v_review
  );
end;
$$;
revoke all on function public.submit_chapter_quiz(uuid, jsonb) from public;
revoke all on function public.submit_chapter_quiz(uuid, jsonb) from anon;
grant execute on function public.submit_chapter_quiz(uuid, jsonb) to authenticated;
