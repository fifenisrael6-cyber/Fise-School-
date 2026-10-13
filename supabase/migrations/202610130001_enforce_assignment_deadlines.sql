-- Enforce assignment deadlines using the database clock, not the student's device.
-- Draft submissions may exist for history/offline preparation, but answer changes
-- and final submission are rejected once the evaluation closes.
create or replace function public.enforce_assignment_submission_window()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_assignment_id uuid;
  assignment_status text;
  assignment_deadline timestamptz;
begin
  if tg_table_name = 'assignment_submissions' then
    target_assignment_id := new.assignment_id;
    if new.status not in ('submitted', 'corrected') then
      return new;
    end if;
  elsif tg_table_name = 'assignment_answers' then
    select s.assignment_id into target_assignment_id
      from public.assignment_submissions s
      where s.id = new.submission_id;
    if target_assignment_id is null then
      raise exception 'Submission not found';
    end if;
  else
    return new;
  end if;

  select a.status, a.due_at
    into assignment_status, assignment_deadline
    from public.assignments a
    where a.id = target_assignment_id;

  if not found then
    raise exception 'Evaluation not found';
  end if;

  if assignment_status <> 'published' then
    raise exception 'This evaluation is not accepting answers';
  end if;

  if assignment_deadline is not null and statement_timestamp() >= assignment_deadline then
    raise exception 'Evaluation deadline has passed; submission is closed';
  end if;

  return new;
end;
$$;

drop trigger if exists assignment_submission_window_guard on public.assignment_submissions;
create trigger assignment_submission_window_guard
before insert or update on public.assignment_submissions
for each row execute function public.enforce_assignment_submission_window();

drop trigger if exists assignment_answer_window_guard on public.assignment_answers;
create trigger assignment_answer_window_guard
before insert or update on public.assignment_answers
for each row execute function public.enforce_assignment_submission_window();
