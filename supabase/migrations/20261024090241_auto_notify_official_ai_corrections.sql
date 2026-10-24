-- Notify students when an official AI correction becomes releasable after 24 hours.
-- Cases requiring review are intentionally held for the teacher.
create or replace function public.notify_evaluation_result(p_score uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $function$
declare
  es public.evaluation_scores%rowtype;
  e public.evaluations%rowtype;
  v_auto_release boolean := false;
begin
  select * into es
  from public.evaluation_scores
  where id = p_score
  for update;
  if not found or es.student_notified_at is not null then
    return false;
  end if;

  select * into e from public.evaluations where id = es.evaluation_id;
  if not found then
    return false;
  end if;

  v_auto_release := e.exam_id is not null
    and es.correction_status = 'done'
    and not exists (
      select 1 from public.evaluation_question_results r
      where r.submission_id = es.submission_id and r.needs_review
    );

  if es.validation_status <> 'validated' and not v_auto_release then
    return false;
  end if;
  if e.results_visible_at is not null and e.results_visible_at > now() then
    return false;
  end if;

  insert into public.notifications (user_id, title, body, type)
  values (
    es.student_id,
    'Correction terminée',
    left(e.title, 160) || ' — votre résultat est disponible.',
    'evaluation_result'
  );
  update public.evaluation_scores set student_notified_at = now() where id = es.id;
  return true;
end;
$function$;

create or replace function public.notify_released_evaluation_results()
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_id uuid;
  v_n integer := 0;
begin
  for v_id in
    select es.id
    from public.evaluation_scores es
    join public.evaluations e on e.id = es.evaluation_id
    where es.student_notified_at is null
      and (e.results_visible_at is null or e.results_visible_at <= now())
      and (
        es.validation_status = 'validated'
        or (
          e.exam_id is not null
          and es.correction_status = 'done'
          and not exists (
            select 1 from public.evaluation_question_results r
            where r.submission_id = es.submission_id and r.needs_review
          )
        )
      )
    limit 500
  loop
    if public.notify_evaluation_result(v_id) then
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$function$;

revoke all on function public.notify_evaluation_result(uuid) from public, anon, authenticated;
revoke all on function public.notify_released_evaluation_results() from public, anon, authenticated;
