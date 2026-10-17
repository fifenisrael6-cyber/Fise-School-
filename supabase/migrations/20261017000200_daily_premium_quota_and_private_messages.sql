-- Daily Premium quotas: rolling 24-hour windows, server-enforced.
-- Existing usage rows remain for compatibility; new events avoid lifetime-only counters.
create table if not exists public.student_free_quota_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  feature text not null check (feature in
    ('ai_question','group_send','group_receive','course','lesson','qcm','annal','evaluation')),
  resource_id text,
  created_at timestamptz not null default now()
);
create index if not exists student_free_quota_events_window_idx
  on public.student_free_quota_events(user_id, feature, created_at desc);
create index if not exists student_free_quota_events_resource_idx
  on public.student_free_quota_events(user_id, feature, resource_id, created_at desc)
  where resource_id is not null;
alter table public.student_free_quota_events enable row level security;
revoke all on public.student_free_quota_events from public, anon, authenticated;

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
  v_limit integer;
  v_used integer;
  v_reset_at timestamptz;
begin
  if p_user_id is null then
    return jsonb_build_object('allowed', false, 'reason', 'authentication_required');
  end if;
  if not exists (
    select 1 from public.profiles p where p.id = p_user_id and p.role = 'student'
  ) then
    return jsonb_build_object('allowed', false, 'reason', 'student_only');
  end if;
  if public.is_student_premium(p_user_id) then
    return jsonb_build_object('allowed', true, 'premium', true, 'used', 0);
  end if;

  v_limit := case p_feature
    when 'ai_question' then 4
    when 'group_send' then 2
    when 'group_receive' then 2
    when 'course' then 2
    when 'lesson' then 2
    when 'qcm' then 2
    when 'annal' then 2
    when 'evaluation' then 2
    else null
  end;
  if v_limit is null then
    return jsonb_build_object('allowed', false, 'reason', 'unknown_feature');
  end if;

  -- Serialize each student's counter to prevent parallel requests from bypassing limits.
  perform pg_advisory_xact_lock(hashtext(p_user_id::text), hashtext(p_feature));

  -- Revisiting a resource already granted during the last 24 hours is allowed
  -- and does not consume another unit.
  if p_feature in ('course','lesson','qcm','annal','evaluation') then
    if nullif(trim(coalesce(p_resource_id, '')), '') is null then
      return jsonb_build_object('allowed', false, 'reason', 'resource_required');
    end if;
    if exists (
      select 1 from public.student_free_quota_events e
      where e.user_id = p_user_id and e.feature = p_feature
        and e.resource_id = p_resource_id
        and e.created_at > now() - interval '24 hours'
    ) then
      select count(*)::integer into v_used
      from public.student_free_quota_events e
      where e.user_id = p_user_id and e.feature = p_feature
        and e.created_at > now() - interval '24 hours';
      return jsonb_build_object('allowed', true, 'already_counted', true,
        'limit', v_limit, 'used', v_used);
    end if;
  end if;

  select count(*)::integer, min(e.created_at + interval '24 hours')
    into v_used, v_reset_at
  from public.student_free_quota_events e
  where e.user_id = p_user_id and e.feature = p_feature
    and e.created_at > now() - interval '24 hours';

  if coalesce(v_used, 0) >= v_limit then
    return jsonb_build_object('allowed', false, 'limit', v_limit,
      'used', v_used, 'resets_at', v_reset_at);
  end if;

  insert into public.student_free_quota_events(user_id, feature, resource_id)
  values (p_user_id, p_feature, nullif(trim(coalesce(p_resource_id, '')), ''));

  return jsonb_build_object('allowed', true, 'limit', v_limit,
    'used', coalesce(v_used, 0) + 1,
    'resets_at', now() + interval '24 hours');
end;
$$;

create or replace function public.student_free_quota_status(p_feature text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_limit integer;
  v_used integer;
  v_reset_at timestamptz;
begin
  if v_user_id is null then
    return jsonb_build_object('allowed', false, 'reason', 'authentication_required');
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_user_id and p.role = 'student') then
    return jsonb_build_object('allowed', true, 'premium', true);
  end if;
  if public.is_student_premium(v_user_id) then
    return jsonb_build_object('allowed', true, 'premium', true, 'used', 0);
  end if;
  v_limit := case p_feature
    when 'ai_question' then 4
    when 'group_send' then 2
    when 'group_receive' then 2
    when 'course' then 2
    when 'lesson' then 2
    when 'qcm' then 2
    when 'annal' then 2
    when 'evaluation' then 2
    else null
  end;
  if v_limit is null then
    return jsonb_build_object('allowed', false, 'reason', 'unknown_feature');
  end if;
  select count(*)::integer, min(e.created_at + interval '24 hours')
    into v_used, v_reset_at
  from public.student_free_quota_events e
  where e.user_id = v_user_id and e.feature = p_feature
    and e.created_at > now() - interval '24 hours';
  return jsonb_build_object('allowed', coalesce(v_used, 0) < v_limit,
    'premium', false, 'limit', v_limit, 'used', coalesce(v_used, 0),
    'resets_at', v_reset_at);
end;
$$;

revoke all on function public.consume_free_quota_for_user(uuid,text,text) from public, anon, authenticated;
revoke all on function public.student_free_quota_status(text) from public, anon;
grant execute on function public.student_free_quota_status(text) to authenticated;

-- Keep group messages private to recipients who still have receive quota, while
-- preserving access for teachers, Premium students and each sender's own messages.
create or replace function public.apply_free_group_message_limits()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_allowed jsonb;
  v_member record;
  v_visible uuid[] := '{}'::uuid[];
begin
  if auth.uid() is null or new.sender_id <> auth.uid() then
    raise exception 'Authenticated sender required';
  end if;
  select p.role into v_role from public.profiles p where p.id = new.sender_id;
  if v_role = 'student' and not public.is_student_premium(new.sender_id) then
    v_allowed := public.consume_free_quota_for_user(new.sender_id, 'group_send', null);
    if coalesce((v_allowed ->> 'allowed')::boolean, false) is not true then
      raise exception 'FREE_GROUP_SEND_LIMIT: les deux messages gratuits sont épuisés pour les prochaines 24 heures.';
    end if;
  end if;

  new.free_limited := true;
  for v_member in
    select gm.user_id, p.role
    from public.message_group_members gm
    join public.profiles p on p.id = gm.user_id
    where gm.group_id = new.group_id and gm.user_id <> new.sender_id
  loop
    if v_member.role <> 'student' or public.is_student_premium(v_member.user_id) then
      v_visible := array_append(v_visible, v_member.user_id);
    else
      v_allowed := public.consume_free_quota_for_user(v_member.user_id, 'group_receive', null);
      if coalesce((v_allowed ->> 'allowed')::boolean, false) is true then
        v_visible := array_append(v_visible, v_member.user_id);
      end if;
    end if;
  end loop;
  new.free_visible_to := v_visible;
  return new;
end;
$$;

drop policy if exists "members read group messages" on public.message_group_messages;
create policy "members read group messages"
on public.message_group_messages for select to authenticated
using (
  public.is_message_group_member(group_id)
  and not ((select auth.uid()) = any(coalesce(hidden_for, '{}'::uuid[])))
  and (
    not free_limited
    or sender_id = (select auth.uid())
    or (select auth.uid()) = any(coalesce(free_visible_to, '{}'::uuid[]))
    or public.is_admin()
  )
);

-- Direct/private messages share the same daily send/receive quota as group chat.
alter table public.private_messages
  add column if not exists free_limited boolean not null default false,
  add column if not exists free_visible_to uuid[] not null default '{}'::uuid[];

create or replace function public.apply_free_private_message_limits()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender_role text;
  v_recipient_role text;
  v_allowed jsonb;
  v_visible uuid[] := '{}'::uuid[];
begin
  if auth.uid() is null or new.sender_id <> auth.uid() then
    raise exception 'Authenticated sender required';
  end if;

  select p.role into v_sender_role from public.profiles p where p.id = new.sender_id;
  select p.role into v_recipient_role from public.profiles p where p.id = new.recipient_id;

  if v_sender_role = 'student' and not public.is_student_premium(new.sender_id) then
    v_allowed := public.consume_free_quota_for_user(new.sender_id, 'group_send', null);
    if coalesce((v_allowed ->> 'allowed')::boolean, false) is not true then
      raise exception 'FREE_PRIVATE_SEND_LIMIT: les deux messages gratuits sont épuisés pour les prochaines 24 heures.';
    end if;
  end if;

  new.free_limited := true;
  if v_recipient_role <> 'student' or public.is_student_premium(new.recipient_id) then
    v_visible := array_append(v_visible, new.recipient_id);
  else
    v_allowed := public.consume_free_quota_for_user(new.recipient_id, 'group_receive', null);
    if coalesce((v_allowed ->> 'allowed')::boolean, false) is true then
      v_visible := array_append(v_visible, new.recipient_id);
    end if;
  end if;
  new.free_visible_to := v_visible;
  return new;
end;
$$;

drop trigger if exists apply_free_private_message_limits on public.private_messages;
create trigger apply_free_private_message_limits
before insert on public.private_messages
for each row execute function public.apply_free_private_message_limits();

drop policy if exists "participants read private messages" on public.private_messages;
create policy "participants read private messages"
on public.private_messages for select to authenticated
using (
  (sender_id = (select auth.uid()) or recipient_id = (select auth.uid()))
  and public.can_message(case when sender_id = (select auth.uid()) then recipient_id else sender_id end)
  and not ((select auth.uid()) = any(coalesce(hidden_for, '{}'::uuid[])))
  and (
    not free_limited
    or sender_id = (select auth.uid())
    or (select auth.uid()) = any(coalesce(free_visible_to, '{}'::uuid[]))
    or public.is_admin()
  )
);

revoke all on function public.apply_free_private_message_limits() from public, anon, authenticated;
grant execute on function public.apply_free_private_message_limits() to authenticated;
