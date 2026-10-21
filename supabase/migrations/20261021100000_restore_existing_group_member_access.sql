-- Restore access for students who are already explicit members of a group.
-- New joins remain protected by join_message_group(), which requires the teacher's shared FISE code.
-- This avoids locking out existing members when their active classroom changes after joining.
create or replace function public.is_message_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.message_groups g
    where g.id = p_group_id
      and (
        g.owner_id = (select auth.uid())
        or exists (
          select 1
          from public.message_group_members m
          where m.group_id = g.id
            and m.user_id = (select auth.uid())
        )
      )
  );
$function$;

revoke all on function public.is_message_group_member(uuid) from public, anon;
grant execute on function public.is_message_group_member(uuid) to authenticated;
