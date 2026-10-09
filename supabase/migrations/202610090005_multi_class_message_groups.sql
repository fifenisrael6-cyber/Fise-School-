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
  end if;

  return v_id;
end;
$$;

revoke all on function public.create_message_group(text, uuid[]) from public, anon;
grant execute on function public.create_message_group(text, uuid[]) to authenticated;
