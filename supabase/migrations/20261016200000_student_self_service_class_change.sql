-- Fise School: safe student self-service move to the next classroom.
-- Keeps the authenticated account, payments, messages, and historical grades.

alter table public.school_classes
  add column if not exists language_option text;

update public.school_classes
set language_option = case
  when position('_lang_' in name) > 0
    then substring(name from '_lang_([a-z]+)$')
  when name ~ '_a5_[a-z]+_[a-z]+$'
    then substring(name from '_a5_([a-z]+_[a-z]+)$')
  else language_option
end
where language_option is null;

create or replace function public.list_student_next_classes()
returns table (
  class_id uuid, class_name text, subsystem text, sector text,
  exam_level_id uuid, exam_id uuid, series_id uuid, specialty_id uuid,
  level_order integer, language_option text, academic_year_id uuid,
  exam_level_label text, exam_label text, track_label text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_current public.school_classes%rowtype;
  v_current_level public.exam_levels%rowtype;
  v_membership_count integer;
  v_language_option text;
begin
  if v_user_id is null then raise exception 'Authentication is required'; end if;

  select * into v_profile from public.profiles
  where id = v_user_id and role = 'student';
  if not found then raise exception 'Only student accounts can change classroom'; end if;

  select count(*) into v_membership_count
  from public.class_students cs
  join public.school_classes sc on sc.id = cs.class_id
  join public.academic_years ay on ay.id = sc.academic_year_id
  where cs.student_id = v_user_id and cs.is_active and sc.is_active and ay.is_current;

  if v_membership_count <> 1 then
    raise exception 'A student must have exactly one active classroom in the current academic year';
  end if;

  select sc.* into v_current
  from public.class_students cs
  join public.school_classes sc on sc.id = cs.class_id
  join public.academic_years ay on ay.id = sc.academic_year_id
  where cs.student_id = v_user_id and cs.is_active and sc.is_active and ay.is_current
  limit 1;

  select * into v_current_level from public.exam_levels
  where id = v_current.exam_level_id and active;
  if not found then raise exception 'The current classroom has no active level in the catalogue'; end if;

  v_language_option := coalesce(nullif(trim(v_profile.language_option), ''),
                                nullif(trim(v_current.language_option), ''));

  return query
  select dest.id, dest.display_name, dest.subsystem::text, dest.sector::text,
         dest.exam_level_id, level.exam_id, dest.series_id, dest.specialty_id,
         level.level_order, dest.language_option, dest.academic_year_id,
         case when v_profile.preferred_language = 'en' then level.level_name_en else level.level_name_fr end,
         case when v_profile.preferred_language = 'en' then exam.name_en else exam.name_fr end,
         case when v_profile.preferred_language = 'en' then coalesce(series.name_en, specialty.name_en)
              else coalesce(series.name_fr, specialty.name_fr) end
  from public.school_classes dest
  join public.academic_years ay on ay.id = dest.academic_year_id
  join public.exam_levels level on level.id = dest.exam_level_id and level.active
  left join public.exams exam on exam.id = level.exam_id
  left join public.series series on series.id = dest.series_id
  left join public.specialties specialty on specialty.id = dest.specialty_id
  where dest.is_active and ay.is_current
    and dest.academic_year_id = v_current.academic_year_id
    and dest.subsystem = v_current.subsystem and dest.sector = v_current.sector
    and level.level_order = v_current_level.level_order + 1
    and (coalesce(v_profile.series_id, v_current.series_id) is null
         or dest.series_id = coalesce(v_profile.series_id, v_current.series_id))
    and (coalesce(v_profile.specialty_id, v_current.specialty_id) is null
         or dest.specialty_id = coalesce(v_profile.specialty_id, v_current.specialty_id))
    and (v_language_option is null
         or lower(coalesce(dest.language_option, '')) = lower(v_language_option))
  order by dest.display_name;
end;
$$;

create or replace function public.change_student_class(target_class_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_source public.school_classes%rowtype;
  v_target public.school_classes%rowtype;
  v_target_level public.exam_levels%rowtype;
  v_membership_count integer;
  v_track_label text;
  v_exam_label text;
  v_level_label text;
  v_updated jsonb;
begin
  if v_user_id is null then raise exception 'Authentication is required'; end if;

  select * into v_profile from public.profiles
  where id = v_user_id and role = 'student' for update;
  if not found then raise exception 'Only student accounts can change classroom'; end if;

  select count(*) into v_membership_count
  from public.class_students cs
  join public.school_classes sc on sc.id = cs.class_id
  join public.academic_years ay on ay.id = sc.academic_year_id
  where cs.student_id = v_user_id and cs.is_active and sc.is_active and ay.is_current;
  if v_membership_count <> 1 then
    raise exception 'A student must have exactly one active classroom in the current academic year';
  end if;

  select sc.* into v_source
  from public.class_students cs
  join public.school_classes sc on sc.id = cs.class_id
  join public.academic_years ay on ay.id = sc.academic_year_id
  where cs.student_id = v_user_id and cs.is_active and sc.is_active and ay.is_current
  limit 1 for update of cs;

  if not exists (select 1 from public.list_student_next_classes() allowed
                where allowed.class_id = target_class_id) then
    raise exception 'The selected classroom is not a valid next step for this student';
  end if;

  select sc.* into v_target from public.school_classes sc
  where sc.id = target_class_id and sc.is_active;
  select * into v_target_level from public.exam_levels
  where id = v_target.exam_level_id and active;

  v_level_label := case when v_profile.preferred_language = 'en'
    then v_target_level.level_name_en else v_target_level.level_name_fr end;
  select case when v_profile.preferred_language = 'en' then e.name_en else e.name_fr end
  into v_exam_label from public.exams e where e.id = v_target_level.exam_id;

  if v_target.series_id is not null then
    select case when v_profile.preferred_language = 'en' then name_en else name_fr end
    into v_track_label from public.series where id = v_target.series_id;
  elsif v_target.specialty_id is not null then
    select case when v_profile.preferred_language = 'en' then name_en else name_fr end
    into v_track_label from public.specialties where id = v_target.specialty_id;
  end if;

  update public.class_students set is_active = false
  where student_id = v_user_id and class_id = v_source.id and is_active;
  insert into public.class_students (class_id, student_id, is_active, joined_at)
  values (v_target.id, v_user_id, true, now());

  update public.profiles as p
  set subsystem = v_target.subsystem, sector = v_target.sector,
      exam_level_id = v_target.exam_level_id, exam_id = v_target_level.exam_id,
      series_id = v_target.series_id, specialty_id = v_target.specialty_id,
      class_name = v_target.display_name, exam_level_label = v_level_label,
      exam_label = v_exam_label, track_label = v_track_label,
      language_option = v_target.language_option
  where p.id = v_user_id
  returning to_jsonb(p) into v_updated;

  return v_updated;
end;
$$;

revoke all on function public.list_student_next_classes() from public, anon;
revoke all on function public.change_student_class(uuid) from public, anon;
grant execute on function public.list_student_next_classes() to authenticated;
grant execute on function public.change_student_class(uuid) to authenticated;
