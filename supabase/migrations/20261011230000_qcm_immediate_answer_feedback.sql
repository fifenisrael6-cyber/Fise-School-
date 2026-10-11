-- Correction immédiate d'une réponse au QCM intelligent.
-- La clé de réponse reste côté serveur.
create or replace function public.check_chapter_quiz_answer(
  p_quiz_id uuid,
  p_question_id uuid,
  p_selected_option_index integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_correct_index integer;
  v_explanation_fr text;
  v_explanation_en text;
  v_options_count integer;
  v_is_published boolean;
begin
  if auth.uid() is null then raise exception 'Authentification requise.'; end if;
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'student') then
    raise exception 'Cette fonction est réservée aux élèves.';
  end if;
  if p_selected_option_index is null or p_selected_option_index < 0 then
    raise exception 'Choix de réponse invalide.';
  end if;

  select jsonb_array_length(q.options_fr), z.is_published
    into v_options_count, v_is_published
  from public.chapter_quiz_questions q
  join public.chapter_quizzes z on z.id = q.quiz_id
  where q.id = p_question_id and q.quiz_id = p_quiz_id;
  if not found or v_is_published is distinct from true then
    raise exception 'Question de QCM indisponible.';
  end if;
  if p_selected_option_index >= v_options_count then raise exception 'Choix de réponse invalide.'; end if;

  select k.correct_option_index, k.explanation_fr, k.explanation_en
    into v_correct_index, v_explanation_fr, v_explanation_en
  from public.chapter_quiz_answer_keys k where k.question_id = p_question_id;
  if not found then raise exception 'Correction indisponible pour cette question.'; end if;

  return jsonb_build_object(
    'is_correct', p_selected_option_index = v_correct_index,
    'explanation_fr', coalesce(v_explanation_fr, ''),
    'explanation_en', coalesce(v_explanation_en, '')
  );
end;
$function$;

revoke all on function public.check_chapter_quiz_answer(uuid, uuid, integer) from public;
revoke all on function public.check_chapter_quiz_answer(uuid, uuid, integer) from anon;
grant execute on function public.check_chapter_quiz_answer(uuid, uuid, integer) to authenticated;
