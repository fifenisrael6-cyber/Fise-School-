-- Final repair: one teacher FISE code works for group discovery/join and payments.
-- Keeps legacy group/payment codes valid. Students only see groups for their active classroom.

create or replace function public.list_teacher_groups_by_code(p_code text)
returns table(group_id uuid, group_name text, class_id uuid, class_name text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text;
  v_suffix text;
  v_teacher_id uuid;
  v_student_class uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.role into v_role from public.profiles p where p.id = auth.uid();
  if coalesce(v_role, '') not in ('student', 'teacher', 'admin') then
    raise exception 'This account cannot browse teacher groups';
  end if;

  v_suffix := upper(regexp_replace(trim(coalesce(p_code, '')), '^(FISE|GPR|GRP)[ -]*', '', 'i'));
  v_suffix := regexp_replace(v_suffix, '[^A-Z0-9]', '', 'g');
  if length(v_suffix) <> 6 then return; end if;

  select c.teacher_id into v_teacher_id
  from public.teacher_group_access_codes c
  where upper(regexp_replace(c.code, '^FISE-', '', 'i')) = v_suffix
    and c.is_active = true
  limit 1;

  -- Compatibility with older teacher codes that predate the shared-code table.
  if v_teacher_id is null then
    select c.teacher_id into v_teacher_id
    from public.teacher_access_codes c
    where upper(regexp_replace(trim(c.code), '^(FISE|GPR|GRP)[ -]*', '', 'i')) = v_suffix
      and c.is_active = true
    order by c.created_at desc
    limit 1;
  end if;
  if v_teacher_id is null then return; end if;

  if v_role = 'student' then
    select cs.class_id into v_student_class
    from public.class_students cs
    where cs.student_id = auth.uid() and cs.is_active = true
    order by cs.joined_at desc
    limit 1;
    if v_student_class is null then return; end if;
  elsif v_role = 'teacher' and v_teacher_id <> auth.uid() then
    -- Teachers may inspect only their own code and groups.
    return;
  end if;

  return query
  select distinct g.id, g.name, target.class_id,
         coalesce(sc.display_name, sc.name, '')
  from public.message_groups g
  cross join lateral (
    select g.class_id as class_id where g.class_id is not null
    union
    select gc.class_id from public.message_group_classrooms gc where gc.group_id = g.id
  ) target
  join public.school_classes sc on sc.id = target.class_id
  where g.owner_id = v_teacher_id
    and sc.is_active = true
    and (v_role <> 'student' or target.class_id = v_student_class)
  order by g.name, coalesce(sc.display_name, sc.name, '');
end;
$$;

create or replace function public.create_teacher_payment_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text;
begin
  if v_user is null or not public.check_profile_role(v_user, 'teacher') then
    raise exception 'Only teachers can create a payment code';
  end if;

  -- Payment/referral must reuse the teacher's one shared FISE code.
  v_code := public.get_or_create_teacher_group_access_code();

  insert into public.teacher_payment_codes(teacher_id, code, active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code, active = true, updated_at = now();

  return v_code;
exception
  when unique_violation then
    raise exception 'The shared FISE code conflicts with an existing payment code; resolve the duplicate before retrying';
end;
$$;

create or replace function public.resolve_teacher_payment_code(p_code text)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_input text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  v_suffix text;
  v_teacher_id uuid;
begin
  -- Called by the authenticated app and by the trusted payment Edge Function.
  v_suffix := upper(regexp_replace(v_input, '^(FISE|GPR|GRP)-?', '', 'i'));

  -- First resolve the canonical shared teacher code.
  if length(v_suffix) = 6 then
    select c.teacher_id into v_teacher_id
    from public.teacher_group_access_codes c
    where c.is_active = true
      and upper(regexp_replace(c.code, '^FISE-', '', 'i')) = v_suffix
    limit 1;
    if v_teacher_id is not null then return v_teacher_id; end if;
  end if;

  -- Preserve existing payment/referral codes for backward compatibility.
  select pc.teacher_id into v_teacher_id
  from public.teacher_payment_codes pc
  where pc.active = true and upper(pc.code) = v_input
  limit 1;
  if v_teacher_id is not null then return v_teacher_id; end if;

  -- Older group/access codes also remain resolvable for existing links.
  if length(v_suffix) = 6 then
    select ac.teacher_id into v_teacher_id
    from public.teacher_access_codes ac
    where ac.is_active = true
      and upper(regexp_replace(trim(ac.code), '^(FISE|GPR|GRP)-?', '', 'i')) = v_suffix
    order by ac.created_at desc
    limit 1;
  end if;
  return v_teacher_id;
end;
$$;

revoke all on function public.list_teacher_groups_by_code(text) from public, anon;
grant execute on function public.list_teacher_groups_by_code(text) to authenticated;
revoke all on function public.create_teacher_payment_code() from public, anon;
grant execute on function public.create_teacher_payment_code() to authenticated;
revoke all on function public.resolve_teacher_payment_code(text) from public, anon;
grant execute on function public.resolve_teacher_payment_code(text) to authenticated, service_role;
