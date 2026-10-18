-- One teacher-owned FISE code is shared by messaging groups and payment attribution.
-- Legacy class-scoped access codes remain untouched for class enrollment.
-- Existing teacher codes are copied once so already-shared codes keep working;
-- teachers can replace them with a code they choose from the teacher screen.

insert into public.teacher_payment_codes (teacher_id, code, active)
select distinct on (t.teacher_id)
  t.teacher_id,
  'FISE-' || upper(regexp_replace(trim(t.code), '^FISE-?', '', 'i')),
  true
from public.teacher_access_codes t
where t.is_active = true
  and trim(coalesce(t.code, '')) <> ''
  and not exists (
    select 1 from public.teacher_payment_codes p where p.teacher_id = t.teacher_id
  )
order by t.teacher_id, t.created_at asc
on conflict do nothing;

create or replace function public.set_teacher_fise_code(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  if not public.check_profile_role(v_user, 'teacher') then
    raise exception 'Only teachers can create a shared FISE code';
  end if;

  v_code := regexp_replace(v_code, '^FISE-?', 'FISE-', 'i');
  if v_code !~ '^FISE-[A-Z0-9]{4,12}$' then
    raise exception 'Use the format FISE- followed by 4 to 12 letters or numbers';
  end if;

  insert into public.teacher_payment_codes (teacher_id, code, active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code,
        active = true,
        updated_at = now();

  return v_code;
exception
  when unique_violation then
    raise exception 'This FISE code is already used by another teacher';
end;
$$;

revoke all on function public.set_teacher_fise_code(text) from public;
grant execute on function public.set_teacher_fise_code(text) to authenticated;

-- The legacy RPC may retrieve the code, but it must never generate one.
create or replace function public.create_teacher_payment_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if auth.uid() is null or not public.check_profile_role(auth.uid(), 'teacher') then
    raise exception 'Only teachers can access their shared code';
  end if;

  select p.code into v_code
  from public.teacher_payment_codes p
  where p.teacher_id = auth.uid() and p.active = true
  limit 1;

  if v_code is null then
    raise exception 'Create your shared FISE code first';
  end if;
  return v_code;
end;
$$;

revoke all on function public.create_teacher_payment_code() from public;
grant execute on function public.create_teacher_payment_code() to authenticated;

create or replace function public.resolve_teacher_payment_code(p_code text)
returns uuid
language sql
security definer
set search_path = public
as $$
  select p.teacher_id
  from public.teacher_payment_codes p
  where p.active = true
    and upper(trim(p.code)) = upper(trim(p_code))
  limit 1;
$$;

revoke all on function public.resolve_teacher_payment_code(text) from public;
grant execute on function public.resolve_teacher_payment_code(text) to authenticated;

-- The group owner sees the same teacher FISE code for every group.
create or replace function public.list_my_message_groups()
returns table (
  id uuid, name text, class_id uuid, class_name text, owner_id uuid,
  invite_code text, member_count bigint, last_body text,
  last_at timestamptz, unread_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    g.id,
    g.name,
    g.class_id,
    c.display_name,
    g.owner_id,
    case when g.owner_id = auth.uid() then (
      select p.code from public.teacher_payment_codes p
      where p.teacher_id = g.owner_id and p.active = true limit 1
    ) else null end,
    (select count(*) from public.message_group_members m2 where m2.group_id = g.id),
    (select case when length(trim(lm.body)) > 0 then lm.body
      else coalesce(lm.attachment_name, 'Pièce jointe') end
      from public.message_group_messages lm
      where lm.group_id = g.id
        and not (auth.uid() = any(coalesce(lm.hidden_for, '{}'::uuid[])))
      order by lm.created_at desc limit 1),
    (select max(lm.created_at) from public.message_group_messages lm
      where lm.group_id = g.id
        and not (auth.uid() = any(coalesce(lm.hidden_for, '{}'::uuid[])))),
    (select count(*) from public.message_group_messages unread
      where unread.group_id = g.id and unread.sender_id <> auth.uid()
        and unread.deleted_at is null
        and not (auth.uid() = any(coalesce(unread.hidden_for, '{}'::uuid[])))
        and not exists (
          select 1 from public.message_group_message_receipts receipt
          where receipt.message_id = unread.id and receipt.user_id = auth.uid()
            and receipt.read_at is not null
        ))
  from public.message_groups g
  join public.message_group_members me on me.group_id = g.id and me.user_id = auth.uid()
  left join public.school_classes c on c.id = g.class_id
  order by coalesce((
    select max(lm.created_at) from public.message_group_messages lm
    where lm.group_id = g.id
      and not (auth.uid() = any(coalesce(lm.hidden_for, '{}'::uuid[])))
  ), g.created_at) desc;
$$;

-- Compatibility RPC for clients that need to preview groups from a teacher code.
-- The returned columns match list_my_message_groups / MessageGroup.fromMap.
create or replace function public.list_teacher_groups_by_code(p_code text)
returns table (
  id uuid, name text, class_id uuid, class_name text, owner_id uuid,
  invite_code text, member_count bigint, last_body text,
  last_at timestamptz, unread_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $
declare
  v_teacher uuid;
  v_role text;
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select p.role into v_role from public.profiles p where p.id = auth.uid();

  select p.teacher_id into v_teacher
  from public.teacher_payment_codes p
  where p.active = true and upper(trim(p.code)) = v_code
  limit 1;

  if v_teacher is null then
    select t.teacher_id into v_teacher
    from public.teacher_access_codes t
    where t.is_active = true
      and ('FISE-' || upper(trim(regexp_replace(t.code, '^FISE-?', '', 'i')))) = v_code
    order by t.created_at asc
    limit 1;
  end if;

  if v_teacher is null then
    raise exception 'Invalid teacher FISE code';
  end if;

  return query
  select
    g.id, g.name, g.class_id, c.display_name, g.owner_id,
    case when g.owner_id = auth.uid() then v_code else null end,
    (select count(*) from public.message_group_members m2 where m2.group_id = g.id),
    (select case when length(trim(lm.body)) > 0 then lm.body
      else coalesce(lm.attachment_name, 'Pièce jointe') end
      from public.message_group_messages lm
      where lm.group_id = g.id
        and not (auth.uid() = any(coalesce(lm.hidden_for, '{}'::uuid[])))
      order by lm.created_at desc limit 1),
    (select max(lm.created_at) from public.message_group_messages lm
      where lm.group_id = g.id
        and not (auth.uid() = any(coalesce(lm.hidden_for, '{}'::uuid[])))),
    (select count(*) from public.message_group_messages unread
      where unread.group_id = g.id and unread.sender_id <> auth.uid()
        and unread.deleted_at is null
        and not (auth.uid() = any(coalesce(unread.hidden_for, '{}'::uuid[])))
        and not exists (
          select 1 from public.message_group_message_receipts receipt
          where receipt.message_id = unread.id and receipt.user_id = auth.uid()
            and receipt.read_at is not null
        ))
  from public.message_groups g
  left join public.school_classes c on c.id = g.class_id
  where g.owner_id = v_teacher
    and (
      v_role <> 'student'
      or (
        (g.class_id is not null and public.is_student_in_class(g.class_id, auth.uid()))
        or exists (
          select 1 from public.message_group_classrooms gc
          where gc.group_id = g.id
            and public.is_student_in_class(gc.class_id, auth.uid())
        )
      )
    )
  order by g.created_at desc;
end;
$;

revoke all on function public.list_teacher_groups_by_code(text) from public;
grant execute on function public.list_teacher_groups_by_code(text) to authenticated;

-- Accept a legacy GRP code for a single group, or the teacher's shared FISE
-- code to join all groups belonging to that teacher for which the student is
-- already assigned to a matching classroom.
create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_code text := upper(trim(coalesce(p_code, '')));
  v_teacher uuid;
  v_first_group uuid;
  v_joined integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select p.role into v_role from public.profiles p where p.id = auth.uid();
  if v_role is null then
    raise exception 'Profile not found';
  end if;

  -- Preserve old group invitation codes for backward compatibility.
  select * into v_group
  from public.message_groups g
  where upper(trim(g.invite_code)) = v_code
  limit 1;

  if found then
    if v_role = 'student' and not (
      (v_group.class_id is not null and public.is_student_in_class(v_group.class_id, auth.uid()))
      or exists (
        select 1 from public.message_group_classrooms gc
        where gc.group_id = v_group.id
          and public.is_student_in_class(gc.class_id, auth.uid())
      )
    ) then
      raise exception 'This group is not assigned to your classroom';
    end if;

    insert into public.message_group_members(group_id, user_id, role)
    values (v_group.id, auth.uid(), case when v_role = 'student' then 'student' else 'teacher' end)
    on conflict (group_id, user_id) do nothing;
    return v_group.id;
  end if;

  select p.teacher_id into v_teacher
  from public.teacher_payment_codes p
  where p.active = true and upper(trim(p.code)) = v_code
  limit 1;

  if v_teacher is null then
    -- Accept old FISE codes from the class-code table while teachers migrate.
    select t.teacher_id into v_teacher
    from public.teacher_access_codes t
    where t.is_active = true
      and ('FISE-' || upper(trim(regexp_replace(t.code, '^FISE-?', '', 'i')))) = v_code
    order by t.created_at asc
    limit 1;
  end if;

  if v_teacher is null then
    raise exception 'Invalid teacher FISE code';
  end if;

  if v_role = 'student' then
    with eligible_groups as (
      select distinct g.id
      from public.message_groups g
      where g.owner_id = v_teacher
        and (
          (g.class_id is not null and public.is_student_in_class(g.class_id, auth.uid()))
          or exists (
            select 1 from public.message_group_classrooms gc
            where gc.group_id = g.id
              and public.is_student_in_class(gc.class_id, auth.uid())
          )
        )
    ), inserted as (
      insert into public.message_group_members(group_id, user_id, role)
      select eg.id, auth.uid(), 'student'
      from eligible_groups eg
      on conflict (group_id, user_id) do nothing
      returning group_id
    )
    select count(*)::integer, (array_agg(group_id))[1] into v_joined, v_first_group from eligible_groups;
    -- Ensure already-joined eligible groups count as success too.
    if v_joined = 0 then
      select count(*)::integer, (array_agg(g.id))[1] into v_joined, v_first_group
      from public.message_groups g
      where g.owner_id = v_teacher
        and exists (
          select 1 from public.message_group_members m
          where m.group_id = g.id and m.user_id = auth.uid()
        )
        and (
          (g.class_id is not null and public.is_student_in_class(g.class_id, auth.uid()))
          or exists (
            select 1 from public.message_group_classrooms gc
            where gc.group_id = g.id
              and public.is_student_in_class(gc.class_id, auth.uid())
          )
        );
    end if;
  else
    with eligible_groups as (
      select g.id from public.message_groups g where g.owner_id = v_teacher
    ), inserted as (
      insert into public.message_group_members(group_id, user_id, role)
      select eg.id, auth.uid(), case when v_role = 'admin' then 'teacher' else v_role end
      from eligible_groups eg
      on conflict (group_id, user_id) do nothing
      returning group_id
    )
    select count(*)::integer, (array_agg(id))[1] into v_joined, v_first_group from eligible_groups;
  end if;

  if coalesce(v_joined, 0) = 0 or v_first_group is null then
    raise exception 'No groups from this teacher are available for your classroom';
  end if;

  return v_first_group;
end;
$$;

revoke all on function public.join_message_group(text) from public;
grant execute on function public.join_message_group(text) to authenticated;

notify pgrst, 'reload schema';
