alter table public.message_groups
  add column if not exists avatar_path text;

create or replace function public.list_my_message_group_avatars()
returns table (group_id uuid, avatar_path text)
language plpgsql stable security definer set search_path = public
as $function$
declare v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  return query
  select g.id, g.avatar_path from public.message_groups g
  where (g.owner_id = v_user_id or exists (
    select 1 from public.message_group_members gm
    where gm.group_id = g.id and gm.user_id = v_user_id
  )) and (g.owner_id = v_user_id or public.is_message_group_member(g.id));
end;
$function$;

create or replace function public.set_message_group_avatar(p_group_id uuid, p_avatar_path text)
returns text language plpgsql security definer set search_path = public
as $function$
declare v_user_id uuid := auth.uid(); v_old_path text;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_avatar_path is null or length(trim(p_avatar_path)) = 0 then
    raise exception 'Group avatar path is required';
  end if;
  if p_avatar_path !~ ('^' || v_user_id::text || '/groups/' || p_group_id::text || '/avatar-[A-Za-z0-9._-]+$') then
    raise exception 'Invalid group avatar path';
  end if;
  select g.avatar_path into v_old_path from public.message_groups g
  where g.id = p_group_id and g.owner_id = v_user_id for update;
  if not found then raise exception 'Only the group owner can change its photo'; end if;
  update public.message_groups set avatar_path = p_avatar_path where id = p_group_id;
  return v_old_path;
end;
$function$;

revoke all on function public.list_my_message_group_avatars() from public, anon;
revoke all on function public.set_message_group_avatar(uuid, text) from public, anon;
grant execute on function public.list_my_message_group_avatars() to authenticated;
grant execute on function public.set_message_group_avatar(uuid, text) to authenticated;
