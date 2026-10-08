-- Ensure a student signup creates the active classroom membership consumed by the Cours page.
-- Validate the selected room against the signup metadata before assigning it.

create or replace function public.sync_signup_language_option()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  requested_role text := coalesce(metadata ->> 'role', 'student');
  requested_class_id uuid;
  requested_option text := nullif(trim(metadata ->> 'language_option'), '');
  selected_class public.school_classes%rowtype;
begin
  if requested_role <> 'student' then
    return new;
  end if;

  if coalesce(metadata ->> 'class_id', '') !~ '^[0-9a-fA-F-]{36}$' then
    raise exception 'A student must select a classroom matching the chosen class and option';
  end if;
  requested_class_id := (metadata ->> 'class_id')::uuid;

  select c.* into selected_class
  from public.school_classes c
  where c.id = requested_class_id
    and c.is_active
    and c.language_option is not distinct from requested_option
    and c.exam_level_id::text is not distinct from nullif(metadata ->> 'exam_level_id', '')
    and c.series_id::text is not distinct from nullif(metadata ->> 'series_id', '')
    and c.specialty_id::text is not distinct from nullif(metadata ->> 'specialty_id', '')
    and c.subsystem::text is not distinct from nullif(metadata ->> 'subsystem', '')
    and c.sector::text is not distinct from nullif(metadata ->> 'sector', '');

  if not found then
    raise exception 'Selected classroom does not match the chosen level, track, or language option';
  end if;

  update public.profiles
  set subsystem = selected_class.subsystem,
      sector = selected_class.sector,
      exam_level_id = selected_class.exam_level_id,
      series_id = selected_class.series_id,
      specialty_id = selected_class.specialty_id,
      class_name = selected_class.display_name,
      exam_level_label = nullif(metadata ->> 'exam_level', ''),
      exam_label = nullif(metadata ->> 'exam', ''),
      track_label = nullif(metadata ->> 'track', ''),
      language_option = requested_option,
      updated_at = now()
  where id = new.id;

  insert into public.class_students (class_id, student_id, is_active)
  select selected_class.id, new.id, true
  where not exists (
    select 1 from public.class_students cs
    where cs.class_id = selected_class.id
      and cs.student_id = new.id
      and cs.is_active
  );

  return new;
end;
$$;

drop trigger if exists zz_sync_signup_language_option on auth.users;
create trigger zz_sync_signup_language_option
after insert on auth.users
for each row execute function public.sync_signup_language_option();
