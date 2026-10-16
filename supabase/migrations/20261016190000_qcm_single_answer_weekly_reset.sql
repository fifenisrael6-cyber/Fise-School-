-- QCM: un choix par question et par semaine UTC, sans effacer l'historique.
-- Une nouvelle semaine commence automatiquement le lundi (week_start).
create table if not exists public.qcm_weekly_answers (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references auth.users(id) on delete cascade,
  qcm_type text not null check (qcm_type in ('chapter_ai','teacher')),
  question_id uuid not null,
  quiz_id uuid,
  selected_value text not null,
  selected_index integer,
  is_correct boolean not null,
  week_start date not null,
  created_at timestamptz not null default now(),
  constraint qcm_weekly_answers_once unique (student_id, qcm_type, question_id, week_start)
);
create index if not exists qcm_weekly_answers_student_week_idx
  on public.qcm_weekly_answers(student_id, week_start, qcm_type);
alter table public.qcm_weekly_answers enable row level security;
revoke all on public.qcm_weekly_answers from public, anon, authenticated;

create or replace function public.check_chapter_quiz_answer(
  p_quiz_id uuid,
  p_question_id uuid,
  p_selected_option_index integer
) returns jsonb
language plpgsql security definer set search_path = public
as $function$
declare
  v_user uuid := auth.uid();
  v_correct_index integer;
  v_explanation_fr text;
  v_explanation_en text;
  v_options_count integer;
  v_published boolean;
  v_week date := date_trunc('week', now() at time zone 'UTC')::date;
  v_saved public.qcm_weekly_answers%rowtype;
  v_count integer;
  v_correct_count integer;
begin
  if v_user is null then raise exception 'Authentification requise.'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_user and p.role = 'student') then
    raise exception 'Cette fonction est réservée aux élèves.';
  end if;
  select jsonb_array_length(q.options_fr), z.is_published
    into v_options_count, v_published
  from public.chapter_quiz_questions q
  join public.chapter_quizzes z on z.id = q.quiz_id
  where q.id = p_question_id and q.quiz_id = p_quiz_id;
  if not found or v_published is distinct from true then raise exception 'Question de QCM indisponible.'; end if;
  if p_selected_option_index is null or p_selected_option_index < 0 or p_selected_option_index >= v_options_count then
    raise exception 'Choix de réponse invalide.';
  end if;
  select k.correct_option_index, k.explanation_fr, k.explanation_en
    into v_correct_index, v_explanation_fr, v_explanation_en
  from public.chapter_quiz_answer_keys k where k.question_id = p_question_id;
  if not found then raise exception 'Correction indisponible pour cette question.'; end if;

  select * into v_saved from public.qcm_weekly_answers
  where student_id = v_user and qcm_type = 'chapter_ai'
    and question_id = p_question_id and week_start = v_week;
  if not found then
    begin
      insert into public.qcm_weekly_answers(
        student_id,qcm_type,question_id,quiz_id,selected_value,selected_index,is_correct,week_start
      ) values (
        v_user,'chapter_ai',p_question_id,p_quiz_id,p_selected_option_index::text,
        p_selected_option_index,p_selected_option_index = v_correct_index,v_week
      ) returning * into v_saved;
    exception when unique_violation then
      select * into v_saved from public.qcm_weekly_answers
      where student_id = v_user and qcm_type = 'chapter_ai'
        and question_id = p_question_id and week_start = v_week;
    end;
  end if;
  select count(*), count(*) filter (where is_correct)
    into v_count, v_correct_count
  from public.qcm_weekly_answers
  where student_id = v_user and qcm_type = 'chapter_ai' and week_start = v_week;
  return jsonb_build_object(
    'is_correct',v_saved.is_correct,
    'correct_option_index',v_correct_index,
    'selected_option_index',v_saved.selected_index,
    'already_answered',v_saved.created_at < now() - interval '1 second',
    'explanation_fr',coalesce(v_explanation_fr,''),
    'explanation_en',coalesce(v_explanation_en,''),
    'weekly_answered',v_count,'weekly_correct',v_correct_count,
    'weekly_total',v_count,
    'weekly_score',case when v_count = 0 then 0 else round(100.0*v_correct_count/v_count) end
  );
end;
$function$;
revoke all on function public.check_chapter_quiz_answer(uuid,uuid,integer) from public, anon;
grant execute on function public.check_chapter_quiz_answer(uuid,uuid,integer) to authenticated;

create or replace function public.check_assignment_qcm_answer(
  p_question_id uuid,
  p_selected_option text
) returns jsonb
language plpgsql security definer set search_path = public
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
  v_week date := date_trunc('week', now() at time zone 'UTC')::date;
  v_saved public.qcm_weekly_answers%rowtype;
  v_count integer;
  v_correct_count integer;
begin
  if v_user is null then raise exception 'Authentification requise.'; end if;
  select p.role into v_role from public.profiles p where p.id = v_user;
  if v_role is distinct from 'student' then raise exception 'Cette fonction est réservée aux élèves.'; end if;
  if p_selected_option is null or length(trim(p_selected_option)) = 0 then raise exception 'Choix de réponse invalide.'; end if;
  select q.* into v_question from public.assignment_questions q where q.id = p_question_id;
  if not found then raise exception 'Question indisponible.'; end if;
  select a.* into v_assignment from public.assignments a
  where a.id = v_question.assignment_id and a.status = 'published';
  if not found then raise exception 'Ce devoir n’est pas disponible.'; end if;
  if v_assignment.class_id is not null and not exists (
    select 1 from public.class_students cs
    where cs.student_id = v_user and cs.class_id = v_assignment.class_id and cs.is_active = true
  ) then raise exception 'Ce devoir ne correspond pas à ta salle.'; end if;
  if v_question.question_type not in ('qcm', 'true_false') then
    raise exception 'Cette question ne possède pas de correction automatique.';
  end if;

  select * into v_saved from public.qcm_weekly_answers
  where student_id = v_user and qcm_type = 'teacher'
    and question_id = p_question_id and week_start = v_week;
  if found then
    select count(*), count(*) filter (where is_correct) into v_count, v_correct_count
    from public.qcm_weekly_answers where student_id = v_user and qcm_type = 'teacher' and week_start = v_week;
    return jsonb_build_object(
      'is_correct',v_saved.is_correct,'correct_option',v_saved.selected_value,
      'selected_option',v_saved.selected_value,'already_answered',true,
      'weekly_answered',v_count,'weekly_correct',v_correct_count,
      'weekly_total',v_count,'weekly_score',case when v_count = 0 then 0 else round(100.0*v_correct_count/v_count) end
    );
  end if;

  v_options := coalesce(v_question.options, '[]'::jsonb);
  v_correct := trim(coalesce(v_question.correct_answer, ''));
  v_selected := lower(regexp_replace(trim(p_selected_option), '\s+', ' ', 'g'));
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
      else v_correct end;
    v_is_correct := (lower(trim(p_selected_option)) in ('true','vrai','1','yes','oui')) =
                    (lower(trim(v_correct)) in ('true','vrai','1','yes','oui'));
  end if;
  begin
    insert into public.qcm_weekly_answers(
      student_id,qcm_type,question_id,quiz_id,selected_value,is_correct,week_start
    ) values (v_user,'teacher',p_question_id,v_question.assignment_id,p_selected_option,v_is_correct,v_week)
    returning * into v_saved;
  exception when unique_violation then
    select * into v_saved from public.qcm_weekly_answers
    where student_id = v_user and qcm_type = 'teacher'
      and question_id = p_question_id and week_start = v_week;
  end;
  select count(*), count(*) filter (where is_correct) into v_count, v_correct_count
  from public.qcm_weekly_answers where student_id = v_user and qcm_type = 'teacher' and week_start = v_week;
  return jsonb_build_object(
    'is_correct',v_saved.is_correct,'correct_option',v_correct_option,
    'selected_option',v_saved.selected_value,'already_answered',v_saved.created_at < now() - interval '1 second',
    'weekly_answered',v_count,'weekly_correct',v_correct_count,
    'weekly_total',v_count,'weekly_score',case when v_count = 0 then 0 else round(100.0*v_correct_count/v_count) end,
    'message_fr',case when v_saved.is_correct then 'Bonne réponse ! Bravo.' else 'Mauvaise réponse. La bonne réponse est indiquée en vert.' end,
    'message_en',case when v_saved.is_correct then 'Correct answer! Well done.' else 'Incorrect. The correct answer is marked in green.' end
  );
end;
$function$;
revoke all on function public.check_assignment_qcm_answer(uuid,text) from public, anon;
grant execute on function public.check_assignment_qcm_answer(uuid,text) to authenticated;
