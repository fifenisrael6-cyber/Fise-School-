-- Classify subjects independently from classroom access and teacher specialty.
alter table public.subjects
  add column if not exists teaching_stream text not null default 'both';

alter table public.subjects
  drop constraint if exists subjects_teaching_stream_check;
alter table public.subjects
  add constraint subjects_teaching_stream_check
  check (teaching_stream in ('literary', 'scientific', 'both'));

-- Best-effort initial classification for obvious stream-specific subjects.
-- Languages and genuinely shared subjects remain available to both streams.
update public.subjects
set teaching_stream = 'scientific'
where lower(coalesce(name_fr, '') || ' ' || coalesce(name_en, '') || ' ' || coalesce(code, ''))
  ~ '(math[ée]mat|physique|physics|chimie|chemistry|biolog|svt|informatique|computer science|algorithm|robotique|robotics|sciences? physiques|sciences? de la vie|g[eé]ologie|geology|electronique|electronics)';

update public.subjects
set teaching_stream = 'literary'
where lower(unaccent(coalesce(name_fr, '') || ' ' || coalesce(name_en, '') || ' ' || coalesce(code, '')))
  ~ '(philosoph|litt[eé]rature|literature|histoire|history|g[eé]ographie|geography|sociolog|psycholog|droit|law|latin|grec ancien|ancient greek|instruction civique|civic education)'
  and teaching_stream = 'both';

-- Enforce the same stream boundary when a teacher creates a course through the API.
create or replace function public.enforce_course_destination_scope()
returns trigger language plpgsql security definer set search_path=public
as $function$
declare
  v_class public.school_classes%rowtype;
  v_curriculum public.curricula%rowtype;
  v_subject public.subjects%rowtype;
  v_teacher public.profiles%rowtype;
  v_stream text;
begin
  select * into v_class from public.school_classes where id=new.class_id and is_active;
  if not found then raise exception 'Target classroom is missing or inactive'; end if;

  select * into v_teacher from public.profiles where id=new.teacher_id;
  if not found or v_teacher.role<>'teacher' then raise exception 'Only a teacher can publish a course'; end if;
  if v_teacher.subsystem is not null and v_teacher.subsystem<>v_class.subsystem then raise exception 'Course destination belongs to another subsystem'; end if;
  if v_teacher.sector is not null and v_teacher.sector<>v_class.sector then raise exception 'Course destination belongs to another sector'; end if;

  select * into v_subject from public.subjects where id=new.subject_id and is_active;
  if not found then raise exception 'Subject is missing or inactive'; end if;
  if v_subject.subsystem<>v_class.subsystem or v_subject.sector<>v_class.sector then raise exception 'Subject does not match the classroom subsystem and sector'; end if;

  v_stream := lower(trim(coalesce(v_teacher.teaching_stream, '')));
  if v_stream in ('littéraire','litteraire') then v_stream := 'literary'; end if;
  if v_stream in ('scientifique') then v_stream := 'scientific'; end if;
  if v_stream in ('literary','scientific') and v_subject.teaching_stream not in ('both', v_stream) then
    raise exception 'This subject is not available for your teaching stream';
  end if;

  select * into v_curriculum from public.curricula where id=new.curriculum_id and is_active;
  if not found then raise exception 'Curriculum is missing or inactive'; end if;
  if v_curriculum.subject_id<>new.subject_id or v_curriculum.subsystem<>v_class.subsystem or v_curriculum.sector<>v_class.sector then raise exception 'Curriculum does not match the selected subject and classroom'; end if;
  if new.chapter_id is not null and not exists(select 1 from public.course_chapters ch where ch.id=new.chapter_id and ch.curriculum_id=new.curriculum_id and ch.is_active) then raise exception 'Chapter does not belong to the selected curriculum'; end if;
  if v_teacher.teaching_stream is not null and lower(trim(v_teacher.teaching_stream)) not in ('literary','litteraire','littéraire','scientific','scientifique','general','technical','') then raise exception 'Teacher must have exactly one valid teaching stream'; end if;
  return new;
end;
$function$;

drop trigger if exists enforce_course_destination_scope on public.courses;
create trigger enforce_course_destination_scope
before insert or update of curriculum_id,chapter_id,subject_id,teacher_id,class_id
on public.courses for each row execute function public.enforce_course_destination_scope();
