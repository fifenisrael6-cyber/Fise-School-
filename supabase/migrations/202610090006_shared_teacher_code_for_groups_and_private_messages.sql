-- Use one teacher code for private messaging and classroom message groups.
-- Legacy GRP invite codes remain accepted for backward compatibility.

create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_code text := upper(trim(p_code));
  v_teacher_id uuid;
  v_class_id uuid;
  v_first_group_id uuid;
begin
  select role into v_role
  from public.profiles
  where id = auth.uid();

  if v_role is null then
    raise exception 'Profile not found';
  end if;

  -- FISE + the teacher's existing access-code body is shared with private chat.
  if left(v_code, 4) = 'FISE' then
    v_code := substring(v_code from 5);

    select t.teacher_id, t.class_id
      into v_teacher_id, v_class_id
    from public.teacher_access_codes t
    where upper(trim(t.code)) = v_code
      and t.is_active = true
    order by t.created_at desc
    limit 1;

    if v_teacher_id is null or v_class_id is null then
      raise exception 'Invalid teacher access code';
    end if;

    if v_role = 'student' then
      if not public.is_student_in_class(v_class_id, auth.uid()) then
        raise exception 'This code is not valid for your classroom';
      end if;
    elsif v_role = 'teacher' then
      if v_teacher_id <> auth.uid()
         and not public.teacher_can_manage_class(v_class_id, auth.uid()) then
        raise exception 'Teacher is not assigned to this classroom';
      end if;
    elsif v_role <> 'admin' then
      raise exception 'This account cannot join message groups';
    end if;

    -- A shared teacher/class code grants membership to that teacher's groups
    -- for the matching classroom, while private access is handled by the
    -- existing unlock_teacher_private_messages RPC.
    for v_group in
      select g.*
      from public.message_groups g
      where g.owner_id = v_teacher_id
        and g.class_id = v_class_id
      order by g.created_at, g.id
    loop
      insert into public.message_group_members (group_id, user_id, role)
      values (
        v_group.id,
        auth.uid(),
        case when v_role = 'student' then 'student' else 'teacher' end
      )
      on conflict (group_id, user_id) do nothing;

      if v_first_group_id is null then
        v_first_group_id := v_group.id;
      end if;
    end loop;

    if v_first_group_id is null then
      raise exception 'No message group exists for this teacher and classroom yet';
    end if;

    return v_first_group_id;
  end if;

  -- Backward compatibility for previously issued GRP- invitation codes.
  select * into v_group
  from public.message_groups
  where invite_code = upper(trim(p_code))
  limit 1;

  if not found then
    raise exception 'Invalid invitation code';
  end if;

  if v_group.class_id is not null and v_role = 'student'
     and not public.is_student_in_class(v_group.class_id, auth.uid()) then
    raise exception 'This group is not assigned to your classroom';
  end if;

  insert into public.message_group_members (group_id, user_id, role)
  values (
    v_group.id,
    auth.uid(),
    case when v_role = 'student' then 'student' else 'teacher' end
  )
  on conflict (group_id, user_id) do nothing;

  return v_group.id;
end;
$$;

create or replace function public.list_my_message_groups()
returns table (
  id uuid,
  name text,
  class_id uuid,
  class_name text,
  owner_id uuid,
  invite_code text,
  member_count bigint,
  last_body text,
  last_at timestamptz
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
    case
      when g.owner_id <> auth.uid() then null
      when g.class_id is null then g.invite_code
      else coalesce(
        (
          select 'fise' || lower(trim(t.code))
          from public.teacher_access_codes t
          where t.teacher_id = g.owner_id
            and t.class_id = g.class_id
            and t.is_active = true
          order by t.created_at desc
          limit 1
        ),
        g.invite_code
      )
    end,
    (select count(*) from public.message_group_members m2 where m2.group_id = g.id),
    (select case
              when length(trim(lm.body)) > 0 then lm.body
              else coalesce(lm.attachment_name, 'Pièce jointe')
            end
     from public.message_group_messages lm
     where lm.group_id = g.id
     order by lm.created_at desc
     limit 1),
    (select max(lm.created_at) from public.message_group_messages lm where lm.group_id = g.id)
  from public.message_groups g
  join public.message_group_members me
    on me.group_id = g.id and me.user_id = auth.uid()
  left join public.school_classes c on c.id = g.class_id
  order by coalesce(
    (select max(lm.created_at) from public.message_group_messages lm where lm.group_id = g.id),
    g.created_at
  ) desc;
$$;

revoke all on function public.join_message_group(text) from public, anon;
grant execute on function public.join_message_group(text) to authenticated;
revoke all on function public.list_my_message_groups() from public, anon;
grant execute on function public.list_my_message_groups() to authenticated;
