-- ─────────────────────────────────────────────────────────────────────────────
-- Réorganise les bonnes réponses des QCM de chapitre DÉJÀ générés par l'IA.
-- À exécuter UNE SEULE FOIS dans Supabase > SQL Editor (pas une migration).
--
-- • Mélange les options (FR et EN avec la même permutation) et répartit la
--   bonne réponse sur A, B, C, D de façon équilibrée dans chaque QCM.
-- • Ne touche PAS aux QCM déjà passés par un élève (sinon l'historique des
--   réponses ne correspondrait plus aux options).
-- • Ne touche pas aux QCM contenant « Toutes les réponses… / Aucune… ».
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  quiz record;
  qst record;
  others int[];
  perm int[];
  target int;
  shift int;
  new_fr jsonb;
  new_en jsonb;
  touched int := 0;
begin
  for quiz in
    select cq.id
    from public.chapter_quizzes cq
    where not exists (
      select 1 from public.chapter_quiz_attempts a where a.quiz_id = cq.id
    )
  loop
    shift := floor(random() * 4)::int;

    for qst in
      select q.id, q.options_fr, q.options_en, k.correct_option_index as correct,
             (row_number() over (order by q.position) - 1)::int as rn
      from public.chapter_quiz_questions q
      join public.chapter_quiz_answer_keys k on k.question_id = q.id
      where q.quiz_id = quiz.id
      order by q.position
    loop
      continue when jsonb_array_length(qst.options_fr) <> 4
                 or jsonb_array_length(qst.options_en) <> 4
                 or qst.correct not between 0 and 3;

      continue when exists (
        select 1 from jsonb_array_elements_text(qst.options_fr || qst.options_en) o
        where o ~* '^(toutes?\s+les\s+(réponses|options|propositions)|aucune?\s+(des|de\s+ces)|all\s+of\s+the\s+above|none\s+of\s+the\s+above)'
      );

      target := (qst.rn + shift) % 4;

      select array_agg(i order by random()) into others
      from generate_series(0, 3) i
      where i <> qst.correct;

      perm := others[1:target] || qst.correct || others[target + 1:3];

      select jsonb_agg(qst.options_fr -> p order by ord) into new_fr
      from unnest(perm) with ordinality as t(p, ord);
      select jsonb_agg(qst.options_en -> p order by ord) into new_en
      from unnest(perm) with ordinality as t(p, ord);

      update public.chapter_quiz_questions
         set options_fr = new_fr, options_en = new_en
       where id = qst.id;
      update public.chapter_quiz_answer_keys
         set correct_option_index = target, updated_at = now()
       where question_id = qst.id;
      touched := touched + 1;
    end loop;
  end loop;

  raise notice 'Questions réorganisées : %', touched;
end $$;
