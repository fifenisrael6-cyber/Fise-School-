-- Enforce final-year series/specialty selection server-side during Supabase Auth signup.
-- This complements the Flutter form; it does not weaken RLS or change non-final registrations.
create or replace function public.validate_final_year_signup_track()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  requested_role text := coalesce(metadata ->> 'role', 'student');
  requested_level_id uuid;
  requested_series_id uuid;
  requested_specialty_id uuid;
  requested_level_order integer;
  requested_sector text;
begin
  if requested_role <> 'student' then
    return new;
  end if;

  if coalesce(metadata ->> 'exam_level_id', '') !~ '^[0-9a-fA-F-]{36}$' then
    return new;
  end if;
  requested_level_id := (metadata ->> 'exam_level_id')::uuid;

  select el.level_order, el.sector::text
    into requested_level_order, requested_sector
  from public.exam_levels el
  where el.id = requested_level_id and el.active;

  if not found or requested_level_order <> 7 then
    return new;
  end if;

  if requested_sector = 'general' then
    if coalesce(metadata ->> 'series_id', '') ~ '^[0-9a-fA-F-]{36}$' then
      requested_series_id := (metadata ->> 'series_id')::uuid;
    end if;

    if requested_series_id is null
       or not exists (
         select 1 from public.exam_level_series els
         where els.exam_level_id = requested_level_id
           and els.series_id = requested_series_id
           and els.active
       ) then
      raise exception 'A final-year general student must choose an official series for this subsystem';
    end if;
  elsif requested_sector = 'technical' then
    if coalesce(metadata ->> 'specialty_id', '') ~ '^[0-9a-fA-F-]{36}$' then
      requested_specialty_id := (metadata ->> 'specialty_id')::uuid;
    end if;

    if requested_specialty_id is null
       or not exists (
         select 1 from public.exam_level_specialties es
         where es.exam_level_id = requested_level_id
           and es.specialty_id = requested_specialty_id
           and es.active
       ) then
      raise exception 'A final-year technical student must choose an official specialty for this subsystem';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists auth_users_validate_final_year_track on auth.users;
create trigger auth_users_validate_final_year_track
before insert on auth.users
for each row execute function public.validate_final_year_signup_track();
