-- TEMPORARY: disable Premium/payment quota gates during end-to-end app testing.
-- Restore normal billing/quota enforcement by deleting the fise_testing_mode row
-- from public.quota_config and setting PremiumGate.testingMode to false.
insert into public.quota_config(key, value_ts)
values ('fise_testing_mode', now())
on conflict (key) do update set value_ts = excluded.value_ts;

create or replace function public.has_full_access()
returns boolean
language sql stable security definer
set search_path = 'public'
as $function$
  select exists (
    select 1 from public.quota_config
    where key = 'fise_testing_mode' and value_ts is not null
  )
  or coalesce((select p.role <> 'student' from public.profiles p where p.id = auth.uid()), false)
  or public.is_student_premium(auth.uid());
$function$;

create or replace function public.consume_feature_quota(
  p_feature text, p_resource_id text default null, p_user_id uuid default null
)
returns jsonb language plpgsql security definer
set search_path = 'public'
as $function$
declare
  v_uid uuid := coalesce(p_user_id, auth.uid());
  v_limit integer := public.free_quota_limit(p_feature);
  v_role text;
  v_now timestamptz := now();
  v_win public.feature_quota_windows%rowtype;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if v_limit is null then raise exception 'Unknown feature %', p_feature; end if;
  if p_user_id is not null and auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception 'Forbidden';
  end if;
  select role into v_role from public.profiles where id = v_uid;
  if v_role is distinct from 'student' then
    return jsonb_build_object('allowed', true, 'premium', false, 'exempt', true, 'feature', p_feature);
  end if;

  if exists (select 1 from public.quota_config where key = 'fise_testing_mode' and value_ts is not null) then
    return jsonb_build_object('allowed', true, 'premium', true, 'testing_mode', true, 'feature', p_feature);
  end if;

  if public.is_student_premium(v_uid) then
    return jsonb_build_object('allowed', true, 'premium', true, 'feature', p_feature);
  end if;
  perform pg_advisory_xact_lock(hashtext(v_uid::text || ':' || p_feature));
  insert into public.feature_quota_windows(user_id, feature, window_start, used)
  values (v_uid, p_feature, v_now, 0) on conflict (user_id, feature) do nothing;
  select * into v_win from public.feature_quota_windows
  where user_id = v_uid and feature = p_feature for update;
  if v_win.window_start + interval '24 hours' <= v_now then
    update public.feature_quota_windows set window_start = v_now, used = 0
    where user_id = v_uid and feature = p_feature returning * into v_win;
  end if;
  if p_resource_id is not null and exists (
    select 1 from public.feature_quota_grants g
    where g.user_id = v_uid and g.feature = p_feature
      and g.resource_id = p_resource_id and g.window_start = v_win.window_start
  ) then
    return jsonb_build_object('allowed', true, 'premium', false, 'feature', p_feature,
      'limit', v_limit, 'used', v_win.used, 'remaining', greatest(v_limit - v_win.used, 0),
      'resets_at', v_win.window_start + interval '24 hours', 'already_granted', true);
  end if;
  if v_win.used >= v_limit then
    return jsonb_build_object('allowed', false, 'premium', false, 'feature', p_feature,
      'limit', v_limit, 'used', v_win.used, 'remaining', 0,
      'resets_at', v_win.window_start + interval '24 hours', 'code', 'QUOTA_EXCEEDED');
  end if;
  update public.feature_quota_windows set used = used + 1
  where user_id = v_uid and feature = p_feature returning * into v_win;
  if p_resource_id is not null then
    insert into public.feature_quota_grants(user_id, feature, resource_id, window_start)
    values (v_uid, p_feature, p_resource_id, v_win.window_start) on conflict do nothing;
  end if;
  return jsonb_build_object('allowed', true, 'premium', false, 'feature', p_feature,
    'limit', v_limit, 'used', v_win.used, 'remaining', greatest(v_limit - v_win.used, 0),
    'resets_at', v_win.window_start + interval '24 hours');
end;
$function$;
