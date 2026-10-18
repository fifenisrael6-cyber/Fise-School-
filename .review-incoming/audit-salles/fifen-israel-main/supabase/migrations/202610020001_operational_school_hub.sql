-- Fise School: operational school hub (timetable, notifications, realtime).

create table if not exists public.class_timetable_entries (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.school_classes(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null,
  subject_fr text not null,
  subject_en text not null,
  teacher_id uuid references public.profiles(id) on delete set null,
  teacher_name text,
  day_of_week integer not null check (day_of_week between 1 and 7),
  start_time time not null,
  end_time time not null,
  room text,
  notes text,
  is_active boolean not null default true,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint timetable_valid_time check (end_time > start_time)
);

create index if not exists class_timetable_class_day_idx
  on public.class_timetable_entries(class_id, day_of_week, start_time);
create index if not exists class_timetable_teacher_idx
  on public.class_timetable_entries(teacher_id, day_of_week, start_time);

alter table public.class_timetable_entries enable row level security;

drop policy if exists "students read class timetable" on public.class_timetable_entries;
create policy "students read class timetable"
on public.class_timetable_entries for select to authenticated
using (
  exists (
    select 1 from public.class_students cs
    where cs.class_id = class_timetable_entries.class_id
      and cs.student_id = auth.uid()
      and cs.is_active
  )
  or public.is_catalog_admin()
  or exists (
    select 1 from public.class_teachers ct
    where ct.class_id = class_timetable_entries.class_id
      and ct.teacher_id = auth.uid()
      and ct.is_active
  )
);

drop policy if exists "admins manage class timetable" on public.class_timetable_entries;
create policy "admins manage class timetable"
on public.class_timetable_entries for all to authenticated
using (public.is_catalog_admin())
with check (public.is_catalog_admin());

create or replace function public.notify_user(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_type text default 'info'
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if p_user_id is null or p_user_id = auth.uid() then
    return;
  end if;
  insert into public.notifications(user_id, title, body, type)
  values (p_user_id, left(coalesce(p_title, ''), 180), left(coalesce(p_body, ''), 1000), left(coalesce(p_type, 'info'), 50));
end;
$$;
revoke all on function public.notify_user(uuid, text, text, text) from public;

create or replace function public.notify_private_message()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare sender_name text;
begin
  select trim(concat(first_name, ' ', last_name)) into sender_name
  from public.profiles where id = new.sender_id;
  insert into public.notifications(user_id, title, body, type)
  values (
    new.recipient_id,
    coalesce(nullif(sender_name, ''), 'Fise School'),
    case when nullif(trim(coalesce(new.body, '')), '') is null then 'Nouvelle pièce jointe' else left(new.body, 500) end,
    'message'
  );
  return new;
end;
$$;

drop trigger if exists private_message_notification on public.private_messages;
create trigger private_message_notification
after insert on public.private_messages
for each row execute function public.notify_private_message();

create or replace function public.notify_assignment_students()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare student_id uuid;
begin
  if new.status = 'published' and tg_op = 'INSERT' then
    for student_id in select cs.student_id from public.class_students cs where cs.class_id = new.class_id and cs.is_active loop
      insert into public.notifications(user_id, title, body, type) values (student_id, 'Nouveau devoir', left(coalesce(new.title_fr, new.title_en, 'Un nouveau devoir est disponible.'), 500), 'assignment');
    end loop;
  elsif new.status = 'published' and old.status is distinct from new.status then
    for student_id in select cs.student_id from public.class_students cs where cs.class_id = new.class_id and cs.is_active loop
      insert into public.notifications(user_id, title, body, type) values (student_id, 'Nouveau devoir', left(coalesce(new.title_fr, new.title_en, 'Un nouveau devoir est disponible.'), 500), 'assignment');
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists assignment_notification on public.assignments;
create trigger assignment_notification
after insert or update of status on public.assignments
for each row execute function public.notify_assignment_students();

create or replace function public.notify_timetable_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare student_id uuid; teacher_id_value uuid; label text;
begin
  label := case when tg_op = 'INSERT' then 'Nouvel emploi du temps' else 'Emploi du temps modifié' end;
  for student_id in
    select cs.student_id from public.class_students cs
    where cs.class_id = new.class_id and cs.is_active
  loop
    insert into public.notifications(user_id, title, body, type)
    values (student_id, label, left(coalesce(new.subject_fr, 'Un créneau a été mis à jour.'), 500), 'timetable');
  end loop;
  teacher_id_value := new.teacher_id;
  if teacher_id_value is not null then
    insert into public.notifications(user_id, title, body, type)
    values (teacher_id_value, label, left(coalesce(new.subject_fr, 'Un créneau a été mis à jour.'), 500), 'timetable');
  end if;
  return new;
end;
$$;

drop trigger if exists timetable_notification on public.class_timetable_entries;
create trigger timetable_notification
after insert or update on public.class_timetable_entries
for each row execute function public.notify_timetable_change();

create or replace function public.notify_forum_post()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare topic_class_id uuid; member_id uuid;
begin
  select class_id into topic_class_id from public.forum_topics where id = new.topic_id;
  if topic_class_id is null then return new; end if;
  for member_id in
    select cs.student_id from public.class_students cs where cs.class_id = topic_class_id and cs.is_active
    union
    select ct.teacher_id from public.class_teachers ct where ct.class_id = topic_class_id and ct.is_active
  loop
    if member_id <> new.author_id then
      insert into public.notifications(user_id, title, body, type)
      values (member_id, 'Nouveau message dans le forum', left(coalesce(new.content, 'Nouvelle publication'), 500), 'forum');
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists forum_post_notification on public.forum_posts;
create trigger forum_post_notification
after insert on public.forum_posts
for each row execute function public.notify_forum_post();

create or replace function public.notify_assignment_submission_teacher()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare teacher_id_value uuid; assignment_title text;
begin
  select a.teacher_id, coalesce(a.title_fr, a.title_en, 'Devoir') into teacher_id_value, assignment_title from public.assignments a where a.id = new.assignment_id;
  if teacher_id_value is not null and new.status = 'submitted' and tg_op = 'INSERT' then
    insert into public.notifications(user_id, title, body, type) values (teacher_id_value, 'Devoir remis', left(assignment_title, 500), 'submission');
  elsif teacher_id_value is not null and new.status = 'submitted' and old.status is distinct from new.status then
    insert into public.notifications(user_id, title, body, type) values (teacher_id_value, 'Devoir remis', left(assignment_title, 500), 'submission');
  end if;
  return new;
end;
$$;

drop trigger if exists assignment_submission_notification on public.assignment_submissions;
create trigger assignment_submission_notification
after insert or update of status on public.assignment_submissions
for each row execute function public.notify_assignment_submission_teacher();

-- Enable Supabase Realtime for the two live user-facing streams.
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.private_messages'; exception when duplicate_object then null; end;
  begin execute 'alter publication supabase_realtime add table public.notifications'; exception when duplicate_object then null; end;
  begin execute 'alter publication supabase_realtime add table public.class_timetable_entries'; exception when duplicate_object then null; end;
end $$;

create or replace function public.validate_class_timetable_conflict()
returns trigger
language plpgsql
as $$
begin
  if exists (
    select 1 from public.class_timetable_entries e
    where e.id <> new.id and e.is_active
      and e.day_of_week = new.day_of_week
      and e.start_time < new.end_time and new.start_time < e.end_time
      and (e.class_id = new.class_id or (new.teacher_id is not null and e.teacher_id = new.teacher_id)
           or (nullif(trim(new.room), '') is not null and nullif(trim(e.room), '') = nullif(trim(new.room), '')))
  ) then
    raise exception 'Conflit dans l''emploi du temps: classe, enseignant ou salle déjà occupé(e) sur ce créneau.';
  end if;
  return new;
end;
$$;

drop trigger if exists class_timetable_conflict on public.class_timetable_entries;
create trigger class_timetable_conflict
before insert or update on public.class_timetable_entries
for each row execute function public.validate_class_timetable_conflict();

create or replace function public.notify_published_course()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare student_id uuid;
begin
  if new.status = 'published' and tg_op = 'INSERT' then
    for student_id in select cs.student_id from public.class_students cs where cs.class_id = new.class_id and cs.is_active loop
      insert into public.notifications(user_id, title, body, type) values (student_id, 'Nouveau cours', left(coalesce(new.title_fr, new.title_en, 'Un nouveau cours est disponible.'), 500), 'course');
    end loop;
  elsif new.status = 'published' and old.status is distinct from new.status then
    for student_id in select cs.student_id from public.class_students cs where cs.class_id = new.class_id and cs.is_active loop
      insert into public.notifications(user_id, title, body, type) values (student_id, 'Nouveau cours', left(coalesce(new.title_fr, new.title_en, 'Un nouveau cours est disponible.'), 500), 'course');
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists published_course_notification on public.courses;
create trigger published_course_notification
after insert or update of status on public.courses
for each row execute function public.notify_published_course();

create or replace function public.notify_forum_topic()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare member_id uuid;
begin
  for member_id in
    select cs.student_id from public.class_students cs where cs.class_id = new.class_id and cs.is_active
    union
    select ct.teacher_id from public.class_teachers ct where ct.class_id = new.class_id and ct.is_active
  loop
    if member_id <> new.creator_id then
      insert into public.notifications(user_id, title, body, type)
      values (member_id, 'Nouveau forum', left(coalesce(new.title, 'Une nouvelle discussion est disponible.'), 500), 'forum');
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists forum_topic_notification on public.forum_topics;
create trigger forum_topic_notification
after insert on public.forum_topics
for each row execute function public.notify_forum_topic();
