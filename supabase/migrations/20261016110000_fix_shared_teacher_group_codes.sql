-- Repair the shared FISE teacher code path and its RPCs.
-- Additive: keep legacy per-group invitation codes and messaging privacy controls.

create table if not exists public.teacher_group_access_codes (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null unique references auth.users(id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_active boolean not null default true,
  constraint teacher_group_access_codes_format check (code ~ '^FISE-[A-Z0-9]{6}$')
);

create index if not exists teacher_group_access_codes_code_idx
  on public.teacher_group_access_codes (upper(code));

alter table public.teacher_group_access_codes enable row level security;
drop policy if exists teacher_reads_own_group_access_code on public.teacher_group_access_codes;
create policy teacher_reads_own_group_access_code
  on public.teacher_group_access_codes for select to authenticated
  using (teacher_id = auth.uid());

create or replace function public.get_or_create_teacher_group_access_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_code text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = v_user;
  if v_role <> 'teacher' then raise exception 'Only teachers can manage this code'; end if;

  select code into v_code
  from public.teacher_group_access_codes
  where teacher_id = v_user and is_active = true;
  if v_code is not null then return v_code; end if;

  loop
    v_code := 'FISE-' || upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 6));
    exit when not exists (
      select 1 from public.teacher_group_access_codes where upper(code) = v_code
    );
  end loop;

  insert into public.teacher_group_access_codes (teacher_id, code)
  values (v_user, v_code)
  on conflict (teacher_id) do update
    set code = excluded.code, is_active = true, updated_at = now()
  returning code into v_code;
  return v_code;
end;
$$;

create or replace function public.set_teacher_group_access_code(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = v_user;
  if v_role <> 'teacher' then raise exception 'Only teachers can manage this code'; end if;

  v_code := regexp_replace(v_code, '^(FISE|GPR|GRP)-?', '');
  if v_code !~ '^[A-Z0-9]{6}$' then
    raise exception 'Code must use format FISE-XXXXXX';
  end if;
  v_code := 'FISE-' || v_code;

  insert into public.teacher_group_access_codes (teacher_id, code, is_active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code, is_active = true, updated_at = now();
  return v_code;
exception
  when unique_violation then raise exception 'This FISE code is already used';
end;
$$;

create or replace function public.list_teacher_groups_by_code(p_code text)
returns table(group_id uuid, group_name text, class_id uuid, class_name text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text;
  v_code text;
  v_teacher_id uuid;
  v_student_class uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  v_code := upper(regexp_replace(trim(coalesce(p_code, '')), '^(FISE|GPR|GRP)[ -]*', '', 'i'));
  v_code := regexp_replace(v_code, '[^A-Z0-9]', '', 'g');
  if length(v_code) <> 6 then return; end if;

  select c.teacher_id into v_teacher_id
  from public.teacher_group_access_codes c
  where upper(regexp_replace(c.code, '^FISE-', '')) = v_code and c.is_active = true
  limit 1;

  if v_teacher_id is null then return; end if;

  if v_role = 'student' then
    select cs.class_id into v_student_class
    from public.class_students cs
    where cs.student_id = auth.uid() and cs.is_active = true
    order by cs.joined_at desc limit 1;
    if v_student_class is null then return; end if;
  elsif v_role = 'teacher' then
    if v_teacher_id <> auth.uid() then return; end if;
  elsif v_role <> 'admin' then
    raise exception 'This account cannot browse message groups';
  end if;

  return query
  select distinct g.id, g.name, target.class_id, coalesce(sc.display_name, sc.name, '')
  from public.message_groups g
  cross join lateral (
    select g.class_id as class_id where g.class_id is not null
    union
    select gc.class_id from public.message_group_classrooms gc where gc.group_id = g.id
  ) target
  join public.school_classes sc on sc.id = target.class_id
  where g.owner_id = v_teacher_id
    and (v_role <> 'student' or target.class_id = v_student_class)
  order by g.name, coalesce(sc.display_name, sc.name, '');
end;
$$;

create or replace function public.join_teacher_group_by_code(
  p_code text, p_group_id uuid, p_class_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_code text;
  v_teacher_id uuid;
  v_student_class uuid;
  v_group_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  v_code := upper(regexp_replace(trim(coalesce(p_code, '')), '^(FISE|GPR|GRP)[ -]*', '', 'i'));
  v_code := regexp_replace(v_code, '[^A-Z0-9]', '', 'g');
  if length(v_code) <> 6 then raise exception 'Invalid teacher code'; end if;

  select c.teacher_id into v_teacher_id
  from public.teacher_group_access_codes c
  where upper(regexp_replace(c.code, '^FISE-', '')) = v_code and c.is_active = true
  limit 1;
  if v_teacher_id is null then raise exception 'Invalid teacher code'; end if;

  if v_role = 'student' then
    select cs.class_id into v_student_class
    from public.class_students cs
    where cs.student_id = auth.uid() and cs.is_active = true
    order by cs.joined_at desc limit 1;
    if v_student_class is null or v_student_class <> p_class_id
       or not public.is_student_in_class(p_class_id, auth.uid()) then
      raise exception 'This code is not valid for your active classroom';
    end if;
  elsif v_role = 'teacher' then
    if v_teacher_id <> auth.uid() then raise exception 'This code belongs to another teacher'; end if;
  elsif v_role <> 'admin' then
    raise exception 'This account cannot join message groups';
  end if;

  select g.id into v_group_id
  from public.message_groups g
  where g.id = p_group_id and g.owner_id = v_teacher_id
    and (
      g.class_id = p_class_id
      or exists (
        select 1 from public.message_group_classrooms gc
        where gc.group_id = g.id and gc.class_id = p_class_id
      )
    )
  limit 1;
  if v_group_id is null then raise exception 'Group is not assigned to this classroom'; end if;

  insert into public.message_group_members(group_id, user_id, role)
  values (v_group_id, auth.uid(), case when v_role = 'student' then 'student' else 'teacher' end)
  on conflict (group_id, user_id) do nothing;
  return v_group_id;
end;
$$;

create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_code text;
  v_teacher_id uuid;
  v_student_class uuid;
  v_first_group_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null then raise exception 'Profile not found'; end if;

  v_code := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  if v_code ~ '^(FISE|GPR|GRP)-?[A-Z0-9]{6}$' then
    v_code := regexp_replace(v_code, '^(FISE|GPR|GRP)-?', '');
    select c.teacher_id into v_teacher_id
    from public.teacher_group_access_codes c
    where upper(regexp_replace(c.code, '^FISE-', '')) = v_code and c.is_active = true
    limit 1;

    if v_teacher_id is not null then
      if v_role = 'student' then
        select cs.class_id into v_student_class
        from public.class_students cs
        where cs.student_id = auth.uid() and cs.is_active = true
        order by cs.joined_at desc limit 1;
        if v_student_class is null then raise exception 'No active classroom is assigned to this student'; end if;

        for v_group in
          select distinct g.* from public.message_groups g
          where g.owner_id = v_teacher_id
            and (
              g.class_id = v_student_class
              or exists (
                select 1 from public.message_group_classrooms gc
                where gc.group_id = g.id and gc.class_id = v_student_class
              )
            )
          order by g.created_at, g.id
        loop
          insert into public.message_group_members(group_id, user_id, role)
          values (v_group.id, auth.uid(), 'student')
          on conflict (group_id, user_id) do nothing;
          if v_first_group_id is null then v_first_group_id := v_group.id; end if;
        end loop;
        if v_first_group_id is null then raise exception 'No group exists for this teacher in your classroom'; end if;
        return v_first_group_id;
      elsif v_role = 'teacher' then
        if v_teacher_id <> auth.uid() then raise exception 'This code belongs to another teacher'; end if;
        select id into v_first_group_id from public.message_groups
        where owner_id = auth.uid() order by created_at, id limit 1;
        if v_first_group_id is null then raise exception 'Create a group first'; end if;
        return v_first_group_id;
      elsif v_role <> 'admin' then
        raise exception 'This account cannot join message groups';
      end if;
    end if;
  end if;

  -- Legacy group codes still work, but classroom authorization remains enforced.
  select * into v_group
  from public.message_groups g
  where upper(regexp_replace(g.invite_code, '^(FISE|GPR|GRP)[ -]*', '', 'i')) =
        upper(regexp_replace(trim(coalesce(p_code, '')), '^(FISE|GPR|GRP)[ -]*', '', 'i'))
  limit 1;
  if not found then raise exception 'Invalid invitation code'; end if;

  if v_role = 'student' and not (
    (v_group.class_id is not null and public.is_student_in_class(v_group.class_id, auth.uid()))
    or exists (
      select 1 from public.message_group_classrooms gc
      where gc.group_id = v_group.id and public.is_student_in_class(gc.class_id, auth.uid())
    )
  ) then
    raise exception 'This group is not assigned to your classroom';
  end if;

  insert into public.message_group_members(group_id, user_id, role)
  values (v_group.id, auth.uid(), case when v_role = 'student' then 'student' else 'teacher' end)
  on conflict (group_id, user_id) do nothing;
  return v_group.id;
end;
$$;

revoke all on function public.get_or_create_teacher_group_access_code() from public, anon;
grant execute on function public.get_or_create_teacher_group_access_code() to authenticated;
revoke all on function public.set_teacher_group_access_code(text) from public, anon;
grant execute on function public.set_teacher_group_access_code(text) to authenticated;
revoke all on function public.list_teacher_groups_by_code(text) from public, anon;
grant execute on function public.list_teacher_groups_by_code(text) to authenticated;
revoke all on function public.join_teacher_group_by_code(text, uuid, uuid) from public, anon;
grant execute on function public.join_teacher_group_by_code(text, uuid, uuid) to authenticated;
revoke all on function public.join_message_group(text) from public, anon;
grant execute on function public.join_message_group(text) to authenticated;
