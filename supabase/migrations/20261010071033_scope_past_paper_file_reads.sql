-- Limit exam-paper downloads to users authorized for the corresponding classroom.
drop policy if exists "authenticated read past papers storage" on storage.objects;
create policy "authenticated read past papers storage"
on storage.objects for select to authenticated
using (
  bucket_id = 'past-papers'
  and exists (
    select 1
    from public.past_papers pp
    where pp.file_path = storage.objects.name
      and (
        public.can_read_past_paper(pp.id)
        or pp.created_by = auth.uid()
      )
  )
);