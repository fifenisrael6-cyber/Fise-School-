create or replace function public.list_teacher_class_subjects(p_class_id uuid)
returns table (
  subject_id uuid,
  is_compulsory boolean,
  option_group text,
  "position" integer,
  subjects jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cs.subject_id,
    cs.is_compulsory,
    cs.option_group,
    cs.position,
    to_jsonb(s) as subjects
  from public.class_subjects cs
  join public.school_classes c on c.id = cs.class_id
  join public.subjects s on s.id = cs.subject_id
  where cs.class_id = p_class_id
    and cs.is_active
    and c.is_active
    and (
      public.is_admin()
      or public.is_teacher_assigned(c.id, auth.uid())
      or exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.role = 'teacher'
          and p.subsystem = c.subsystem
          and p.sector = c.sector
      )
    )
  order by cs.position, s.name_fr;
$$;

revoke all on function public.list_teacher_class_subjects(uuid) from public, anon;
grant execute on function public.list_teacher_class_subjects(uuid) to authenticated;
