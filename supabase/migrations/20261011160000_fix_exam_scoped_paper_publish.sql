-- Publish teacher past papers to their matching exam without requiring
-- a redundant per-class target. Reader access remains scoped by exam/subsystem.
drop policy if exists "teachers update own past papers" on public.past_papers;

create policy "teachers update own past papers"
on public.past_papers
for update
to authenticated
using (
  created_by = auth.uid()
  and public.check_profile_role(auth.uid(), 'teacher')
)
with check (
  created_by = auth.uid()
  and public.check_profile_role(auth.uid(), 'teacher')
  and (
    is_published = false
    or (
      exam_id is not null
      and subsystem is not null
      and exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and p.role = 'teacher'
          and p.subsystem = past_papers.subsystem
      )
    )
  )
);
