create or replace function public.is_forum_member(target_class_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1
      from public.class_students cs
      where cs.class_id = target_class_id
        and cs.student_id = auth.uid()
        and cs.is_active = true
    )
    or
    exists (
      select 1
      from public.class_teachers ct
      where ct.class_id = target_class_id
        and ct.teacher_id = auth.uid()
        and ct.is_active = true
    );
$$;
