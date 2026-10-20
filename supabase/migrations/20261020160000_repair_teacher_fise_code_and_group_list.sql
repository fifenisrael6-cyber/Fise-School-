-- Repair the RPC used by the "Mon code unique FISE" screen and provide
-- a safe owner-only recovery RPC for groups that are missing from the client list.
create or replace function public.set_teacher_fise_code(p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_role text;
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id = v_user;

  if v_role is distinct from 'teacher' then
    raise exception 'Only teachers can manage this code';
  end if;

  -- Accept FISE-XXXXXX, FISEXXXXXX, or XXXXXX, then store one canonical form.
  v_code := translate(v_code, '‐‑‒–—−', '------');
  v_code := regexp_replace(v_code, '^FISE-?', '', 'i');
  if v_code !~ '^[A-Z0-9]{6}$' then
    raise exception 'Use the format FISE- followed by exactly six letters or numbers';
  end if;
  v_code := 'FISE-' || v_code;

  insert into public.teacher_payment_codes (teacher_id, code, active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code,
        active = true,
        updated_at = now();

  return v_code;
exception
  when unique_violation then
    raise exception 'This FISE code is already used by another teacher';
end;
$$;

revoke all on function public.set_teacher_fise_code(text) from public, anon;
grant execute on function public.set_teacher_fise_code(text) to authenticated;

create or replace function public.list_teacher_owned_message_groups()
returns table (
  id uuid,
  name text,
  class_id uuid,
  class_name text,
  owner_id uuid,
  invite_code text,
  member_count bigint,
  last_body text,
  last_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_role text;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id = v_user;

  if v_role not in ('teacher', 'admin') then
    return;
  end if;

  return query
  select
    g.id,
    g.name,
    g.class_id,
    c.display_name::text,
    g.owner_id,
    case when g.owner_id = v_user then g.invite_code else null end,
    (select count(*) from public.message_group_members m where m.group_id = g.id),
    (select case when length(trim(m.body)) > 0 then m.body
      else coalesce(m.attachment_name, 'Pièce jointe') end
      from public.message_group_messages m
      where m.group_id = g.id
        and m.created_at >= coalesce(me.joined_at, g.created_at)
        and not (v_user = any(coalesce(m.hidden_for, '{}'::uuid[])))
      order by m.created_at desc limit 1),
    (select max(m.created_at)
      from public.message_group_messages m
      where m.group_id = g.id
        and m.created_at >= coalesce(me.joined_at, g.created_at)
        and not (v_user = any(coalesce(m.hidden_for, '{}'::uuid[]))))
  from public.message_groups g
  left join public.message_group_members me
    on me.group_id = g.id and me.user_id = v_user
  left join public.school_classes c on c.id = g.class_id
  where g.owner_id = v_user
  order by coalesce(me.joined_at, g.created_at) desc;
end;
$$;

revoke all on function public.list_teacher_owned_message_groups() from public, anon;
grant execute on function public.list_teacher_owned_message_groups() to authenticated;

notify pgrst, 'reload schema';
