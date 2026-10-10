-- Prefer real student classrooms over empty generic level buckets when
-- the level already has series/specialty-specific rooms. Keep generic rooms
-- when students are actually enrolled there or no specific room exists.
create or replace function public.list_compatible_teacher_classes()
returns table (id uuid)
language sql
stable
security definer
set search_path = public
as $function$
  select c.id
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
    and not (
      c.series_id is null
      and c.specialty_id is null
      and not exists (
        select 1 from public.class_students enrolled
        where enrolled.class_id = c.id and enrolled.is_active
      )
      and exists (
        select 1
        from public.school_classes specific
        where specific.is_active
          and specific.id <> c.id
          and specific.exam_level_id = c.exam_level_id
          and specific.subsystem = c.subsystem
          and specific.sector = c.sector
          and (specific.series_id is not null or specific.specialty_id is not null)
      )
    )
  order by c.display_name;
$function$;

revoke all on function public.list_compatible_teacher_classes() from public, anon;
grant execute on function public.list_compatible_teacher_classes() to authenticated;
