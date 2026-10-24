-- Give a student access only to their own corrected PDF after the score is released.
drop policy if exists "students read released correction PDFs" on storage.objects;
create policy "students read released correction PDFs"
on storage.objects for select to authenticated
using (
  bucket_id = 'evaluation-corrections'
  and exists (
    select 1 from public.evaluation_submissions sub
    where sub.corrected_pdf_path = storage.objects.name
      and sub.student_id = auth.uid()
      and public.evaluation_result_released(sub.id)
  )
);

create or replace function public.my_released_correction_pdf_path(p_evaluation uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_result jsonb;
begin
  if v_uid is null then raise exception 'Session requise.'; end if;
  select jsonb_build_object('path', sub.corrected_pdf_path, 'name', sub.corrected_pdf_name)
    into v_result
  from public.evaluation_submissions sub
  where sub.evaluation_id = p_evaluation
    and sub.student_id = v_uid
    and sub.corrected_pdf_path is not null
    and public.evaluation_result_released(sub.id)
  limit 1;
  return coalesce(v_result, jsonb_build_object('path', null, 'name', null));
end;
$$;
revoke all on function public.my_released_correction_pdf_path(uuid) from public, anon;
grant execute on function public.my_released_correction_pdf_path(uuid) to authenticated;
