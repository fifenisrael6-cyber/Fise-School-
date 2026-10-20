-- Restore groups missing from the student's membership table after a valid FISE join.
-- Only repairs membership when the student has an active FISE membership for the
-- group owner and an active classroom assignment matching that group.
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
  last_at timestamptz,
  unread_count bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_role text;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id = v_uid;

  if v_role = 'student' then
    insert into public.message_group_members (group_id, user_id, role)
    select distinct g.id, v_uid, 'student'
    from public.message_groups g
    join public.teacher_fise_code_memberships fm
      on fm.teacher_id = g.owner_id
     and fm.student_id = v_uid
    join public.class_students cs
      on cs.student_id = fm.student_id
     and cs.class_id = fm.class_id
     and cs.is_active = true
    where (
        fm.class_id = g.class_id
        or exists (
          select 1
          from public.message_group_classrooms gc
          where gc.group_id = g.id
            and gc.class_id = fm.class_id
        )
      )
      and not exists (
        select 1 from public.message_group_members existing
        where existing.group_id = g.id and existing.user_id = v_uid
      );
  end if;

  return query
  select
    g.id,
    g.name,
    g.class_id,
    c.display_name::text,
    g.owner_id,
    case when g.owner_id = v_uid then g.invite_code else null end,
    (select count(*) from public.message_group_members m2 where m2.group_id = g.id),
    (
      select case when length(trim(coalesce(lm.body, ''))) > 0 then lm.body
        else coalesce(lm.attachment_name, 'Pièce jointe') end
      from public.message_group_messages lm
      where lm.group_id = g.id
        and lm.created_at >= coalesce(me.joined_at, g.created_at)
        and not (v_uid = any(coalesce(lm.hidden_for, '{}'::uuid[])))
      order by lm.created_at desc
      limit 1
    ),
    (
      select max(lm.created_at)
      from public.message_group_messages lm
      where lm.group_id = g.id
        and lm.created_at >= coalesce(me.joined_at, g.created_at)
        and not (v_uid = any(coalesce(lm.hidden_for, '{}'::uuid[])))
    ),
    (
      select count(*)
      from public.message_group_messages unread
      where unread.group_id = g.id
        and unread.created_at >= coalesce(me.joined_at, g.created_at)
        and unread.sender_id <> v_uid
        and unread.deleted_at is null
        and not (v_uid = any(coalesce(unread.hidden_for, '{}'::uuid[])))
        and not exists (
          select 1
          from public.message_group_message_receipts receipt
          where receipt.message_id = unread.id
            and receipt.user_id = v_uid
            and receipt.read_at is not null
        )
    )
  from public.message_groups g
  left join public.message_group_members me
    on me.group_id = g.id and me.user_id = v_uid
  left join public.school_classes c on c.id = g.class_id
  where g.owner_id = v_uid or me.user_id is not null
  order by coalesce(
    (
      select max(lm.created_at)
      from public.message_group_messages lm
      where lm.group_id = g.id
        and lm.created_at >= coalesce(me.joined_at, g.created_at)
        and not (v_uid = any(coalesce(lm.hidden_for, '{}'::uuid[])))
    ),
    coalesce(me.joined_at, g.created_at)
  ) desc;
end;
$function$;

revoke all on function public.list_my_message_groups() from public, anon;
grant execute on function public.list_my_message_groups() to authenticated;
notify pgrst, 'reload schema';
