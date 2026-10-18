-- Fise School: finalisation du catalogue scolaire et des pièces jointes privées.
-- Sources de référence:
-- MINESEC: https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone
-- GCE Board: https://camgceb.org/examinations/gce-ordinary-level/
-- GCE Board: https://camgceb.org/examinations/gce-advanced-level/

-- Technical francophone: 4-year first cycle, then 2nde T, 1ere T, Tle T.
insert into public.exam_levels
  (code, subsystem, sector, level_name_fr, level_name_en, exam_id,
   verification_status, is_exam_class, level_order, curriculum_fr, curriculum_en)
select data.code, 'francophone', 'technical',
       data.level_name_fr, data.level_name_en,
       case when data.exam_code is null then null else e.id end,
       'verified', data.is_exam_class, data.level_order,
       'Programme officiel MINESEC - enseignement secondaire technique et professionnel',
       'Official MINESEC technical and vocational secondary curriculum'
from (values
  ('fr_technical_1ere_annee', '1ère année technique', 'Technical Year 1', null, false, 1),
  ('fr_technical_2eme_annee', '2ème année technique', 'Technical Year 2', null, false, 2),
  ('fr_technical_3eme_annee', '3ème année technique', 'Technical Year 3', null, false, 3)
) as data(code, level_name_fr, level_name_en, exam_code, is_exam_class, level_order)
left join public.exams e on e.code = data.exam_code
on conflict (code) do update set
  level_name_fr = excluded.level_name_fr,
  level_name_en = excluded.level_name_en,
  exam_id = excluded.exam_id,
  verification_status = 'verified',
  is_exam_class = excluded.is_exam_class,
  level_order = excluded.level_order,
  curriculum_fr = excluded.curriculum_fr,
  curriculum_en = excluded.curriculum_en,
  active = true,
  updated_at = now();


-- The technical first cycle is represented as Year 1-4; older placeholder
-- names (Sixième/Cinquième/Quatrième/Troisième technique) are retired.
update public.exam_levels
set active = false, updated_at = now()
where code in (
  'fr_technical_sixieme',
  'fr_technical_cinquieme',
  'fr_technical_quatrieme',
  'fr_technical_troisieme'
);

-- Classes techniques d'examen.
update public.exam_levels
set level_name_fr = '4ème année technique (CAP)',
    level_name_en = 'Technical Year 4 (CAP)',
    exam_id = (select id from public.exams where code = 'cap'),
    is_exam_class = true,
    verification_status = 'verified',
    level_order = 4,
    active = true
where code = 'fr_technical_cap';

update public.exam_levels
set level_name_fr = 'Première technique (Probatoire)',
    level_name_en = 'Technical First Year (Probatoire)',
    exam_id = (select id from public.exams where code = 'probatoire_technique'),
    is_exam_class = true,
    verification_status = 'verified',
    level_order = 6,
    active = true
where code = 'fr_technical_premiere';

update public.exam_levels
set level_name_fr = 'Terminale technique (Baccalauréat)',
    level_name_en = 'Technical Final Year (Baccalaureat)',
    exam_id = (select id from public.exams where code = 'baccalaureat_technique'),
    is_exam_class = true,
    verification_status = 'verified',
    level_order = 7,
    active = true
where code = 'fr_technical_terminale';

-- The Brevet de Technicien is also an end-of-second-cycle pathway.
update public.exam_levels
set level_name_fr = 'Terminale technique (Brevet de Technicien)',
    level_name_en = 'Technical Final Year (Brevet de Technicien)',
    exam_id = (select id from public.exams where code = 'brevet_de_technicien'),
    is_exam_class = true,
    verification_status = 'verified',
    level_order = 7,
    active = true
where code = 'fr_technical_brevet_technicien';

-- 2nde technique was already present in the previous catalogue.
update public.exam_levels
set verification_status = 'verified',
    curriculum_fr = 'Programme officiel MINESEC - enseignement secondaire technique et professionnel',
    curriculum_en = 'Official MINESEC technical and vocational secondary curriculum'
where code = 'fr_technical_seconde';

-- English general and technical examination classes are explicitly verified.
update public.exam_levels
set verification_status = 'verified',
    is_exam_class = true
where code in (
  'en_general_form_5',
  'en_general_upper_sixth',
  'en_technical_form_5',
  'en_technical_upper_sixth'
);

-- Keep the complete 7-year general pathways ordered.
update public.exam_levels set level_order = case code
  when 'fr_general_sixieme' then 1
  when 'fr_general_cinquieme' then 2
  when 'fr_general_quatrieme' then 3
  when 'fr_general_troisieme' then 4
  when 'fr_general_seconde' then 5
  when 'fr_general_premiere' then 6
  when 'fr_general_terminale' then 7
  when 'en_general_form_1' then 1
  when 'en_general_form_2' then 2
  when 'en_general_form_3' then 3
  when 'en_general_form_4' then 4
  when 'en_general_form_5' then 5
  when 'en_general_lower_sixth' then 6
  when 'en_general_upper_sixth' then 7
  else level_order end
where code like 'fr_general_%' or code like 'en_general_%';

-- Private-message attachments.
alter table public.private_messages
  add column if not exists attachment_path text,
  add column if not exists attachment_name text,
  add column if not exists attachment_type text,
  add column if not exists attachment_size bigint;

-- Allow an attachment-only message.
alter table public.private_messages
  drop constraint if exists private_messages_body_not_blank;

alter table public.private_messages
  add constraint private_messages_body_or_attachment check (
    length(trim(coalesce(body, ''))) > 0
    or attachment_path is not null
  );

insert into storage.buckets (id, name, public)
values ('private-message-attachments', 'private-message-attachments', false)
on conflict (id) do update set public = false;

drop policy if exists "private message attachments participants read"
  on storage.objects;
create policy "private message attachments participants read"
on storage.objects for select to authenticated
using (
  bucket_id = 'private-message-attachments'
  and exists (
    select 1
    from public.private_messages pm
    where pm.attachment_path = name
      and (pm.sender_id = auth.uid() or pm.recipient_id = auth.uid())
  )
);

drop policy if exists "private message attachments sender upload"
  on storage.objects;
create policy "private message attachments sender upload"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'private-message-attachments'
  and owner_id = auth.uid()::text
  and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "private message attachments sender delete"
  on storage.objects;
create policy "private message attachments sender delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'private-message-attachments'
  and owner_id = auth.uid()::text
);

-- The RPC already returns setof private_messages, so the new attachment columns
-- are returned automatically without changing its public signature.


-- Officially listed general series from MINESEC and the main GCE registration groups.
insert into public.series (code, name_fr, name_en, verification_status, source_url)
values
  ('a1', 'A1 - Lettres, Latin et Grec', 'A1 - Arts, Latin and Greek', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('a2', 'A2 - Lettres, Latin et Langue Vivante II', 'A2 - Arts, Latin and Modern Language II', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('a3', 'A3 - Lettres et Latin', 'A3 - Arts and Latin', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('a4', 'A4 - Lettres, Langue Vivante II et Philosophie', 'A4 - Arts, Modern Language II and Philosophy', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('a5', 'A5 - Langues Vivantes II et III', 'A5 - Modern Languages II and III', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('ac', 'AC - Art Cinématographique', 'AC - Cinematographic Arts', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('c', 'C - Mathématiques et Physique', 'C - Mathematics and Physics', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('d', 'D - Sciences de la Vie et de la Terre et Mathématique', 'D - Life and Earth Sciences and Mathematics', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('ti', 'TI - Technologie de l’Information', 'TI - Information Technology', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('bil', 'BIL - Bilingue', 'BIL - Bilingual', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('gce_arts', 'Arts', 'Arts', 'verified', 'https://camgceb.org/wp-content/uploads/2025/10/2026-E-Reg-user-manual.pdf'),
  ('gce_science', 'Science', 'Science', 'verified', 'https://camgceb.org/wp-content/uploads/2025/10/2026-E-Reg-user-manual.pdf')
on conflict (code) do update set
  name_fr = excluded.name_fr,
  name_en = excluded.name_en,
  verification_status = 'verified',
  source_url = excluded.source_url,
  active = true,
  updated_at = now();

-- A practical catalogue of technical/vocational specialties explicitly listed by MINESEC.
insert into public.specialties (code, name_fr, name_en, verification_status, source_url)
values
  ('aat', 'Accueil et Animation Touristique', 'Tourist Reception and Animation', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('aca', 'Action et Communication Administrative', 'Administrative Action and Communication', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('acc', 'Action et Communication Commerciale', 'Commercial Action and Communication', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('av', 'Agence de Voyage', 'Travel Agency', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('cg', 'Comptabilité de Gestion', 'Accounting and Management', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('esf', 'Économie Sociale et Familiale', 'Social and Family Economy', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('fig', 'Fiscalité et Informatique de Gestion', 'Taxation and Management Information Systems', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('he', 'Hébergement', 'Accommodation', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('ho', 'Hôtellerie', 'Hotel Management', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('to', 'Tourisme', 'Tourism', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('vente', 'Vendeur', 'Sales', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('f3', 'Électrotechnique', 'Electrotechnics', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('f5', 'Froid et Climatisation', 'Refrigeration and Air Conditioning', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('f7', 'Science et Technique Biologique', 'Biological Science and Technology', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('f8', 'Science et Technologie de la Santé', 'Health Science and Technology', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('mav', 'Maintenance Audiovisuelle', 'Audiovisual Maintenance', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('mise', 'Maintenance et Installation des Systèmes Électroniques', 'Maintenance and Installation of Electronic Systems', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('insa', 'Installation Sanitaire', 'Plumbing and Sanitary Installation', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('maco', 'Maçonnerie', 'Masonry', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('menu', 'Menuiserie', 'Carpentry', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('pa', 'Production Animale', 'Animal Production', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('pv', 'Production Végétale', 'Crop Production', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('come', 'Couture sur Mesure', 'Custom Tailoring', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('decor', 'Décoration', 'Decoration', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('esco', 'Esthétique Coiffure', 'Hairdressing and Beauty', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone'),
  ('peint', 'Peinture', 'Painting', 'verified', 'https://minesec.gov.cm/web/index.php/fr/systeme-educatif/offre-de-formation/sous-systeme-francophone')
on conflict (code) do update set
  name_fr = excluded.name_fr,
  name_en = excluded.name_en,
  verification_status = 'verified',
  source_url = excluded.source_url,
  active = true,
  updated_at = now();

-- Link general series to the general exam levels. This keeps registration
-- consistent with the selected subsystem and sector.
insert into public.exam_level_series (exam_level_id, series_id, verification_status, active)
select el.id, s.id, 'verified', true
from public.exam_levels el
cross join public.series s
where el.sector = 'general'
  and (
    (el.subsystem = 'francophone' and s.code in ('a1','a2','a3','a4','a5','ac','c','d','ti','bil'))
    or
    (el.subsystem = 'anglophone' and s.code in ('gce_arts','gce_science'))
  )
on conflict (exam_level_id, series_id) do update set
  verification_status = 'verified',
  active = true;

-- Technical specialties apply from the technical second-cycle choice onward.
insert into public.exam_level_specialties (exam_level_id, specialty_id, verification_status, active)
select el.id, s.id, 'verified', true
from public.exam_levels el
cross join public.specialties s
where el.sector = 'technical'
  and el.level_order >= 5
on conflict (exam_level_id, specialty_id) do update set
  verification_status = 'verified',
  active = true;

-- Create the 2026-2027 academic year and the complete 28-room base:
-- 7 francophone general + 7 anglophone general + 7 francophone technical
-- + 7 anglophone technical. Admins may rename/deactivate rooms later.
update public.academic_years
set is_current = false
where is_current = true and label <> '2026-2027';

insert into public.academic_years (label, start_date, end_date, is_current)
values ('2026-2027', '2026-09-01', '2027-07-31', true)
on conflict (label) do update set
  start_date = excluded.start_date,
  end_date = excluded.end_date,
  is_current = true;

insert into public.school_classes
  (name, display_name, subsystem, sector, academic_year_id, exam_level_id, series_id, specialty_id)
select
  el.code,
  case
    when el.subsystem = 'francophone' then el.level_name_fr
    else el.level_name_en
  end,
  el.subsystem,
  el.sector,
  ay.id,
  el.id,
  null,
  null
from public.exam_levels el
cross join public.academic_years ay
where ay.label = '2026-2027'
  and el.active
  and el.code <> 'fr_technical_brevet_technicien'
on conflict (name, academic_year_id) do update set
  display_name = excluded.display_name,
  subsystem = excluded.subsystem,
  sector = excluded.sector,
  exam_level_id = excluded.exam_level_id,
  updated_at = now();
