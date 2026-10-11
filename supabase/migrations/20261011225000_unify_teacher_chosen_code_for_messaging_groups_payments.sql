-- One teacher-chosen code shared by private messaging, groups, and payments.
-- The teacher supplies the code; this migration never generates a replacement.
create or replace function public.set_teacher_shared_code(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_input text := upper(trim(coalesce(p_code, '')));
  v_body text;
  v_class_id uuid;
  v_access_id text;
  v_full_code text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not public.check_profile_role(v_user, 'teacher') then
    raise exception 'Only teachers can choose a shared code';
  end if;

  if v_input like 'FISE-%' then v_body := substring(v_input from 6);
  elsif v_input like 'FISE%' then v_body := substring(v_input from 5);
  else v_body := v_input;
  end if;

  if length(v_body) < 3 or length(v_body) > 40
     or v_body !~ '^[A-Z0-9_-]+$' then
    raise exception 'Code must contain 3 to 40 letters, numbers, underscores or hyphens';
  end if;

  select t.class_id::uuid, t.id into v_class_id, v_access_id
  from public.teacher_access_codes t
  where t.teacher_id = v_user and t.is_active = true
  order by t.created_at
  limit 1;

  if v_class_id is null then
    select c.id into v_class_id
    from public.school_classes c
    where c.is_active = true
      and public.teacher_can_manage_class(c.id, v_user)
    order by c.display_name, c.id
    limit 1;
  end if;

  if v_class_id is null then
    raise exception 'No classroom is assigned to this teacher';
  end if;

  if not exists (
    select 1 from public.school_classes c
    where c.id = v_class_id and c.is_active = true
  ) then
    raise exception 'The teacher classroom is unavailable';
  end if;

  v_full_code := 'FISE-' || v_body;
  v_access_id := coalesce(v_access_id, v_user::text || '_' || v_class_id::text);

  if exists (
    select 1 from public.teacher_access_codes t
    where upper(trim(t.code)) = v_body and t.id <> v_access_id
  ) or exists (
    select 1 from public.teacher_payment_codes p
    where upper(trim(p.code)) = v_full_code and p.teacher_id <> v_user
  ) then
    raise exception 'This code is already used by another teacher';
  end if;

  update public.teacher_access_codes
     set is_active = false, updated_at = now()
   where teacher_id = v_user and id <> v_access_id;

  insert into public.teacher_access_codes
    (id, teacher_id, code, class_id, created_at, updated_at, is_active)
  values
    (v_access_id, v_user, v_body, v_class_id::text, now(), now(), true)
  on conflict (teacher_id, class_id)
  do update set code = excluded.code, is_active = true, updated_at = now();

  insert into public.teacher_payment_codes (teacher_id, code, active, updated_at)
  values (v_user, v_full_code, true, now())
  on conflict (teacher_id)
  do update set code = excluded.code, active = true, updated_at = now();

  return v_full_code;
exception
  when unique_violation then
    raise exception 'This code is already used. Choose another code.';
end;
$$;

revoke all on function public.set_teacher_shared_code(text) from public, anon;
grant execute on function public.set_teacher_shared_code(text) to authenticated;

-- Legacy no-argument RPC returns an existing teacher-chosen code only.
create or replace function public.create_teacher_payment_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if auth.uid() is null or not public.check_profile_role(auth.uid(), 'teacher') then
    raise exception 'Only teachers can access their shared code';
  end if;

  select 'FISE-' || upper(trim(t.code)) into v_code
  from public.teacher_access_codes t
  where t.teacher_id = auth.uid() and t.is_active
  order by t.created_at
  limit 1;

  if v_code is null then
    raise exception 'Create your shared teacher code first';
  end if;
  return v_code;
end;
$$;

revoke all on function public.create_teacher_payment_code() from public, anon;
grant execute on function public.create_teacher_payment_code() to authenticated;

create or replace function public.resolve_teacher_payment_code(p_code text)
returns uuid
language sql
security definer
set search_path = public
as $$
  select t.teacher_id
  from public.teacher_access_codes t
  where t.is_active
    and ('FISE-' || upper(trim(t.code))) = upper(trim(p_code))
  limit 1;
$$;

revoke all on function public.resolve_teacher_payment_code(text) from public, anon;
grant execute on function public.resolve_teacher_payment_code(text) to authenticated;

-- Group creation must not manufacture a separate code from an invitation code.
create or replace function public.sync_group_code_to_teacher_access(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  return;
end;
$$;

revoke all on function public.sync_group_code_to_teacher_access(uuid) from public, anon;
grant execute on function public.sync_group_code_to_teacher_access(uuid) to authenticated;


-- Make the shared code's displayed format identical in group lists and payments.
create or replace function public.list_my_message_groups()
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
language sql
stable
security definer
set search_path = public
as $$
  select
    g.id,
    g.name,
    g.class_id,
    c.display_name,
    g.owner_id,
    case
      when g.owner_id <> auth.uid() then null
      when g.class_id is null then g.invite_code
      else coalesce(
        (
          select 'FISE-' || upper(trim(t.code))
          from public.teacher_access_codes t
          where t.teacher_id = g.owner_id
            and t.class_id::text = g.class_id::text
            and t.is_active = true
          order by t.created_at
          limit 1
        ),
        g.invite_code
      )
    end,
    (select count(*) from public.message_group_members m2 where m2.group_id = g.id),
    (select case
              when length(trim(lm.body)) > 0 then lm.body
              else coalesce(lm.attachment_name, 'Pièce jointe')
            end
     from public.message_group_messages lm
     where lm.group_id = g.id
     order by lm.created_at desc
     limit 1),
    (select max(lm.created_at) from public.message_group_messages lm where lm.group_id = g.id)
  from public.message_groups g
  join public.message_group_members me
    on me.group_id = g.id and me.user_id = auth.uid()
  left join public.school_classes c on c.id = g.class_id
  order by coalesce(
    (select max(lm.created_at) from public.message_group_messages lm where lm.group_id = g.id),
    g.created_at
  ) desc;
$$;

revoke all on function public.list_my_message_groups() from public, anon;
grant execute on function public.list_my_message_groups() to authenticated;
