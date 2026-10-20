-- Keep already-authorized students able to read their own submitted photos after an exam closes.
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
  if v_student = auth.uid() then return public.evaluation_is_visible_to_student(v_eval); end if;
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
  (student_id = auth.uid() and public.evaluation_is_visible_to_student(evaluation_id))
  or public.evaluation_can_review(evaluation_id, class_id)
);
