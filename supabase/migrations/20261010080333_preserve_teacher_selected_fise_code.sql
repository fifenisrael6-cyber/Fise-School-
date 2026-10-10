create or replace function public.sync_group_code_to_teacher_access(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.message_groups%rowtype;
  v_suffix text;
begin
  select * into v_group
  from public.message_groups
  where id = p_group_id and owner_id = auth.uid();

  if not found or v_group.class_id is null then
    return;
  end if;

  v_suffix := substring(v_group.invite_code from 6);

  insert into public.teacher_access_codes
    (id, teacher_id, code, class_id, created_at, updated_at, is_active)
  values
    (v_group.owner_id::text || '_' || v_group.class_id::text || '_' || extract(epoch from now())::bigint::text,
     v_group.owner_id, v_suffix, v_group.class_id::text, now(), now(), true)
  on conflict (teacher_id, class_id)
  do update set
    updated_at = now(),
    is_active = true;
end;
$$;

revoke all on function public.sync_group_code_to_teacher_access(uuid) from public, anon;
grant execute on function public.sync_group_code_to_teacher_access(uuid) to authenticated;
