-- Store AI correction PDFs privately and expose their path only with a released result.
alter table public.evaluation_submissions
  add column if not exists corrected_pdf_path text,
  add column if not exists corrected_pdf_name text;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('evaluation-corrections','evaluation-corrections',false,52428800,array['application/pdf'])
on conflict(id) do update set public=false,file_size_limit=52428800,allowed_mime_types=array['application/pdf'];

drop policy if exists "students read released correction PDFs" on storage.objects;
create policy "students read released correction PDFs"
on storage.objects for select to authenticated
using (
  bucket_id='evaluation-corrections'
  and exists (
    select 1 from public.evaluation_submissions sub
    where sub.corrected_pdf_path=storage.objects.name
      and sub.student_id=auth.uid()
      and public.evaluation_result_released(sub.id)
  )
);

CREATE OR REPLACE FUNCTION public.list_my_evaluations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_rows jsonb;
begin
  if v_uid is null then
    raise exception 'Session requise.';
  end if;

  select coalesce(jsonb_agg(x.item order by x.due_at desc), '[]'::jsonb)
    into v_rows
  from (
    select e.due_at,
      jsonb_build_object(
        'id', e.id,
        'title', e.title,
        'instructions', e.instructions,
        'subject_name_fr', sj.name_fr,
        'subject_name_en', sj.name_en,
        'starts_at', e.starts_at,
        'due_at', e.due_at,
        'duration_minutes', e.duration_minutes,
        'late_policy', e.late_policy,
        'late_grace_minutes', e.late_grace_minutes,
        'late_penalty_percent', e.late_penalty_percent,
        'max_score', e.max_score,
        'status', e.status,
        'pdf_name', e.pdf_name,
        'pdf_path', case when now() >= e.starts_at then e.pdf_path else null end,
        'submission', (
          select jsonb_build_object(
            'id', s.id, 'status', s.status, 'submitted_at', s.submitted_at,
            'is_late', s.is_late, 'late_minutes', s.late_minutes, 'photo_count', s.photo_count)
          from public.evaluation_submissions s
          where s.evaluation_id = e.id and s.student_id = v_uid
        ),
        'result', (
          select jsonb_build_object(
            'final_score', coalesce(es.final_score, es.provisional_score),
            'max_score', es.max_score,
            'penalty_percent', es.penalty_percent,
            'comment', es.teacher_comment,
            'correction_pdf_path', (select s2.corrected_pdf_path from public.evaluation_submissions s2 where s2.id = es.submission_id),
            'correction_pdf_name', (select s2.corrected_pdf_name from public.evaluation_submissions s2 where s2.id = es.submission_id),
            'questions', coalesce((
              select jsonb_agg(jsonb_build_object(
                'label', coalesce(r.question_label, 'Question ' || r.question_key),
                'points', coalesce(r.final_points, r.ai_points),
                'max_points', r.max_points,
                'feedback', coalesce(r.teacher_comment, r.feedback_fr)
              ) order by r.question_key)
              from public.evaluation_question_results r
              where r.submission_id = es.submission_id
            ), '[]'::jsonb))
          from public.evaluation_scores es
          where es.student_id = v_uid and es.evaluation_id = e.id
            and public.evaluation_result_released(es.submission_id)
        )
      ) as item
    from public.evaluations e
    join public.subjects sj on sj.id = e.subject_id
    where e.status in ('published', 'closed')
      and exists (
        select 1 from public.evaluation_classes ec
        where ec.evaluation_id = e.id
          and public.is_student_in_class(ec.class_id, v_uid)
      )
      and public.evaluation_is_visible_to_student(e.id)
  ) x;

  return jsonb_build_object('server_now', now(), 'evaluations', v_rows);
end;
$function$


revoke all on function public.list_my_evaluations() from public, anon;
grant execute on function public.list_my_evaluations() to authenticated;
