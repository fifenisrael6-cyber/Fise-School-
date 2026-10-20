-- Let a student clear their own group conversation without leaving the group.
create or replace function public.clear_message_group_for_me(p_group_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not public.is_message_group_member(p_group_id) then
    raise exception 'Not a member of this group';
  end if;
  update public.message_group_messages
     set hidden_for = array_append(coalesce(hidden_for, '{}'::uuid[]), v_user)
   where group_id = p_group_id
     and not (v_user = any(coalesce(hidden_for, '{}'::uuid[])));
  return true;
end;
$$;
revoke all on function public.clear_message_group_for_me(uuid) from public, anon;
grant execute on function public.clear_message_group_for_me(uuid) to authenticated;
notify pgrst, 'reload schema';
