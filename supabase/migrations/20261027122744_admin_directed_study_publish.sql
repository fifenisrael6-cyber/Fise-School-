-- L'administration peut publier un TD sur un cours existant même si
-- l'administrateur n'est pas lui-même affecté à la salle.
-- Les enseignants restent soumis à leurs affectations habituelles.
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
  select * into v_course
  from public.courses
  where id = new.course_id and status <> 'archived';

  if not found
     or v_course.class_id is distinct from new.source_class_id
     or v_course.subject_id is distinct from new.subject_id
     or v_course.teacher_id is distinct from new.teacher_id then
    raise exception 'TD must match the teacher, subject and source classroom of its course';
  end if;

  select * into v_source
  from public.school_classes
  where id = new.source_class_id and is_active;

  if not found then
    raise exception 'TD source classroom is missing or inactive';
  end if;

  if not public.is_admin()
     and not public.teacher_can_manage_class(new.source_class_id, new.teacher_id) then
    raise exception 'Teacher is not assigned to the source classroom';
  end if;

  if not public.is_admin() and exists (
    select 1
    from unnest(coalesce(new.requested_class_ids, '{}'::uuid[])) selected(id)
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
        and (
          candidate.exam_level_id is not distinct from v_source.exam_level_id
          or candidate.exam_level_id is null
          or v_source.exam_level_id is null
        )
        and (
          candidate.series_id is not distinct from v_source.series_id
          or candidate.series_id is null
          or v_source.series_id is null
        )
        and (
          candidate.specialty_id is not distinct from v_source.specialty_id
          or candidate.specialty_id is null
          or v_source.specialty_id is null
        )
    ) into new.target_class_ids;

    new.published_at := coalesce(new.published_at, now());
  end if;

  return new;
end;
$$;