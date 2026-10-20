-- Repair student group membership when a valid FISE membership exists but
-- the message_group_members row was not created during enrollment.
create or replace function public.list_message_group_messages(p_group_id uuid)
returns table(
  id uuid, sender_id uuid, sender_name text, sender_role text,
  sender_avatar_path text, body text, attachment_path text,
  attachment_name text, attachment_type text, created_at timestamptz,
  view_once boolean, viewed_by_me boolean, deleted_at timestamptz,
  delivered_count bigint, read_count bigint, recipient_count bigint,
  reply_to_id uuid
)
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_joined_at timestamptz;
  v_role text;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select member.joined_at into v_joined_at
  from public.message_group_members member
  where member.group_id = p_group_id and member.user_id = v_uid;

  if v_joined_at is null then
    select p.role::text into v_role from public.profiles p where p.id = v_uid;
    if v_role = 'student' and exists (
      select 1 from public.message_groups g
      join public.teacher_fise_code_memberships fm
        on fm.teacher_id = g.owner_id and fm.student_id = v_uid
      join public.class_students cs
        on cs.student_id = fm.student_id and cs.class_id = fm.class_id and cs.is_active
      where g.id = p_group_id
        and (fm.class_id = g.class_id or exists (
          select 1 from public.message_group_classrooms gc
          where gc.group_id = g.id and gc.class_id = fm.class_id
        ))
    ) then
      insert into public.message_group_members(group_id, user_id, role)
      values (p_group_id, v_uid, 'student')
      on conflict (group_id, user_id) do nothing;
      select member.joined_at into v_joined_at
      from public.message_group_members member
      where member.group_id = p_group_id and member.user_id = v_uid;
    end if;
  end if;

  if v_joined_at is null then raise exception 'Not a member of this group'; end if;

  return query
  select m.id, m.sender_id,
    trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')),
    p.role::text, p.avatar_path,
    case when m.deleted_at is null then m.body else '' end,
    case when m.deleted_at is null then m.attachment_path else null end,
    case when m.deleted_at is null then m.attachment_name else null end,
    case when m.deleted_at is null then m.attachment_type else null end,
    m.created_at, m.view_once,
    exists (select 1 from public.message_group_message_views v
      where v.message_id = m.id and v.user_id = v_uid),
    m.deleted_at,
    (select count(*) from public.message_group_message_receipts r
      where r.message_id = m.id and r.delivered_at is not null and r.user_id <> m.sender_id),
    (select count(*) from public.message_group_message_receipts r
      where r.message_id = m.id and r.read_at is not null and r.user_id <> m.sender_id),
    (select count(*) from public.message_group_members gm
      where gm.group_id = p_group_id and gm.user_id <> m.sender_id),
    m.reply_to_id
  from public.message_group_messages m
  left join public.profiles p on p.id = m.sender_id
  where m.group_id = p_group_id and m.created_at >= v_joined_at
    and not (v_uid = any(coalesce(m.hidden_for, '{}'::uuid[])))
  order by m.created_at asc;
end;
$function$;
