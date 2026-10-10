-- Give each teacher access to every active classroom in their own
-- subsystem AND sector (for example Francophone-General, not all systems).
-- Keep existing class_teachers rows for history; do not delete assignments.

create or replace function public.is_teacher_assigned(
  target_class_id uuid,
  target_teacher_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    join public.school_classes c on c.id = target_class_id
    where p.id = target_teacher_id
      and p.role = 'teacher'
      and p.subsystem is not null
      and p.sector is not null
      and p.subsystem = c.subsystem
      and p.sector = c.sector
      and c.is_active
  );
$$;

create or replace function public.teacher_can_manage_class(
  p_class_id uuid,
  p_teacher_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_admin()
    or (
      p_teacher_id = auth.uid()
      and exists (
        select 1
        from public.profiles p
        join public.school_classes c on c.id = p_class_id
        where p.id = p_teacher_id
          and p.role = 'teacher'
          and p.subsystem is not null
          and p.sector is not null
          and p.subsystem = c.subsystem
          and p.sector = c.sector
          and c.is_active
      )
    );
$$;

revoke all on function public.is_teacher_assigned(uuid, uuid) from public, anon;
grant execute on function public.is_teacher_assigned(uuid, uuid) to authenticated;

revoke all on function public.teacher_can_manage_class(uuid, uuid) from public, anon;
grant execute on function public.teacher_can_manage_class(uuid, uuid) to authenticated;
