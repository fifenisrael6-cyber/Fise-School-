-- Complete the evaluation window with a server-side start and end time.
-- Student answer writes are rejected before starts_at and at/after due_at.
-- Teachers/admins can still grade or correct submissions after the window closes.
alter table public.assignments
  add column if not exists starts_at timestamptz;

create index if not exists assignments_window_idx
  on public.assignments (class_id, status, starts_at, due_at);

create or replace function public.enforce_assignment_submission_window()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_assignment_id uuid;
  assignment_status text;
  assignment_start timestamptz;
  assignment_deadline timestamptz;
  target_student_id uuid;
begin
  if tg_table_name = 'assignment_submissions' then
    target_assignment_id := new.assignment_id;
    target_student_id := new.student_id;

    -- Do not prevent teachers from correcting/grading after the student window.
    if auth.uid() is distinct from target_student_id then
      return new;
    end if;

    -- Only enforce the student submission transition; draft rows can be created
    -- before the window, but cannot receive answers or be submitted early.
    if new.status <> 'submitted' then
      return new;
    end if;
  elsif tg_table_name = 'assignment_answers' then
    select s.assignment_id, s.student_id
      into target_assignment_id, target_student_id
      from public.assignment_submissions s
      where s.id = new.submission_id;

    if target_assignment_id is null then
      raise exception 'Submission not found';
    end if;

    -- Staff grading updates are not constrained by the student window.
    if auth.uid() is distinct from target_student_id then
      return new;
    end if;
  else
    return new;
  end if;

  select a.status, a.starts_at, a.due_at
    into assignment_status, assignment_start, assignment_deadline
    from public.assignments a
    where a.id = target_assignment_id;

  if not found then
    raise exception 'Evaluation not found';
  end if;

  if assignment_status <> 'published' then
    raise exception 'This evaluation is not accepting answers';
  end if;

  if assignment_start is not null and statement_timestamp() < assignment_start then
    raise exception 'Evaluation has not started yet';
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
