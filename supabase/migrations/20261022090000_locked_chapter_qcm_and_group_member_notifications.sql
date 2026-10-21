-- Definitive per-question selection for chapter smart quizzes.
-- The answer key remains server-only; students receive feedback only after saving a choice.
create table if not exists public.chapter_quiz_answer_selections (
  student_id uuid not null references public.profiles(id) on delete cascade,
  quiz_id uuid not null references public.chapter_quizzes(id) on delete cascade,
  question_id uuid not null references public.chapter_quiz_questions(id) on delete cascade,
  selected_option_index integer not null check (selected_option_index >= 0),
  is_correct boolean not null,
  selected_at timestamptz not null default now(),
  primary key (student_id, question_id)
);

alter table public.chapter_quiz_answer_selections enable row level security;
drop policy if exists "students read own locked chapter quiz answers" on public.chapter_quiz_answer_selections;
create policy "students read own locked chapter quiz answers"
  on public.chapter_quiz_answer_selections for select to authenticated
  using (student_id = (select auth.uid()));
revoke all on public.chapter_quiz_answer_selections from anon, authenticated;

create or replace function public.check_chapter_quiz_answer(
  p_question_id uuid,
  p_selected_option_index integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_question public.chapter_quiz_questions%rowtype;
  v_quiz public.chapter_quizzes%rowtype;
  v_correct_index integer;
  v_saved public.chapter_quiz_answer_selections%rowtype;
  v_explanation_fr text;
  v_explanation_en text;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_selected_option_index is null or p_selected_option_index < 0 then
    raise exception 'Invalid selected option';
  end if;

  select q.* into v_question
  from public.chapter_quiz_questions q
  where q.id = p_question_id;
  if not found then raise exception 'Question unavailable'; end if;

  select quiz.* into v_quiz
  from public.chapter_quizzes quiz
  where quiz.id = v_question.quiz_id and quiz.is_published;
  if not found or not public.student_can_access_chapter(v_quiz.chapter_id) then
    raise exception 'Quiz is not available to this student';
  end if;

  if p_selected_option_index >= jsonb_array_length(v_question.options_fr)
     or p_selected_option_index >= jsonb_array_length(v_question.options_en) then
    raise exception 'Selected option is out of range';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_uid::text || p_question_id::text));

  select s.* into v_saved
  from public.chapter_quiz_answer_selections s
  where s.student_id = v_uid and s.question_id = p_question_id;

  if found then
    if v_saved.selected_option_index <> p_selected_option_index then
      raise exception 'This answer is already locked and cannot be changed';
    end if;
    select k.correct_option_index, k.explanation_fr, k.explanation_en
      into v_correct_index, v_explanation_fr, v_explanation_en
    from public.chapter_quiz_answer_keys k where k.question_id = p_question_id;
    return jsonb_build_object(
      'selected_option_index', v_saved.selected_option_index,
      'correct_option_index', v_correct_index,
      'is_correct', v_saved.is_correct,
      'explanation_fr', coalesce(v_explanation_fr, ''),
      'explanation_en', coalesce(v_explanation_en, ''),
      'locked', true
    );
  end if;

  select k.correct_option_index, k.explanation_fr, k.explanation_en
    into v_correct_index, v_explanation_fr, v_explanation_en
  from public.chapter_quiz_answer_keys k
  where k.question_id = p_question_id;
  if not found then raise exception 'Answer key unavailable'; end if;

  insert into public.chapter_quiz_answer_selections
    (student_id, quiz_id, question_id, selected_option_index, is_correct)
  values
    (v_uid, v_quiz.id, p_question_id, p_selected_option_index,
     p_selected_option_index = v_correct_index);

  return jsonb_build_object(
    'selected_option_index', p_selected_option_index,
    'correct_option_index', v_correct_index,
    'is_correct', p_selected_option_index = v_correct_index,
    'explanation_fr', coalesce(v_explanation_fr, ''),
    'explanation_en', coalesce(v_explanation_en, ''),
    'locked', true
  );
end;
$function$;

revoke all on function public.check_chapter_quiz_answer(uuid, integer) from public, anon;
grant execute on function public.check_chapter_quiz_answer(uuid, integer) to authenticated;

-- Require submitted answers to match the server-saved immutable choices.
create or replace function public.submit_chapter_quiz(p_quiz_id uuid, p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
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
       or not exists (
         select 1 from public.chapter_quiz_answer_selections saved
         where saved.student_id = v_uid
           and saved.quiz_id = p_quiz_id
           and saved.question_id = q.id
           and saved.selected_option_index = (a.value::text)::integer
       )
  ) then raise exception 'Every answer must be saved and locked before submitting'; end if;

  select count(*) into v_correct
  from public.chapter_quiz_answer_selections saved
  where saved.student_id = v_uid
    and saved.quiz_id = p_quiz_id
    and saved.is_correct;

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
revoke all on function public.submit_chapter_quiz(uuid, jsonb) from public, anon;
grant execute on function public.submit_chapter_quiz(uuid, jsonb) to authenticated;

-- Notify existing group members when someone joins or leaves.
create or replace function public.notify_group_membership_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_group_id uuid;
  v_user_id uuid;
  v_group_name text;
  v_person_name text;
  v_action text;
  recipient record;
begin
  if tg_op = 'INSERT' then
    v_group_id := new.group_id;
    v_user_id := new.user_id;
    v_action := 'joined';
  else
    v_group_id := old.group_id;
    v_user_id := old.user_id;
    v_action := 'left';
  end if;

  select g.name into v_group_name
  from public.message_groups g where g.id = v_group_id;
  if v_group_name is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  select trim(concat(p.first_name, ' ', p.last_name)) into v_person_name
  from public.profiles p where p.id = v_user_id;
  if nullif(trim(v_person_name), '') is null then v_person_name := 'Un membre'; end if;

  for recipient in
    select gm.user_id
    from public.message_group_members gm
    where gm.group_id = v_group_id
      and gm.user_id <> v_user_id
  loop
    insert into public.notifications(user_id, title, body, type, target_type, target_id)
    values (
      recipient.user_id,
      v_group_name,
      case when v_action = 'joined'
        then v_person_name || ' a rejoint le groupe / joined the group'
        else v_person_name || ' a quitté le groupe / left the group'
      end,
      'group_member',
      'group',
      v_group_id
    );
  end loop;

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$function$;

drop trigger if exists message_group_member_notification on public.message_group_members;
create trigger message_group_member_notification
after insert or delete on public.message_group_members
for each row execute function public.notify_group_membership_change();

notify pgrst, 'reload schema';

-- Restore already locked choices when a student returns to the quiz.
create or replace function public.list_locked_chapter_quiz_answers(p_quiz_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_chapter uuid;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select q.chapter_id into v_chapter
  from public.chapter_quizzes q
  where q.id = p_quiz_id and q.is_published;
  if v_chapter is null or not public.student_can_access_chapter(v_chapter) then
    raise exception 'Quiz is not available to this student';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'question_id', s.question_id,
    'selected_option_index', s.selected_option_index,
    'correct_option_index', k.correct_option_index,
    'is_correct', s.is_correct,
    'explanation_fr', coalesce(k.explanation_fr, ''),
    'explanation_en', coalesce(k.explanation_en, ''),
    'locked', true
  )), '[]'::jsonb)
  into v_result
  from public.chapter_quiz_answer_selections s
  join public.chapter_quiz_questions question
    on question.id = s.question_id and question.quiz_id = p_quiz_id
  join public.chapter_quiz_answer_keys k on k.question_id = s.question_id
  where s.student_id = v_uid and s.quiz_id = p_quiz_id;

  return v_result;
end;
$function$;
revoke all on function public.list_locked_chapter_quiz_answers(uuid) from public, anon;
grant execute on function public.list_locked_chapter_quiz_answers(uuid) to authenticated;

-- Ensure membership changes are delivered to live chat screens.
do $publication$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'message_group_members'
     ) then
    alter publication supabase_realtime add table public.message_group_members;
  end if;
end;
$publication$;


-- Enforce the same permanent-choice rule for teacher-authored assignment QCMs.
create table if not exists public.assignment_qcm_locked_answers (
  submission_id uuid not null references public.assignment_submissions(id) on delete cascade,
  question_id uuid not null references public.assignment_questions(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  selected_option text not null,
  locked_at timestamptz not null default now(),
  primary key (submission_id, question_id)
);
alter table public.assignment_qcm_locked_answers enable row level security;
revoke all on public.assignment_qcm_locked_answers from anon, authenticated;

create or replace function public.prevent_locked_assignment_qcm_answer_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if exists (
    select 1 from public.assignment_qcm_locked_answers locked
    where locked.submission_id = old.submission_id
      and locked.question_id = old.question_id
  ) then
    if tg_op = 'DELETE' then
      raise exception 'This QCM answer is locked and cannot be deleted';
    end if;
    if lower(regexp_replace(trim(coalesce(new.selected_option, '')), '\s+', ' ', 'g')) <>
       lower(regexp_replace(trim(coalesce(old.selected_option, '')), '\s+', ' ', 'g')) then
      raise exception 'This QCM answer is locked and cannot be changed';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$function$;

drop trigger if exists assignment_qcm_answer_lock on public.assignment_answers;
create trigger assignment_qcm_answer_lock
before update or delete on public.assignment_answers
for each row execute function public.prevent_locked_assignment_qcm_answer_change();

create or replace function public.check_assignment_qcm_answer(
  p_question_id uuid,
  p_selected_option text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_question public.assignment_questions%rowtype;
  v_assignment public.assignments%rowtype;
  v_correct text;
  v_correct_option text;
  v_selected text;
  v_is_correct boolean := false;
  v_options jsonb;
  v_index integer;
  v_submission_id uuid;
  v_locked_option text;
begin
  if v_user is null then raise exception 'Authentification requise.'; end if;
  select p.role into v_role from public.profiles p where p.id = v_user;
  if v_role is distinct from 'student' then raise exception 'Cette fonction est réservée aux élèves.'; end if;
  if p_selected_option is null or length(trim(p_selected_option)) = 0 then raise exception 'Choix de réponse invalide.'; end if;

  select q.* into v_question from public.assignment_questions q where q.id = p_question_id;
  if not found then raise exception 'Question indisponible.'; end if;

  select a.* into v_assignment from public.assignments a
  where a.id = v_question.assignment_id and a.status in ('published', 'closed');
  if not found then raise exception 'Ce devoir n’est pas disponible.'; end if;

  if not public.student_can_access_assignment(v_assignment.id, v_user) then
    raise exception 'Ce devoir ne correspond pas à ta salle ou à ton programme.';
  end if;

  if v_question.question_type not in ('qcm', 'true_false') then
    raise exception 'Cette question ne possède pas de correction automatique.';
  end if;

  v_options := coalesce(v_question.options, '[]'::jsonb);
  v_correct := trim(coalesce(v_question.correct_answer, ''));
  v_selected := lower(regexp_replace(trim(p_selected_option), '\s+', ' ', 'g'));

  select s.id into v_submission_id
  from public.assignment_answers aa
  join public.assignment_submissions s on s.id = aa.submission_id
  where s.student_id = v_user
    and s.assignment_id = v_assignment.id
    and s.status in ('draft', 'submitted', 'corrected')
    and aa.question_id = v_question.id
    and lower(regexp_replace(trim(coalesce(aa.selected_option, '')), '\s+', ' ', 'g')) = v_selected
  limit 1;
  if v_submission_id is null then
    raise exception 'Save your selected answer before requesting correction';
  end if;

  if v_question.question_type = 'qcm' then
    if jsonb_typeof(v_options) <> 'array' or not exists (
      select 1 from jsonb_array_elements_text(v_options) opt
      where lower(regexp_replace(trim(opt), '\s+', ' ', 'g')) = v_selected
    ) then raise exception 'Cette option ne fait pas partie du QCM.'; end if;

    v_index := case when v_correct ~ '^[0-9]+$' then v_correct::integer else null end;
    if v_index is not null and v_index >= 0 and v_index < jsonb_array_length(v_options) then
      v_correct_option := v_options ->> v_index;
    else
      v_correct_option := v_correct;
    end if;
    v_is_correct := lower(regexp_replace(trim(coalesce(p_selected_option, '')), '\s+', ' ', 'g')) =
                    lower(regexp_replace(trim(coalesce(v_correct_option, '')), '\s+', ' ', 'g'));
  else
    v_correct_option := case
      when lower(v_correct) in ('true','vrai','1','yes','oui') then 'Vrai'
      when lower(v_correct) in ('false','faux','0','no','non') then 'Faux'
      else v_correct
    end;
    v_is_correct := (lower(trim(p_selected_option)) in ('true','vrai','1','yes','oui')) =
                    (lower(trim(v_correct)) in ('true','vrai','1','yes','oui'));
  end if;

  perform pg_advisory_xact_lock(hashtext(v_submission_id::text || p_question_id::text));
  select locked.selected_option into v_locked_option
  from public.assignment_qcm_locked_answers locked
  where locked.submission_id = v_submission_id
    and locked.question_id = p_question_id;
  if found then
    if lower(regexp_replace(trim(v_locked_option), '\s+', ' ', 'g')) <> v_selected then
      raise exception 'This QCM answer is already locked and cannot be changed';
    end if;
  else
    insert into public.assignment_qcm_locked_answers
      (submission_id, question_id, student_id, selected_option)
    values (v_submission_id, p_question_id, v_user, p_selected_option);
  end if;

  return jsonb_build_object(
    'is_correct', v_is_correct,
    'correct_option', coalesce(v_correct_option, ''),
    'message_fr', case when v_is_correct then 'Bonne réponse ! Bravo.' else 'Mauvaise réponse. La bonne réponse est indiquée en vert.' end,
    'message_en', case when v_is_correct then 'Correct answer! Well done.' else 'Incorrect. The correct answer is marked in green.' end
  );
end;
$function$;

revoke all on function public.check_assignment_qcm_answer(uuid, text) from public, anon;
grant execute on function public.check_assignment_qcm_answer(uuid, text) to authenticated;

