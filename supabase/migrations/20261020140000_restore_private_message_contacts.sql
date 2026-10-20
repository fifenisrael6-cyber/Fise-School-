-- Restore private-message contacts lost when the avatar migration replaced the
-- group/code-aware contact RPC. Keep avatar_path for the current Flutter UI.
-- This migration preserves existing users, messages, groups, and memberships.

create or replace function public.list_private_message_contacts()
returns table (
  id uuid,
  first_name text,
  last_name text,
  role text,
  class_name text,
  avatar_path text
)
language sql
stable
security definer
set search_path = public
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
      and (
        g.class_id = cs.class_id
        or exists (
          select 1
          from public.message_group_classrooms gc
          where gc.group_id = g.id and gc.class_id = cs.class_id
        )
      )
  )
  select distinct on (p.id)
    p.id,
    p.first_name,
    p.last_name,
    p.role,
    c.display_name as class_name,
    p.avatar_path
  from authorized_pairs ap
  join public.school_classes c on c.id = ap.class_id
  join public.profiles p
    on p.id = case
      when ap.student_id = auth.uid() then ap.teacher_id
      else ap.student_id
    end
  where ap.student_id = auth.uid() or ap.teacher_id = auth.uid()
  order by p.id, c.display_name;
$function$;

revoke all on function public.list_private_message_contacts() from public, anon;
grant execute on function public.list_private_message_contacts() to authenticated;
