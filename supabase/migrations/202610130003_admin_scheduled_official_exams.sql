-- Admin-scheduled official evaluations (PDF) attached to a subject and class.
-- Existing teacher assignments keep their course requirement; only catalog admins
-- may create course-less scheduled exam records.
alter table public.assignments
  alter column course_id drop not null;

alter table public.assignments
  add column if not exists exam_id uuid references public.exams(id) on delete set null,
  add column if not exists subject_id uuid references public.subjects(id) on delete set null,
  add column if not exists evaluation_file_path text,
  add column if not exists evaluation_file_name text;

create index if not exists assignments_exam_subject_window_idx
  on public.assignments (exam_id, subject_id, starts_at, due_at);

create or replace function public.validate_assignment_context()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_course public.courses%rowtype;
begin
  if new.course_id is null then
    if not public.is_catalog_admin() then
      raise exception 'Only an administrator can schedule an official exam without a course';
    end if;
    if new.subject_id is null then
      raise exception 'An official exam must specify a subject';
    end if;
    if new.status = 'published'
       and nullif(trim(coalesce(new.evaluation_file_path, '')), '') is null then
      raise exception 'A published official exam must include its PDF file';
    end if;
    if not exists (
      select 1 from public.class_subjects cs
      where cs.class_id = new.class_id
        and cs.subject_id = new.subject_id
        and cs.is_active
    ) then
      raise exception 'The selected subject is not assigned to this classroom';
    end if;
    if new.starts_at is not null and new.due_at is not null
       and new.due_at <= new.starts_at then
      raise exception 'The deadline must be later than the start time';
    end if;
    return new;
  end if;

  select * into v_course
  from public.courses
  where id = new.course_id;

  if not found or v_course.status = 'archived' then
    raise exception 'Assignment course is not available';
  end if;

  if new.class_id is distinct from v_course.class_id then
    raise exception 'Assignment class must match the course class';
  end if;

  if new.teacher_id is distinct from v_course.teacher_id and not public.is_admin() then
    raise exception 'Assignment teacher must own the selected course';
  end if;

  if not public.is_admin()
     and not public.teacher_can_manage_class(new.class_id, new.teacher_id) then
    raise exception 'Teacher is not assigned to the selected class';
  end if;

  if new.lesson_id is not null and not exists (
    select 1 from public.lessons l
    where l.id = new.lesson_id
      and l.course_id = new.course_id
  ) then
    raise exception 'Assignment lesson must belong to the selected course';
  end if;

  if new.starts_at is not null and new.due_at is not null
     and new.due_at <= new.starts_at then
    raise exception 'The deadline must be later than the start time';
  end if;

  return new;
end;
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('assignment-files', 'assignment-files', false, 52428800, array['application/pdf'])
on conflict (id) do update
set public = false,
    file_size_limit = 52428800,
    allowed_mime_types = array['application/pdf'];

drop policy if exists "admins upload scheduled exam files" on storage.objects;
create policy "admins upload scheduled exam files"
on storage.objects for insert to authenticated
with check (bucket_id = 'assignment-files' and public.is_catalog_admin());

drop policy if exists "authorized users read scheduled exam files" on storage.objects;
create policy "authorized users read scheduled exam files"
on storage.objects for select to authenticated
using (
  bucket_id = 'assignment-files'
  and exists (
    select 1
    from public.assignments a
    where a.evaluation_file_path = storage.objects.name
      and (
        public.is_catalog_admin()
        or a.teacher_id = auth.uid()
        or (
          a.status in ('published', 'closed')
          and public.is_student_in_class(a.class_id, auth.uid())
          and (a.starts_at is null or statement_timestamp() >= a.starts_at)
          and (a.due_at is null or statement_timestamp() < a.due_at)
        )
      )
  )
);

drop policy if exists "admins update scheduled exam files" on storage.objects;
create policy "admins update scheduled exam files"
on storage.objects for update to authenticated
using (bucket_id = 'assignment-files' and public.is_catalog_admin())
with check (bucket_id = 'assignment-files' and public.is_catalog_admin());

drop policy if exists "admins delete scheduled exam files" on storage.objects;
create policy "admins delete scheduled exam files"
on storage.objects for delete to authenticated
using (bucket_id = 'assignment-files' and public.is_catalog_admin());
