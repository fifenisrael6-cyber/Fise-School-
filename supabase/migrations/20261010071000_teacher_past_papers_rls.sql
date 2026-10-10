-- Teacher exam papers: permit teachers to upload papers only to rooms they teach.
-- The UI requires at least one selected room; RLS independently verifies every target.

drop policy if exists "teachers insert own past papers" on public.past_papers;
create policy "teachers insert own past papers"
on public.past_papers for insert to authenticated
with check (
  created_by = auth.uid()
  and public.check_profile_role(auth.uid(), 'teacher')
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "teachers read own past papers" on public.past_papers;
create policy "teachers read own past papers"
on public.past_papers for select to authenticated
using (
  created_by = auth.uid()
  and public.check_profile_role(auth.uid(), 'teacher')
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
);

drop policy if exists "teachers add own paper targets" on public.past_paper_classes;
create policy "teachers add own paper targets"
on public.past_paper_classes for insert to authenticated
with check (
  exists (
    select 1 from public.past_papers pp
    where pp.id = paper_id and pp.created_by = auth.uid()
  )
  and exists (
    select 1 from public.class_teachers ct
    where ct.class_id = past_paper_classes.class_id
      and ct.teacher_id = auth.uid() and ct.is_active
  )
);

drop policy if exists "teachers read own paper targets" on public.past_paper_classes;
create policy "teachers read own paper targets"
on public.past_paper_classes for select to authenticated
using (
  exists (
    select 1 from public.past_papers pp
    where pp.id = paper_id and pp.created_by = auth.uid()
  )
);

drop policy if exists "teachers delete own paper targets" on public.past_paper_classes;
create policy "teachers delete own paper targets"
on public.past_paper_classes for delete to authenticated
using (
  exists (
    select 1 from public.past_papers pp
    where pp.id = paper_id and pp.created_by = auth.uid()
  )
);

drop policy if exists "teachers write past papers storage" on storage.objects;
create policy "teachers write past papers storage"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'past-papers'
  and public.check_profile_role(auth.uid(), 'teacher')
);

drop policy if exists "teachers update past papers storage" on storage.objects;
create policy "teachers update past papers storage"
on storage.objects for update to authenticated
using (bucket_id = 'past-papers' and public.check_profile_role(auth.uid(), 'teacher') and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'past-papers' and public.check_profile_role(auth.uid(), 'teacher') and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "teachers delete past papers storage" on storage.objects;
create policy "teachers delete past papers storage"
on storage.objects for delete to authenticated
using (bucket_id = 'past-papers' and public.check_profile_role(auth.uid(), 'teacher') and (storage.foldername(name))[1] = auth.uid()::text);
