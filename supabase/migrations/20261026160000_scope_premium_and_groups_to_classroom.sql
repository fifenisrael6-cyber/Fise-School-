-- Scope Premium entitlements and message-group access to the student's active classroom.
-- Historical subscriptions are associated with their recorded payment classroom when
-- available, otherwise with the student's current classroom (non-destructive backfill).

alter table public.student_subscriptions
  add column if not exists class_id uuid references public.school_classes(id) on delete set null;

update public.student_subscriptions s
set class_id = coalesce(
  (select po.related_class_id from public.payment_orders po where po.id = s.payment_order_id),
  (select cs.class_id
     from public.class_students cs
     join public.school_classes sc on sc.id = cs.class_id and sc.is_active
     join public.academic_years ay on ay.id = sc.academic_year_id and ay.is_current
    where cs.student_id = s.user_id and cs.is_active
    order by cs.joined_at desc limit 1)
)
where s.class_id is null;

create index if not exists student_subscriptions_user_class_active_idx
  on public.student_subscriptions(user_id, class_id, expires_at desc)
  where plan = 'premium' and status = 'active';

-- A checkout must identify the room for which the payment was initiated.
alter table public.payment_orders
  add column if not exists related_class_id uuid references public.school_classes(id) on delete set null;

create or replace function public.is_student_premium(p_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_class_id uuid;
begin
  if auth.uid() is not null and auth.uid() <> p_user_id
     and not coalesce(public.is_catalog_admin(), false) then
    return false;
  end if;

  select cs.class_id into v_class_id
  from public.class_students cs
  join public.school_classes sc on sc.id = cs.class_id and sc.is_active
  join public.academic_years ay on ay.id = sc.academic_year_id and ay.is_current
  where cs.student_id = p_user_id and cs.is_active
  order by cs.joined_at desc
  limit 1;

  if v_class_id is null then
    return false;
  end if;

  return exists (
    select 1
    from public.student_subscriptions s
    where s.user_id = p_user_id
      and s.class_id = v_class_id
      and s.plan = 'premium'
      and s.status = 'active'
      and (s.expires_at is null or s.expires_at > now())
  );
end;
$function$;

create or replace function public.activate_student_premium(
  p_user_id uuid,
  p_payment_order_id uuid,
  p_duration_days integer default 30
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_subscription_id uuid;
  v_class_id uuid;
begin
  if p_duration_days <= 0 then raise exception 'Invalid subscription duration'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id and role = 'student') then
    raise exception 'User is not a student';
  end if;

  select po.related_class_id into v_class_id
  from public.payment_orders po
  where po.id = p_payment_order_id
    and po.user_id = p_user_id
    and po.status = 'SUCCESS'
    and po.amount = public.premium_price_xaf()
    and po.currency = 'XAF'
  for update;

  if not found or v_class_id is null then
    raise exception 'A successful Premium payment linked to a classroom is required';
  end if;

  select s.id into v_subscription_id
  from public.student_subscriptions s
  where s.payment_order_id = p_payment_order_id
  limit 1;
  if v_subscription_id is not null then return v_subscription_id; end if;

  select s.id into v_subscription_id
  from public.student_subscriptions s
  where s.user_id = p_user_id
    and s.class_id = v_class_id
    and s.plan = 'premium'
    and s.status = 'active'
  order by s.expires_at desc nulls last
  limit 1
  for update;

  if v_subscription_id is not null then
    update public.student_subscriptions
    set expires_at = greatest(coalesce(expires_at, now()), now()) + make_interval(days => p_duration_days),
        payment_order_id = p_payment_order_id,
        updated_at = now()
    where id = v_subscription_id;
  else
    insert into public.student_subscriptions
      (user_id, class_id, plan, status, starts_at, expires_at, payment_order_id)
    values
      (p_user_id, v_class_id, 'premium', 'active', now(),
       now() + make_interval(days => p_duration_days), p_payment_order_id)
    returning id into v_subscription_id;
  end if;

  update public.profiles
  set subscription_plan = case
    when exists (
      select 1 from public.class_students cs
      where cs.student_id = p_user_id and cs.class_id = v_class_id and cs.is_active
    ) then 'premium'
    else subscription_plan
  end
  where id = p_user_id and role = 'student';

  return v_subscription_id;
end;
$function$;

create or replace function public.get_my_quota_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_class_id uuid;
  v_premium boolean;
  v_expires timestamptz;
  v_out jsonb := '{}'::jsonb;
  v_feature text;
  v_win public.feature_quota_windows%rowtype;
  v_limit integer;
  v_used integer;
  v_reset timestamptz;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select cs.class_id into v_class_id
  from public.class_students cs
  join public.school_classes sc on sc.id = cs.class_id and sc.is_active
  join public.academic_years ay on ay.id = sc.academic_year_id and ay.is_current
  where cs.student_id = v_uid and cs.is_active
  order by cs.joined_at desc limit 1;

  v_premium := public.is_student_premium(v_uid);
  select max(s.expires_at) into v_expires
  from public.student_subscriptions s
  where s.user_id = v_uid and s.class_id = v_class_id
    and s.plan = 'premium' and s.status = 'active';

  foreach v_feature in array array['lesson','qcm','annale','ai_text','msg_sent','msg_recv'] loop
    v_limit := public.free_quota_limit(v_feature);
    select * into v_win from public.feature_quota_windows
    where user_id = v_uid and feature = v_feature;
    if found and v_win.window_start + interval '24 hours' > now() then
      v_used := v_win.used;
      v_reset := v_win.window_start + interval '24 hours';
    else
      v_used := 0;
      v_reset := null;
    end if;
    v_out := v_out || jsonb_build_object(v_feature, jsonb_build_object(
      'limit', v_limit, 'used', v_used,
      'remaining', greatest(v_limit - v_used, 0), 'resets_at', v_reset));
  end loop;

  return jsonb_build_object(
    'premium', v_premium,
    'premium_expires_at', case when v_premium then v_expires else null end,
    'price_xaf', public.premium_price_xaf(),
    'duration_days', public.premium_duration_days(),
    'has_pending_payment', exists (
      select 1 from public.payment_orders po
      where po.user_id = v_uid
        and po.related_class_id = v_class_id
        and po.status in ('NOTPAY','PENDING')
        and po.created_at > now() - interval '2 hours'),
    'was_premium', (not v_premium) and exists (
      select 1 from public.student_subscriptions s
      where s.user_id = v_uid and s.class_id = v_class_id and s.plan = 'premium'),
    'quotas', v_out
  );
end;
$function$;

-- Students can read a group only when they are enrolled in one of its linked
-- classrooms AND have Premium for that active classroom (or admin test mode is on).
-- Membership rows are retained, so returning to the old classroom restores access.
create or replace function public.is_message_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.message_groups g
    where g.id = p_group_id
      and (
        (g.owner_id = (select auth.uid())
          and exists (
            select 1 from public.profiles p
            where p.id = (select auth.uid()) and p.role <> 'student'
          ))
        or exists (
          select 1
          from public.message_group_members m
          join public.profiles p on p.id = m.user_id
          where m.group_id = g.id
            and m.user_id = (select auth.uid())
            and (
              p.role <> 'student'
              or (
                exists (
                  select 1
                  from public.class_students cs
                  join public.school_classes sc on sc.id = cs.class_id and sc.is_active
                  join public.academic_years ay on ay.id = sc.academic_year_id and ay.is_current
                  where cs.student_id = m.user_id
                    and cs.is_active
                    and (
                      sc.id = g.class_id
                      or exists (
                        select 1 from public.message_group_classrooms gc
                        where gc.group_id = g.id and gc.class_id = sc.id
                      )
                    )
                )
                and (
                  public.is_student_premium(m.user_id)
                  or exists (
                    select 1 from public.quota_config qc
                    where qc.key = 'fise_testing_mode' and qc.value_ts is not null
                  )
                )
              )
            )
        )
      )
  );
$function$;

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

  -- End the old active membership without deleting it. This preserves the
  -- classroom history and allows access to be restored if the student returns.
  update public.class_students cs set is_active = false
  where cs.student_id = v_user_id and cs.is_active
    and cs.class_id in (
      select sc.id from public.school_classes sc
      where sc.academic_year_id = v_target.academic_year_id
    );

  insert into public.class_students (class_id, student_id, is_active, joined_at)
  values (v_target.id, v_user_id, true, now())
  on conflict (class_id, student_id) do update
    set is_active = true, joined_at = now();

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

-- FISE code joining only works for the student's current room's groups.
-- Require room-specific Premium before adding membership; the server-side
-- group-member predicate also blocks previously joined groups in other rooms.
create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_code text;
  v_teacher_id uuid;
  v_shared_code text;
  v_student_class uuid;
  v_first_group_id uuid;
  v_access_code_id text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null then raise exception 'Profile not found'; end if;

  v_code := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  v_code := translate(v_code, '‐‑‒–—−', '------');
  if v_code !~ '^FISE-?[A-Z0-9]{6}$' then
    raise exception 'Use the teacher FISE code in the format FISE-XXXXXX';
  end if;
  v_code := regexp_replace(v_code, '^FISE-?', 'FISE-', 'i');

  select c.teacher_id, c.code into v_teacher_id, v_shared_code
    from public.teacher_group_access_codes c
   where upper(c.code) = v_code and c.is_active = true
   limit 1;
  if v_teacher_id is null then raise exception 'Invalid or inactive FISE code'; end if;

  if v_role = 'student' then
    select cs.class_id into v_student_class
      from public.class_students cs
      join public.school_classes sc on sc.id = cs.class_id and sc.is_active
      join public.academic_years ay on ay.id = sc.academic_year_id and ay.is_current
     where cs.student_id = auth.uid() and cs.is_active = true
     order by cs.joined_at desc limit 1;
    if v_student_class is null then raise exception 'No active classroom is assigned to this student'; end if;

    if not (
      public.is_student_premium(auth.uid())
      or exists (select 1 from public.quota_config qc
                 where qc.key = 'fise_testing_mode' and qc.value_ts is not null)
    ) then
      raise exception 'Premium payment is required for this classroom before joining groups';
    end if;

    insert into public.teacher_fise_code_memberships(student_id, teacher_id, class_id, code, joined_at)
    values (auth.uid(), v_teacher_id, v_student_class, v_shared_code, now())
    on conflict (student_id, teacher_id, class_id)
    do update set code = excluded.code, joined_at = now();

    insert into public.teacher_access_codes(id, teacher_id, code, class_id, is_active, updated_at)
    values (v_teacher_id::text || ':' || v_student_class::text, v_teacher_id, v_shared_code, v_student_class::text, true, now())
    on conflict (teacher_id, class_id)
    do update set code = excluded.code, is_active = true, updated_at = now()
    returning id into v_access_code_id;

    insert into public.teacher_access_memberships(student_id, teacher_id, class_id, access_code_id, joined_at)
    values (auth.uid(), v_teacher_id, v_student_class, v_access_code_id, now())
    on conflict (student_id, teacher_id, class_id)
    do update set access_code_id = excluded.access_code_id, joined_at = now();

    delete from public.message_group_hidden_for_user h
    using public.message_groups g
    where h.user_id = auth.uid() and h.group_id = g.id and g.owner_id = v_teacher_id
      and (g.class_id = v_student_class or exists (
        select 1 from public.message_group_classrooms gc
        where gc.group_id = g.id and gc.class_id = v_student_class
      ));

    for v_group in
      select distinct g.* from public.message_groups g
       where g.owner_id = v_teacher_id
         and (g.class_id = v_student_class or exists (
           select 1 from public.message_group_classrooms gc
            where gc.group_id = g.id and gc.class_id = v_student_class
         ))
       order by g.created_at, g.id
    loop
      insert into public.message_group_members(group_id, user_id, role)
      values (v_group.id, auth.uid(), 'student')
      on conflict (group_id, user_id) do nothing;
      if v_first_group_id is null then v_first_group_id := v_group.id; end if;
    end loop;
    return v_first_group_id;
  elsif v_role = 'teacher' then
    if v_teacher_id <> auth.uid() then raise exception 'This code belongs to another teacher'; end if;
    select id into v_first_group_id from public.message_groups
     where owner_id = auth.uid() order by created_at, id limit 1;
    return v_first_group_id;
  elsif v_role = 'admin' then
    raise exception 'Administrators do not join teacher groups with student codes';
  else
    raise exception 'This account cannot join message groups';
  end if;
end;
$function$;

revoke all on function public.join_message_group(text) from public, anon;
grant execute on function public.join_message_group(text) to authenticated;

notify pgrst, 'reload schema';
