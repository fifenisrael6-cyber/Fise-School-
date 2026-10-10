-- Persist each teacher's chosen classrooms. This is a UI/content-target
-- preference only: actual access is still independently checked by existing RLS.
create table if not exists public.teacher_followed_classes (
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (teacher_id, class_id)
);

alter table public.teacher_followed_classes enable row level security;

drop policy if exists "teachers read own followed classes" on public.teacher_followed_classes;
create policy "teachers read own followed classes"
on public.teacher_followed_classes for select to authenticated
using (teacher_id = auth.uid() or public.is_admin());

drop policy if exists "teachers manage own followed classes" on public.teacher_followed_classes;
create policy "teachers manage own followed classes"
on public.teacher_followed_classes for all to authenticated
using (teacher_id = auth.uid() or public.is_admin())
with check (teacher_id = auth.uid() or public.is_admin());

create or replace function public.list_teacher_followed_class_ids()
returns table (id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select tfc.class_id
  from public.teacher_followed_classes tfc
  where tfc.teacher_id = auth.uid()
  order by tfc.created_at, tfc.class_id;
$$;

create or replace function public.save_teacher_followed_classes(p_class_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = v_uid and p.role = 'teacher'
  ) then
    raise exception 'Only teachers can choose followed classrooms';
  end if;

  if coalesce(cardinality(p_class_ids), 0) = 0 then
    raise exception 'Choose at least one classroom';
  end if;

  if exists (
    select 1
    from unnest(p_class_ids) requested(class_id)
    left join public.school_classes c
      on c.id = requested.class_id and c.is_active
    left join public.profiles p on p.id = v_uid
    where c.id is null
       or p.subsystem is null
       or p.sector is null
       or p.subsystem is distinct from c.subsystem
       or p.sector is distinct from c.sector
  ) then
    raise exception 'A classroom is outside your subsystem or sector';
  end if;

  delete from public.teacher_followed_classes where teacher_id = v_uid;

  insert into public.teacher_followed_classes (teacher_id, class_id)
  select v_uid, requested.class_id
  from (
    select distinct unnest(p_class_ids) as class_id
  ) requested;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.list_teacher_followed_class_ids() from public, anon;
grant execute on function public.list_teacher_followed_class_ids() to authenticated;
revoke all on function public.save_teacher_followed_classes(uuid[]) from public, anon;
grant execute on function public.save_teacher_followed_classes(uuid[]) to authenticated;
