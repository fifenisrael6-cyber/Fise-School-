-- Fise School: annales d'examens (sujets et corrigés).

create table if not exists public.past_papers (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid references public.exams(id) on delete set null,
  subsystem public.catalog_subsystem,
  exam_year integer not null check (exam_year between 1990 and 2100),
  session_label text,
  subject_fr text not null,
  subject_en text not null,
  kind text not null default 'subject' check (kind in ('subject', 'correction')),
  file_path text not null,
  file_name text not null,
  is_published boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists past_papers_exam_year_idx
  on public.past_papers(exam_id, exam_year desc);
create index if not exists past_papers_published_idx
  on public.past_papers(is_published, exam_year desc);

alter table public.past_papers enable row level security;

drop policy if exists "read published past papers" on public.past_papers;
create policy "read published past papers"
on public.past_papers for select to authenticated
using (is_published or public.is_catalog_admin());

drop policy if exists "admins manage past papers" on public.past_papers;
create policy "admins manage past papers"
on public.past_papers for all to authenticated
using (public.is_catalog_admin())
with check (public.is_catalog_admin());

insert into storage.buckets (id, name, public)
values ('past-papers', 'past-papers', false)
on conflict (id) do nothing;

drop policy if exists "authenticated read past papers storage" on storage.objects;
create policy "authenticated read past papers storage"
on storage.objects for select to authenticated
using (bucket_id = 'past-papers');

drop policy if exists "admins write past papers storage" on storage.objects;
create policy "admins write past papers storage"
on storage.objects for insert to authenticated
with check (bucket_id = 'past-papers' and public.is_catalog_admin());

drop policy if exists "admins update past papers storage" on storage.objects;
create policy "admins update past papers storage"
on storage.objects for update to authenticated
using (bucket_id = 'past-papers' and public.is_catalog_admin())
with check (bucket_id = 'past-papers' and public.is_catalog_admin());

drop policy if exists "admins delete past papers storage" on storage.objects;
create policy "admins delete past papers storage"
on storage.objects for delete to authenticated
using (bucket_id = 'past-papers' and public.is_catalog_admin());
