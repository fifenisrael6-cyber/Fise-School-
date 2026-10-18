-- Fise School: subjects visible by class + teacher referral codes.
-- The class-to-subject layer prevents a student from seeing subjects from another
-- subsystem and gives each room its own curriculum catalogue.

create table if not exists public.class_subjects (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.school_classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  is_compulsory boolean not null default true,
  option_group text,
  position integer not null default 0 check (position >= 0),
  is_active boolean not null default true,
  unique (class_id, subject_id)
);

create index if not exists class_subjects_class_idx
  on public.class_subjects(class_id, is_active, position);

alter table public.class_subjects enable row level security;

drop policy if exists "students read subjects of their classes" on public.class_subjects;
create policy "students read subjects of their classes"
on public.class_subjects for select to authenticated
using (
  exists (
    select 1 from public.class_students cs
    where cs.class_id = class_subjects.class_id
      and cs.student_id = auth.uid()
      and cs.is_active
  )
  or public.is_catalog_admin()
  or exists (
    select 1 from public.class_teachers ct
    where ct.class_id = class_subjects.class_id
      and ct.teacher_id = auth.uid()
      and ct.is_active
  )
);

drop policy if exists "admins manage class subjects" on public.class_subjects;
create policy "admins manage class subjects"
on public.class_subjects for all to authenticated
using (public.is_catalog_admin())
with check (public.is_catalog_admin());

-- Seed a reusable official subject catalogue. Exact syllabus chapters remain
-- editable by teachers/admins through curricula and courses.
insert into public.subjects (code, name_fr, name_en, subsystem, sector, description_fr, description_en)
values
('francais','Français','French','francophone','general','Langue et littérature françaises','French language and literature'),
('anglais','Anglais','English','francophone','general','Langue anglaise','English language'),
('mathematiques','Mathématiques','Mathematics','francophone','general','Mathématiques','Mathematics'),
('physique','Physique','Physics','francophone','general','Physique','Physics'),
('chimie','Chimie','Chemistry','francophone','general','Chimie','Chemistry'),
('svt','Sciences de la Vie et de la Terre','Life and Earth Sciences','francophone','general','Sciences de la vie et de la Terre','Life and Earth Sciences'),
('histoire','Histoire','History','francophone','general','Histoire','History'),
('geographie','Géographie','Geography','francophone','general','Géographie','Geography'),
('informatique','Informatique','Computer Science','francophone','general','Informatique','Computer Science'),
('education_civique','Éducation à la citoyenneté','Citizenship Education','francophone','general','Citoyenneté et vie sociale','Citizenship education'),
('philosophie','Philosophie','Philosophy','francophone','general','Philosophie','Philosophy'),
('seconde_langue','Langue vivante II','Modern Language II','francophone','general','Deuxième langue vivante','Second modern language'),
('latin','Latin','Latin','francophone','general','Latin','Latin'),
('grec','Grec','Greek','francophone','general','Grec ancien','Ancient Greek'),
('arts_cinematographiques','Arts cinématographiques','Cinematographic Arts','francophone','general','Arts cinématographiques','Cinematographic arts'),
('english_language','English Language','English Language','anglophone','general','English language','English language'),
('french_language','French','French','anglophone','general','French language','French language'),
('mathematics_en','Mathematics','Mathematics','anglophone','general','Mathematics','Mathematics'),
('biology_en','Biology','Biology','anglophone','general','Biology','Biology'),
('chemistry_en','Chemistry','Chemistry','anglophone','general','Chemistry','Chemistry'),
('physics_en','Physics','Physics','anglophone','general','Physics','Physics'),
('geography_en','Geography','Geography','anglophone','general','Geography','Geography'),
('history_en','History','History','anglophone','general','History','History'),
('citizenship_en','Citizenship Education','Citizenship Education','anglophone','general','Citizenship Education','Citizenship Education'),
('religious_studies','Religious Studies','Religious Studies','anglophone','general','Religious Studies','Religious Studies'),
('computer_science_en','Computer Science','Computer Science','anglophone','general','Computer Science','Computer Science'),
('additional_mathematics','Additional Mathematics','Additional Mathematics','anglophone','general','Additional Mathematics','Additional Mathematics'),
('economics','Economics','Economics','anglophone','general','Economics','Economics'),
('accounting','Comptabilité','Accounting','anglophone','general','Comptabilité','Accounting'),
('commerce','Commerce','Commerce','anglophone','general','Commerce','Commerce'),
('literature_in_english','Littérature anglaise','Literature in English','anglophone','general','Littérature anglaise','Literature in English'),
('food_nutrition','Alimentation et nutrition','Food and Nutrition','anglophone','general','Alimentation et nutrition','Food and Nutrition'),
('geology','Géologie','Geology','anglophone','general','Géologie','Geology'),
('human_biology','Biologie humaine','Human Biology','anglophone','general','Biologie humaine','Human Biology'),
('logic','Logique','Logic','anglophone','general','Logique','Logic'),
('technical_math','Mathématiques techniques','Technical Mathematics','francophone','technical','Mathématiques techniques','Technical Mathematics'),
('technical_science','Sciences techniques','Technical Science','francophone','technical','Sciences techniques','Technical Science'),
('dessin_technique','Dessin technique','Technical Drawing','francophone','technical','Dessin technique','Technical Drawing'),
('technologie','Technologie','Technology','francophone','technical','Technologie','Technology'),
('entrepreneuriat','Entrepreneuriat','Entrepreneurship','francophone','technical','Entrepreneuriat','Entrepreneurship'),
('technical_english','Anglais technique','Technical English','francophone','technical','Anglais technique','Technical English'),
('technical_french','Français technique','Technical French','anglophone','technical','Français technique','Technical French'),
('technical_communication','Communication technique','Technical Communication','anglophone','technical','Communication technique','Technical Communication'),
('technical_math_en','Technical Mathematics','Technical Mathematics','anglophone','technical','Technical Mathematics','Technical Mathematics'),
('technical_science_en','Technical Science','Technical Science','anglophone','technical','Technical Science','Technical Science'),
('workshop_practice','Travaux pratiques','Workshop Practice','anglophone','technical','Travaux pratiques','Workshop Practice')
on conflict (code) do update set
  name_fr = excluded.name_fr,
  name_en = excluded.name_en,
  subsystem = excluded.subsystem,
  sector = excluded.sector,
  description_fr = excluded.description_fr,
  description_en = excluded.description_en,
  is_active = true,
  updated_at = now();

-- Populate the 2026-2027 rooms with a class-specific base catalogue.
-- First-cycle rooms get common subjects; second-cycle rooms additionally expose
-- the relevant options/series already present in the exam catalogue.
with current_classes as (
  select c.id, c.subsystem, c.sector, el.level_order
  from public.school_classes c
  join public.academic_years ay on ay.id = c.academic_year_id and ay.label = '2026-2027'
  join public.exam_levels el on el.id = c.exam_level_id
  where c.is_active
), chosen as (
  select cc.id class_id, s.id subject_id, true is_compulsory, null::text option_group,
         row_number() over (partition by cc.id order by s.code) - 1 position
  from current_classes cc
  join public.subjects s on s.is_active and s.subsystem = cc.subsystem and s.sector = cc.sector
  where (
    (cc.subsystem = 'francophone' and cc.sector = 'general' and s.code in
      ('francais','anglais','mathematiques','histoire','geographie','education_civique'))
    or
    (cc.subsystem = 'anglophone' and cc.sector = 'general' and s.code in
      ('english_language','french_language','mathematics_en','history_en','geography_en','citizenship_en'))
    or
    (cc.sector = 'technical' and s.code in
      ('technical_math','technical_science','dessin_technique','technologie','entrepreneuriat','technical_english'))
    or
    (cc.subsystem = 'anglophone' and cc.sector = 'technical' and s.code in
      ('technical_french','technical_communication','technical_math_en','technical_science_en','workshop_practice'))
  )
)
insert into public.class_subjects (class_id, subject_id, is_compulsory, option_group, position)
select class_id, subject_id, is_compulsory, option_group, position from chosen
on conflict (class_id, subject_id) do update set
  is_active = true,
  position = excluded.position;

-- Second-cycle option subjects.
with current_classes as (
  select c.id, c.subsystem, c.sector, el.level_order
  from public.school_classes c
  join public.academic_years ay on ay.id = c.academic_year_id and ay.label = '2026-2027'
  join public.exam_levels el on el.id = c.exam_level_id
  where c.is_active and el.level_order >= 5
), option_subjects as (
  select cc.id class_id, s.id subject_id, false is_compulsory,
         case when cc.subsystem = 'francophone' then 'Série / option' else 'GCE Arts / Science' end option_group,
         100 + row_number() over (partition by cc.id order by s.code) position
  from current_classes cc
  join public.subjects s on s.is_active
  where (
    (cc.subsystem = 'francophone' and cc.sector = 'general' and s.code in
      ('physique','chimie','svt','philosophie','seconde_langue','latin','grec','informatique'))
    or
    (cc.subsystem = 'anglophone' and cc.sector = 'general' and s.code in
      ('biology_en','chemistry_en','physics_en','economics','accounting','commerce','literature_in_english',
       'religious_studies','computer_science_en','additional_mathematics','food_nutrition','geology','human_biology','logic'))
  )
)
insert into public.class_subjects (class_id, subject_id, is_compulsory, option_group, position)
select class_id, subject_id, is_compulsory, option_group, position from option_subjects
on conflict (class_id, subject_id) do update set
  is_compulsory = excluded.is_compulsory,
  option_group = excluded.option_group,
  position = excluded.position,
  is_active = true;

-- Teacher payment/referral code. The code identifies the teacher at payment
-- creation time; the 200 XAF commission is credited only after successful
-- payment finalization on the server.
create table if not exists public.teacher_payment_codes (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null unique references public.profiles(id) on delete cascade,
  code text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.teacher_payment_codes enable row level security;

drop policy if exists "teachers read own payment code" on public.teacher_payment_codes;
create policy "teachers read own payment code"
on public.teacher_payment_codes for select to authenticated
using (teacher_id = auth.uid() or public.is_catalog_admin());

drop policy if exists "teachers insert own payment code" on public.teacher_payment_codes;
create policy "teachers insert own payment code"
on public.teacher_payment_codes for insert to authenticated
with check (teacher_id = auth.uid() and public.check_profile_role(auth.uid(), 'teacher'));

drop policy if exists "teachers update own payment code" on public.teacher_payment_codes;
create policy "teachers update own payment code"
on public.teacher_payment_codes for update to authenticated
using (teacher_id = auth.uid() or public.is_catalog_admin())
with check (teacher_id = auth.uid() or public.is_catalog_admin());

create or replace function public.create_teacher_payment_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if not public.check_profile_role(auth.uid(), 'teacher') then
    raise exception 'Only teachers can create a payment code';
  end if;

  select code into v_code
  from public.teacher_payment_codes
  where teacher_id = auth.uid() and active
  limit 1;

  if v_code is not null then
    return v_code;
  end if;

  loop
    v_code := 'FISE-' || upper(substr(md5(gen_random_uuid()::text), 1, 8));
    begin
      insert into public.teacher_payment_codes(teacher_id, code)
      values (auth.uid(), v_code);
      return v_code;
    exception when unique_violation then
      -- Extremely unlikely collision: generate another code.
    end;
  end loop;
end;
$$;

revoke all on function public.create_teacher_payment_code() from public;
grant execute on function public.create_teacher_payment_code() to authenticated;

create or replace function public.resolve_teacher_payment_code(p_code text)
returns uuid
language sql
security definer
set search_path = public
as $$
  select teacher_id
  from public.teacher_payment_codes
  where active and upper(code) = upper(trim(p_code))
  limit 1;
$$;

revoke all on function public.resolve_teacher_payment_code(text) from public;
grant execute on function public.resolve_teacher_payment_code(text) to authenticated;

-- Keep the existing payment finalization at 200 XAF per successful referred
-- premium payment.
update public.payment_orders
set teacher_commission_xaf = 200,
    platform_revenue_xaf = greatest(amount - 200, 0)
where amount = 1000 and provider = 'notchpay';
