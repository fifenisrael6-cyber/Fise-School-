-- Link official exams to the next unpublished grading period and sync grades after
-- all scheduled official exams for that subject have finished and the student's scores are ready.
create or replace function public.assign_official_evaluation_period()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.exam_id is not null and new.period_id is null then
    select id into new.period_id from public.grade_periods
    where not is_published and coalesce(publish_status,'draft') in ('draft','scheduled','blocked')
    order by position, created_at limit 1;
  end if;
  return new;
end;
$$;
drop trigger if exists evaluations_assign_official_period on public.evaluations;
create trigger evaluations_assign_official_period
before insert or update of exam_id, period_id on public.evaluations
for each row execute function public.assign_official_evaluation_period();
revoke all on function public.assign_official_evaluation_period() from public, anon, authenticated;

update public.evaluations e
set period_id = (
  select gp.id from public.grade_periods gp
  where not gp.is_published and coalesce(gp.publish_status,'draft') in ('draft','scheduled','blocked')
  order by gp.position, gp.created_at limit 1
)
where e.exam_id is not null and e.period_id is null
  and exists (select 1 from public.grade_periods gp where not gp.is_published);

create or replace function public.sync_official_exam_grade()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_period uuid;
  v_official boolean;
  v_all_ready boolean;
  v_avg numeric;
  v_count integer;
begin
  select e.period_id, e.exam_id is not null into v_period, v_official
  from public.evaluations e where e.id = new.evaluation_id;
  if not coalesce(v_official,false) or v_period is null then return new; end if;

  if new.validation_status <> 'validated'
     and (new.correction_status <> 'done'
       or exists (select 1 from public.evaluation_question_results r
                  where r.submission_id=new.submission_id and r.needs_review)) then
    return new;
  end if;

  select not exists (
    select 1 from public.evaluations e
    join public.evaluation_classes ec on ec.evaluation_id=e.id and ec.class_id=new.class_id
    where e.exam_id is not null and e.period_id=v_period and e.subject_id=new.subject_id
      and e.status in ('published','closed') and e.due_at <= now()
      and not exists (
        select 1 from public.evaluation_submissions sub
        join public.evaluation_scores sc on sc.submission_id=sub.id
        where sub.evaluation_id=e.id and sub.student_id=new.student_id
          and (sc.validation_status='validated' or (
            sc.correction_status='done'
            and not exists (select 1 from public.evaluation_question_results qr
              where qr.submission_id=sub.id and qr.needs_review)
          ))
      )
  ) into v_all_ready;
  if not v_all_ready then return new; end if;

  select round(sum((coalesce(sc.final_score,sc.provisional_score)/nullif(sc.max_score,0)*20)
                    * coalesce(e.weight,1)) / nullif(sum(coalesce(e.weight,1)),0),2),
         count(*)
    into v_avg,v_count
  from public.evaluations e
  join public.evaluation_classes ec on ec.evaluation_id=e.id and ec.class_id=new.class_id
  join public.evaluation_submissions sub on sub.evaluation_id=e.id and sub.student_id=new.student_id
  join public.evaluation_scores sc on sc.submission_id=sub.id
  where e.exam_id is not null and e.period_id=v_period and e.subject_id=new.subject_id
    and e.status in ('published','closed') and e.due_at <= now()
    and (sc.validation_status='validated' or (
      sc.correction_status='done'
      and not exists (select 1 from public.evaluation_question_results qr
        where qr.submission_id=sub.id and qr.needs_review)
    ));

  if v_avg is not null and v_count > 0 then
    insert into public.grades(class_id,subject_id,student_id,period_id,score,max_score,
      comment,entered_by,source,evaluation_count)
    values(new.class_id,new.subject_id,new.student_id,v_period,v_avg,20,
      'Moyenne calculée automatiquement à partir des évaluations officielles terminées.',
      null,'official_evaluations',v_count)
    on conflict(student_id,subject_id,period_id) do update set
      score=excluded.score,max_score=20,comment=excluded.comment,source=excluded.source,
      evaluation_count=excluded.evaluation_count,updated_at=now();
  end if;
  return new;
end;
$$;
drop trigger if exists evaluation_scores_sync_official_grade on public.evaluation_scores;
create trigger evaluation_scores_sync_official_grade
after insert or update of correction_status,validation_status,final_score,provisional_score
on public.evaluation_scores for each row execute function public.sync_official_exam_grade();
revoke all on function public.sync_official_exam_grade() from public, anon, authenticated;
