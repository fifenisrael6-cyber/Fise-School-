-- Fise School — changement de salle simple pour l'élève.
-- Avant : seul le niveau suivant, avec même série ET même option de langue,
-- était proposé ; une erreur à l'inscription ne pouvait pas être corrigée.
-- Maintenant : toutes les salles actives de la même année, du même
-- sous-système et du même enseignement sont proposées, la plus probable
-- (niveau suivant, même série) étant recommandée. Aucun code enseignant requis.

create or replace function public.list_student_available_classes()
returns table (
  class_id uuid, class_name text, subsystem text, sector text,
  exam_level_id uuid, exam_id uuid, series_id uuid, specialty_id uuid,
  level_order integer, language_option text, academic_year_id uuid,
  exam_level_label text, exam_label text, track_label text,
  relation text, recommended boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
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

  select * into v_profile from public.profiles
  where id = v_user_id and role = 'student';
  if not found then raise exception 'Only student accounts can change classroom'; end if;

  select sc.* into v_current
  from public.class_students cs
  join public.school_classes sc on sc.id = cs.class_id
  join public.academic_years ay on ay.id = sc.academic_year_id
  where cs.student_id = v_user_id and cs.is_active and sc.is_active and ay.is_current
  order by cs.joined_at desc
  limit 1;

  if v_current.id is not null then
    select el.level_order into v_current_order from public.exam_levels el
    where el.id = v_current.exam_level_id;
    v_year := v_current.academic_year_id;
    v_subsystem := v_current.subsystem::text;
    v_sector := v_current.sector::text;
    v_series := coalesce(v_profile.series_id, v_current.series_id);
    v_specialty := coalesce(v_profile.specialty_id, v_current.specialty_id);
  else
    -- Élève sans salle active : on s'appuie sur son profil.
    select ay.id into v_year from public.academic_years ay where ay.is_current limit 1;
    v_subsystem := v_profile.subsystem::text;
    v_sector := v_profile.sector::text;
    v_series := v_profile.series_id;
    v_specialty := v_profile.specialty_id;
  end if;

  return query
  select dest.id, dest.display_name, dest.subsystem::text, dest.sector::text,
         dest.exam_level_id, level.exam_id, dest.series_id, dest.specialty_id,
         level.level_order, dest.language_option, dest.academic_year_id,
         case when v_profile.preferred_language = 'en' then level.level_name_en else level.level_name_fr end,
         case when v_profile.preferred_language = 'en' then exam.name_en else exam.name_fr end,
         case when v_profile.preferred_language = 'en' then coalesce(series.name_en, specialty.name_en)
              else coalesce(series.name_fr, specialty.name_fr) end,
         case
           when v_current_order is null then 'other'
           when level.level_order = v_current_order + 1 then 'next'
           when level.level_order = v_current_order then 'same'
           when level.level_order < v_current_order then 'previous'
           else 'other'
         end,
         (v_current_order is not null
          and level.level_order = v_current_order + 1
          and (v_series is null or dest.series_id = v_series)
          and (v_specialty is null or dest.specialty_id = v_specialty))
  from public.school_classes dest
  join public.academic_years ay on ay.id = dest.academic_year_id
  join public.exam_levels level on level.id = dest.exam_level_id and level.active
  left join public.exams exam on exam.id = level.exam_id
  left join public.series series on series.id = dest.series_id
  left join public.specialties specialty on specialty.id = dest.specialty_id
  where dest.is_active and ay.is_current
    and dest.academic_year_id = v_year
    and (v_subsystem is null or dest.subsystem::text = v_subsystem)
    and (v_sector is null or dest.sector::text = v_sector)
    and dest.id is distinct from v_current.id
  order by 16 desc, level.level_order, dest.display_name;
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
  v_target public.school_classes%rowtype;
  v_target_level public.exam_levels%rowtype;
  v_track_label text;
  v_exam_label text;
  v_level_label text;
  v_updated jsonb;
begin
  if v_user_id is null then raise exception 'Authentication is required'; end if;

  select * into v_profile from public.profiles
  where id = v_user_id and role = 'student' for update;
  if not found then raise exception 'Only student accounts can change classroom'; end if;

  if not exists (
    select 1 from public.list_student_available_classes() allowed
    where allowed.class_id = target_class_id
  ) then
    raise exception 'The selected classroom is not available for this student';
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

  -- Quitte toutes les salles actives de l'année de la nouvelle salle,
  -- puis rejoint la nouvelle (une seule salle active par année).
  update public.class_students cs set is_active = false
  where cs.student_id = v_user_id and cs.is_active
    and cs.class_id in (
      select sc.id from public.school_classes sc
      where sc.academic_year_id = v_target.academic_year_id
    );
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

revoke all on function public.list_student_available_classes() from public, anon;
revoke all on function public.change_student_class(uuid) from public, anon;
grant execute on function public.list_student_available_classes() to authenticated;
grant execute on function public.change_student_class(uuid) to authenticated;
