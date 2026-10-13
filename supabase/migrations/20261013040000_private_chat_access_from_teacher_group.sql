-- Allow a student who is already a member of a teacher-owned group to
-- privately message that group's teacher, without requiring a second code.
-- Access is limited to the group's owner and the student's active classroom.

create or replace function public.can_message(target_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and target_user_id is not null
    and target_user_id <> (select auth.uid())
    and exists (
      select 1 from public.profiles me
      join public.profiles them on them.id = target_user_id
      where me.id = (select auth.uid())
        and (
          (me.role = 'student' and them.role = 'teacher' and (
            exists (
              select 1 from public.teacher_access_memberships tam
              where tam.student_id = me.id and tam.teacher_id = them.id
                and tam.class_id in (select cs.class_id from public.class_students cs
                                     where cs.student_id = me.id and cs.is_active)
            )
            or exists (
              select 1 from public.message_groups g
              join public.message_group_members gm on gm.group_id = g.id and gm.user_id = me.id
              join public.class_students cs on cs.student_id = me.id and cs.is_active
              where g.owner_id = them.id
                and (g.class_id = cs.class_id or exists (
                  select 1 from public.message_group_classrooms gc
                  where gc.group_id = g.id and gc.class_id = cs.class_id
                ))
            )
          ))
          or
          (me.role = 'teacher' and them.role = 'student' and (
            exists (
              select 1 from public.teacher_access_memberships tam
              where tam.student_id = them.id and tam.teacher_id = me.id
                and tam.class_id in (select ct.class_id from public.class_teachers ct
                                     where ct.teacher_id = me.id and ct.is_active)
            )
            or exists (
              select 1 from public.message_groups g
              join public.message_group_members gm on gm.group_id = g.id and gm.user_id = them.id
              join public.class_students cs on cs.student_id = them.id and cs.is_active
              where g.owner_id = me.id
                and (g.class_id = cs.class_id or exists (
                  select 1 from public.message_group_classrooms gc
                  where gc.group_id = g.id and gc.class_id = cs.class_id
                ))
            )
          ))
          or (me.role = 'admin' and them.role in ('student', 'teacher'))
        )
    );
$function$;

revoke all on function public.can_message(uuid) from public, anon;
grant execute on function public.can_message(uuid) to authenticated;

-- Keep the existing Flutter contact RPC return shape. Include code-based
-- relationships and contacts inferred from teacher-owned group membership.
create or replace function public.list_private_message_contacts()
returns table (id uuid, first_name text, last_name text, role text, class_name text, unread_count bigint)
language sql stable security definer set search_path = public
as $function$
  with authorized_pairs as (
    select tam.student_id, tam.teacher_id, tam.class_id
    from public.teacher_access_memberships tam
    where tam.student_id = auth.uid() or tam.teacher_id = auth.uid()
    union
    select distinct gm.user_id as student_id, g.owner_id as teacher_id, cs.class_id
    from public.message_groups g
    join public.message_group_members gm on gm.group_id = g.id
    join public.profiles sp on sp.id = gm.user_id and sp.role = 'student'
    join public.class_students cs on cs.student_id = gm.user_id and cs.is_active
    join public.profiles tp on tp.id = g.owner_id and tp.role = 'teacher'
    where (gm.user_id = auth.uid() or g.owner_id = auth.uid())
      and (g.class_id = cs.class_id or exists (
        select 1 from public.message_group_classrooms gc
        where gc.group_id = g.id and gc.class_id = cs.class_id
      ))
  )
  select distinct on (p.id)
    p.id, p.first_name, p.last_name, p.role, c.display_name as class_name,
    (select count(*) from public.private_messages pm
     where pm.sender_id = p.id and pm.recipient_id = auth.uid()
       and pm.read_at is null
       and not (auth.uid() = any(coalesce(pm.hidden_for, '{}'::uuid[])))) as unread_count
  from authorized_pairs ap
  join public.school_classes c on c.id = ap.class_id
  join public.profiles p on p.id = case when ap.student_id = auth.uid()
                                        then ap.teacher_id else ap.student_id end
  where ap.student_id = auth.uid() or ap.teacher_id = auth.uid()
  order by p.id, c.display_name;
$function$;

revoke all on function public.list_private_message_contacts() from public, anon;
grant execute on function public.list_private_message_contacts() to authenticated;
