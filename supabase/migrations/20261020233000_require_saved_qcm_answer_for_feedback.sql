-- Correction instantanée des QCM de devoirs, sans renvoyer la clé de réponse au client.
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
  -- Never reveal the answer key before the selected option has been persisted.
  if not exists (
    select 1
    from public.assignment_answers aa
    join public.assignment_submissions s on s.id = aa.submission_id
    where s.student_id = v_user
      and s.assignment_id = v_assignment.id
      and s.status in ('draft', 'submitted', 'corrected')
      and aa.question_id = v_question.id
      and lower(regexp_replace(trim(coalesce(aa.selected_option, '')), '\s+', ' ', 'g')) = v_selected
  ) then
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

  return jsonb_build_object(
    'is_correct', v_is_correct,
    'correct_option', coalesce(v_correct_option, ''),
    'message_fr', case when v_is_correct then 'Bonne réponse ! Bravo.' else 'Mauvaise réponse. La bonne réponse est indiquée en vert.' end,
    'message_en', case when v_is_correct then 'Correct answer! Well done.' else 'Incorrect. The correct answer is marked in green.' end
  );
end;
$function$;

revoke all on function public.check_assignment_qcm_answer(uuid, text) from public;
revoke all on function public.check_assignment_qcm_answer(uuid, text) from anon;
grant execute on function public.check_assignment_qcm_answer(uuid, text) to authenticated;
