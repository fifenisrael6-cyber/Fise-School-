-- Fise School: pedagogical foundation.
-- No pedagogical seed data is inserted here.

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  name_fr text not null,
  name_en text not null,
  code text not null unique,
  subsystem public.catalog_subsystem not null,
  sector public.catalog_sector not null,
  description_fr text,
  description_en text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subjects_code_format check (code ~ '^[a-z0-9_]+$'),
  constraint subjects_names_not_blank check (length(trim(name_fr)) > 0 and length(trim(name_en)) > 0)
);

create table if not exists public.curricula (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete restrict,
  subsystem public.catalog_subsystem not null,
  sector public.catalog_sector not null,
  exam_level_id uuid references public.exam_levels(id) on delete set null,
  series_id uuid references public.series(id) on delete set null,
  specialty_id uuid references public.specialties(id) on delete set null,
  title_fr text not null,
  title_en text not null,
  description_fr text,
  description_en text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint curricula_title_not_blank check (length(trim(title_fr)) > 0 and length(trim(title_en)) > 0)
);

create table if not exists public.course_chapters (
  id uuid primary key default gen_random_uuid(),
  curriculum_id uuid not null references public.curricula(id) on delete cascade,
  title_fr text not null,
  title_en text not null,
  description_fr text,
  description_en text,
  position integer not null default 0 check (position >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_chapters_title_not_blank check (length(trim(title_fr)) > 0 and length(trim(title_en)) > 0),
  unique (curriculum_id, position)
);

create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  curriculum_id uuid not null references public.curricula(id) on delete restrict,
  chapter_id uuid not null references public.course_chapters(id) on delete restrict,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  teacher_id uuid not null references public.profiles(id) on delete restrict,
  class_id uuid references public.school_classes(id) on delete restrict,
  title_fr text not null,
  title_en text not null,
  description_fr text,
  description_en text,
  content_fr text,
  content_en text,
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint courses_title_not_blank check (length(trim(title_fr)) > 0 and length(trim(title_en)) > 0),
  constraint courses_published_date_valid check (status <> 'published' or published_at is not null)
);

create table if not exists public.lessons (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  title_fr text not null,
  title_en text not null,
  content_fr text,
  content_en text,
  objectives_fr text,
  objectives_en text,
  examples_fr text,
  examples_en text,
  summary_fr text,
  summary_en text,
  position integer not null default 0 check (position >= 0),
  estimated_minutes integer check (estimated_minutes is null or estimated_minutes > 0),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint lessons_title_not_blank check (length(trim(title_fr)) > 0 and length(trim(title_en)) > 0),
  unique (course_id, position)
);

create table if not exists public.course_resources (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  lesson_id uuid references public.lessons(id) on delete cascade,
  resource_type text not null check (resource_type in ('pdf', 'image', 'video', 'audio', 'document', 'other')),
  storage_path text not null unique,
  file_name text not null,
  mime_type text,
  file_size bigint check (file_size is null or file_size >= 0),
  title_fr text not null,
  title_en text not null,
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now(),
  constraint course_resources_title_not_blank check (length(trim(title_fr)) > 0 and length(trim(title_en)) > 0)
);

create table if not exists public.lesson_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  status text not null default 'not_started' check (status in ('not_started', 'in_progress', 'completed')),
  progress_percent integer not null default 0 check (progress_percent between 0 and 100),
  started_at timestamptz,
  completed_at timestamptz,
  last_opened_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (student_id, lesson_id),
  constraint lesson_progress_status_dates check (
    (status = 'completed' and progress_percent = 100 and completed_at is not null)
    or status <> 'completed'
  )
);

create index if not exists curricula_context_idx on public.curricula (subsystem, sector, subject_id, is_active);
create index if not exists course_chapters_curriculum_position_idx on public.course_chapters (curriculum_id, position);
create index if not exists courses_class_status_idx on public.courses (class_id, status, updated_at desc);
create index if not exists courses_teacher_status_idx on public.courses (teacher_id, status, updated_at desc);
create index if not exists lessons_course_position_idx on public.lessons (course_id, position);
create index if not exists resources_course_lesson_idx on public.course_resources (course_id, lesson_id, position);
create index if not exists lesson_progress_student_idx on public.lesson_progress (student_id, updated_at desc);

create or replace function public.set_pedagogy_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

drop trigger if exists subjects_set_updated_at on public.subjects;
create trigger subjects_set_updated_at before update on public.subjects for each row execute function public.set_pedagogy_updated_at();
drop trigger if exists curricula_set_updated_at on public.curricula;
create trigger curricula_set_updated_at before update on public.curricula for each row execute function public.set_pedagogy_updated_at();
drop trigger if exists chapters_set_updated_at on public.course_chapters;
create trigger chapters_set_updated_at before update on public.course_chapters for each row execute function public.set_pedagogy_updated_at();
drop trigger if exists courses_set_updated_at on public.courses;
create trigger courses_set_updated_at before update on public.courses for each row execute function public.set_pedagogy_updated_at();
drop trigger if exists lessons_set_updated_at on public.lessons;
create trigger lessons_set_updated_at before update on public.lessons for each row execute function public.set_pedagogy_updated_at();
drop trigger if exists progress_set_updated_at on public.lesson_progress;
create trigger progress_set_updated_at before update on public.lesson_progress for each row execute function public.set_pedagogy_updated_at();

create or replace function public.validate_pedagogy_context()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  subject_subsystem public.catalog_subsystem;
  subject_sector public.catalog_sector;
  curriculum_subsystem public.catalog_subsystem;
  curriculum_sector public.catalog_sector;
  class_subsystem public.catalog_subsystem;
  class_sector public.catalog_sector;
begin
  if tg_table_name = 'curricula' then
    select subsystem, sector into subject_subsystem, subject_sector from public.subjects where id = new.subject_id and is_active;
    if not found or subject_subsystem is distinct from new.subsystem or subject_sector is distinct from new.sector then
      raise exception 'Curriculum context does not match its subject';
    end if;
  elsif tg_table_name = 'courses' then
    select subsystem, sector into curriculum_subsystem, curriculum_sector from public.curricula where id = new.curriculum_id and is_active;
    if not found then raise exception 'Curriculum is not active'; end if;
    select subsystem, sector into subject_subsystem, subject_sector from public.subjects where id = new.subject_id and is_active;
    if not found or curriculum_subsystem is distinct from subject_subsystem or curriculum_sector is distinct from subject_sector then
      raise exception 'Course context does not match its curriculum and subject';
    end if;
    if not exists (select 1 from public.course_chapters where id = new.chapter_id and curriculum_id = new.curriculum_id and is_active) then
      raise exception 'Course chapter does not belong to its curriculum';
    end if;
    if not public.check_profile_role(new.teacher_id, 'teacher') then raise exception 'Only teachers can own courses'; end if;
    if new.class_id is not null then
      select subsystem, sector into class_subsystem, class_sector from public.school_classes where id = new.class_id and is_active;
      if not found or class_subsystem is distinct from subject_subsystem or class_sector is distinct from subject_sector then
        raise exception 'Course class context does not match its subject';
      end if;
      if not public.is_teacher_assigned(new.class_id, new.teacher_id) then raise exception 'Teacher is not assigned to this class'; end if;
    end if;
  elsif tg_table_name = 'lessons' then
    if not exists (select 1 from public.courses where id = new.course_id and status <> 'archived') then raise exception 'Course is not available'; end if;
  end if;
  return new;
end;
$$;

drop trigger if exists curricula_validate_context on public.curricula;
create trigger curricula_validate_context before insert or update on public.curricula for each row execute function public.validate_pedagogy_context();
drop trigger if exists courses_validate_context on public.courses;
create trigger courses_validate_context before insert or update on public.courses for each row execute function public.validate_pedagogy_context();
drop trigger if exists lessons_validate_context on public.lessons;
create trigger lessons_validate_context before insert or update on public.lessons for each row execute function public.validate_pedagogy_context();

create or replace function public.is_course_student(target_course_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.courses c
    join public.class_students cs on cs.class_id = c.class_id and cs.student_id = auth.uid() and cs.is_active
    where c.id = target_course_id and c.status = 'published'
  );
$$;

create or replace function public.is_lesson_student(target_lesson_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.lessons l where l.id = target_lesson_id and l.is_published and public.is_course_student(l.course_id)
  );
$$;

alter table public.subjects enable row level security;
alter table public.curricula enable row level security;
alter table public.course_chapters enable row level security;
alter table public.courses enable row level security;
alter table public.lessons enable row level security;
alter table public.course_resources enable row level security;
alter table public.lesson_progress enable row level security;

create policy "authenticated users read active subjects" on public.subjects for select to authenticated using (is_active or public.is_catalog_admin());
create policy "admins manage subjects" on public.subjects for all to authenticated using (public.is_catalog_admin()) with check (public.is_catalog_admin());
create policy "authenticated users read active curricula" on public.curricula for select to authenticated using (is_active or public.is_catalog_admin());
create policy "admins manage curricula" on public.curricula for all to authenticated using (public.is_catalog_admin()) with check (public.is_catalog_admin());
create policy "authenticated users read active chapters" on public.course_chapters for select to authenticated using (is_active or public.is_catalog_admin());
create policy "admins manage chapters" on public.course_chapters for all to authenticated using (public.is_catalog_admin()) with check (public.is_catalog_admin());
create policy "teachers manage own courses" on public.courses for all to authenticated using (teacher_id = auth.uid() or public.is_catalog_admin()) with check ((teacher_id = auth.uid() and public.check_profile_role(auth.uid(), 'teacher')) or public.is_catalog_admin());
create policy "students read published class courses" on public.courses for select to authenticated using (status = 'published' and public.is_course_student(id));
create policy "teachers manage own lessons" on public.lessons for all to authenticated using (exists (select 1 from public.courses c where c.id = course_id and (c.teacher_id = auth.uid() or public.is_catalog_admin()))) with check (exists (select 1 from public.courses c where c.id = course_id and (c.teacher_id = auth.uid() or public.is_catalog_admin())));
create policy "students read published lessons" on public.lessons for select to authenticated using (is_published and public.is_lesson_student(id));
create policy "course members read resources" on public.course_resources for select to authenticated using (public.is_course_student(course_id) or exists (select 1 from public.courses c where c.id = course_id and (c.teacher_id = auth.uid() or public.is_catalog_admin())));
create policy "course owners manage resources" on public.course_resources for all to authenticated using (exists (select 1 from public.courses c where c.id = course_id and (c.teacher_id = auth.uid() or public.is_catalog_admin()))) with check (exists (select 1 from public.courses c where c.id = course_id and (c.teacher_id = auth.uid() or public.is_catalog_admin())));
create policy "students manage own progress" on public.lesson_progress for all to authenticated using (student_id = auth.uid() and public.is_lesson_student(lesson_id)) with check (student_id = auth.uid() and public.is_lesson_student(lesson_id));
create policy "teachers read assigned student progress" on public.lesson_progress for select to authenticated using (exists (select 1 from public.lessons l join public.courses c on c.id = l.course_id where l.id = lesson_id and c.teacher_id = auth.uid()));
create policy "admins manage progress" on public.lesson_progress for all to authenticated using (public.is_catalog_admin()) with check (public.is_catalog_admin());

insert into storage.buckets (id, name, public) values ('course-resources', 'course-resources', false) on conflict (id) do nothing;
create policy "course members read course resources storage" on storage.objects for select to authenticated using (bucket_id = 'course-resources' and (public.is_course_student((storage.foldername(name))[1]::uuid) or exists (select 1 from public.courses c where c.id = (storage.foldername(name))[1]::uuid and c.teacher_id = auth.uid())));
create policy "course owners upload resources storage" on storage.objects for insert to authenticated with check (bucket_id = 'course-resources' and exists (select 1 from public.courses c where c.id = (storage.foldername(name))[1]::uuid and c.teacher_id = auth.uid()));
create policy "course owners update resources storage" on storage.objects for update to authenticated using (bucket_id = 'course-resources' and exists (select 1 from public.courses c where c.id = (storage.foldername(name))[1]::uuid and c.teacher_id = auth.uid())) with check (bucket_id = 'course-resources');
create policy "course owners delete resources storage" on storage.objects for delete to authenticated using (bucket_id = 'course-resources' and exists (select 1 from public.courses c where c.id = (storage.foldername(name))[1]::uuid and c.teacher_id = auth.uid()));
