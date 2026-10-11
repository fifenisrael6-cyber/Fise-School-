-- Teachers can always read their own course library, even if class scope changed.
-- Course creation and edits remain guarded by the existing assigned-class policy.
-- Resource edit/delete is handled separately by the owner-scoped course_resources policy.
drop policy if exists "teachers retain own course management" on public.courses;
drop policy if exists "teachers read own course library" on public.courses;

create policy "teachers read own course library"
on public.courses for select to authenticated
using (
  public.is_admin()
  or (
    teacher_id = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'teacher'
    )
  )
);

notify pgrst, 'reload schema';
