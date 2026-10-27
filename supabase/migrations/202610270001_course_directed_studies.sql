-- Travaux dirigés par cours, avec diffusion aux salles compatibles.
-- Migration additive : aucune donnée pédagogique existante n'est supprimée.
create table if not exists public.directed_studies (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  source_class_id uuid not null references public.school_classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text,
  storage_path text not null,
  file_name text not null,
  target_class_ids uuid[] not null default '{}',
  status text not null default 'published' check (status in ('draft','published')),
  created_at timestamptz not null default now(),
  published_at timestamptz
);
create index if not exists directed_studies_course_idx on public.directed_studies(course_id, status, created_at desc);
create index if not exists directed_studies_teacher_idx on public.directed_studies(teacher_id, created_at desc);
alter table public.directed_studies enable row level security;

-- Les élèves ne voient que les TD publiés dans une salle dont ils sont membres.
drop policy if exists "students read directed studies for their classes" on public.directed_studies;
create policy "students read directed studies for their classes"
on public.directed_studies for select to authenticated
using (
  status = 'published'
  and exists (
    select 1 from public.class_students cs
    where cs.student_id = auth.uid()
      and cs.is_active
      and cs.class_id = any(target_class_ids)
  )
);
drop policy if exists "teachers manage own directed studies" on public.directed_studies;
create policy "teachers manage own directed studies"
on public.directed_studies for all to authenticated
using (teacher_id = auth.uid() and public.teacher_can_manage_class(source_class_id, auth.uid()))
with check (teacher_id = auth.uid() and public.teacher_can_manage_class(source_class_id, auth.uid()));

-- Au moment de la publication, complète en arrière-plan les salles compatibles :
-- même matière, même système/sous-système et niveau/série/spécialité compatibles.
create or replace function public.expand_directed_study_compatible_classes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source public.school_classes%rowtype;
  v_course public.courses%rowtype;
begin
  select * into v_course from public.courses
  where id = new.course_id and status <> 'archived';
  if not found or v_course.class_id is distinct from new.source_class_id
     or v_course.subject_id is distinct from new.subject_id
     or v_course.teacher_id is distinct from new.teacher_id then
    raise exception 'TD must match the teacher, subject and source classroom of its course';
  end if;

  select * into v_source from public.school_classes
  where id = new.source_class_id and is_active;
  if not found then raise exception 'TD source classroom is missing or inactive'; end if;

  if not public.teacher_can_manage_class(new.source_class_id, new.teacher_id) then
    raise exception 'Teacher is not assigned to the source classroom';
  end if;
  if exists (
    select 1 from unnest(coalesce(new.target_class_ids, '{}'::uuid[])) selected(id)
    where not public.teacher_can_manage_class(selected.id, new.teacher_id)
  ) then
    raise exception 'Teacher may select only classrooms they teach';
  end if;

  if new.status = 'published' then
    select array(
      select distinct candidate.id
      from public.school_classes candidate
      join public.class_subjects cs
        on cs.class_id = candidate.id
       and cs.subject_id = new.subject_id
       and cs.is_active
      where candidate.is_active
        and candidate.subsystem = v_source.subsystem
        and candidate.sector = v_source.sector
        and (candidate.exam_level_id is not distinct from v_source.exam_level_id
             or candidate.exam_level_id is null or v_source.exam_level_id is null)
        and (candidate.series_id is not distinct from v_source.series_id
             or candidate.series_id is null or v_source.series_id is null)
        and (candidate.specialty_id is not distinct from v_source.specialty_id
             or candidate.specialty_id is null or v_source.specialty_id is null)

    ) into new.target_class_ids;
    new.published_at := coalesce(new.published_at, now());
  end if;
  return new;
end;
$$;

drop trigger if exists directed_studies_expand_compatible_classes on public.directed_studies;
create trigger directed_studies_expand_compatible_classes
before insert or update of status, target_class_ids, source_class_id, subject_id
on public.directed_studies
for each row execute function public.expand_directed_study_compatible_classes();

insert into storage.buckets (id, name, public)
values ('directed-study-files', 'directed-study-files', false)
on conflict (id) do nothing;

drop policy if exists "teachers upload directed study files" on storage.objects;
create policy "teachers upload directed study files"
on storage.objects for insert to authenticated
with check (bucket_id = 'directed-study-files' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "read directed study files for enrolled classes" on storage.objects;
create policy "read directed study files for enrolled classes"
on storage.objects for select to authenticated
using (
  bucket_id = 'directed-study-files'
  and exists (
    select 1 from public.directed_studies td
    where td.storage_path = name
      and td.status = 'published'
      and exists (
        select 1 from public.class_students cs
        where cs.student_id = auth.uid()
          and cs.is_active
          and cs.class_id = any(td.target_class_ids)
      )
  )
);
