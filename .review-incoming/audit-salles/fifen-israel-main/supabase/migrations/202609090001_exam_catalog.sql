-- Fise School: examination catalogue only.
-- No subjects, courses, assignments, forums, messages, or school classes are stored here.

create extension if not exists pgcrypto;

do $$
begin
  create type public.catalog_subsystem as enum ('francophone', 'anglophone');
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.catalog_sector as enum ('general', 'technical');
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  create type public.catalog_verification_status as enum (
    'verified',
    'pending_official_confirmation'
  );
exception
  when duplicate_object then null;
end
$$;

create table if not exists public.exams (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_fr text not null,
  name_en text not null,
  verification_status public.catalog_verification_status not null
    default 'pending_official_confirmation',
  source_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint exams_code_format check (code ~ '^[a-z0-9_]+$')
);

create table if not exists public.exam_levels (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  subsystem public.catalog_subsystem not null,
  sector public.catalog_sector not null,
  level_name_fr text not null,
  level_name_en text not null,
  exam_id uuid not null references public.exams(id) on delete restrict,
  verification_status public.catalog_verification_status not null
    default 'pending_official_confirmation',
  source_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint exam_levels_code_format check (code ~ '^[a-z0-9_]+$'),
  constraint exam_levels_subsystem_sector_unique
    unique (subsystem, sector, code)
);

create table if not exists public.series (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_fr text not null,
  name_en text not null,
  verification_status public.catalog_verification_status not null
    default 'pending_official_confirmation',
  source_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint series_code_format check (code ~ '^[a-z0-9_]+$')
);

create table if not exists public.specialties (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_fr text not null,
  name_en text not null,
  verification_status public.catalog_verification_status not null
    default 'pending_official_confirmation',
  source_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint specialties_code_format check (code ~ '^[a-z0-9_]+$')
);

create table if not exists public.exam_level_series (
  exam_level_id uuid not null references public.exam_levels(id) on delete cascade,
  series_id uuid not null references public.series(id) on delete cascade,
  verification_status public.catalog_verification_status not null
    default 'pending_official_confirmation',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (exam_level_id, series_id)
);

create table if not exists public.exam_level_specialties (
  exam_level_id uuid not null references public.exam_levels(id) on delete cascade,
  specialty_id uuid not null references public.specialties(id) on delete cascade,
  verification_status public.catalog_verification_status not null
    default 'pending_official_confirmation',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (exam_level_id, specialty_id)
);

create index if not exists exams_active_idx
  on public.exams (active);

create index if not exists exam_levels_filter_idx
  on public.exam_levels (subsystem, sector, active);

create index if not exists exam_levels_exam_id_idx
  on public.exam_levels (exam_id);

create index if not exists exam_level_series_series_id_idx
  on public.exam_level_series (series_id);

create index if not exists exam_level_specialties_specialty_id_idx
  on public.exam_level_specialties (specialty_id);

create index if not exists series_active_idx
  on public.series (active);

create index if not exists specialties_active_idx
  on public.specialties (active);

create or replace function public.set_catalog_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists exams_set_updated_at on public.exams;
create trigger exams_set_updated_at
before update on public.exams
for each row execute function public.set_catalog_updated_at();

drop trigger if exists exam_levels_set_updated_at on public.exam_levels;
create trigger exam_levels_set_updated_at
before update on public.exam_levels
for each row execute function public.set_catalog_updated_at();

drop trigger if exists series_set_updated_at on public.series;
create trigger series_set_updated_at
before update on public.series
for each row execute function public.set_catalog_updated_at();

drop trigger if exists specialties_set_updated_at on public.specialties;
create trigger specialties_set_updated_at
before update on public.specialties
for each row execute function public.set_catalog_updated_at();

-- The catalogue is readable by the public. Writes require an admin JWT.
-- service_role can also manage it because Supabase bypasses RLS for that role.
alter table public.exams enable row level security;
alter table public.exam_levels enable row level security;
alter table public.series enable row level security;
alter table public.specialties enable row level security;
alter table public.exam_level_series enable row level security;
alter table public.exam_level_specialties enable row level security;

create policy "catalog exams are publicly readable"
  on public.exams for select using (active = true);
create policy "catalog exam levels are publicly readable"
  on public.exam_levels for select using (active = true);
create policy "catalog series are publicly readable"
  on public.series for select using (active = true);
create policy "catalog specialties are publicly readable"
  on public.specialties for select using (active = true);
create policy "catalog level series are publicly readable"
  on public.exam_level_series for select using (active = true);
create policy "catalog level specialties are publicly readable"
  on public.exam_level_specialties for select using (active = true);

create policy "admins can insert catalogue exams"
  on public.exams for insert
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can update catalogue exams"
  on public.exams for update
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can delete catalogue exams"
  on public.exams for delete
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "admins can insert catalogue levels"
  on public.exam_levels for insert
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can update catalogue levels"
  on public.exam_levels for update
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can delete catalogue levels"
  on public.exam_levels for delete
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "admins can insert catalogue series"
  on public.series for insert
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can update catalogue series"
  on public.series for update
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can delete catalogue series"
  on public.series for delete
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "admins can insert catalogue specialties"
  on public.specialties for insert
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can update catalogue specialties"
  on public.specialties for update
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can delete catalogue specialties"
  on public.specialties for delete
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "admins can insert level series links"
  on public.exam_level_series for insert
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can update level series links"
  on public.exam_level_series for update
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can delete level series links"
  on public.exam_level_series for delete
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "admins can insert level specialty links"
  on public.exam_level_specialties for insert
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can update level specialty links"
  on public.exam_level_specialties for update
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
create policy "admins can delete level specialty links"
  on public.exam_level_specialties for delete
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- Verified English-system examination names from the Cameroon GCE Board.
insert into public.exams (code, name_fr, name_en, verification_status, source_url)
values
  ('bepc', 'BEPC', 'BEPC', 'pending_official_confirmation', null),
  ('probatoire', 'Probatoire', 'Probatoire', 'pending_official_confirmation', null),
  ('baccalaureat', 'Baccalauréat', 'Baccalaureat', 'pending_official_confirmation', null),
  ('cap', 'CAP', 'CAP', 'pending_official_confirmation', null),
  ('probatoire_technique', 'Probatoire technique', 'Technical Probatoire', 'pending_official_confirmation', null),
  ('baccalaureat_technique', 'Baccalauréat technique', 'Technical Baccalaureat', 'pending_official_confirmation', null),
  ('brevet_de_technicien', 'Brevet de Technicien', 'Brevet de Technicien', 'pending_official_confirmation', null),
  ('gce_ordinary_level', 'GCE Ordinary Level', 'GCE Ordinary Level', 'verified', 'https://camgceb.org/examinations/gce-ordinary-level/'),
  ('gce_advanced_level', 'GCE Advanced Level', 'GCE Advanced Level', 'verified', 'https://camgceb.org/examinations/gce-advanced-level/'),
  ('tve_intermediate_level', 'TVE Intermediate Level', 'Technical and Vocational Education Examination Intermediate Level', 'verified', 'https://camgceb.org/examinations/tve-intermediate-level/'),
  ('tve_advanced_level', 'TVE Advanced Level', 'Technical and Vocational Education Examination Advanced Level', 'verified', 'https://camgceb.org/examinations/tve-advanced-level/')
on conflict (code) do update set
  name_fr = excluded.name_fr,
  name_en = excluded.name_en,
  verification_status = excluded.verification_status,
  source_url = excluded.source_url,
  updated_at = now();

insert into public.exam_levels
  (code, subsystem, sector, level_name_fr, level_name_en, exam_id, verification_status, source_url)
select data.code, data.subsystem::public.catalog_subsystem, data.sector::public.catalog_sector,
  data.level_name_fr, data.level_name_en, exams.id,
  data.verification_status::public.catalog_verification_status, data.source_url
from (values
  ('fr_general_troisieme', 'francophone', 'general', 'Troisième', 'Third year', 'bepc', 'pending_official_confirmation', null),
  ('fr_general_premiere', 'francophone', 'general', 'Première', 'First year', 'probatoire', 'pending_official_confirmation', null),
  ('fr_general_terminale', 'francophone', 'general', 'Terminale', 'Final year', 'baccalaureat', 'pending_official_confirmation', null),
  ('fr_technical_cap', 'francophone', 'technical', 'Niveau lié au CAP', 'CAP level', 'cap', 'pending_official_confirmation', null),
  ('fr_technical_premiere', 'francophone', 'technical', 'Première technique', 'Technical first year', 'probatoire_technique', 'pending_official_confirmation', null),
  ('fr_technical_terminale', 'francophone', 'technical', 'Terminale technique', 'Technical final year', 'baccalaureat_technique', 'pending_official_confirmation', null),
  ('fr_technical_brevet_technicien', 'francophone', 'technical', 'Niveau lié au Brevet de Technicien', 'Brevet de Technicien level', 'brevet_de_technicien', 'pending_official_confirmation', null),
  ('en_general_form_5', 'anglophone', 'general', 'Form 5', 'Form 5', 'gce_ordinary_level', 'verified', 'https://camgceb.org/examinations/gce-ordinary-level/'),
  ('en_general_upper_sixth', 'anglophone', 'general', 'Upper Sixth', 'Upper Sixth', 'gce_advanced_level', 'verified', 'https://camgceb.org/examinations/gce-advanced-level/'),
  ('en_technical_form_5', 'anglophone', 'technical', 'Form 5', 'Form 5', 'tve_intermediate_level', 'verified', 'https://camgceb.org/examinations/tve-intermediate-level/'),
  ('en_technical_upper_sixth', 'anglophone', 'technical', 'Upper Sixth', 'Upper Sixth', 'tve_advanced_level', 'verified', 'https://camgceb.org/examinations/tve-advanced-level/')
) as data(code, subsystem, sector, level_name_fr, level_name_en, exam_code, verification_status, source_url)
join public.exams on exams.code = data.exam_code
on conflict (code) do update set
  subsystem = excluded.subsystem,
  sector = excluded.sector,
  level_name_fr = excluded.level_name_fr,
  level_name_en = excluded.level_name_en,
  exam_id = excluded.exam_id,
  verification_status = excluded.verification_status,
  source_url = excluded.source_url,
  updated_at = now();
