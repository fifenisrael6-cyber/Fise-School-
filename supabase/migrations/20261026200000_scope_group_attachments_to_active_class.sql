-- Ensure group media storage follows the same room-scoped Premium authorization
-- as group metadata and messages. A retained membership from an old room must not
-- independently authorize attachment downloads.
create or replace function public.can_read_group_attachment(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.message_group_messages m
      join public.message_groups g on g.id = m.group_id
      left join public.message_group_members gm
        on gm.group_id = m.group_id and gm.user_id = (select auth.uid())
      where m.attachment_path = p_object_name
        and m.group_id = split_part(p_object_name, '/', 1)::uuid
        and m.deleted_at is null
        and (not m.view_once or m.sender_id = (select auth.uid()))
        and (
          (
            g.owner_id = (select auth.uid())
            and exists (
              select 1 from public.profiles p
              where p.id = (select auth.uid()) and p.role <> 'student'
            )
          )
          or (
            gm.user_id = (select auth.uid())
            and m.created_at >= gm.joined_at
            and public.is_message_group_member(m.group_id)
          )
          or exists (
            select 1
            from public.teacher_fise_code_memberships fm
            join public.class_students cs
              on cs.student_id = fm.student_id
             and cs.class_id = fm.class_id
             and cs.is_active = true
            where fm.student_id = (select auth.uid())
              and fm.teacher_id = g.owner_id
              and m.created_at >= fm.joined_at
              and m.created_at >= coalesce(gm.joined_at, fm.joined_at)
              and public.is_message_group_member(m.group_id)
              and (
                fm.class_id = g.class_id
                or exists (
                  select 1 from public.message_group_classrooms gc
                  where gc.group_id = g.id and gc.class_id = fm.class_id
                )
              )
          )
        )
    );
$function$;

revoke all on function public.can_read_group_attachment(text) from public, anon;
grant execute on function public.can_read_group_attachment(text) to authenticated;

notify pgrst, 'reload schema';
