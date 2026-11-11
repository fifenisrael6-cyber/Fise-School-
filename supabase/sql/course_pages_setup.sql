-- Fise School: pages image du cahier de cours.
-- Exécuter dans le SQL Editor du projet Fise School.
-- course_id référence chapter_content_items.id (le cours publié), pas chapter_id.

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('course-pages', 'course-pages', false, 12582912, array['image/png'])
on conflict (id) do nothing;

create table if not exists public.course_pages (
  course_id uuid not null references public.chapter_content_items(id) on delete cascade,
  page_number integer not null check (page_number > 0),
  image_url text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (course_id, page_number)
);

create index if not exists course_pages_course_order_idx
  on public.course_pages (course_id, page_number);

alter table public.course_pages enable row level security;

grant select, insert, update, delete on public.course_pages to authenticated;

drop policy if exists "Students read pages of accessible published courses" on public.course_pages;
create policy "Students read pages of accessible published courses"
on public.course_pages
for select
to authenticated
using (
  public.is_catalog_admin()
  or public.student_can_access_chapter_content(course_id)
);

drop policy if exists "Admins manage course pages" on public.course_pages;
create policy "Admins manage course pages"
on public.course_pages
for all
to authenticated
using (public.is_catalog_admin())
with check (public.is_catalog_admin());

drop policy if exists "Course members read private course page images" on storage.objects;
create policy "Course members read private course page images"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'course-pages'
  and (
    public.is_catalog_admin()
    or exists (
      select 1
      from public.course_pages cp
      where cp.image_url = storage.objects.name
        and public.student_can_access_chapter_content(cp.course_id)
    )
  )
);

drop policy if exists "Admins upload course page images" on storage.objects;
create policy "Admins upload course page images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'course-pages'
  and public.is_catalog_admin()
);

drop policy if exists "Admins update course page images" on storage.objects;
create policy "Admins update course page images"
on storage.objects
for update
to authenticated
using (bucket_id = 'course-pages' and public.is_catalog_admin())
with check (bucket_id = 'course-pages' and public.is_catalog_admin());

drop policy if exists "Admins delete course page images" on storage.objects;
create policy "Admins delete course page images"
on storage.objects
for delete
to authenticated
using (bucket_id = 'course-pages' and public.is_catalog_admin());

commit;
