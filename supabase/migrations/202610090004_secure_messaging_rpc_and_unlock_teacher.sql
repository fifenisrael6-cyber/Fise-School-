-- Restrict messaging RPCs to authenticated callers and provide the client RPC used to unlock teacher chats.
create or replace function public.unlock_teacher_private_messages(p_code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  joined_teacher uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;
  select j.teacher_id into joined_teacher
  from public.join_teacher_access_code(trim(p_code)) as j
  limit 1;
  return joined_teacher is not null;
end;
$$;

revoke all on function public.unlock_teacher_private_messages(text) from public, anon;
grant execute on function public.unlock_teacher_private_messages(text) to authenticated;

revoke all on function public.list_my_message_groups() from public, anon;
grant execute on function public.list_my_message_groups() to authenticated;

revoke all on function public.list_message_group_members(uuid) from public, anon;
grant execute on function public.list_message_group_members(uuid) to authenticated;