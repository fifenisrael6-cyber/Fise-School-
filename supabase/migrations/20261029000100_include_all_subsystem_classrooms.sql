-- Allow students to change into any valid active classroom in their own subsystem and sector.
-- Do not require a teacher to have followed the destination room; the classroom catalogue is complete.
-- Keep the current academic year, valid MINESEC series/specialties and language-option exclusions.
create or replace function public.list_student_available_classes()
returns table (
  class_id uuid, class_name text, subsystem text, sector text,
  exam_level_id uuid, exam_id uuid, series_id uuid, specialty_id uuid,
  level_order integer, language_option text, academic_year_id uuid,
  exam_level_label text, exam_label text, track_label text,
  relation text, recommended boolean
)
language plpgsql stable security definer set search_path = public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_current public.school_classes%rowtype;
  v_current_order integer;
  v_year uuid;
  v_subsystem text;
  v_sector text;
  v_series uuid;
  v_specialty uuid;
begin
  if v_user_id is null then raise exception 'Authentication is required'; end if;
  select * into v_profile from public.profiles where id = v_user_id and role = 'student';
  if not found then raise exception 'Only student accounts can change classroom'; end if;

  select sc.* into v_current
  from public.class_students cs
  join public.school_classes sc on sc.id = cs.class_id
  join public.academic_years ay on ay.id = sc.academic_year_id
  where cs.student_id = v_user_id and cs.is_active and sc.is_active and ay.is_current
  order by cs.joined_at desc limit 1;

  if v_current.id is not null then
    select el.level_order into v_current_order from public.exam_levels el where el.id = v_current.exam_level_id;
    v_year := v_current.academic_year_id;
    v_subsystem := v_current.subsystem::text;
    v_sector := v_current.sector::text;
    v_series := coalesce(v_profile.series_id, v_current.series_id);
    v_specialty := coalesce(v_profile.specialty_id, v_current.specialty_id);
  else
    select ay.id into v_year from public.academic_years ay where ay.is_current limit 1;
    v_subsystem := v_profile.subsystem::text;
    v_sector := v_profile.sector::text;
    v_series := v_profile.series_id;
    v_specialty := v_profile.specialty_id;
  end if;

  if v_subsystem is null or v_sector is null
     or v_subsystem not in ('francophone','anglophone')
     or v_sector not in ('general','technical') then
    raise exception 'Student subsystem and sector must be set before changing classroom';
  end if;

  return query
  select dest.id, dest.display_name, dest.subsystem::text, dest.sector::text,
    dest.exam_level_id, level.exam_id, dest.series_id, dest.specialty_id,
    level.level_order, dest.language_option, dest.academic_year_id,
    case when v_profile.preferred_language = 'en' then level.level_name_en else level.level_name_fr end,
    case when v_profile.preferred_language = 'en' then exam.name_en else exam.name_fr end,
    case when v_profile.preferred_language = 'en' then coalesce(series.name_en, specialty.name_en)
      else coalesce(series.name_fr, specialty.name_fr) end,
    case when level.level_order = v_current_order + 1 then 'next'
      when level.level_order = v_current_order then 'same'
      when level.level_order < v_current_order then 'previous' else 'other' end,
    (v_current_order is not null and level.level_order = v_current_order + 1
      and (v_series is null or dest.series_id = v_series)
      and (v_specialty is null or dest.specialty_id = v_specialty))
  from public.school_classes dest
  join public.academic_years ay on ay.id = dest.academic_year_id
  join public.exam_levels level on level.id = dest.exam_level_id and level.active
  left join public.exams exam on exam.id = level.exam_id
  left join public.series series on series.id = dest.series_id
  left join public.specialties specialty on specialty.id = dest.specialty_id
  where dest.is_active and ay.is_current and dest.academic_year_id = v_year
    and dest.id is distinct from v_current.id
    and dest.subsystem::text = v_subsystem and dest.sector::text = v_sector
    and position('_' in coalesce(dest.language_option,'')) = 0
    and (dest.series_id is null or exists (
      select 1 from public.exam_level_series els
      where els.exam_level_id = dest.exam_level_id and els.series_id = dest.series_id and els.active))
    and (dest.specialty_id is null or exists (
      select 1 from public.exam_level_specialties es
      where es.exam_level_id = dest.exam_level_id and es.specialty_id = dest.specialty_id and es.active))
    and not (dest.series_id is null and dest.specialty_id is null and exists (
      select 1 from public.school_classes specific
      where specific.is_active and specific.id <> dest.id
        and specific.academic_year_id = dest.academic_year_id
        and specific.exam_level_id = dest.exam_level_id
        and specific.subsystem = dest.subsystem and specific.sector = dest.sector
        and (specific.series_id is not null or specific.specialty_id is not null)))
  order by 16 desc, level.level_order, dest.display_name;
end;
$function$;

revoke all on function public.list_student_available_classes() from public, anon;
grant execute on function public.list_student_available_classes() to authenticated;
notify pgrst, 'reload schema';
