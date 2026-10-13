-- AI grading is stored privately until the administrator's release time.
alter table public.assignments
  add column if not exists results_publish_at timestamptz;

create or replace function public.set_assignment_results_publish_default()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.results_publish_at is null then
    new.results_publish_at := new.due_at;
  end if;
  return new;
end;
$$;

drop trigger if exists assignment_results_publish_default on public.assignments;
create trigger assignment_results_publish_default
before insert or update of due_at, results_publish_at on public.assignments
for each row execute function public.set_assignment_results_publish_default();

create table if not exists public.assignment_private_grades (
  submission_id uuid primary key references public.assignment_submissions(id) on delete cascade,
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  score numeric,
  feedback_fr text,
  feedback_en text,
  details jsonb not null default '[]'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'graded', 'published', 'error')),
  grading_source text not null default 'ai',
  error_message text,
  graded_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists assignment_private_grades_release_idx
  on public.assignment_private_grades(status, assignment_id);

alter table public.assignment_private_grades enable row level security;
drop policy if exists "staff read private assignment grades" on public.assignment_private_grades;
create policy "staff read private assignment grades"
on public.assignment_private_grades for select to authenticated
using (
  exists (
    select 1 from public.assignments a
    where a.id = assignment_private_grades.assignment_id
      and (a.teacher_id = auth.uid() or public.is_catalog_admin())
  )
);

drop policy if exists "staff manage private assignment grades" on public.assignment_private_grades;
create policy "staff manage private assignment grades"
on public.assignment_private_grades for all to authenticated
using (
  exists (
    select 1 from public.assignments a
    where a.id = assignment_private_grades.assignment_id
      and (a.teacher_id = auth.uid() or public.is_catalog_admin())
  )
)
with check (
  exists (
    select 1 from public.assignments a
    where a.id = assignment_private_grades.assignment_id
      and (a.teacher_id = auth.uid() or public.is_catalog_admin())
  )
);

-- Students must never be able to forge grades or mark their own submission corrected.
create or replace function public.protect_student_assignment_grades()
returns trigger
language plpgsql
set search_path = public
as $$
begin
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
    if new.status not in ('draft', 'submitted') or (old.status = 'submitted' and new.status = 'draft') then
      raise exception 'Students cannot mark an evaluation corrected';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_student_assignment_grades on public.assignment_submissions;
create trigger protect_student_assignment_grades
before insert or update on public.assignment_submissions
for each row execute function public.protect_student_assignment_grades();

-- Do not let a student forge objective marks or feedback in answer rows.
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

drop trigger if exists protect_student_assignment_answer_grades on public.assignment_answers;
create trigger protect_student_assignment_answer_grades
before insert or update on public.assignment_answers
for each row execute function public.protect_student_assignment_answer_grades();

-- Grading-only updates must remain possible after the submission deadline.
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
    if auth.uid() is distinct from target_student_id then return new; end if;
    if new.status <> 'submitted' then return new; end if;
  elsif tg_table_name = 'assignment_answers' then
    if tg_op = 'UPDATE'
       and new.answer_text is not distinct from old.answer_text
       and new.selected_option is not distinct from old.selected_option then
      return new;
    end if;
    select s.assignment_id, s.student_id
      into target_assignment_id, target_student_id
      from public.assignment_submissions s
      where s.id = new.submission_id;
    if target_assignment_id is null then raise exception 'Submission not found'; end if;
    if auth.uid() is distinct from target_student_id then return new; end if;
  else
    return new;
  end if;

  select a.status, a.starts_at, a.due_at
    into assignment_status, assignment_start, assignment_deadline
    from public.assignments a where a.id = target_assignment_id;
  if not found then raise exception 'Evaluation not found'; end if;
  if assignment_status <> 'published' then raise exception 'This evaluation is not accepting answers'; end if;
  if assignment_start is not null and statement_timestamp() < assignment_start then
    raise exception 'Evaluation has not started yet';
  end if;
  if assignment_deadline is not null and statement_timestamp() >= assignment_deadline then
    raise exception 'Evaluation deadline has passed; submission is closed';
  end if;
  return new;
end;
$$;

create or replace function public.publish_due_assignment_results()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer := 0;
begin
  -- Copy marks to student-visible rows only once their configured release time arrives.
  with due as (
    select g.submission_id, g.score, g.feedback_fr, g.feedback_en
    from public.assignment_private_grades g
    join public.assignments a on a.id = g.assignment_id
    where g.status = 'graded'
      and g.published_at is null
      and a.results_publish_at is not null
      and a.results_publish_at <= statement_timestamp()
  )
  update public.assignment_submissions s
  set score = due.score,
      teacher_feedback_fr = due.feedback_fr,
      teacher_feedback_en = due.feedback_en,
      corrected_at = statement_timestamp(),
      status = 'corrected',
      updated_at = statement_timestamp()
  from due
  where s.id = due.submission_id
    and s.status = 'submitted';

  get diagnostics affected = row_count;

  update public.assignment_answers aa
  set is_correct = (detail.value->>'is_correct')::boolean,
      points_awarded = nullif(detail.value->>'points_awarded', '')::numeric,
      teacher_feedback_fr = detail.value->>'feedback_fr',
      teacher_feedback_en = detail.value->>'feedback_en',
      updated_at = statement_timestamp()
  from public.assignment_private_grades g
  join public.assignments a on a.id = g.assignment_id
  cross join lateral jsonb_array_elements(g.details) as detail(value)
  where g.submission_id = aa.submission_id
    and g.status = 'graded'
    and g.published_at is null
    and a.results_publish_at is not null
    and a.results_publish_at <= statement_timestamp()
    and aa.question_id::text = detail.value->>'question_id';

  update public.assignment_private_grades g
  set status = 'published', published_at = statement_timestamp(), updated_at = statement_timestamp()
  from public.assignments a
  where a.id = g.assignment_id
    and g.status = 'graded'
    and g.published_at is null
    and a.results_publish_at is not null
    and a.results_publish_at <= statement_timestamp();

  return affected;
end;
$$;

revoke all on function public.publish_due_assignment_results() from public, anon;\ngrant execute on function public.publish_due_assignment_results() to authenticated;
grant execute on function public.publish_due_assignment_results() to service_role;
