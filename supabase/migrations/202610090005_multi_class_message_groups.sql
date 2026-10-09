-- Allow one message group to target multiple teacher-assigned classrooms.
-- Keep class_id as a legacy primary classroom for older clients.
create table if not exists public.message_group_classrooms (
  group_id uuid not null references public.message_groups(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (group_id, class_id)
);

alter table public.message_group_classrooms enable row level security;
drop policy if exists "group members can read target classrooms" on public.message_group_classrooms;
create policy "group members can read target classrooms"
on public.message_group_classrooms for select to authenticated
using (public.is_message_group_member(group_id));

-- Backfill the old single-class target.
insert into public.message_group_classrooms (group_id, class_id)
select id, class_id from public.message_groups where class_id is not null
on conflict do nothing;

create or replace function public.create_message_group(p_name text, p_class_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_class_id uuid;
  v_count integer := 0;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('teacher', 'admin')
  ) then
    raise exception 'Only a teacher can create a group';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Group name is required';
  end if;

  if coalesce(cardinality(p_class_ids), 0) > 0 then
    foreach v_class_id in array p_class_ids loop
      if not public.teacher_can_manage_class(v_class_id, auth.uid())
         and not public.is_admin() then
        raise exception 'Teacher is not assigned to one of the selected classrooms';
      end if;
      v_count := v_count + 1;
    end loop;
  end if;

  insert into public.message_groups (class_id, name, owner_id, invite_code)
  values (
    case when coalesce(cardinality(p_class_ids), 0) > 0 then p_class_ids[1] else null end,
    trim(p_name),
    auth.uid(),
    public.generate_group_invite_code()
  )
  returning id into v_id;

  insert into public.message_group_members (group_id, user_id, role)
  values (v_id, auth.uid(), 'teacher');

  if coalesce(cardinality(p_class_ids), 0) > 0 then
    insert into public.message_group_classrooms (group_id, class_id)
    select v_id, selected_id
    from unnest(p_class_ids) as selected_id
    on conflict do nothing;

    -- Students already assigned to any selected classroom see the group
    -- automatically; unrelated classrooms are not added.
    insert into public.message_group_members (group_id, user_id, role)
    select distinct v_id, cs.student_id, 'student'
    from public.class_students cs
    join public.message_group_classrooms gc on gc.class_id = cs.class_id
    where gc.group_id = v_id and cs.is_active
    on conflict (group_id, user_id) do nothing;
  end if;

  return v_id;
end;
$;

-- Existing invite codes remain useful, but cannot bypass classroom targeting
-- when a group has one or more classroom targets.
create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $
declare
  v_group public.message_groups%rowtype;
  v_role text;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null then
    raise exception 'Profile not found';
  end if;

  select * into v_group
  from public.message_groups
  where invite_code = upper(trim(p_code));

  if not found then
    raise exception 'Invalid invitation code';
  end if;

  if v_role = 'student'
     and exists (select 1 from public.message_group_classrooms gc where gc.group_id = v_group.id)
     and not exists (
       select 1
       from public.message_group_classrooms gc
       join public.class_students cs on cs.class_id = gc.class_id
       where gc.group_id = v_group.id
         and cs.student_id = auth.uid()
         and cs.is_active
     ) then
    raise exception 'This group is only available to students in its selected classrooms';
  end if;

  insert into public.message_group_members (group_id, user_id, role)
  values (v_group.id, auth.uid(), case when v_role = 'student' then 'student' else 'teacher' end)
  on conflict (group_id, user_id) do nothing;

  return v_group.id;
end;
$;

revoke all on function public.create_message_group(text, uuid[]) from public, anon;
grant execute on function public.create_message_group(text, uuid[]) to authenticated;
revoke all on function public.join_message_group(text) from public, anon;
grant execute on function public.join_message_group(text) to authenticated;
