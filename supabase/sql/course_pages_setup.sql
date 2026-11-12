-- Fise School: pages rasterisées des PDF de cours.
-- Prend en charge les cours historiques (courses/course_resources)
-- et les cours du catalogue de chapitres (chapter_content_items).
-- course_id contient l'identifiant du cours propriétaire, jamais un chemin Storage.

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('course-pages', 'course-pages', false, 26214400, array['image/png'])
on conflict (id) do nothing;

create table if not exists public.course_pages (
  course_id uuid not null,
  page_number integer not null check (page_number > 0),
  image_url text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (course_id, page_number)
);

-- Si une première version locale de la table a été créée avec une FK
-- limitée à chapter_content_items, la retirer : course_id peut aussi
-- désigner courses.id pour les anciens PDF dans course_resources.
do $$
declare
  constraint_row record;
begin
  for constraint_row in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace ns on ns.oid = rel.relnamespace
    join pg_class referenced on referenced.oid = con.confrelid
    where ns.nspname = 'public'
      and rel.relname = 'course_pages'
      and con.contype = 'f'
      and referenced.relname = 'chapter_content_items'
  loop
    execute format('alter table public.course_pages drop constraint %I', constraint_row.conname);
  end loop;
end $$;

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
  public.is_admin()
  or public.is_catalog_admin()
  or public.is_course_student(course_id)
  or public.student_can_access_chapter_content(course_id)
);

drop policy if exists "Admins manage course pages" on public.course_pages;
create policy "Admins manage course pages"
on public.course_pages
for all
to authenticated
using (public.is_admin() or public.is_catalog_admin())
with check (public.is_admin() or public.is_catalog_admin());

drop policy if exists "Course members read private course page images" on storage.objects;
create policy "Course members read private course page images"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'course-pages'
  and (
    public.is_admin()
    or public.is_catalog_admin()
    or exists (
      select 1
      from public.course_pages cp
      where cp.image_url = storage.objects.name
        and (
          public.is_course_student(cp.course_id)
          or public.student_can_access_chapter_content(cp.course_id)
        )
    )
  )
);

-- Admins need read access to the original private PDF in order to
-- render its pages locally on the administrator's device.
drop policy if exists "Admins read course resource files for page conversion" on storage.objects;
create policy "Admins read course resource files for page conversion"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'course-resources'
  and (public.is_admin() or public.is_catalog_admin())
);

drop policy if exists "Admins upload course page images" on storage.objects;
create policy "Admins upload course page images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'course-pages'
  and (public.is_admin() or public.is_catalog_admin())
);

drop policy if exists "Admins update course page images" on storage.objects;
create policy "Admins update course page images"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'course-pages'
  and (public.is_admin() or public.is_catalog_admin())
)
with check (
  bucket_id = 'course-pages'
  and (public.is_admin() or public.is_catalog_admin())
);

drop policy if exists "Admins delete course page images" on storage.objects;
create policy "Admins delete course page images"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'course-pages'
  and (public.is_admin() or public.is_catalog_admin())
);

commit;
