-- Repair student classroom matching for generic classes.
-- A generic classroom may intentionally have no series or specialty, so it
-- remains compatible with a student's more specific profile.

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
      select 1 from public.school_classes c
      where c.id = requested_class_id
        and c.is_active
        and c.subsystem::text = requested_subsystem
        and c.sector::text = requested_sector
        and c.exam_level_id = requested_exam_level_id
        and (
          (c.sector = 'general'
            and (c.series_id is null or c.series_id is not distinct from requested_series_id)
            and c.specialty_id is null)
          or
          (c.sector = 'technical'
            and (c.specialty_id is null or c.specialty_id is not distinct from requested_specialty_id)
            and c.series_id is null)
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

-- Repair existing students whose selected classroom is already stored in the
-- profile but whose class_students membership is missing.
insert into public.class_students (class_id, student_id, joined_at, is_active)
select chosen.class_id, chosen.student_id, now(), true
from (
  select distinct on (p.id)
    c.id as class_id,
    p.id as student_id
  from public.profiles p
  join public.school_classes c
    on c.is_active
   and (c.name = p.class_name or c.display_name = p.class_name)
   and c.subsystem = p.subsystem
   and c.sector = p.sector
   and (p.exam_level_id is null or c.exam_level_id = p.exam_level_id)
   and (c.series_id is null or c.series_id = p.series_id)
   and (c.specialty_id is null or c.specialty_id = p.specialty_id)
  left join public.academic_years ay on ay.id = c.academic_year_id
  where p.role = 'student'
    and p.class_name is not null
    and not exists (
      select 1 from public.class_students cs
      where cs.student_id = p.id and cs.is_active
    )
  order by
    p.id,
    (c.series_id is not null and c.series_id = p.series_id) desc,
    (c.specialty_id is not null and c.specialty_id = p.specialty_id) desc,
    coalesce(ay.is_current, false) desc,
    c.created_at desc
) chosen
on conflict (class_id, student_id) where is_active
do update set is_active = true, joined_at = excluded.joined_at;