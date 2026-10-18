-- Separate group invitation codes from teacher/class access codes.
-- No tables, columns, policies, or other database structures are changed.

create or replace function public.generate_group_invite_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_code text;
begin
  loop
    v_code := 'GRP-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.message_groups where invite_code = v_code);
  end loop;
  return v_code;
end;
$$;

-- Students must explicitly enter the group invitation code.
create or replace function public.create_message_group(p_name text, p_class_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_class_id uuid;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('teacher', 'admin')
  ) then
    raise exception 'Only a teacher can create a group';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Group name is required';
  end if;

  if coalesce(cardinality(p_class_ids), 0) > 0 then
    foreach v_class_id in array p_class_ids loop
      if not public.teacher_can_manage_class(v_class_id, auth.uid())
         and not public.is_admin() then
        raise exception 'Teacher is not assigned to one of the selected classrooms';
      end if;
    end loop;
  end if;

  insert into public.message_groups (class_id, name, owner_id, invite_code)
  values (
    case when coalesce(cardinality(p_class_ids), 0) > 0 then p_class_ids[1] else null end,
    trim(p_name), auth.uid(), public.generate_group_invite_code()
  )
  returning id into v_id;

  insert into public.message_group_members (group_id, user_id, role)
  values (v_id, auth.uid(), 'teacher');

  if coalesce(cardinality(p_class_ids), 0) > 0 then
    insert into public.message_group_classrooms (group_id, class_id)
    select v_id, selected_id
    from unnest(p_class_ids) as selected_id
    on conflict do nothing;
  end if;

  return v_id;
end;
$$;

-- The owner sees the group's own code, not the teacher/class access code.
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
    g.id, g.name, g.class_id, c.display_name, g.owner_id,
    case when g.owner_id = auth.uid() then g.invite_code else null end,
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

-- Group codes join exactly one group. Teacher access codes continue to use
-- public.join_teacher_access_code from the teacher/class access flow.
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
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select p.role into v_role from public.profiles p where p.id = auth.uid();
  if v_role is null then
    raise exception 'Profile not found';
  end if;

  select * into v_group
  from public.message_groups g
  where upper(trim(g.invite_code)) = v_code
  limit 1;

  if not found then
    raise exception 'Invalid group invitation code';
  end if;

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
end;
$$;