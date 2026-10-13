-- Prevent staff/manual API writes from exposing a grade before its release time.
create or replace function public.protect_student_assignment_grades()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_release_at timestamptz;
begin
  -- The guarded publication RPC runs as the database owner and is the only path
  -- that copies private grades into student-visible submission columns early/at release.
  if current_user in ('postgres', 'service_role') then return new; end if;

  if tg_op = 'INSERT' then
    if auth.uid() is not null and auth.uid() = new.student_id
       and (new.score is not null or new.corrected_at is not null
         or new.teacher_feedback_fr is not null or new.teacher_feedback_en is not null
         or new.status not in ('draft', 'submitted')) then
      raise exception 'Students cannot create pre-graded submissions';
    end if;
    return new;
  end if;

  if auth.uid() is not null and auth.uid() = old.student_id then
    if new.score is distinct from old.score
       or new.corrected_at is distinct from old.corrected_at
       or new.teacher_feedback_fr is distinct from old.teacher_feedback_fr
       or new.teacher_feedback_en is distinct from old.teacher_feedback_en
       or new.submitted_at is distinct from old.submitted_at then
      raise exception 'Students cannot modify evaluation grades';
    end if;
    if new.status not in ('draft', 'submitted')
       or (old.status = 'submitted' and new.status = 'draft') then
      raise exception 'Students cannot reopen or mark an evaluation corrected';
    end if;
    return new;
  end if;

  if new.score is distinct from old.score
     or new.teacher_feedback_fr is distinct from old.teacher_feedback_fr
     or new.teacher_feedback_en is distinct from old.teacher_feedback_en
     or new.status = 'corrected' then
    select a.results_publish_at into v_release_at
    from public.assignments a where a.id = new.assignment_id;
    if v_release_at is not null and v_release_at > statement_timestamp() then
      raise exception 'Evaluation results are not released yet';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.protect_student_assignment_answer_grades()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_student_id uuid;
begin
  if current_user in ('postgres', 'service_role') then return new; end if;
  if auth.uid() is null then return new; end if;
  select s.student_id into v_student_id
  from public.assignment_submissions s where s.id = new.submission_id;
  if v_student_id = auth.uid() then
    if tg_op = 'INSERT' then
      if new.is_correct is not null or new.points_awarded is not null
         or new.teacher_feedback_fr is not null or new.teacher_feedback_en is not null then
        raise exception 'Students cannot set evaluation marks';
      end if;
    elsif new.is_correct is distinct from old.is_correct
       or new.points_awarded is distinct from old.points_awarded
       or new.teacher_feedback_fr is distinct from old.teacher_feedback_fr
       or new.teacher_feedback_en is distinct from old.teacher_feedback_en then
      raise exception 'Students cannot modify evaluation marks';
    end if;
  end if;
  return new;
end;
$$;
