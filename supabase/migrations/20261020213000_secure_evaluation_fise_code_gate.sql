-- Apply the shared FISE-code gate to every direct evaluation read path as well as RPCs.
create or replace function public.evaluation_can_read_photo(p_path text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_eval uuid;
  v_student uuid;
  v_class uuid;
begin
  select pp.evaluation_id, pp.student_id into v_eval, v_student
  from public.evaluation_photo_path_parts(p_path) pp;
  if v_eval is null then return false; end if;
  if v_student = auth.uid() then
    return public.evaluation_student_class(v_eval, auth.uid()) is not null;
  end if;
  select s.class_id into v_class from public.evaluation_submissions s
  where s.evaluation_id = v_eval and s.student_id = v_student;
  if v_class is null then return public.evaluation_is_owner(v_eval); end if;
  return public.evaluation_can_review(v_eval, v_class);
end;
$$;

drop policy if exists "evaluation photos read" on public.evaluation_photos;
create policy "evaluation photos read" on public.evaluation_photos
for select to authenticated
using (
  (student_id = auth.uid() and public.evaluation_student_class(evaluation_id, auth.uid()) is not null)
  or public.evaluation_can_review(evaluation_id, class_id)
);

drop policy if exists "evaluation submissions read" on public.evaluation_submissions;
create policy "evaluation submissions read" on public.evaluation_submissions
for select to authenticated
using (
  (student_id = auth.uid() and public.evaluation_is_visible_to_student(evaluation_id))
  or public.evaluation_can_review(evaluation_id, class_id)
);

drop policy if exists "eval scores read" on public.evaluation_scores;
create policy "eval scores read" on public.evaluation_scores
for select to authenticated
using (
  public.evaluation_can_review(evaluation_id, class_id)
  or (student_id = auth.uid()
      and public.evaluation_is_visible_to_student(evaluation_id)
      and public.evaluation_result_released(submission_id))
);

drop policy if exists "eval question results read" on public.evaluation_question_results;
create policy "eval question results read" on public.evaluation_question_results
for select to authenticated
using (
  exists (
    select 1 from public.evaluation_submissions s
    where s.id = evaluation_question_results.submission_id
      and public.evaluation_can_review(s.evaluation_id, s.class_id)
  )
  or (
    student_id = auth.uid()
    and public.evaluation_result_released(submission_id)
    and exists (
      select 1 from public.evaluation_submissions s
      where s.id = evaluation_question_results.submission_id
        and public.evaluation_is_visible_to_student(s.evaluation_id)
    )
  )
);
notify pgrst, 'reload schema';
