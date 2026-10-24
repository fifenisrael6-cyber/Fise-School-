-- Release official AI corrections automatically 24 hours after the exam when the worker
-- completed confidently. Anything requiring review still waits for the teacher.
create or replace function public.evaluation_result_released(p_submission uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.evaluation_scores es
    join public.evaluations e on e.id = es.evaluation_id
    where es.submission_id = p_submission
      and (e.results_visible_at is null or e.results_visible_at <= now())
      and (
        es.validation_status = 'validated'
        or (
          e.exam_id is not null
          and es.correction_status = 'done'
          and not exists (
            select 1
            from public.evaluation_question_results r
            where r.submission_id = es.submission_id
              and r.needs_review
          )
        )
      )
  );
$function$;

create or replace function public.list_my_evaluations()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
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
$function$;

revoke all on function public.evaluation_result_released(uuid) from public, anon;
grant execute on function public.evaluation_result_released(uuid) to authenticated;
revoke all on function public.list_my_evaluations() from public, anon;
grant execute on function public.list_my_evaluations() to authenticated;
