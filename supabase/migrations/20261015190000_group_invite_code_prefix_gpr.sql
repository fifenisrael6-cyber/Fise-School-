-- Normalize group invitation codes to GPR-XXXXXX and keep existing groups joinable.
-- Teacher access codes remain FISE-XXXXXX; group invite codes use GPR-XXXXXX.
create or replace function public.generate_group_invite_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_code text;
begin
  loop
    v_code := 'GPR-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (
      select 1 from public.message_groups where invite_code = v_code
    );
  end loop;
  return v_code;
end;
$$;

revoke all on function public.generate_group_invite_code() from public;

-- Keep the old suffixes and change only the group-code prefix.
update public.message_groups
set invite_code = 'GPR-' || upper(substr(invite_code, 5))
where invite_code ~ '^GRP-[A-F0-9]{6}$';

create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_code text;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null then
    raise exception 'Profile not found';
  end if;

  v_code := upper(regexp_replace(trim(coalesce(p_code, '')), '^FISE-', ''));

  select * into v_group
  from public.message_groups
  where upper(invite_code) = v_code
     or upper(invite_code) = regexp_replace(v_code, '^GPR-', 'GRP-');

  if not found then
    raise exception 'Invalid invitation code';
  end if;

  insert into public.message_group_members (group_id, user_id, role)
  values (
    v_group.id,
    auth.uid(),
    case when v_role = 'student' then 'student' else 'teacher' end
  )
  on conflict (group_id, user_id) do nothing;

  return v_group.id;
end;
$$;

revoke all on function public.join_message_group(text) from public;
grant execute on function public.join_message_group(text) to authenticated;
