-- Fix teacher publication check: compare target paper to the outer paper ID,
-- not to class_teachers.id. Without this, upload can succeed but publication is denied.
drop policy if exists "teachers update own past papers" on public.past_papers;
create policy "teachers update own past papers"
on public.past_papers for update to authenticated
using (
  created_by = auth.uid()
  and public.check_profile_role(auth.uid(), 'teacher')
)
with check (
  created_by = auth.uid()
  and public.check_profile_role(auth.uid(), 'teacher')
  and (
    is_published = false
    or exists (
      select 1
      from public.past_paper_classes t
      join public.class_teachers ct on ct.class_id = t.class_id
      where t.paper_id = past_papers.id
        and ct.teacher_id = auth.uid()
        and ct.is_active
    )
  )
);
