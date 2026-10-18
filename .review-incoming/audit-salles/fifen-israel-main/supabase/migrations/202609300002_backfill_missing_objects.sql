-- Fise School: objets utilisés par l'application Flutter mais absents des migrations
-- du dépôt (devoirs, notifications, messages privés, emploi du temps, photo de profil).
--
-- Migration idempotente : "if not exists" partout, et les politiques RLS ne sont
-- créées que si elles n'existent pas déjà. Elle peut donc être appliquée sans risque
-- sur une base où ces objets ont déjà été créés à la main.

-- Petit utilitaire local (session courante uniquement) : créer une politique si absente.
create or replace function pg_temp.ensure_policy(
  p_schema text, p_table text, p_name text, p_ddl text
) returns void
language plpgsql
as $fn$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = p_schema and tablename = p_table and policyname = p_name
  ) then
    execute p_ddl;
  end if;
end
$fn$;

-- ---------------------------------------------------------------------------
-- Photo de profil
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists avatar_path text;

insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', false)
on conflict (id) do nothing;

select pg_temp.ensure_policy('storage', 'objects', 'users read own profile photos', $p$
  create policy "users read own profile photos" on storage.objects
    for select to authenticated
    using (bucket_id = 'profile-photos'
           and (storage.foldername(name))[1] = auth.uid()::text)
$p$);
select pg_temp.ensure_policy('storage', 'objects', 'users upload own profile photos', $p$
  create policy "users upload own profile photos" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'profile-photos'
                and (storage.foldername(name))[1] = auth.uid()::text)
$p$);
select pg_temp.ensure_policy('storage', 'objects', 'users delete own profile photos', $p$
  create policy "users delete own profile photos" on storage.objects
    for delete to authenticated
    using (bucket_id = 'profile-photos'
           and (storage.foldername(name))[1] = auth.uid()::text)
$p$);

-- ---------------------------------------------------------------------------
-- Devoirs
-- ---------------------------------------------------------------------------
create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  lesson_id uuid references public.lessons(id) on delete set null,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  title_fr text not null default '',
  title_en text not null default '',
  instructions_fr text,
  instructions_en text,
  due_at timestamptz,
  status text not null default 'draft',
  max_score numeric not null default 20,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint assignments_status_valid check (status in ('draft', 'published', 'closed'))
);

create table if not exists public.assignment_questions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  position integer not null default 1,
  question_fr text not null default '',
  question_en text not null default '',
  question_type text not null default 'text',
  points numeric not null default 1,
  options jsonb not null default '[]'::jsonb,
  correct_answer text,
  created_at timestamptz not null default now()
);

create table if not exists public.assignment_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'draft',
  score numeric,
  submitted_at timestamptz,
  corrected_at timestamptz,
  teacher_feedback_fr text,
  teacher_feedback_en text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint assignment_submissions_one_per_student unique (assignment_id, student_id)
);

create table if not exists public.assignment_answers (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.assignment_submissions(id) on delete cascade,
  question_id uuid not null references public.assignment_questions(id) on delete cascade,
  answer_text text,
  selected_option text,
  is_correct boolean,
  points_awarded numeric,
  teacher_feedback_fr text,
  teacher_feedback_en text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- requis par upsert(onConflict: 'submission_id,question_id') dans l'application
  constraint assignment_answers_one_per_question unique (submission_id, question_id)
);

create index if not exists assignments_class_idx on public.assignments (class_id, status);
create index if not exists assignments_teacher_idx on public.assignments (teacher_id);
create index if not exists assignments_course_idx on public.assignments (course_id);
create index if not exists assignment_questions_assignment_idx
  on public.assignment_questions (assignment_id, position);
create index if not exists assignment_submissions_student_idx
  on public.assignment_submissions (student_id);

drop trigger if exists assignments_set_updated_at on public.assignments;
create trigger assignments_set_updated_at before update on public.assignments
  for each row execute function public.set_profiles_updated_at();
drop trigger if exists assignment_submissions_set_updated_at on public.assignment_submissions;
create trigger assignment_submissions_set_updated_at before update on public.assignment_submissions
  for each row execute function public.set_profiles_updated_at();
drop trigger if exists assignment_answers_set_updated_at on public.assignment_answers;
create trigger assignment_answers_set_updated_at before update on public.assignment_answers
  for each row execute function public.set_profiles_updated_at();

create or replace function public.owns_assignment(target_assignment_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.assignments
    where id = target_assignment_id and teacher_id = auth.uid()
  ) or public.is_catalog_admin();
$$;

create or replace function public.can_read_assignment(target_assignment_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.owns_assignment(target_assignment_id) or exists (
    select 1 from public.assignments a
    where a.id = target_assignment_id
      and a.status in ('published', 'closed')
      and public.is_student_in_class(a.class_id, auth.uid())
  );
$$;

create or replace function public.owns_submission(target_submission_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.assignment_submissions s
    where s.id = target_submission_id and s.student_id = auth.uid()
  );
$$;

create or replace function public.grades_submission(target_submission_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.assignment_submissions s
    where s.id = target_submission_id and public.owns_assignment(s.assignment_id)
  );
$$;

alter table public.assignments enable row level security;
alter table public.assignment_questions enable row level security;
alter table public.assignment_submissions enable row level security;
alter table public.assignment_answers enable row level security;

select pg_temp.ensure_policy('public', 'assignments', 'teachers manage own assignments', $p$
  create policy "teachers manage own assignments" on public.assignments
    for all to authenticated
    using (teacher_id = auth.uid() or public.is_catalog_admin())
    with check (
      (teacher_id = auth.uid() and public.check_profile_role(auth.uid(), 'teacher'))
      or public.is_catalog_admin()
    )
$p$);
select pg_temp.ensure_policy('public', 'assignments', 'students read published class assignments', $p$
  create policy "students read published class assignments" on public.assignments
    for select to authenticated
    using (status in ('published', 'closed')
           and public.is_student_in_class(class_id, auth.uid()))
$p$);

select pg_temp.ensure_policy('public', 'assignment_questions', 'teachers manage assignment questions', $p$
  create policy "teachers manage assignment questions" on public.assignment_questions
    for all to authenticated
    using (public.owns_assignment(assignment_id))
    with check (public.owns_assignment(assignment_id))
$p$);
select pg_temp.ensure_policy('public', 'assignment_questions', 'students read visible assignment questions', $p$
  create policy "students read visible assignment questions" on public.assignment_questions
    for select to authenticated
    using (public.can_read_assignment(assignment_id))
$p$);

select pg_temp.ensure_policy('public', 'assignment_submissions', 'students manage own submissions', $p$
  create policy "students manage own submissions" on public.assignment_submissions
    for all to authenticated
    using (student_id = auth.uid())
    with check (student_id = auth.uid() and public.can_read_assignment(assignment_id))
$p$);
select pg_temp.ensure_policy('public', 'assignment_submissions', 'teachers grade submissions', $p$
  create policy "teachers grade submissions" on public.assignment_submissions
    for all to authenticated
    using (public.owns_assignment(assignment_id))
    with check (public.owns_assignment(assignment_id))
$p$);

select pg_temp.ensure_policy('public', 'assignment_answers', 'students manage own answers', $p$
  create policy "students manage own answers" on public.assignment_answers
    for all to authenticated
    using (public.owns_submission(submission_id))
    with check (public.owns_submission(submission_id))
$p$);
select pg_temp.ensure_policy('public', 'assignment_answers', 'teachers grade answers', $p$
  create policy "teachers grade answers" on public.assignment_answers
    for all to authenticated
    using (public.grades_submission(submission_id))
    with check (public.grades_submission(submission_id))
$p$);

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null default '',
  type text not null default 'info',
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx
  on public.notifications (user_id, is_read, created_at desc);

alter table public.notifications enable row level security;

select pg_temp.ensure_policy('public', 'notifications', 'users read own notifications', $p$
  create policy "users read own notifications" on public.notifications
    for select to authenticated using (user_id = auth.uid())
$p$);
select pg_temp.ensure_policy('public', 'notifications', 'users update own notifications', $p$
  create policy "users update own notifications" on public.notifications
    for update to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid())
$p$);
select pg_temp.ensure_policy('public', 'notifications', 'admins manage notifications', $p$
  create policy "admins manage notifications" on public.notifications
    for all to authenticated
    using (public.is_catalog_admin()) with check (public.is_catalog_admin())
$p$);

-- ---------------------------------------------------------------------------
-- Messages privés (enseignant <-> élèves d'une même classe)
-- ---------------------------------------------------------------------------
create table if not exists public.private_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint private_messages_body_not_blank check (length(trim(body)) > 0),
  constraint private_messages_not_self check (sender_id <> recipient_id)
);
create index if not exists private_messages_pair_idx
  on public.private_messages (sender_id, recipient_id, created_at);
create index if not exists private_messages_recipient_idx
  on public.private_messages (recipient_id, read_at);

-- Deux utilisateurs peuvent s'écrire s'ils partagent une classe (élève <-> enseignant).
create or replace function public.can_message(target_user_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.class_students cs
    join public.class_teachers ct on ct.class_id = cs.class_id
    where cs.is_active and ct.is_active
      and ((cs.student_id = auth.uid() and ct.teacher_id = target_user_id)
        or (ct.teacher_id = auth.uid() and cs.student_id = target_user_id))
  );
$$;

alter table public.private_messages enable row level security;

select pg_temp.ensure_policy('public', 'private_messages', 'participants read private messages', $p$
  create policy "participants read private messages" on public.private_messages
    for select to authenticated
    using (sender_id = auth.uid() or recipient_id = auth.uid())
$p$);
select pg_temp.ensure_policy('public', 'private_messages', 'members send private messages', $p$
  create policy "members send private messages" on public.private_messages
    for insert to authenticated
    with check (sender_id = auth.uid() and public.can_message(recipient_id))
$p$);
select pg_temp.ensure_policy('public', 'private_messages', 'recipients mark messages read', $p$
  create policy "recipients mark messages read" on public.private_messages
    for update to authenticated
    using (recipient_id = auth.uid()) with check (recipient_id = auth.uid())
$p$);

create or replace function public.list_private_message_contacts()
returns table (id uuid, first_name text, last_name text, role text, class_name text)
language sql stable security definer set search_path = public
as $$
  select distinct on (p.id)
    p.id, p.first_name, p.last_name, p.role, c.display_name as class_name
  from public.class_students cs
  join public.class_teachers ct on ct.class_id = cs.class_id
  join public.school_classes c on c.id = cs.class_id
  join public.profiles p
    on p.id = case when cs.student_id = auth.uid() then ct.teacher_id else cs.student_id end
  where cs.is_active and ct.is_active
    and (cs.student_id = auth.uid() or ct.teacher_id = auth.uid())
  order by p.id, c.display_name;
$$;

create or replace function public.list_private_messages(target_user_id uuid)
returns setof public.private_messages
language sql stable security definer set search_path = public
as $$
  select m.* from public.private_messages m
  where (m.sender_id = auth.uid() and m.recipient_id = target_user_id)
     or (m.sender_id = target_user_id and m.recipient_id = auth.uid())
  order by m.created_at;
$$;

revoke all on function public.list_private_message_contacts() from public;
revoke all on function public.list_private_messages(uuid) from public;
grant execute on function public.list_private_message_contacts() to authenticated;
grant execute on function public.list_private_messages(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Emploi du temps
-- ---------------------------------------------------------------------------
create table if not exists public.student_timetable_entries (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  day_of_week integer not null,
  start_time time not null,
  end_time time not null,
  subject text not null,
  teacher_name text,
  room text,
  notes text,
  created_at timestamptz not null default now(),
  constraint timetable_day_valid check (day_of_week between 1 and 7),
  constraint timetable_time_valid check (end_time > start_time)
);
create index if not exists student_timetable_student_idx
  on public.student_timetable_entries (student_id, day_of_week, start_time);

alter table public.student_timetable_entries enable row level security;

select pg_temp.ensure_policy('public', 'student_timetable_entries', 'students read own timetable', $p$
  create policy "students read own timetable" on public.student_timetable_entries
    for select to authenticated
    using (student_id = auth.uid() or public.is_catalog_admin())
$p$);
select pg_temp.ensure_policy('public', 'student_timetable_entries', 'admins manage timetable', $p$
  create policy "admins manage timetable" on public.student_timetable_entries
    for all to authenticated
    using (public.is_catalog_admin()) with check (public.is_catalog_admin())
$p$);
