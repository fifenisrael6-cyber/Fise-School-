-- One teacher-owned FISE code is valid for the selected classroom.
-- It activates both the evaluation access and all groups targeted at that classroom.
create or replace function public.join_teacher_access_code_for_class(
  p_code text,
  p_expected_class_id uuid
)
returns table(teacher_id uuid, class_id uuid, access_code_id text)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_user uuid := auth.uid();
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  v_suffix text;
  v_teacher uuid;
  v_canonical_code text;
  v_access_code_id text;
  v_class public.school_classes%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_expected_class_id is null then raise exception 'A classroom is required'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_user and p.role = 'student') then
    raise exception 'Only students can join a teacher space';
  end if;

  v_code := translate(v_code, '‐‑‒–—−', '------');
  if v_code !~ '^FISE-?[A-Z0-9]{6}$' then
    raise exception 'Use the teacher FISE code in the format FISE-XXXXXX';
  end if;
  v_suffix := regexp_replace(v_code, '^FISE-?', '', 'i');
  v_canonical_code := 'FISE-' || v_suffix;

  select c.teacher_id, c.code
    into v_teacher, v_canonical_code
    from public.teacher_group_access_codes c
   where upper(regexp_replace(trim(c.code), '^FISE-?', '', 'i')) = v_suffix
     and c.is_active = true
   limit 1;
  if v_teacher is null then raise exception 'Invalid or inactive FISE code'; end if;

  select sc.* into v_class
    from public.school_classes sc
   where sc.id = p_expected_class_id and sc.is_active = true;
  if not found then raise exception 'The selected classroom is unavailable'; end if;

  if not public.teacher_can_manage_class(p_expected_class_id, v_teacher)
     and not exists (
       select 1 from public.message_groups g
        where g.owner_id = v_teacher
          and (g.class_id = p_expected_class_id or exists (
            select 1 from public.message_group_classrooms gc
             where gc.group_id = g.id and gc.class_id = p_expected_class_id
          ))
     )
     and not exists (
       select 1 from public.assignments a
        where a.teacher_id = v_teacher and a.class_id = p_expected_class_id
          and a.status in ('published', 'closed')
     ) then
    raise exception 'This teacher does not have a group or evaluation for the selected classroom';
  end if;

  if exists (
    select 1 from public.class_students cs
     where cs.student_id = v_user and cs.is_active = true and cs.class_id <> p_expected_class_id
  ) then
    raise exception 'Student already assigned to another classroom';
  end if;

  insert into public.teacher_access_codes(id, teacher_id, code, class_id, is_active, updated_at)
  values (v_teacher::text || ':' || p_expected_class_id::text, v_teacher, v_canonical_code, p_expected_class_id::text, true, now())
  on conflict (teacher_id, class_id)
  do update set code = excluded.code, is_active = true, updated_at = now()
  returning id into v_access_code_id;

  update public.profiles p
     set subsystem = v_class.subsystem,
         sector = v_class.sector,
         exam_level_id = v_class.exam_level_id,
         exam_id = (select el.exam_id from public.exam_levels el where el.id = v_class.exam_level_id),
         exam_level_label = case when p.preferred_language = 'en'
           then (select el.level_name_en from public.exam_levels el where el.id = v_class.exam_level_id)
           else (select el.level_name_fr from public.exam_levels el where el.id = v_class.exam_level_id) end,
         exam_label = case when p.preferred_language = 'en'
           then (select e.name_en from public.exams e join public.exam_levels el on el.exam_id = e.id where el.id = v_class.exam_level_id)
           else (select e.name_fr from public.exams e join public.exam_levels el on el.exam_id = e.id where el.id = v_class.exam_level_id) end,
         track_label = case
           when v_class.series_id is not null then
             (select case when p.preferred_language = 'en' then s.name_en else s.name_fr end from public.series s where s.id = v_class.series_id)
           when v_class.specialty_id is not null then
             (select case when p.preferred_language = 'en' then sp.name_en else sp.name_fr end from public.specialties sp where sp.id = v_class.specialty_id)
           else null end,
         series_id = v_class.series_id,
         specialty_id = v_class.specialty_id,
         class_name = v_class.display_name,
         language_option = v_class.language_option,
         updated_at = now()
   where p.id = v_user;

  if not exists (
    select 1 from public.class_students cs
     where cs.student_id = v_user and cs.class_id = p_expected_class_id and cs.is_active = true
  ) then
    insert into public.class_students(class_id, student_id, joined_at, is_active)
    values (p_expected_class_id, v_user, now(), true);
  end if;

  insert into public.teacher_fise_code_memberships(student_id, teacher_id, class_id, code, joined_at)
  values (v_user, v_teacher, p_expected_class_id, v_canonical_code, now())
  on conflict (student_id, teacher_id, class_id)
  do update set code = excluded.code, joined_at = now();

  insert into public.teacher_access_memberships(student_id, teacher_id, class_id, access_code_id, joined_at)
  values (v_user, v_teacher, p_expected_class_id, v_access_code_id, now())
  on conflict (student_id, teacher_id, class_id)
  do update set access_code_id = excluded.access_code_id, joined_at = now();

  insert into public.message_group_members(group_id, user_id, role)
  select distinct g.id, v_user, 'student'
    from public.message_groups g
   where g.owner_id = v_teacher
     and (g.class_id = p_expected_class_id or exists (
       select 1 from public.message_group_classrooms gc
        where gc.group_id = g.id and gc.class_id = p_expected_class_id
     ))
  on conflict (group_id, user_id) do nothing;

  return query select v_teacher, p_expected_class_id, v_access_code_id;
end;
$$;

revoke all on function public.join_teacher_access_code_for_class(text, uuid) from public, anon;
grant execute on function public.join_teacher_access_code_for_class(text, uuid) to authenticated;
notify pgrst, 'reload schema';
