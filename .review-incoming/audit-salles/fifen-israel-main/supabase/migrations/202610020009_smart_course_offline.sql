-- Fise School — Smart Course + offline learning (Parts 1–6).
-- IMPORTANT: this migration is intentionally the single SQL migration for this feature.
-- It does not alter forum, payments, messaging, bulletins, or the admin catalogue.

-- ============================================================
-- PART 1 — Remote resource versioning + local-cache support metadata
-- ============================================================
alter table public.course_resources
  add column if not exists updated_at timestamptz not null default now();

alter table public.course_resources
  add column if not exists index_status text not null default 'pending'
    check (index_status in ('pending','indexed','failed')),
  add column if not exists index_error text,
  add column if not exists index_preview text,
  add column if not exists index_word_count integer not null default 0,
  add column if not exists index_approved boolean not null default false,
  add column if not exists indexed_at timestamptz;

alter table public.courses
  add column if not exists smart_lesson_enabled boolean not null default true,
  add column if not exists minimum_exercise_score integer not null default 50
    check (minimum_exercise_score between 0 and 100);

create or replace function public.set_course_resources_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_course_resources_updated_at on public.course_resources;
create trigger trg_course_resources_updated_at
before update on public.course_resources
for each row execute function public.set_course_resources_updated_at();

create index if not exists course_resources_updated_at_idx
  on public.course_resources(course_id, updated_at desc);

-- ============================================================
-- PART 2 — PDF chunks / indexing state
-- ============================================================
create table if not exists public.course_chunks (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  resource_id uuid not null references public.course_resources(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  position integer not null check (position >= 0),
  title text not null,
  content text not null,
  language text not null default 'fr' check (language in ('fr','en')),
  created_at timestamptz not null default now(),
  unique(resource_id, position, language)
);

create index if not exists course_chunks_course_position_idx
  on public.course_chunks(course_id, position, language);
create index if not exists course_chunks_subject_idx
  on public.course_chunks(class_id, subject_id, position, language);

alter table public.course_chunks enable row level security;
drop policy if exists "class members read course chunks" on public.course_chunks;
create policy "class members read course chunks"
on public.course_chunks for select to authenticated
using (
  public.is_course_student(course_id)
  or exists (
    select 1 from public.courses c
    where c.id = course_chunks.course_id
      and (c.teacher_id = auth.uid() or public.is_catalog_admin())
  )
);

-- No INSERT/UPDATE/DELETE policy for authenticated users: writes are server-side.

create or replace function public.approve_course_resource_index(p_resource_id uuid, p_approved boolean default true)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_course public.courses%rowtype;
begin
  select c.* into v_course
  from public.courses c
  join public.course_resources r on r.course_id = c.id
  where r.id = p_resource_id;

  if v_course.id is null then
    raise exception 'Resource not found';
  end if;
  if not (public.is_catalog_admin() or public.teacher_can_manage_class(v_course.class_id, auth.uid())) then
    raise exception 'Not allowed';
  end if;

  update public.course_resources
  set index_approved = p_approved
  where id = p_resource_id
    and index_status = 'indexed';
end;
$$;
revoke all on function public.approve_course_resource_index(uuid, boolean) from public;
grant execute on function public.approve_course_resource_index(uuid, boolean) to authenticated;

-- ============================================================
-- PART 3 — Student progress + generated lessons
-- ============================================================
create table if not exists public.student_lesson_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  last_chunk_id uuid references public.course_chunks(id) on delete set null,
  status text not null default 'not_started'
    check (status in ('not_started','available','completed')),
  updated_at timestamptz not null default now(),
  unique(student_id, subject_id)
);

create index if not exists student_lesson_progress_student_idx
  on public.student_lesson_progress(student_id, updated_at desc);

create table if not exists public.generated_lessons (
  id uuid primary key default gen_random_uuid(),
  chunk_id uuid not null references public.course_chunks(id) on delete cascade,
  language text not null check (language in ('fr','en')),
  text text not null,
  generated_at timestamptz not null default now(),
  unique(chunk_id, language)
);

create index if not exists generated_lessons_chunk_idx
  on public.generated_lessons(chunk_id, language);

alter table public.student_lesson_progress enable row level security;
alter table public.generated_lessons enable row level security;

drop policy if exists "students manage own smart lesson progress" on public.student_lesson_progress;
drop policy if exists "students read own smart lesson progress" on public.student_lesson_progress;
create policy "students read own smart lesson progress"
on public.student_lesson_progress for select to authenticated
using (student_id = auth.uid());

drop policy if exists "teachers read smart lesson progress" on public.student_lesson_progress;
create policy "teachers read smart lesson progress"
on public.student_lesson_progress for select to authenticated
using (public.teacher_can_manage_class(class_id, auth.uid()) or public.is_catalog_admin());

drop policy if exists "students read generated lessons for their class" on public.generated_lessons;
create policy "students read generated lessons for their class"
on public.generated_lessons for select to authenticated
using (
  exists (
    select 1
    from public.course_chunks ch
    where ch.id = generated_lessons.chunk_id
      and (
        public.is_course_student(ch.course_id)
        or exists (select 1 from public.courses c where c.id = ch.course_id and (c.teacher_id = auth.uid() or public.is_catalog_admin()))
      )
  )
);

-- No direct client writes to generated_lessons.

-- ============================================================
-- PART 4 — Generated exercises + secure server-side correction
-- ============================================================
create table if not exists public.generated_exercises (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.generated_lessons(id) on delete cascade,
  chunk_id uuid not null references public.course_chunks(id) on delete cascade,
  language text not null check (language in ('fr','en')),
  questions jsonb not null,
  answer_key jsonb not null,
  explanations jsonb not null,
  generated_at timestamptz not null default now(),
  unique(lesson_id)
);

create index if not exists generated_exercises_lesson_idx
  on public.generated_exercises(lesson_id);

create table if not exists public.student_lesson_results (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  lesson_id uuid not null references public.generated_lessons(id) on delete cascade,
  score integer not null check (score between 0 and 100),
  answers jsonb not null,
  corrections jsonb not null,
  attempt_no integer not null default 1 check (attempt_no > 0),
  submitted_at timestamptz not null default now()
);

create index if not exists student_lesson_results_student_idx
  on public.student_lesson_results(student_id, submitted_at desc);
create index if not exists student_lesson_results_lesson_idx
  on public.student_lesson_results(lesson_id, student_id, score desc);

alter table public.generated_exercises enable row level security;
alter table public.student_lesson_results enable row level security;

-- Answer keys must never be selectable by a normal client.

drop policy if exists "teachers read exercise definitions" on public.generated_exercises;

create policy "students read own exercise results"
on public.student_lesson_results for select to authenticated
using (student_id = auth.uid());

drop policy if exists "students insert own exercise results" on public.student_lesson_results;

drop policy if exists "teachers read class exercise results" on public.student_lesson_results;
create policy "teachers read class exercise results"
on public.student_lesson_results for select to authenticated
using (
  exists (
    select 1
    from public.generated_lessons gl
    join public.course_chunks ch on ch.id = gl.chunk_id
    where gl.id = student_lesson_results.lesson_id
      and public.teacher_can_manage_class(ch.class_id, auth.uid())
  )
  or public.is_catalog_admin()
);

drop policy if exists "admins manage exercise results" on public.student_lesson_results;
create policy "admins manage exercise results"
on public.student_lesson_results for all to authenticated
using (public.is_catalog_admin())
with check (public.is_catalog_admin());

create or replace function public.get_smart_exercise(p_lesson_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_questions jsonb;
  v_chunk uuid;
  v_allowed boolean;
begin
  select ch.id, (
    public.is_course_student(ch.course_id)
    or public.teacher_can_manage_class(ch.class_id, auth.uid())
    or public.is_catalog_admin()
  )
  into v_chunk, v_allowed
  from public.generated_lessons gl
  join public.course_chunks ch on ch.id = gl.chunk_id
  where gl.id = p_lesson_id;

  if not coalesce(v_allowed, false) then
    raise exception 'Not allowed';
  end if;

  select questions into v_questions
  from public.generated_exercises
  where lesson_id = p_lesson_id;

  if v_questions is null then
    raise exception 'Exercise not ready';
  end if;

  return v_questions;
end;
$$;
revoke all on function public.get_smart_exercise(uuid) from public;
grant execute on function public.get_smart_exercise(uuid) to authenticated;

create or replace function public.submit_exercise_answers(p_lesson_id uuid, p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_questions jsonb;
  v_key jsonb;
  v_explanations jsonb;
  v_chunk_id uuid;
  v_course_id uuid;
  v_class_id uuid;
  v_subject_id uuid;
  v_course_min integer;
  v_allowed boolean;
  v_correct integer := 0;
  v_total integer := 0;
  v_item jsonb;
  v_qid text;
  v_given text;
  v_correct_answer text;
  v_corrections jsonb := '[]'::jsonb;
  v_attempt integer;
  v_score integer;
  v_passed boolean;
  v_next uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;

  select
    ch.id, ch.course_id, ch.class_id, ch.subject_id,
    (public.is_course_student(ch.course_id) or public.is_catalog_admin()),
    c.minimum_exercise_score
  into v_chunk_id, v_course_id, v_class_id, v_subject_id, v_allowed, v_course_min
  from public.generated_lessons gl
  join public.course_chunks ch on ch.id = gl.chunk_id
  join public.courses c on c.id = ch.course_id
  where gl.id = p_lesson_id;

  if not coalesce(v_allowed, false) then raise exception 'Not allowed'; end if;

  select ge.questions, ge.answer_key, ge.explanations
  into v_questions, v_key, v_explanations
  from public.generated_exercises ge
  where ge.lesson_id = p_lesson_id;
  if v_questions is null then raise exception 'Exercise not ready'; end if;

  v_total := jsonb_array_length(v_questions);
  for v_item in select * from jsonb_array_elements(v_questions)
  loop
    v_qid := v_item ->> 'id';
    v_given := p_answers ->> v_qid;
    v_correct_answer := v_key ->> v_qid;
    if v_given is not null and v_given = v_correct_answer then
      v_correct := v_correct + 1;
    end if;
    v_corrections := v_corrections || jsonb_build_array(jsonb_build_object(
      'id', v_qid,
      'correct', v_correct_answer,
      'selected', v_given,
      'explanation', coalesce(v_explanations ->> v_qid, '')
    ));
  end loop;

  v_score := case when v_total = 0 then 0 else round(v_correct * 100.0 / v_total)::integer end;
  v_passed := v_score >= coalesce(v_course_min, 50);

  select coalesce(max(attempt_no), 0) + 1 into v_attempt
  from public.student_lesson_results
  where student_id = v_user and lesson_id = p_lesson_id;

  insert into public.student_lesson_results(student_id, lesson_id, score, answers, corrections, attempt_no)
  values (v_user, p_lesson_id, v_score, coalesce(p_answers, '{}'::jsonb), v_corrections, v_attempt);

  if v_passed then
    update public.student_lesson_progress
    set last_chunk_id = v_chunk_id, status = 'completed', updated_at = now()
    where student_id = v_user and subject_id = v_subject_id;

    if not found then
      insert into public.student_lesson_progress(student_id, class_id, subject_id, last_chunk_id, status)
      values (v_user, v_class_id, v_subject_id, v_chunk_id, 'completed')
      on conflict (student_id, subject_id) do update
      set last_chunk_id = excluded.last_chunk_id, status = 'completed', updated_at = now();
    end if;

    select ch.id into v_next
    from public.course_chunks ch
    join public.course_resources r on r.id = ch.resource_id
    where ch.course_id = v_course_id
      and ch.subject_id = v_subject_id
      and r.index_status = 'indexed'
      and r.index_approved
      and ch.language = (select gl.language from public.generated_lessons gl where gl.id = p_lesson_id)
      and ch.position > (select ch2.position from public.course_chunks ch2 where ch2.id = v_chunk_id)
    order by ch.position
    limit 1;
  end if;

  return jsonb_build_object(
    'score', v_score,
    'passed', v_passed,
    'attempt', v_attempt,
    'correction', v_corrections,
    'next_chunk_id', v_next,
    'minimum_score', coalesce(v_course_min, 50)
  );
end;
$$;
revoke all on function public.submit_exercise_answers(uuid, jsonb) from public;
grant execute on function public.submit_exercise_answers(uuid, jsonb) to authenticated;

-- ============================================================
-- PART 3 — Student error reports on generated lessons
-- ============================================================
create table if not exists public.smart_lesson_error_reports (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  lesson_id uuid not null references public.generated_lessons(id) on delete cascade,
  reason text not null default '',
  created_at timestamptz not null default now()
);

alter table public.smart_lesson_error_reports enable row level security;

drop policy if exists "students report own lesson errors" on public.smart_lesson_error_reports;
create policy "students report own lesson errors"
on public.smart_lesson_error_reports for insert to authenticated
with check (student_id = auth.uid());

drop policy if exists "teachers read lesson error reports" on public.smart_lesson_error_reports;
create policy "teachers read lesson error reports"
on public.smart_lesson_error_reports for select to authenticated
using (
  exists (
    select 1
    from public.generated_lessons gl
    join public.course_chunks ch on ch.id = gl.chunk_id
    where gl.id = smart_lesson_error_reports.lesson_id
      and public.teacher_can_manage_class(ch.class_id, auth.uid())
  )
  or public.is_catalog_admin()
);

create or replace function public.report_smart_lesson_error(p_lesson_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.generated_lessons gl
    join public.course_chunks ch on ch.id = gl.chunk_id
    where gl.id = p_lesson_id and public.is_course_student(ch.course_id)
  ) then
    raise exception 'Not allowed';
  end if;
  insert into public.smart_lesson_error_reports(student_id, lesson_id, reason)
  values (auth.uid(), p_lesson_id, left(coalesce(trim(p_reason), ''), 1000));
end;
$$;
revoke all on function public.report_smart_lesson_error(uuid, text) from public;
grant execute on function public.report_smart_lesson_error(uuid, text) to authenticated;

-- ============================================================
-- PART 6 — AI quota / shared cache safeguards
-- ============================================================
create table if not exists public.ai_generation_usage (
  user_id uuid not null references public.profiles(id) on delete cascade,
  usage_date date not null,
  generation_count integer not null default 0 check (generation_count >= 0),
  updated_at timestamptz not null default now(),
  primary key(user_id, usage_date)
);

alter table public.ai_generation_usage enable row level security;
-- No direct client policies. Edge Functions use service-role access.

create or replace function public.consume_ai_generation(p_user_id uuid, p_limit integer default 10)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  insert into public.ai_generation_usage(user_id, usage_date, generation_count)
  values (p_user_id, current_date, 1)
  on conflict (user_id, usage_date) do update
    set generation_count = public.ai_generation_usage.generation_count + 1,
        updated_at = now()
  returning generation_count into v_count;

  if v_count > coalesce(p_limit, 10) then
    update public.ai_generation_usage
    set generation_count = generation_count - 1
    where user_id = p_user_id and usage_date = current_date;
    return 0;
  end if;
  return v_count;
end;
$$;
revoke all on function public.consume_ai_generation(uuid, integer) from public;

-- ============================================================
-- PART 3/6 — Notification deduplication for scheduled lessons
-- ============================================================
create table if not exists public.smart_lesson_notifications (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  timetable_entry_id uuid not null references public.class_timetable_entries(id) on delete cascade,
  occurrence_date date not null,
  created_at timestamptz not null default now(),
  unique(student_id, timetable_entry_id, occurrence_date)
);

alter table public.smart_lesson_notifications enable row level security;
drop policy if exists "students read own smart lesson notifications" on public.smart_lesson_notifications;
create policy "students read own smart lesson notifications"
on public.smart_lesson_notifications for select to authenticated
using (student_id = auth.uid());

-- ============================================================
-- PART 5 — Anonymous class progress + teacher detail
-- ============================================================
create or replace function public.get_class_progress_summary(p_class_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_count integer;
  v_own_score numeric := 0;
  v_class_score numeric := 0;
  v_rank_position integer := 1;
  v_top_percent integer := 100;
  v_available boolean := false;
  v_subjects jsonb := '[]'::jsonb;
begin
  if not public.is_student_in_class(p_class_id, v_user)
     and not public.teacher_can_manage_class(p_class_id, v_user)
     and not public.is_catalog_admin() then
    raise exception 'Not allowed';
  end if;

  select count(*) into v_count
  from public.class_students
  where class_id = p_class_id and is_active;

  v_available := v_count >= 5;

  with student_scores as (
    select cs.student_id,
           coalesce(avg(r.score) filter (where ch.class_id = p_class_id), 0)::numeric as score
    from public.class_students cs
    left join public.student_lesson_results r on r.student_id = cs.student_id
    left join public.generated_lessons gl on gl.id = r.lesson_id
    left join public.course_chunks ch on ch.id = gl.chunk_id
    where cs.class_id = p_class_id and cs.is_active
    group by cs.student_id
  )
  select coalesce(max(score) filter (where student_id = v_user), 0),
         coalesce(avg(score), 0),
         1 + coalesce(sum(case when score > coalesce((select score from student_scores where student_id = v_user), 0) then 1 else 0 end), 0)
  into v_own_score, v_class_score, v_rank_position
  from student_scores;

  if v_available then
    v_top_percent := greatest(1, ceil(v_rank_position * 100.0 / greatest(v_count, 1))::integer);
  end if;

  select coalesce(jsonb_agg(x.value order by x.value->>'subject_name'), '[]'::jsonb)
  into v_subjects
  from (
    select jsonb_build_object(
      'subject_id', s.id,
      'subject_name', s.name_fr,
      'own_score', coalesce(avg(r.score) filter (where r.student_id = v_user), 0),
      'class_average', coalesce(avg(r.score), 0),
      'lessons_completed', coalesce((select count(*) from public.student_lesson_results rr join public.generated_lessons gg on gg.id = rr.lesson_id join public.course_chunks cc on cc.id = gg.chunk_id where rr.student_id = v_user and cc.class_id = p_class_id and cc.subject_id = s.id), 0),
      'lessons_available', coalesce((select count(*) from public.course_chunks cc join public.course_resources cr on cr.id = cc.resource_id where cc.class_id = p_class_id and cc.subject_id = s.id and cr.index_status = 'indexed' and cr.index_approved), 0)
    ) as value
    from public.subjects s
    left join public.course_chunks ch on ch.class_id = p_class_id and ch.subject_id = s.id
    left join public.generated_lessons gl on gl.chunk_id = ch.id
    left join public.student_lesson_results r on r.lesson_id = gl.id
    where exists (select 1 from public.class_subjects csu where csu.class_id = p_class_id and csu.subject_id = s.id and csu.is_active)
    group by s.id, s.name_fr
  ) x;

  return jsonb_build_object(
    'class_size', v_count,
    'comparison_available', v_available,
    'own_average_score', round(v_own_score, 1),
    'class_average_score', round(v_class_score, 1),
    'top_percent', case when v_available then v_top_percent else null end,
    'subjects', v_subjects
  );
end;
$$;
revoke all on function public.get_class_progress_summary(uuid) from public;
grant execute on function public.get_class_progress_summary(uuid) to authenticated;

create or replace function public.get_student_weekly_progress(p_class_id uuid, p_weeks integer default 8)
returns table(week_start date, average_score numeric, lessons_completed integer)
language sql
stable
security definer
set search_path = public
as $$
  with weeks as (
    select generate_series(
      date_trunc('week', current_date - make_interval(weeks => greatest(p_weeks, 1) - 1))::date,
      date_trunc('week', current_date)::date,
      interval '1 week'
    )::date as week_start
  )
  select
    w.week_start,
    coalesce(round(avg(r.score) filter (where ch.class_id = p_class_id), 1), 0)::numeric,
    coalesce(count(r.id) filter (where ch.class_id = p_class_id), 0)::integer
  from weeks w
  left join public.student_lesson_results r
    on r.student_id = auth.uid()
   and r.submitted_at::date >= w.week_start
   and r.submitted_at::date < (w.week_start + 7)
  left join public.generated_lessons gl on gl.id = r.lesson_id
  left join public.course_chunks ch on ch.id = gl.chunk_id
  where public.is_student_in_class(p_class_id, auth.uid())
  group by w.week_start
  order by w.week_start;
$$;
revoke all on function public.get_student_weekly_progress(uuid, integer) from public;
grant execute on function public.get_student_weekly_progress(uuid, integer) to authenticated;

create or replace function public.get_teacher_class_progress_detail(p_class_id uuid)
returns table(
  student_id uuid,
  student_name text,
  average_score numeric,
  completed_lessons integer,
  available_lessons integer,
  late boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cs.student_id,
    trim(concat(p.first_name, ' ', p.last_name)),
    coalesce(round(avg(r.score) filter (where ch.class_id = p_class_id), 1), 0)::numeric,
    coalesce(count(distinct r.lesson_id) filter (where ch.class_id = p_class_id), 0)::integer,
    coalesce((select count(*) from public.course_chunks ch2 join public.course_resources cr on cr.id = ch2.resource_id where ch2.class_id = p_class_id and cr.index_status = 'indexed' and cr.index_approved), 0)::integer,
    coalesce(count(distinct r.lesson_id) filter (where ch.class_id = p_class_id), 0) < coalesce((select count(*) from public.course_chunks ch2 join public.course_resources cr on cr.id = ch2.resource_id where ch2.class_id = p_class_id and cr.index_status = 'indexed' and cr.index_approved), 0)
  from public.class_students cs
  join public.profiles p on p.id = cs.student_id
  left join public.student_lesson_results r on r.student_id = cs.student_id
  left join public.generated_lessons gl on gl.id = r.lesson_id
  left join public.course_chunks ch on ch.id = gl.chunk_id
  where cs.class_id = p_class_id
    and cs.is_active
    and (public.teacher_can_manage_class(p_class_id, auth.uid()) or public.is_catalog_admin())
  group by cs.student_id, p.first_name, p.last_name
  order by
    (
      coalesce(count(distinct r.lesson_id) filter (where ch.class_id = p_class_id), 0)
      <
      coalesce((
        select count(*)
        from public.course_chunks ch2
        join public.course_resources cr on cr.id = ch2.resource_id
        where ch2.class_id = p_class_id
          and cr.index_status = 'indexed'
          and cr.index_approved
      ), 0)
    ) desc,
    coalesce(round(avg(r.score) filter (where ch.class_id = p_class_id), 1), 0)::numeric asc,
    trim(concat(p.first_name, ' ', p.last_name));
$$;
revoke all on function public.get_teacher_class_progress_detail(uuid) from public;
grant execute on function public.get_teacher_class_progress_detail(uuid) to authenticated;

create or replace function public.get_teacher_class_subject_summary(p_class_id uuid)
returns table(
  subject_id uuid,
  subject_name text,
  average_score numeric,
  completed_lessons integer,
  available_lessons integer,
  difficult boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.id,
    coalesce(nullif(s.name_fr, ''), s.name_en),
    coalesce(round(avg(r.score), 1), 0)::numeric,
    coalesce(count(distinct r.lesson_id), 0)::integer,
    coalesce((select count(*) from public.course_chunks ch2
      join public.course_resources cr on cr.id = ch2.resource_id
      where ch2.class_id = p_class_id and ch2.subject_id = s.id
        and cr.index_status = 'indexed' and cr.index_approved), 0)::integer,
    coalesce(round(avg(r.score), 1), 0) < 50
  from public.class_subjects csu
  join public.subjects s on s.id = csu.subject_id
  left join public.course_chunks ch on ch.class_id = p_class_id and ch.subject_id = s.id
  left join public.generated_lessons gl on gl.chunk_id = ch.id
  left join public.student_lesson_results r on r.lesson_id = gl.id
  where csu.class_id = p_class_id
    and csu.is_active
    and (public.teacher_can_manage_class(p_class_id, auth.uid()) or public.is_catalog_admin())
  group by s.id, s.name_fr, s.name_en
  order by
    coalesce(round(avg(r.score), 1), 0)::numeric asc,
    coalesce(nullif(s.name_fr, ''), s.name_en) asc;
$$;
revoke all on function public.get_teacher_class_subject_summary(uuid) from public;
grant execute on function public.get_teacher_class_subject_summary(uuid) to authenticated;

-- ============================================================
-- Course access helpers used by Edge Functions and future readers
-- ============================================================
create or replace function public.can_prepare_smart_lesson(p_course_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.courses c
    where c.id = p_course_id
      and c.status = 'published'
      and c.smart_lesson_enabled
      and (
        public.is_catalog_admin()
        or c.teacher_id = auth.uid()
        or public.is_course_student(c.id)
      )
  );
$$;
revoke all on function public.can_prepare_smart_lesson(uuid) from public;
grant execute on function public.can_prepare_smart_lesson(uuid) to authenticated;

-- Realtime is useful for teacher index status updates.
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.course_resources'; exception when duplicate_object then null; end;
  begin execute 'alter publication supabase_realtime add table public.generated_lessons'; exception when duplicate_object then null; end;
end $$;

-- ============================================================
-- Scheduler note
-- ============================================================
-- The Edge Function `daily-lesson` exposes `mode=prepare` and `mode=notify`.
-- It can be attached to Supabase Scheduled Functions / pg_cron in the project:
--   prepare: once daily (24h ahead)
--   notify: every 5 minutes (30 minutes before a class)
-- No Gemini key is stored in SQL or on the mobile app.
