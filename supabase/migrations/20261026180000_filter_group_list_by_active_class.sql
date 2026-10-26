-- Prevent the group-list recovery RPC from re-adding or displaying groups
-- for a student who has not paid for the current classroom.
create or replace function public.list_my_message_groups()
returns table(
  id uuid, name text, class_id uuid, class_name text, owner_id uuid,
  invite_code text, member_count bigint, last_body text,
  last_at timestamptz, unread_count bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_role text;
  v_testing_mode boolean;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id = v_uid;

  select exists (
    select 1 from public.quota_config qc
    where qc.key = 'fise_testing_mode' and qc.value_ts is not null
  ) into v_testing_mode;

  if v_role = 'student'
     and not (public.is_student_premium(v_uid) or v_testing_mode) then
    return;
  end if;

  if v_role = 'student' then
    insert into public.message_group_members (group_id, user_id, role)
    select distinct g.id, v_uid, 'student'
    from public.message_groups g
    join public.teacher_fise_code_memberships fm
      on fm.teacher_id = g.owner_id and fm.student_id = v_uid
    join public.class_students cs
      on cs.student_id = fm.student_id
     and cs.class_id = fm.class_id
     and cs.is_active = true
    join public.school_classes sc
      on sc.id = cs.class_id and sc.is_active = true
    join public.academic_years ay
      on ay.id = sc.academic_year_id and ay.is_current = true
    where (
        fm.class_id = g.class_id
        or exists (
          select 1 from public.message_group_classrooms gc
          where gc.group_id = g.id and gc.class_id = fm.class_id
        )
      )
      and not exists (
        select 1 from public.message_group_hidden_for_user h
        where h.user_id = v_uid and h.group_id = g.id
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
      order by lm.created_at desc limit 1
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
  where (g.owner_id = v_uid or me.user_id is not null)
    and (
      v_role <> 'student'
      or (
        (public.is_student_premium(v_uid) or v_testing_mode)
        and exists (
          select 1
          from public.class_students active_cs
          join public.school_classes active_sc
            on active_sc.id = active_cs.class_id and active_sc.is_active
          join public.academic_years active_ay
            on active_ay.id = active_sc.academic_year_id and active_ay.is_current
          where active_cs.student_id = v_uid
            and active_cs.is_active
            and (
              active_sc.id = g.class_id
              or exists (
                select 1 from public.message_group_classrooms gc
                where gc.group_id = g.id and gc.class_id = active_sc.id
              )
            )
        )
      )
    )
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
