-- Fise School : évaluations automatisées (3/3)
-- Publication des bulletins contrôlée par l'administrateur (immédiate ou programmée),
-- politique de validation, règles de classement configurables, bulletin enrichi.
--
-- Réutilise `grade_periods` (is_published + trigger notify_period_published existants)
-- et `get_student_bulletin` (même signature, mêmes clés JSON + nouvelles clés).

-- ---------------------------------------------------------------------------
-- 1. Règles de calcul / classement de l'établissement
-- ---------------------------------------------------------------------------
create table if not exists public.grading_settings (
  id boolean primary key default true check (id),
  -- standard : 1, 2, 2, 4 — dense : 1, 2, 2, 3
  ranking_method text not null default 'standard' check (ranking_method in ('standard', 'dense')),
  -- Nombre minimal de matières notées pour apparaître au classement.
  min_subjects_for_rank integer not null default 1 check (min_subjects_for_rank >= 1),
  updated_at timestamptz not null default now()
);

insert into public.grading_settings (id) values (true) on conflict (id) do nothing;

alter table public.grading_settings enable row level security;

drop policy if exists "grading settings read" on public.grading_settings;
create policy "grading settings read" on public.grading_settings
for select to authenticated using (true);

drop policy if exists "grading settings admin write" on public.grading_settings;
create policy "grading settings admin write" on public.grading_settings
for all to authenticated
using (public.eval_is_admin()) with check (public.eval_is_admin());

-- ---------------------------------------------------------------------------
-- 2. Publication des périodes (bulletins)
-- ---------------------------------------------------------------------------
alter table public.grade_periods
  add column if not exists publish_status text not null default 'draft',
  add column if not exists publish_at timestamptz,
  add column if not exists unvalidated_policy text not null default 'block',
  add column if not exists publish_note text,
  add column if not exists published_at timestamptz,
  add column if not exists scheduled_by uuid references public.profiles(id) on delete set null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'grade_periods_publish_status_valid') then
    alter table public.grade_periods
      add constraint grade_periods_publish_status_valid
      check (publish_status in ('draft', 'scheduled', 'publishing', 'published', 'blocked', 'cancelled'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'grade_periods_unvalidated_policy_valid') then
    alter table public.grade_periods
      add constraint grade_periods_unvalidated_policy_valid
      check (unvalidated_policy in ('block', 'exclude'));
  end if;
end $$;

-- Périodes déjà publiées avant cette migration : on conserve leur état.
update public.grade_periods
set publish_status = 'published', published_at = coalesce(published_at, now())
where is_published and publish_status <> 'published';

-- Point d'application unique de la politique de validation (publication manuelle ou programmée).
--   block   : refuse la publication tant que des notes d'épreuves sont provisoires / à vérifier
--   exclude : publie ; seules les notes validées existent dans `grades`, les autres sont ignorées
create or replace function public.grade_periods_publication_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open integer;
begin
  if new.is_published and not old.is_published then
    select count(*) into v_open
    from public.evaluation_scores es
    where es.period_id = new.id and es.validation_status <> 'validated';
    if v_open > 0 and new.unvalidated_policy = 'block' then
      raise exception 'PUBLICATION_BLOQUEE : % note(s) d''épreuve encore provisoire(s) ou à vérifier pour cette période.', v_open;
    end if;
    new.publish_status := 'published';
    new.published_at := now();
    new.publish_note := case when v_open > 0
      then v_open || ' note(s) non validée(s) exclue(s) du bulletin (politique « exclure »).'
      else null end;
  elsif not new.is_published and old.is_published then
    new.publish_status := 'draft';
    new.published_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists grade_periods_publication_guard_trg on public.grade_periods;
create trigger grade_periods_publication_guard_trg
before update of is_published on public.grade_periods
for each row execute function public.grade_periods_publication_guard();

-- ---------------------------------------------------------------------------
-- 3. État de préparation (administrateur)
-- ---------------------------------------------------------------------------
create or replace function public.admin_period_publication_report(p_period uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  gp public.grade_periods%rowtype;
  v_total integer;
  v_validated integer;
  v_provisional integer;
  v_review integer;
  v_error integer;
  v_pending integer;
  v_open integer;
begin
  if not public.eval_is_admin() then
    raise exception 'Accès réservé à l''administration.';
  end if;
  select * into gp from public.grade_periods where id = p_period;
  if not found then
    raise exception 'Période introuvable.';
  end if;

  select count(*),
         count(*) filter (where validation_status = 'validated'),
         count(*) filter (where validation_status = 'provisional'),
         count(*) filter (where validation_status = 'provisional' and correction_status = 'needs_review'),
         count(*) filter (where validation_status = 'provisional' and correction_status = 'error'),
         count(*) filter (where validation_status = 'provisional' and correction_status in ('pending', 'processing'))
    into v_total, v_validated, v_provisional, v_review, v_error, v_pending
  from public.evaluation_scores where period_id = p_period;
  v_open := v_total - v_validated;

  return jsonb_build_object(
    'period', jsonb_build_object(
      'id', gp.id, 'label_fr', gp.label_fr, 'is_published', gp.is_published,
      'publish_status', gp.publish_status, 'publish_at', gp.publish_at,
      'unvalidated_policy', gp.unvalidated_policy, 'publish_note', gp.publish_note,
      'published_at', gp.published_at),
    'evaluations_count', (select count(*) from public.evaluations e where e.period_id = p_period and e.status <> 'draft'),
    'scores_total', v_total,
    'scores_validated', v_validated,
    'scores_provisional', v_provisional,
    'scores_needs_review', v_review,
    'scores_error', v_error,
    'scores_pending', v_pending,
    'grades_count', (select count(*) from public.grades g where g.period_id = p_period),
    'students_with_grades', (select count(distinct g.student_id) from public.grades g where g.period_id = p_period),
    'manual_conflicts', (select count(*) from public.evaluation_scores es
                         where es.period_id = p_period and es.grade_sync_status = 'skipped_manual'),
    'sync_errors', (select count(*) from public.evaluation_scores es
                    where es.period_id = p_period and es.grade_sync_status = 'error'),
    'classes_without_grades', coalesce((
      select jsonb_agg(c.display_name order by c.display_name)
      from public.school_classes c
      where c.is_active
        and exists (select 1 from public.class_students cs where cs.class_id = c.id and cs.is_active)
        and not exists (select 1 from public.grades g where g.class_id = c.id and g.period_id = p_period)
    ), '[]'::jsonb),
    'blocking', (gp.unvalidated_policy = 'block' and v_open > 0),
    'open_scores', v_open
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Exécution unique d'une publication
-- ---------------------------------------------------------------------------
create or replace function public.execute_period_publication(p_period uuid, p_actor uuid default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed uuid;
  v_label text;
begin
  -- Réservation atomique : une seule exécution peut passer de « non publiée » à « publishing ».
  update public.grade_periods
  set publish_status = 'publishing'
  where id = p_period
    and not is_published
    and publish_status in ('draft', 'scheduled', 'blocked', 'cancelled')
  returning id, label_fr into v_claimed, v_label;

  if v_claimed is null then
    return 'already_done';
  end if;

  begin
    -- Le trigger de garde applique la politique de validation, puis notify_period_published
    -- (existant) notifie uniquement les élèves qui ont des notes dans la période.
    update public.grade_periods set is_published = true where id = p_period;
  exception when others then
    update public.grade_periods
    set publish_status = 'blocked', publish_note = left(sqlerrm, 500)
    where id = p_period;
    insert into public.notifications (user_id, title, body, type)
    select p.id, 'Publication bloquée',
           left(coalesce(v_label, 'Période'), 120) || ' — ' || left(sqlerrm, 300), 'bulletin_admin'
    from public.profiles p where p.role = 'admin';
    return 'blocked';
  end;

  return 'published';
end;
$$;

revoke all on function public.execute_period_publication(uuid, uuid) from public, anon, authenticated;
grant execute on function public.execute_period_publication(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 5. RPC administrateur : programmer / modifier / annuler / publier maintenant
-- ---------------------------------------------------------------------------
create or replace function public.admin_schedule_period_publication(
  p_period uuid,
  p_publish_at timestamptz,
  p_policy text default 'block'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  gp public.grade_periods%rowtype;
begin
  if not public.eval_is_admin() then
    raise exception 'Accès réservé à l''administration.';
  end if;
  if p_policy not in ('block', 'exclude') then
    raise exception 'Politique de validation invalide.';
  end if;
  if p_publish_at is null or p_publish_at <= now() + interval '30 seconds' then
    raise exception 'La date de publication doit être dans le futur (ou utilisez « publier maintenant »).';
  end if;
  select * into gp from public.grade_periods where id = p_period for update;
  if not found then
    raise exception 'Période introuvable.';
  end if;
  if gp.is_published or gp.publish_status in ('published', 'publishing') then
    raise exception 'Cette période est déjà publiée ou en cours de publication.';
  end if;
  update public.grade_periods
  set publish_status = 'scheduled', publish_at = p_publish_at, unvalidated_policy = p_policy,
      scheduled_by = auth.uid(), publish_note = null
  where id = p_period;
  return jsonb_build_object('publish_status', 'scheduled', 'publish_at', p_publish_at, 'policy', p_policy);
end;
$$;

create or replace function public.admin_cancel_period_publication(p_period uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer;
begin
  if not public.eval_is_admin() then
    raise exception 'Accès réservé à l''administration.';
  end if;
  update public.grade_periods
  set publish_status = 'cancelled', publish_at = null, publish_note = null
  where id = p_period and not is_published and publish_status in ('scheduled', 'blocked');
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'Aucune publication programmée à annuler (déjà exécutée ou en cours).';
  end if;
end;
$$;

create or replace function public.admin_publish_period_now(p_period uuid, p_policy text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result text;
  v_note text;
begin
  if not public.eval_is_admin() then
    raise exception 'Accès réservé à l''administration.';
  end if;
  if p_policy is not null then
    if p_policy not in ('block', 'exclude') then
      raise exception 'Politique de validation invalide.';
    end if;
    update public.grade_periods set unvalidated_policy = p_policy
    where id = p_period and not is_published and publish_status <> 'publishing';
  end if;
  v_result := public.execute_period_publication(p_period, auth.uid());
  select publish_note into v_note from public.grade_periods where id = p_period;
  return jsonb_build_object('result', v_result, 'note', v_note);
end;
$$;

revoke all on function public.admin_schedule_period_publication(uuid, timestamptz, text) from public, anon;
revoke all on function public.admin_cancel_period_publication(uuid) from public, anon;
revoke all on function public.admin_publish_period_now(uuid, text) from public, anon;
revoke all on function public.admin_period_publication_report(uuid) from public, anon;
grant execute on function public.admin_schedule_period_publication(uuid, timestamptz, text) to authenticated;
grant execute on function public.admin_cancel_period_publication(uuid) to authenticated;
grant execute on function public.admin_publish_period_now(uuid, text) to authenticated;
grant execute on function public.admin_period_publication_report(uuid) to authenticated;

-- Exécution à l'heure décidée (chaque minute). Le claim atomique empêche toute double exécution.
create or replace function public.run_due_period_publications()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_n integer := 0;
begin
  for v_id in
    select gp.id from public.grade_periods gp
    where gp.publish_status = 'scheduled' and gp.publish_at <= now() and not gp.is_published
    order by gp.publish_at
    limit 20
  loop
    if public.execute_period_publication(v_id, null) = 'published' then
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$$;

revoke all on function public.run_due_period_publications() from public, anon, authenticated;
grant execute on function public.run_due_period_publications() to service_role;

do $$
begin
  create extension if not exists pg_cron with schema pg_catalog;
  perform cron.unschedule(jobid) from cron.job where jobname = 'fise-period-publications';
  perform cron.schedule('fise-period-publications', '* * * * *',
    'select public.run_due_period_publications();');
exception when others then
  raise notice 'pg_cron non configuré : planifiez fise-period-publications manuellement. (%)', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Bulletin : moyennes, coefficients, rang selon les règles configurées
-- ---------------------------------------------------------------------------
-- Moyenne pondérée par les coefficients ; une matière sans note est ignorée (jamais comptée 0).
create or replace function public.bulletin_class_averages(p_class uuid, p_period uuid)
returns table (student_id uuid, moy numeric, subjects_count integer)
language sql
stable
security definer
set search_path = public
as $$
  select g.student_id,
         sum((g.score / g.max_score * 20) * coalesce(cs.coefficient, 1))
           / nullif(sum(coalesce(cs.coefficient, 1)), 0) as moy,
         count(*)::integer as subjects_count
  from public.grades g
  left join public.class_subjects cs on cs.class_id = g.class_id and cs.subject_id = g.subject_id
  where g.class_id = p_class and g.period_id = p_period
  group by g.student_id;
$$;

revoke all on function public.bulletin_class_averages(uuid, uuid) from public, anon, authenticated;
grant execute on function public.bulletin_class_averages(uuid, uuid) to service_role;

create or replace function public.get_student_bulletin(p_student_id uuid, p_period_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_class uuid;
  v_published boolean;
  v_position integer;
  v_prev uuid;
  v_caller uuid := auth.uid();
  v_method text;
  v_min integer;
  v_avg numeric;
  v_prev_avg numeric;
  v_class_avg numeric;
  v_rank integer;
  v_size integer;
  v_result jsonb;
begin
  select cs.class_id into v_class
  from public.class_students cs
  where cs.student_id = p_student_id and cs.is_active
  order by cs.joined_at desc limit 1;
  if v_class is null then
    raise exception 'Élève sans salle.';
  end if;

  select gp.is_published, gp.position into v_published, v_position
  from public.grade_periods gp where gp.id = p_period_id;
  if v_published is null then
    raise exception 'Période introuvable.';
  end if;

  if not (
    public.is_catalog_admin()
    or public.is_admin()
    or public.teacher_can_manage_class(v_class, v_caller)
    or (v_caller = p_student_id and v_published)
  ) then
    raise exception 'Accès refusé.';
  end if;

  select gs.ranking_method, gs.min_subjects_for_rank into v_method, v_min
  from public.grading_settings gs where gs.id;
  v_method := coalesce(v_method, 'standard');
  v_min := coalesce(v_min, 1);

  select a.moy into v_avg from public.bulletin_class_averages(v_class, p_period_id) a
  where a.student_id = p_student_id;

  select round(avg(a.moy)::numeric, 2) into v_class_avg
  from public.bulletin_class_averages(v_class, p_period_id) a;

  select count(*) into v_size
  from public.bulletin_class_averages(v_class, p_period_id) a
  where a.subjects_count >= v_min;

  -- Rang recalculé à chaque appel : toute note validée modifiée est prise en compte.
  select r.rk into v_rank
  from (
    select a.student_id,
           case when v_method = 'dense'
                then dense_rank() over (order by a.moy desc)
                else rank() over (order by a.moy desc) end as rk
    from public.bulletin_class_averages(v_class, p_period_id) a
    where a.subjects_count >= v_min
  ) r
  where r.student_id = p_student_id;

  -- Progression : dernière période publiée précédente.
  select gp.id into v_prev
  from public.grade_periods gp
  where gp.position < v_position and gp.is_published
  order by gp.position desc limit 1;
  if v_prev is not null then
    select a.moy into v_prev_avg from public.bulletin_class_averages(v_class, v_prev) a
    where a.student_id = p_student_id;
  end if;

  with per_subject as (
    select g.subject_id,
           avg(g.score / g.max_score * 20) as c_avg,
           min(g.score / g.max_score * 20) as c_min,
           max(g.score / g.max_score * 20) as c_max
    from public.grades g
    where g.class_id = v_class and g.period_id = p_period_id
    group by g.subject_id
  )
  select jsonb_build_object(
    'class_id', v_class,
    'average', round(v_avg, 2),
    'rank', v_rank,
    'class_size', v_size,
    'class_average', v_class_avg,
    'average_gap', case when v_avg is null or v_class_avg is null then null
                        else round(v_avg - v_class_avg, 2) end,
    'previous_average', round(v_prev_avg, 2),
    'progress', case when v_avg is null or v_prev_avg is null then null
                     else round(v_avg - v_prev_avg, 2) end,
    'ranking_method', v_method,
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

revoke all on function public.get_student_bulletin(uuid, uuid) from public, anon;
grant execute on function public.get_student_bulletin(uuid, uuid) to authenticated;
