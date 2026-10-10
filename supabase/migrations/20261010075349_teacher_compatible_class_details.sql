create or replace function public.list_compatible_teacher_class_details()
returns setof public.school_classes
language sql
stable
security definer
set search_path = public
as $$
  select c.*
  from public.school_classes c
  where c.is_active
    and (
      public.is_admin()
      or exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.role = 'teacher'
          and p.subsystem is not null
          and p.sector is not null
          and p.subsystem = c.subsystem
          and p.sector = c.sector
      )
    )
  order by c.display_name;
$$;

revoke all on function public.list_compatible_teacher_class_details() from public, anon;
grant execute on function public.list_compatible_teacher_class_details() to authenticated;
