-- Fise School: notes et bulletins.

alter table public.class_subjects
  add column if not exists coefficient numeric(4,2) not null default 1 check (coefficient > 0);

create table if not exists public.grade_periods (
  id uuid primary key default gen_random_uuid(),
  label_fr text not null,
  label_en text not null,
  position integer not null default 0,
  is_published boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.grade_periods (label_fr, label_en, position)
select 'Séquence ' || n, 'Sequence ' || n, n
from generate_series(1, 6) as n
where not exists (select 1 from public.grade_periods);

create table if not exists public.grades (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.school_classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  period_id uuid not null references public.grade_periods(id) on delete cascade,
  score numeric(5,2) not null check (score >= 0),
  max_score numeric(5,2) not null default 20 check (max_score > 0),
  comment text,
  entered_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, subject_id, period_id),
  constraint grades_score_within_max check (score <= max_score)
);

create index if not exists grades_class_period_idx on public.grades(class_id, period_id, subject_id);
create index if not exists grades_student_idx on public.grades(student_id, period_id);

create or replace function public.validate_grade()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.class_students cs
    where cs.class_id = new.class_id and cs.student_id = new.student_id and cs.is_active
  ) then
    raise exception 'Cet élève n''appartient pas à cette salle.';
  end if;
  if not exists (
    select 1 from public.class_subjects s
    where s.class_id = new.class_id and s.subject_id = new.subject_id and s.is_active
  ) then
    raise exception 'Cette matière n''appartient pas à cette salle.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists grades_validate on public.grades;
create trigger grades_validate
before insert or update on public.grades
for each row execute function public.validate_grade();

alter table public.grade_periods enable row level security;
alter table public.grades enable row level security;

drop policy if exists "authenticated read grade periods" on public.grade_periods;
create policy "authenticated read grade periods"
on public.grade_periods for select to authenticated using (true);

drop policy if exists "admins manage grade periods" on public.grade_periods;
create policy "admins manage grade periods"
on public.grade_periods for all to authenticated
using (public.is_catalog_admin()) with check (public.is_catalog_admin());

drop policy if exists "students read own published grades" on public.grades;
create policy "students read own published grades"
on public.grades for select to authenticated
using (
  student_id = auth.uid()
  and exists (select 1 from public.grade_periods p where p.id = grades.period_id and p.is_published)
);

drop policy if exists "staff read class grades" on public.grades;
create policy "staff read class grades"
on public.grades for select to authenticated
using (public.is_catalog_admin() or public.teacher_can_manage_class(class_id, auth.uid()));

drop policy if exists "staff write class grades" on public.grades;
create policy "staff write class grades"
on public.grades for all to authenticated
using (public.is_catalog_admin() or public.teacher_can_manage_class(class_id, auth.uid()))
with check (public.is_catalog_admin() or public.teacher_can_manage_class(class_id, auth.uid()));

-- Les coefficients des matières d'une salle sont modifiables par l'administrateur.
drop policy if exists "admins update class subject coefficients" on public.class_subjects;
create policy "admins update class subject coefficients"
on public.class_subjects for update to authenticated
using (public.is_catalog_admin()) with check (public.is_catalog_admin());

-- Liste des élèves d'une salle pour la saisie des notes.
create or replace function public.list_grade_roster(p_class_id uuid)
returns table (student_id uuid, first_name text, last_name text)
language sql stable security definer set search_path = public
as $$
  select p.id, p.first_name, p.last_name
  from public.class_students cs
  join public.profiles p on p.id = cs.student_id
  where cs.class_id = p_class_id
    and cs.is_active
    and (public.is_catalog_admin() or public.teacher_can_manage_class(p_class_id, auth.uid()))
  order by p.last_name, p.first_name;
$$;
revoke all on function public.list_grade_roster(uuid) from public;
grant execute on function public.list_grade_roster(uuid) to authenticated;

-- Bulletin d'un élève pour une période : notes, moyennes, rang.
create or replace function public.get_student_bulletin(p_student_id uuid, p_period_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_class uuid;
  v_published boolean;
  v_caller uuid := auth.uid();
  v_result jsonb;
begin
  select cs.class_id into v_class
  from public.class_students cs
  where cs.student_id = p_student_id and cs.is_active
  order by cs.joined_at desc limit 1;
  if v_class is null then
    raise exception 'Élève sans salle.';
  end if;

  select gp.is_published into v_published from public.grade_periods gp where gp.id = p_period_id;
  if v_published is null then
    raise exception 'Période introuvable.';
  end if;

  if not (
    public.is_catalog_admin()
    or public.teacher_can_manage_class(v_class, v_caller)
    or (v_caller = p_student_id and v_published)
  ) then
    raise exception 'Accès refusé.';
  end if;

  with scored as (
    select g.student_id, g.subject_id,
           g.score / g.max_score * 20 as s20,
           coalesce(cs.coefficient, 1) as coef
    from public.grades g
    left join public.class_subjects cs on cs.class_id = g.class_id and cs.subject_id = g.subject_id
    where g.class_id = v_class and g.period_id = p_period_id
  ),
  averages as (
    select student_id, sum(s20 * coef) / nullif(sum(coef), 0) as moy
    from scored group by student_id
  ),
  ranked as (
    select student_id, moy, rank() over (order by moy desc) as rk from averages
  ),
  per_subject as (
    select subject_id, avg(s20) as c_avg, min(s20) as c_min, max(s20) as c_max
    from scored group by subject_id
  )
  select jsonb_build_object(
    'class_id', v_class,
    'average', (select round(r.moy::numeric, 2) from ranked r where r.student_id = p_student_id),
    'rank', (select r.rk from ranked r where r.student_id = p_student_id),
    'class_size', (select count(*) from ranked),
    'class_average', (select round(avg(a.moy)::numeric, 2) from averages a),
    'subjects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'subject_id', g.subject_id,
        'name_fr', s.name_fr,
        'name_en', s.name_en,
        'score', g.score,
        'max_score', g.max_score,
        'score20', round((g.score / g.max_score * 20)::numeric, 2),
        'coefficient', coalesce(cs.coefficient, 1),
        'class_average', round(ps.c_avg::numeric, 2),
        'class_min', round(ps.c_min::numeric, 2),
        'class_max', round(ps.c_max::numeric, 2),
        'comment', g.comment
      ) order by cs.position nulls last, s.name_fr)
      from public.grades g
      join public.subjects s on s.id = g.subject_id
      left join public.class_subjects cs on cs.class_id = g.class_id and cs.subject_id = g.subject_id
      left join per_subject ps on ps.subject_id = g.subject_id
      where g.class_id = v_class and g.period_id = p_period_id and g.student_id = p_student_id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;
revoke all on function public.get_student_bulletin(uuid, uuid) from public;
grant execute on function public.get_student_bulletin(uuid, uuid) to authenticated;

-- Notification aux élèves quand une période est publiée.
create or replace function public.notify_period_published()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.is_published and not old.is_published then
    insert into public.notifications(user_id, title, body, type)
    select distinct g.student_id, 'Bulletin disponible', left(new.label_fr, 500), 'bulletin'
    from public.grades g where g.period_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists grade_period_published on public.grade_periods;
create trigger grade_period_published
after update of is_published on public.grade_periods
for each row execute function public.notify_period_published();
