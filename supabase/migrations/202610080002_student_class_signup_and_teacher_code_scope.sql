-- Student classroom membership is created from the classroom selected at signup.
-- Teacher access codes never enroll students.

drop function if exists public.join_class_with_teacher_access_code(text);

drop policy if exists "public can read active school classes for signup" on public.school_classes;
create policy "public can read active school classes for signup"
on public.school_classes
for select to anon
using (is_active = true);

grant select on public.school_classes to anon;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  requested_role text := coalesce(metadata ->> 'role', 'student');
  requested_subsystem text := metadata ->> 'subsystem';
  requested_sector text := metadata ->> 'sector';
  requested_class_id uuid;
  requested_exam_level_id uuid;
  requested_series_id uuid;
  requested_specialty_id uuid;
begin
  if metadata ->> 'class_id' ~ '^[0-9a-fA-F-]{36}$' then
    requested_class_id := (metadata ->> 'class_id')::uuid;
  end if;
  if metadata ->> 'exam_level_id' ~ '^[0-9a-fA-F-]{36}$' then
    requested_exam_level_id := (metadata ->> 'exam_level_id')::uuid;
  end if;
  if metadata ->> 'series_id' ~ '^[0-9a-fA-F-]{36}$' then
    requested_series_id := (metadata ->> 'series_id')::uuid;
  end if;
  if metadata ->> 'specialty_id' ~ '^[0-9a-fA-F-]{36}$' then
    requested_specialty_id := (metadata ->> 'specialty_id')::uuid;
  end if;

  insert into public.profiles (
    id, first_name, last_name, email, role, preferred_language,
    subsystem, sector, exam_level_id, exam_id, series_id, specialty_id,
    class_name, exam_level_label, exam_label, track_label
  )
  values (
    new.id,
    coalesce(nullif(trim(metadata ->> 'first_name'), ''), nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'Utilisateur'),
    coalesce(nullif(trim(metadata ->> 'last_name'), ''), 'Fise'),
    new.email,
    case when requested_role in ('student', 'teacher') then requested_role else 'student' end,
    case when metadata ->> 'preferred_language' in ('fr', 'en') then metadata ->> 'preferred_language' else 'fr' end,
    case when requested_subsystem in ('francophone', 'anglophone') then requested_subsystem::public.catalog_subsystem else null end,
    case when requested_sector in ('general', 'technical') then requested_sector::public.catalog_sector else null end,
    requested_exam_level_id,
    case when metadata ->> 'exam_id' ~ '^[0-9a-fA-F-]{36}$' then (metadata ->> 'exam_id')::uuid else null end,
    requested_series_id,
    requested_specialty_id,
    nullif(trim(metadata ->> 'class_name'), ''),
    nullif(trim(metadata ->> 'exam_level'), ''),
    nullif(trim(metadata ->> 'exam'), ''),
    nullif(trim(metadata ->> 'track'), '')
  )
  on conflict (id) do nothing;

  if requested_role = 'student' and requested_class_id is not null then
    if not exists (
      select 1
      from public.school_classes c
      where c.id = requested_class_id
        and c.is_active
        and c.subsystem::text = requested_subsystem
        and c.sector::text = requested_sector
        and c.exam_level_id = requested_exam_level_id
        and (
          (c.sector = 'general' and c.series_id is not distinct from requested_series_id and c.specialty_id is null)
          or
          (c.sector = 'technical' and c.specialty_id is not distinct from requested_specialty_id and c.series_id is null)
        )
    ) then
      raise exception 'Selected classroom is not compatible with the student profile';
    end if;

    update public.class_students
      set is_active = false
      where student_id = new.id and is_active = true;

    insert into public.class_students (class_id, student_id, joined_at, is_active)
    values (requested_class_id, new.id, now(), true)
    on conflict (class_id, student_id) where is_active
    do update set is_active = true, joined_at = now();
  end if;

  return new;
end;
$$;

create or replace function public.validate_teacher_access_code(
  p_code text,
  p_class_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text := trim(p_code);
  v_class_id uuid;
  v_teacher uuid;
  v_code_id text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.profiles where id = v_user and role = 'student') then
    raise exception 'Only students can validate teacher access codes';
  end if;

  if lower(v_code) like 'fise%' then
    v_code := substring(v_code from 5);
  end if;

  select t.id, t.teacher_id, t.class_id
    into v_code_id, v_teacher, v_class_id
  from public.teacher_access_codes t
  where lower(trim(t.code)) = lower(v_code)
    and t.is_active = true
  limit 1;

  if v_code_id is null or v_class_id is distinct from p_class_id then
    return false;
  end if;

  if not public.is_student_in_class(p_class_id, v_user) then
    return false;
  end if;

  insert into public.teacher_access_memberships(student_id, teacher_id, class_id, access_code_id)
  values (v_user, v_teacher, p_class_id, v_code_id)
  on conflict (student_id, teacher_id, class_id)
  do update set access_code_id = excluded.access_code_id;

  return true;
end;
$$;

revoke all on function public.validate_teacher_access_code(text, uuid) from public;
grant execute on function public.validate_teacher_access_code(text, uuid) to authenticated;
