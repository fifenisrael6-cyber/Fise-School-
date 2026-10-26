-- Repair classroom switching without relying on a uniqueness constraint that
-- legacy class_students data does not have. Keep history; reactivate the newest
-- existing membership for the target classroom, inserting only if none exists.
create or replace function public.change_student_class(target_class_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
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
  if not found then raise exception 'The selected classroom is not active'; end if;

  select * into v_target_level from public.exam_levels
  where id = v_target.exam_level_id and active;
  if not found then raise exception 'The selected classroom has no active exam level'; end if;

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

  update public.class_students cs set is_active = false
  where cs.student_id = v_user_id and cs.is_active
    and cs.class_id in (
      select sc.id from public.school_classes sc
      where sc.academic_year_id = v_target.academic_year_id
    );

  update public.class_students cs
  set is_active = true, joined_at = now()
  where cs.id = (
    select existing.id
    from public.class_students existing
    where existing.student_id = v_user_id and existing.class_id = v_target.id
    order by existing.joined_at desc nulls last, existing.created_at desc
    limit 1
  );

  if not found then
    insert into public.class_students (class_id, student_id, is_active, joined_at)
    values (v_target.id, v_user_id, true, now());
  end if;

  update public.profiles as p
  set subsystem = v_target.subsystem, sector = v_target.sector,
      exam_level_id = v_target.exam_level_id, exam_id = v_target_level.exam_id,
      series_id = v_target.series_id, specialty_id = v_target.specialty_id,
      class_name = v_target.display_name, exam_level_label = v_level_label,
      exam_label = v_exam_label, track_label = v_track_label,
      language_option = v_target.language_option,
      subscription_plan = case when exists (
        select 1 from public.student_subscriptions s
        where s.user_id = v_user_id and s.class_id = v_target.id
          and s.plan = 'premium' and s.status = 'active'
          and (s.expires_at is null or s.expires_at > now())
      ) then 'premium' else 'free' end
  where p.id = v_user_id
  returning to_jsonb(p) into v_updated;

  return v_updated;
end;
$function$;
