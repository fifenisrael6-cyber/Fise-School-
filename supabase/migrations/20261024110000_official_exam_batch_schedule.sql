-- Batch scheduling for official exams. RLS remains enabled.
create or replace function public.generate_official_exam_schedule(
  p_exam_id uuid, p_start_date date, p_days integer, p_class_ids uuid[] default null
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  s record; c record; v_teacher uuid; v_day date; v_start timestamptz;
  v_eval uuid; v_period uuid; v_created integer := 0; v_skipped integer := 0;
  v_missing integer := 0; v_i integer := 0; v_title text; v_clock time;
begin
  if auth.uid() is null or not public.is_catalog_admin() then
    raise exception 'Accès réservé à l’administration.';
  end if;
  if not exists (select 1 from public.exams where id = p_exam_id and active) then
    raise exception 'Examen actif introuvable.';
  end if;
  if p_start_date is null or p_start_date < (now() at time zone 'Africa/Douala')::date
     or p_days < 1 or p_days > 30 then
    raise exception 'Date ou nombre de jours invalide (1 à 30 jours).';
  end if;
  select id into v_period from public.grade_periods
   where not is_published and coalesce(publish_status,'draft') in ('draft','scheduled','blocked')
   order by position, created_at limit 1;

  for s in
    select distinct sj.id subject_id, sj.name_fr, sj.name_en
    from public.class_subjects cs
    join public.school_classes sc on sc.id=cs.class_id and sc.is_active
    join public.subjects sj on sj.id=cs.subject_id and sj.is_active
    where cs.is_active and (p_class_ids is null or cs.class_id=any(p_class_ids))
      and exists (select 1 from public.class_teachers ct join public.profiles tp on tp.id=ct.teacher_id
        where ct.class_id=sc.id and ct.is_active and tp.role='teacher'
          and tp.subsystem=sc.subsystem and tp.sector=sc.sector)
    order by sj.name_fr
  loop
    if v_i >= p_days then
      raise exception 'Il faut au moins % jours pour programmer toutes les matières.', v_i+1;
    end if;
    v_day := p_start_date + v_i;
    v_clock := case when extract(isodow from v_day) in (6,7) then time '18:00' else time '19:20' end;
    v_start := (v_day + v_clock) at time zone 'Africa/Douala';

    for c in
      select distinct sc.id class_id, sc.display_name, sc.name, sc.subsystem, sc.sector
      from public.class_subjects cs join public.school_classes sc on sc.id=cs.class_id and sc.is_active
      where cs.is_active and cs.subject_id=s.subject_id
        and (p_class_ids is null or cs.class_id=any(p_class_ids))
        and exists (select 1 from public.class_teachers ct join public.profiles tp on tp.id=ct.teacher_id
          where ct.class_id=sc.id and ct.is_active and tp.role='teacher'
            and tp.subsystem=sc.subsystem and tp.sector=sc.sector)
      order by sc.display_name nulls last, sc.name
    loop
      if exists (select 1 from public.evaluations e join public.evaluation_classes ec on ec.evaluation_id=e.id
        where e.exam_id=p_exam_id and e.subject_id=s.subject_id and ec.class_id=c.class_id
          and (e.starts_at at time zone 'Africa/Douala')::date=v_day
          and e.status in ('draft','published','closed')) then
        v_skipped := v_skipped+1; continue;
      end if;
      select ct.teacher_id into v_teacher from public.class_teachers ct
       join public.profiles tp on tp.id=ct.teacher_id
       where ct.class_id=c.class_id and ct.is_active and tp.role='teacher'
         and tp.subsystem=c.subsystem and tp.sector=c.sector
       order by random() limit 1;
      if v_teacher is null then v_missing:=v_missing+1; continue; end if;
      select coalesce(nullif(name_fr,''),name_en) into v_title from public.exams where id=p_exam_id;
      v_title := v_title || ' — ' || coalesce(nullif(s.name_fr,''),s.name_en)
        || ' (' || coalesce(c.display_name,c.name) || ')';
      insert into public.evaluations(teacher_id,subject_id,period_id,exam_id,title,instructions,
        starts_at,due_at,results_visible_at,max_score,weight,status)
      values(v_teacher,s.subject_id,v_period,p_exam_id,v_title,
        'Épreuve officielle programmée automatiquement par l’administration.',
        v_start,v_start+interval '2 hours',v_start+interval '26 hours',20,1,'draft')
      returning id into v_eval;
      insert into public.evaluation_classes(evaluation_id,class_id) values(v_eval,c.class_id);
      v_created:=v_created+1;
    end loop;
    v_i:=v_i+1;
  end loop;
  return jsonb_build_object('created',v_created,'skipped_existing',v_skipped,
    'missing_teacher',v_missing,'subjects_scheduled',v_i,'period_id',v_period);
end;
$$;
revoke all on function public.generate_official_exam_schedule(uuid,date,integer,uuid[]) from public, anon;
grant execute on function public.generate_official_exam_schedule(uuid,date,integer,uuid[]) to authenticated;
