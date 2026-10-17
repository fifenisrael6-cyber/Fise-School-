-- Cyber payment policy: final server-side quota rules and role treatment.
-- Students only use free-tier quotas. Teachers and administrators are not forced
-- through the student subscription paywall; teacher revenue is commission-based.
-- Student Premium remains 2,000 XAF / 30 days, finalized server-side by Notch Pay.

create or replace function public.consume_free_quota_for_user(
  p_user_id uuid,
  p_feature text,
  p_resource_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_limit integer;
  v_used integer;
  v_reset_at timestamptz;
begin
  if p_user_id is null then
    return jsonb_build_object('allowed', false, 'reason', 'authentication_required');
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id = p_user_id;

  if v_role is null then
    return jsonb_build_object('allowed', false, 'reason', 'profile_not_found');
  end if;

  -- Teacher/admin access is role-based; never consume student quota for them.
  if v_role <> 'student' then
    return jsonb_build_object('allowed', true, 'role', v_role, 'premium', true);
  end if;

  if public.is_student_premium(p_user_id) then
    return jsonb_build_object('allowed', true, 'premium', true, 'used', 0);
  end if;

  v_limit := case p_feature
    when 'ai_question' then 3
    when 'group_send' then 2
    when 'group_receive' then 2
    when 'lesson' then 2
    when 'qcm' then 2
    when 'annal' then 2
    else null
  end;

  if v_limit is null then
    return jsonb_build_object('allowed', false, 'reason', 'unknown_feature');
  end if;

  perform pg_advisory_xact_lock(hashtext(p_user_id::text), hashtext(p_feature));

  if p_feature in ('lesson','qcm','annal') then
    if nullif(trim(coalesce(p_resource_id, '')), '') is null then
      return jsonb_build_object('allowed', false, 'reason', 'resource_required');
    end if;

    if exists (
      select 1
      from public.student_free_quota_events e
      where e.user_id = p_user_id
        and e.feature = p_feature
        and e.resource_id = p_resource_id
        and e.created_at > now() - interval '24 hours'
    ) then
      select count(*)::integer, min(e.created_at + interval '24 hours')
        into v_used, v_reset_at
      from public.student_free_quota_events e
      where e.user_id = p_user_id
        and e.feature = p_feature
        and e.created_at > now() - interval '24 hours';

      return jsonb_build_object(
        'allowed', true, 'already_counted', true,
        'limit', v_limit, 'used', coalesce(v_used, 0), 'resets_at', v_reset_at
      );
    end if;
  end if;

  select count(*)::integer, min(e.created_at + interval '24 hours')
    into v_used, v_reset_at
  from public.student_free_quota_events e
  where e.user_id = p_user_id
    and e.feature = p_feature
    and e.created_at > now() - interval '24 hours';

  if coalesce(v_used, 0) >= v_limit then
    return jsonb_build_object(
      'allowed', false, 'limit', v_limit, 'used', v_used, 'resets_at', v_reset_at
    );
  end if;

  insert into public.student_free_quota_events(user_id, feature, resource_id)
  values (p_user_id, p_feature, nullif(trim(coalesce(p_resource_id, '')), ''));

  return jsonb_build_object(
    'allowed', true, 'limit', v_limit, 'used', coalesce(v_used, 0) + 1,
    'resets_at', now() + interval '24 hours'
  );
end;
$$;

create or replace function public.student_free_quota_status(p_feature text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_limit integer;
  v_used integer;
  v_reset_at timestamptz;
begin
  if v_user_id is null then
    return jsonb_build_object('allowed', false, 'reason', 'authentication_required');
  end if;

  select p.role::text into v_role
  from public.profiles p where p.id = v_user_id;

  if v_role is null then
    return jsonb_build_object('allowed', false, 'reason', 'profile_not_found');
  end if;

  if v_role <> 'student' or public.is_student_premium(v_user_id) then
    return jsonb_build_object('allowed', true, 'premium', true, 'role', v_role, 'used', 0);
  end if;

  v_limit := case p_feature
    when 'ai_question' then 3
    when 'group_send' then 2
    when 'group_receive' then 2
    when 'lesson' then 2
    when 'qcm' then 2
    when 'annal' then 2
    else null
  end;

  if v_limit is null then
    return jsonb_build_object('allowed', false, 'reason', 'unknown_feature');
  end if;

  select count(*)::integer, min(e.created_at + interval '24 hours')
    into v_used, v_reset_at
  from public.student_free_quota_events e
  where e.user_id = v_user_id
    and e.feature = p_feature
    and e.created_at > now() - interval '24 hours';

  return jsonb_build_object(
    'allowed', coalesce(v_used, 0) < v_limit,
    'premium', false,
    'limit', v_limit,
    'used', coalesce(v_used, 0),
    'resets_at', v_reset_at
  );
end;
$$;

revoke all on function public.consume_free_quota_for_user(uuid,text,text) from public, anon, authenticated;
revoke all on function public.student_free_quota_status(text) from public, anon;
grant execute on function public.student_free_quota_status(text) to authenticated;
