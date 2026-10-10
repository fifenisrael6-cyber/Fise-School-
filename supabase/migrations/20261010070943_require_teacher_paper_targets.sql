-- Prevent teacher uploads from becoming visible to all classrooms by default.
-- A teacher creates an unpublished row, adds validated classroom targets, then publishes it.
drop policy if exists "teachers insert own past papers" on public.past_papers;
create policy "teachers insert own past papers"
on public.past_papers for insert to authenticated
with check (
  created_by = auth.uid()
  and public.check_profile_role(auth.uid(), 'teacher')
  and is_published = false
);

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
      select 1 from public.past_paper_classes t
      join public.class_teachers ct on ct.class_id = t.class_id
      where t.paper_id = id
        and ct.teacher_id = auth.uid()
        and ct.is_active
    )
  )
);

drop policy if exists "teachers delete own past papers" on public.past_papers;
create policy "teachers delete own past papers"
on public.past_papers for delete to authenticated
using (
  created_by = auth.uid()
  and public.check_profile_role(auth.uid(), 'teacher')
);