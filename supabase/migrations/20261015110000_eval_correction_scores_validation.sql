-- Fise School : évaluations automatisées (2/3)
-- Remise définitive, file de corrections IA (asynchrone, idempotente), notes centralisées,
-- historique, validation par l'enseignant, alimentation de `grades` (bulletins).
--
-- Réutilise `grades`, `grade_periods`, `notifications` (+ webhook send-push existant).

-- ---------------------------------------------------------------------------
-- 1. Tâches de correction (une seule par remise)
-- ---------------------------------------------------------------------------
create table if not exists public.evaluation_corrections (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null unique references public.evaluation_submissions(id) on delete cascade,
  evaluation_id uuid not null references public.evaluations(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  -- en attente / en cours / terminée / à vérifier / en erreur
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'done', 'needs_review', 'error')),
  attempts integer not null default 0,
  max_attempts integer not null default 4,
  next_attempt_at timestamptz not null default now(),
  locked_until timestamptz,
  last_error text,
  ai_model text,
  overall_confidence numeric(4,3),
  review_reasons text[] not null default '{}',
  -- Données brutes de l'IA (transcription, qualité des images) conservées pour vérification.
  extracted jsonb,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists evaluation_corrections_queue_idx
  on public.evaluation_corrections(status, next_attempt_at);
create index if not exists evaluation_corrections_eval_idx
  on public.evaluation_corrections(evaluation_id, status);

create table if not exists public.evaluation_question_results (
  id uuid primary key default gen_random_uuid(),
  correction_id uuid not null references public.evaluation_corrections(id) on delete cascade,
  submission_id uuid not null references public.evaluation_submissions(id) on delete cascade,
  evaluation_id uuid not null references public.evaluations(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  question_key text not null,
  question_label text,
  student_answer text,
  legible boolean not null default true,
  ambiguous boolean not null default false,
  confidence numeric(4,3),
  ai_points numeric(6,2),
  max_points numeric(6,2) not null default 0,
  final_points numeric(6,2),
  flags text[] not null default '{}',
  needs_review boolean not null default false,
  feedback_fr text,
  teacher_comment text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint evaluation_question_results_unique unique (correction_id, question_key),
  constraint evaluation_question_results_points check (
    (ai_points is null or (ai_points >= 0 and ai_points <= max_points))
    and (final_points is null or (final_points >= 0 and final_points <= max_points))
  )
);

create index if not exists evaluation_question_results_sub_idx
  on public.evaluation_question_results(submission_id);

-- ---------------------------------------------------------------------------
-- 2. Notes centralisées par épreuve + historique
-- ---------------------------------------------------------------------------
create table if not exists public.evaluation_scores (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null unique references public.evaluation_submissions(id) on delete cascade,
  evaluation_id uuid not null references public.evaluations(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  period_id uuid references public.grade_periods(id) on delete set null,
  evaluation_date date not null,
  max_score numeric(6,2) not null check (max_score > 0),
  provisional_score numeric(6,2),
  raw_score numeric(6,2),
  penalty_percent numeric(5,2) not null default 0,
  final_score numeric(6,2),
  correction_status text not null default 'pending'
    check (correction_status in ('pending', 'processing', 'done', 'needs_review', 'error')),
  validation_status text not null default 'provisional'
    check (validation_status in ('provisional', 'validated')),
  validated_by uuid references public.profiles(id) on delete set null,
  validated_at timestamptz,
  teacher_comment text,
  grade_sync_status text,
  student_notified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint evaluation_scores_range check (
    (provisional_score is null or (provisional_score >= 0 and provisional_score <= max_score))
    and (raw_score is null or (raw_score >= 0 and raw_score <= max_score))
    and (final_score is null or (final_score >= 0 and final_score <= max_score))
  ),
  constraint evaluation_scores_validated_has_score check (
    validation_status <> 'validated' or final_score is not null
  )
);

create index if not exists evaluation_scores_student_idx
  on public.evaluation_scores(student_id, subject_id, period_id);
create index if not exists evaluation_scores_eval_idx
  on public.evaluation_scores(evaluation_id, validation_status);
create index if not exists evaluation_scores_period_idx
  on public.evaluation_scores(period_id, validation_status);

create table if not exists public.evaluation_score_history (
  id uuid primary key default gen_random_uuid(),
  score_id uuid not null references public.evaluation_scores(id) on delete cascade,
  submission_id uuid not null,
  evaluation_id uuid not null,
  student_id uuid not null,
  changed_by uuid references public.profiles(id) on delete set null,
  change_type text not null,
  old_provisional numeric(6,2),
  new_provisional numeric(6,2),
  old_raw numeric(6,2),
  new_raw numeric(6,2),
  old_final numeric(6,2),
  new_final numeric(6,2),
  old_validation text,
  new_validation text,
  old_correction_status text,
  new_correction_status text,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists evaluation_score_history_score_idx
  on public.evaluation_score_history(score_id, created_at desc);

create or replace function public.evaluation_scores_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text := nullif(current_setting('fise.change_reason', true), '');
begin
  if tg_op = 'INSERT' then
    insert into public.evaluation_score_history
      (score_id, submission_id, evaluation_id, student_id, changed_by, change_type,
       new_provisional, new_raw, new_final, new_validation, new_correction_status, reason)
    values
      (new.id, new.submission_id, new.evaluation_id, new.student_id, auth.uid(), 'created',
       new.provisional_score, new.raw_score, new.final_score, new.validation_status,
       new.correction_status, v_reason);
  elsif new.provisional_score is distinct from old.provisional_score
     or new.raw_score is distinct from old.raw_score
     or new.final_score is distinct from old.final_score
     or new.validation_status is distinct from old.validation_status
     or new.correction_status is distinct from old.correction_status then
    insert into public.evaluation_score_history
      (score_id, submission_id, evaluation_id, student_id, changed_by, change_type,
       old_provisional, new_provisional, old_raw, new_raw, old_final, new_final,
       old_validation, new_validation, old_correction_status, new_correction_status, reason)
    values
      (new.id, new.submission_id, new.evaluation_id, new.student_id, auth.uid(),
       case
         when new.validation_status is distinct from old.validation_status then
           case when new.validation_status = 'validated' then 'validated' else 'reopened' end
         when new.correction_status is distinct from old.correction_status then 'correction_status'
         else 'adjusted'
       end,
       old.provisional_score, new.provisional_score, old.raw_score, new.raw_score,
       old.final_score, new.final_score, old.validation_status, new.validation_status,
       old.correction_status, new.correction_status, v_reason);
  end if;
  return new;
end;
$$;

drop trigger if exists evaluation_scores_audit_trg on public.evaluation_scores;
create trigger evaluation_scores_audit_trg
after insert or update on public.evaluation_scores
for each row execute function public.evaluation_scores_audit();

-- ---------------------------------------------------------------------------
-- 3. `grades` (source des bulletins) : origine de la note + historique complet
-- ---------------------------------------------------------------------------
alter table public.grades
  add column if not exists source text not null default 'manual',
  add column if not exists evaluation_count integer not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'grades_source_valid'
  ) then
    alter table public.grades
      add constraint grades_source_valid check (source in ('manual', 'evaluation'));
  end if;
end $$;

create or replace function public.grades_track_source()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Seule la synchronisation des épreuves validées peut poser source = 'evaluation'.
  if coalesce(current_setting('fise.eval_sync', true), '') = '1' then
    return new;
  end if;
  new.source := 'manual';
  new.evaluation_count := 0;
  return new;
end;
$$;

drop trigger if exists grades_track_source_trg on public.grades;
create trigger grades_track_source_trg
before insert or update on public.grades
for each row execute function public.grades_track_source();

create table if not exists public.grade_history (
  id uuid primary key default gen_random_uuid(),
  grade_id uuid,
  student_id uuid not null,
  class_id uuid,
  subject_id uuid,
  period_id uuid,
  change_type text not null check (change_type in ('insert', 'update', 'delete')),
  old_score numeric(5,2),
  new_score numeric(5,2),
  old_max_score numeric(5,2),
  new_max_score numeric(5,2),
  source text,
  changed_by uuid,
  created_at timestamptz not null default now()
);

create index if not exists grade_history_student_idx
  on public.grade_history(student_id, subject_id, period_id, created_at desc);

create or replace function public.grades_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.grade_history
      (grade_id, student_id, class_id, subject_id, period_id, change_type,
       new_score, new_max_score, source, changed_by)
    values (new.id, new.student_id, new.class_id, new.subject_id, new.period_id, 'insert',
            new.score, new.max_score, new.source, auth.uid());
    return new;
  elsif tg_op = 'UPDATE' then
    if new.score is distinct from old.score or new.max_score is distinct from old.max_score then
      insert into public.grade_history
        (grade_id, student_id, class_id, subject_id, period_id, change_type,
         old_score, new_score, old_max_score, new_max_score, source, changed_by)
      values (new.id, new.student_id, new.class_id, new.subject_id, new.period_id, 'update',
              old.score, new.score, old.max_score, new.max_score, new.source, auth.uid());
    end if;
    return new;
  else
    insert into public.grade_history
      (grade_id, student_id, class_id, subject_id, period_id, change_type,
       old_score, old_max_score, source, changed_by)
    values (old.id, old.student_id, old.class_id, old.subject_id, old.period_id, 'delete',
            old.score, old.max_score, old.source, auth.uid());
    return old;
  end if;
end;
$$;

drop trigger if exists grades_audit_trg on public.grades;
create trigger grades_audit_trg
after insert or update or delete on public.grades
for each row execute function public.grades_audit();

-- ---------------------------------------------------------------------------
-- 4. RLS des tables de correction et de notes
-- ---------------------------------------------------------------------------
alter table public.evaluation_corrections enable row level security;
alter table public.evaluation_question_results enable row level security;
alter table public.evaluation_scores enable row level security;
alter table public.evaluation_score_history enable row level security;
alter table public.grade_history enable row level security;

-- Résultat publié à l'élève : note validée ET date de visibilité atteinte.
create or replace function public.evaluation_result_released(p_submission uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.evaluation_scores es
    join public.evaluations e on e.id = es.evaluation_id
    where es.submission_id = p_submission
      and es.validation_status = 'validated'
      and (e.results_visible_at is null or e.results_visible_at <= now())
  );
$$;

revoke all on function public.evaluation_result_released(uuid) from public, anon;
grant execute on function public.evaluation_result_released(uuid) to authenticated;

drop policy if exists "eval corrections staff read" on public.evaluation_corrections;
create policy "eval corrections staff read" on public.evaluation_corrections
for select to authenticated
using (public.evaluation_can_review(evaluation_id, class_id));

drop policy if exists "eval question results read" on public.evaluation_question_results;
create policy "eval question results read" on public.evaluation_question_results
for select to authenticated
using (
  exists (
    select 1 from public.evaluation_submissions s
    where s.id = evaluation_question_results.submission_id
      and public.evaluation_can_review(s.evaluation_id, s.class_id)
  )
  or (student_id = auth.uid() and public.evaluation_result_released(submission_id))
);

drop policy if exists "eval scores read" on public.evaluation_scores;
create policy "eval scores read" on public.evaluation_scores
for select to authenticated
using (
  public.evaluation_can_review(evaluation_id, class_id)
  or (student_id = auth.uid() and public.evaluation_result_released(submission_id))
);

drop policy if exists "eval score history staff read" on public.evaluation_score_history;
create policy "eval score history staff read" on public.evaluation_score_history
for select to authenticated
using (
  exists (
    select 1 from public.evaluation_scores es
    where es.id = evaluation_score_history.score_id
      and public.evaluation_can_review(es.evaluation_id, es.class_id)
  )
);

drop policy if exists "grade history staff read" on public.grade_history;
create policy "grade history staff read" on public.grade_history
for select to authenticated
using (
  public.eval_is_admin()
  or (class_id is not null and public.teacher_can_manage_class(class_id, auth.uid()))
);

-- ---------------------------------------------------------------------------
-- 5. Remise définitive (idempotente)
-- ---------------------------------------------------------------------------
create or replace function public.submit_evaluation(p_evaluation uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  e public.evaluations%rowtype;
  v_sub public.evaluation_submissions%rowtype;
  v_now timestamptz := clock_timestamp();
  v_late boolean := false;
  v_late_min integer := 0;
  v_photos integer;
begin
  if v_uid is null then
    raise exception 'Session requise.';
  end if;
  select * into e from public.evaluations where id = p_evaluation;
  if not found or e.status <> 'published' then
    raise exception 'Épreuve indisponible.';
  end if;

  select * into v_sub
  from public.evaluation_submissions s
  where s.evaluation_id = p_evaluation and s.student_id = v_uid
  for update;
  if not found then
    raise exception 'Ajoutez au moins une photographie avant d''envoyer.';
  end if;

  -- Un renvoi (réseau instable, double appui) ne crée ni nouvelle remise ni nouvelle correction.
  if v_sub.status = 'submitted' then
    return jsonb_build_object(
      'status', 'submitted', 'already', true,
      'submitted_at', v_sub.submitted_at, 'is_late', v_sub.is_late,
      'late_minutes', v_sub.late_minutes);
  end if;

  select count(*) into v_photos from public.evaluation_photos where submission_id = v_sub.id;
  if v_photos = 0 then
    raise exception 'Ajoutez au moins une photographie avant d''envoyer.';
  end if;

  if v_now >= e.due_at then
    if v_now < e.due_at + make_interval(mins => e.late_grace_minutes)
       and v_sub.first_photo_at is not null and v_sub.first_photo_at < e.due_at then
      -- Envoi commencé avant l'échéance et terminé dans la tolérance : pas de retard.
      v_late := false;
    elsif e.late_policy = 'reject' then
      raise exception 'DEADLINE_PASSED';
    else
      v_late := true;
      v_late_min := ceil(extract(epoch from (v_now - e.due_at)) / 60.0)::integer;
    end if;
  end if;

  update public.evaluation_submissions
  set status = 'submitted', submitted_at = v_now, is_late = v_late, late_minutes = v_late_min,
      photo_count = v_photos, updated_at = v_now
  where id = v_sub.id;

  insert into public.evaluation_scores
    (submission_id, evaluation_id, student_id, class_id, subject_id, period_id,
     evaluation_date, max_score, correction_status)
  values
    (v_sub.id, e.id, v_uid, v_sub.class_id, v_sub.subject_id, e.period_id,
     (e.starts_at at time zone 'Africa/Douala')::date, e.max_score, 'pending')
  on conflict (submission_id) do nothing;

  insert into public.evaluation_corrections
    (submission_id, evaluation_id, student_id, class_id, subject_id)
  values (v_sub.id, e.id, v_uid, v_sub.class_id, v_sub.subject_id)
  on conflict (submission_id) do nothing;

  insert into public.notifications (user_id, title, body, type)
  values (v_uid, 'Remise reçue',
          left(e.title, 160) || ' — reçue le '
            || to_char(v_now at time zone 'Africa/Douala', 'DD/MM/YYYY "à" HH24:MI')
            || case when v_late then ' (en retard)' else '' end,
          'evaluation_receipt');

  return jsonb_build_object(
    'status', 'submitted', 'already', false,
    'submitted_at', v_now, 'is_late', v_late, 'late_minutes', v_late_min);
end;
$$;

revoke all on function public.submit_evaluation(uuid) from public, anon;
grant execute on function public.submit_evaluation(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Déclenchement serveur de la correction (continue même si l'app est fermée)
-- ---------------------------------------------------------------------------
do $$
begin
  create extension if not exists pg_net;
exception when others then
  raise notice 'pg_net indisponible : le déclenchement se fera via le balayage pg_cron et le webhook.';
end $$;

-- Appelle l'Edge Function `evaluation-correct-worker`. Les deux secrets sont lus dans Vault :
--   fise_eval_worker_url    = https://<ref>.supabase.co/functions/v1/evaluation-correct-worker
--   fise_eval_worker_secret = même valeur que le secret de fonction EVAL_WORKER_SECRET
-- Sans configuration, la fonction ne fait rien (la remise n'est jamais bloquée).
create or replace function public.dispatch_evaluation_worker()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url
  from vault.decrypted_secrets where name = 'fise_eval_worker_url' limit 1;
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'fise_eval_worker_secret' limit 1;
  if v_url is null or v_secret is null then
    return;
  end if;
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-worker-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  );
exception when others then
  null;
end;
$$;

revoke all on function public.dispatch_evaluation_worker() from public, anon, authenticated;
grant execute on function public.dispatch_evaluation_worker() to service_role;

create or replace function public.evaluation_corrections_dispatch_trg()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.dispatch_evaluation_worker();
  return new;
end;
$$;

drop trigger if exists evaluation_corrections_dispatch on public.evaluation_corrections;
create trigger evaluation_corrections_dispatch
after insert on public.evaluation_corrections
for each row execute function public.evaluation_corrections_dispatch_trg();

-- ---------------------------------------------------------------------------
-- 7. RPC réservées au worker (service_role uniquement)
-- ---------------------------------------------------------------------------
create or replace function public.claim_evaluation_corrections(p_limit integer default 2)
returns setof public.evaluation_corrections
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with picked as (
    select c.id
    from public.evaluation_corrections c
    where c.attempts < c.max_attempts
      and (
        (c.status = 'pending' and c.next_attempt_at <= now())
        or (c.status = 'processing' and c.locked_until is not null and c.locked_until < now())
      )
    order by c.next_attempt_at
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 2), 5))
  ),
  upd as (
    update public.evaluation_corrections c
    set status = 'processing',
        attempts = c.attempts + 1,
        locked_until = now() + interval '10 minutes',
        started_at = coalesce(c.started_at, now()),
        updated_at = now()
    from picked
    where c.id = picked.id
    returning c.*
  )
  select * from upd;

  update public.evaluation_scores es
  set correction_status = 'processing', updated_at = now()
  where es.submission_id in (
    select submission_id from public.evaluation_corrections where status = 'processing'
  ) and es.correction_status = 'pending';
end;
$$;

create or replace function public.save_evaluation_correction(
  p_correction uuid,
  p_results jsonb,
  p_model text default null,
  p_overall_confidence numeric default null,
  p_review_reasons text[] default '{}',
  p_extracted jsonb default null,
  p_min_confidence numeric default 0.75
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.evaluation_corrections%rowtype;
  e public.evaluations%rowtype;
  r jsonb;
  v_status text;
  v_total numeric := 0;
  v_max numeric := 0;
  v_unresolved integer := 0;
  v_count integer := 0;
  v_points numeric;
  v_maxp numeric;
  v_legible boolean;
  v_ambiguous boolean;
  v_conf numeric;
  v_review boolean;
  v_flags text[];
  v_reasons text[] := coalesce(p_review_reasons, '{}');
  v_provisional numeric;
begin
  select * into c from public.evaluation_corrections where id = p_correction for update;
  if not found then
    raise exception 'Correction introuvable.';
  end if;
  -- Idempotence : une correction terminée n'est jamais réécrite (pas de double attribution).
  if c.status in ('done', 'needs_review') then
    return jsonb_build_object('status', c.status, 'already', true);
  end if;
  select * into e from public.evaluations where id = c.evaluation_id;

  if p_results is null or jsonb_typeof(p_results) <> 'array' then
    raise exception 'Résultats invalides.';
  end if;

  for r in select * from jsonb_array_elements(p_results) loop
    v_maxp := greatest(0, coalesce((r->>'max_points')::numeric, 0));
    v_legible := coalesce((r->>'legible')::boolean, false);
    v_ambiguous := coalesce((r->>'ambiguous')::boolean, false);
    v_conf := nullif(r->>'confidence', '')::numeric;
    v_conf := case when v_conf is null then null else greatest(0, least(1, v_conf)) end;
    v_points := nullif(r->>'ai_points', '')::numeric;
    -- L'IA ne note jamais une réponse illisible.
    if not v_legible then
      v_points := null;
    elsif v_points is not null then
      v_points := greatest(0, least(v_maxp, v_points));
    end if;
    v_flags := coalesce(
      (select array_agg(x) from jsonb_array_elements_text(coalesce(r->'flags', '[]'::jsonb)) x),
      '{}');
    v_review := not v_legible or v_ambiguous or v_points is null
                or v_conf is null or v_conf < p_min_confidence
                or coalesce((r->>'needs_review')::boolean, false);

    insert into public.evaluation_question_results
      (correction_id, submission_id, evaluation_id, student_id, question_key, question_label,
       student_answer, legible, ambiguous, confidence, ai_points, max_points, flags,
       needs_review, feedback_fr)
    values
      (c.id, c.submission_id, c.evaluation_id, c.student_id,
       coalesce(nullif(r->>'question_key', ''), (v_count + 1)::text),
       nullif(r->>'question_label', ''),
       nullif(left(coalesce(r->>'student_answer', ''), 4000), ''),
       v_legible, v_ambiguous, v_conf, v_points, v_maxp, v_flags, v_review,
       nullif(left(coalesce(r->>'feedback_fr', ''), 1000), ''))
    on conflict (correction_id, question_key) do update
      set student_answer = excluded.student_answer,
          legible = excluded.legible,
          ambiguous = excluded.ambiguous,
          confidence = excluded.confidence,
          ai_points = excluded.ai_points,
          max_points = excluded.max_points,
          flags = excluded.flags,
          needs_review = excluded.needs_review,
          feedback_fr = excluded.feedback_fr,
          updated_at = now()
      where public.evaluation_question_results.final_points is null;

    v_count := v_count + 1;
    v_max := v_max + v_maxp;
    if v_points is not null then
      v_total := v_total + v_points;
    end if;
    if v_review then
      v_unresolved := v_unresolved + 1;
    end if;
  end loop;

  if v_count = 0 then
    v_reasons := array_append(v_reasons, 'Aucune question identifiée');
    v_unresolved := 1;
  end if;
  if v_unresolved > 0 then
    v_reasons := array_append(v_reasons, v_unresolved || ' question(s) à vérifier');
  end if;

  v_status := case when v_unresolved > 0 or coalesce(array_length(p_review_reasons, 1), 0) > 0
                   then 'needs_review' else 'done' end;

  update public.evaluation_corrections
  set status = v_status,
      ai_model = p_model,
      overall_confidence = p_overall_confidence,
      review_reasons = (select coalesce(array_agg(distinct x), '{}') from unnest(v_reasons) x),
      extracted = p_extracted,
      last_error = null,
      locked_until = null,
      finished_at = now(),
      updated_at = now()
  where id = c.id;

  v_provisional := case when v_max > 0 then round(v_total / v_max * e.max_score, 2) else null end;

  update public.evaluation_scores
  set provisional_score = v_provisional,
      raw_score = coalesce(raw_score, v_provisional),
      correction_status = v_status,
      updated_at = now()
  where submission_id = c.submission_id and validation_status = 'provisional';

  if v_status = 'needs_review' then
    insert into public.notifications (user_id, title, body, type)
    values (e.teacher_id, 'Correction à vérifier',
            left(e.title, 160) || ' — une remise nécessite votre vérification.',
            'evaluation_review');
  elsif not exists (
    select 1 from public.evaluation_corrections x
    where x.evaluation_id = c.evaluation_id and x.status in ('pending', 'processing')
  ) then
    insert into public.notifications (user_id, title, body, type)
    values (e.teacher_id, 'Corrections terminées',
            left(e.title, 160) || ' — les corrections proposées par l''IA sont prêtes à valider.',
            'evaluation_review');
  end if;

  return jsonb_build_object('status', v_status, 'already', false, 'provisional_score', v_provisional);
end;
$$;

create or replace function public.fail_evaluation_correction(p_correction uuid, p_error text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.evaluation_corrections%rowtype;
  e public.evaluations%rowtype;
begin
  select * into c from public.evaluation_corrections where id = p_correction for update;
  if not found or c.status <> 'processing' then
    return jsonb_build_object('status', coalesce(c.status, 'missing'), 'changed', false);
  end if;
  if c.attempts >= c.max_attempts then
    update public.evaluation_corrections
    set status = 'error', last_error = left(coalesce(p_error, 'Erreur inconnue'), 500),
        locked_until = null, finished_at = now(), updated_at = now()
    where id = c.id;
    update public.evaluation_scores
    set correction_status = 'error', updated_at = now()
    where submission_id = c.submission_id and validation_status = 'provisional';
    select * into e from public.evaluations where id = c.evaluation_id;
    insert into public.notifications (user_id, title, body, type)
    values (e.teacher_id, 'Correction impossible',
            left(e.title, 160) || ' — une remise doit être corrigée manuellement ou relancée.',
            'evaluation_review');
    return jsonb_build_object('status', 'error', 'changed', true);
  end if;
  update public.evaluation_corrections
  set status = 'pending',
      last_error = left(coalesce(p_error, 'Erreur inconnue'), 500),
      next_attempt_at = now() + (c.attempts * interval '2 minutes'),
      locked_until = null, updated_at = now()
  where id = c.id;
  update public.evaluation_scores
  set correction_status = 'pending', updated_at = now()
  where submission_id = c.submission_id and validation_status = 'provisional';
  return jsonb_build_object('status', 'pending', 'changed', true);
end;
$$;

revoke all on function public.claim_evaluation_corrections(integer) from public, anon, authenticated;
revoke all on function public.save_evaluation_correction(uuid, jsonb, text, numeric, text[], jsonb, numeric)
  from public, anon, authenticated;
revoke all on function public.fail_evaluation_correction(uuid, text) from public, anon, authenticated;
grant execute on function public.claim_evaluation_corrections(integer) to service_role;
grant execute on function public.save_evaluation_correction(uuid, jsonb, text, numeric, text[], jsonb, numeric)
  to service_role;
grant execute on function public.fail_evaluation_correction(uuid, text) to service_role;

-- Balayage : relance du worker, abandon des tâches bloquées au-delà du nombre d'essais.
create or replace function public.dispatch_pending_evaluation_corrections()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pending integer;
begin
  with stuck as (
    update public.evaluation_corrections
    set status = 'error', last_error = coalesce(last_error, 'Délai de traitement dépassé'),
        locked_until = null, finished_at = now(), updated_at = now()
    where status = 'processing' and locked_until < now() and attempts >= max_attempts
    returning submission_id
  )
  update public.evaluation_scores es
  set correction_status = 'error', updated_at = now()
  from stuck
  where es.submission_id = stuck.submission_id and es.validation_status = 'provisional';

  select count(*) into v_pending
  from public.evaluation_corrections c
  where c.attempts < c.max_attempts
    and ((c.status = 'pending' and c.next_attempt_at <= now())
      or (c.status = 'processing' and c.locked_until < now()));
  if v_pending > 0 then
    perform public.dispatch_evaluation_worker();
  end if;
  return v_pending;
end;
$$;

revoke all on function public.dispatch_pending_evaluation_corrections() from public, anon, authenticated;
grant execute on function public.dispatch_pending_evaluation_corrections() to service_role;

-- Relance manuelle d'une correction en erreur (enseignant propriétaire / administrateur).
create or replace function public.retry_evaluation_correction(p_submission uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.evaluation_corrections%rowtype;
begin
  select * into c from public.evaluation_corrections where submission_id = p_submission for update;
  if not found then
    raise exception 'Correction introuvable.';
  end if;
  if not public.evaluation_can_review(c.evaluation_id, c.class_id) then
    raise exception 'Accès refusé.';
  end if;
  if c.status <> 'error' then
    raise exception 'Seule une correction en erreur peut être relancée.';
  end if;
  update public.evaluation_corrections
  set status = 'pending', attempts = 0, next_attempt_at = now(), last_error = null,
      finished_at = null, updated_at = now()
  where id = c.id;
  update public.evaluation_scores
  set correction_status = 'pending', updated_at = now()
  where submission_id = p_submission and validation_status = 'provisional';
  perform public.dispatch_evaluation_worker();
end;
$$;

revoke all on function public.retry_evaluation_correction(uuid) from public, anon;
grant execute on function public.retry_evaluation_correction(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Alimentation de `grades` à partir des notes validées
-- ---------------------------------------------------------------------------
create or replace function public.sync_evaluation_period_grade(
  p_student uuid,
  p_subject uuid,
  p_period uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_avg numeric;
  v_n integer;
  v_class uuid;
  v_existing public.grades%rowtype;
begin
  if p_period is null then
    return 'no_period';
  end if;

  select sum(es.final_score / es.max_score * 20 * ev.weight) / nullif(sum(ev.weight), 0),
         count(*)
    into v_avg, v_n
  from public.evaluation_scores es
  join public.evaluations ev on ev.id = es.evaluation_id
  where es.student_id = p_student and es.subject_id = p_subject and es.period_id = p_period
    and es.validation_status = 'validated' and es.final_score is not null;

  select es.class_id into v_class
  from public.evaluation_scores es
  where es.student_id = p_student and es.subject_id = p_subject and es.period_id = p_period
  order by es.updated_at desc limit 1;

  select * into v_existing
  from public.grades g
  where g.student_id = p_student and g.subject_id = p_subject and g.period_id = p_period;

  -- Une note saisie à la main par l'enseignant n'est jamais écrasée automatiquement.
  if found and v_existing.source = 'manual' then
    return 'skipped_manual';
  end if;

  perform set_config('fise.eval_sync', '1', true);

  if coalesce(v_n, 0) = 0 or v_avg is null then
    delete from public.grades g
    where g.student_id = p_student and g.subject_id = p_subject and g.period_id = p_period
      and g.source = 'evaluation';
    perform set_config('fise.eval_sync', '', true);
    return 'cleared';
  end if;

  begin
    insert into public.grades
      (class_id, subject_id, student_id, period_id, score, max_score, source,
       evaluation_count, entered_by)
    values
      (v_class, p_subject, p_student, p_period, round(v_avg, 2), 20, 'evaluation', v_n, auth.uid())
    on conflict (student_id, subject_id, period_id) do update
      set score = excluded.score,
          max_score = 20,
          class_id = excluded.class_id,
          evaluation_count = excluded.evaluation_count,
          entered_by = excluded.entered_by,
          updated_at = now()
      where public.grades.source = 'evaluation';
  exception when others then
    perform set_config('fise.eval_sync', '', true);
    return 'error';
  end;

  perform set_config('fise.eval_sync', '', true);
  return 'synced';
end;
$$;

revoke all on function public.sync_evaluation_period_grade(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.sync_evaluation_period_grade(uuid, uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 9. Notification de résultat à l'élève (sans afficher la note dans le texte)
-- ---------------------------------------------------------------------------
create or replace function public.notify_evaluation_result(p_score uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  es public.evaluation_scores%rowtype;
  e public.evaluations%rowtype;
begin
  select * into es from public.evaluation_scores where id = p_score for update;
  if not found or es.validation_status <> 'validated' or es.student_notified_at is not null then
    return false;
  end if;
  select * into e from public.evaluations where id = es.evaluation_id;
  if e.results_visible_at is not null and e.results_visible_at > now() then
    return false;
  end if;
  insert into public.notifications (user_id, title, body, type)
  values (es.student_id, 'Correction terminée',
          left(e.title, 160) || ' — votre résultat est disponible.', 'evaluation_result');
  update public.evaluation_scores set student_notified_at = now() where id = es.id;
  return true;
end;
$$;

revoke all on function public.notify_evaluation_result(uuid) from public, anon, authenticated;
grant execute on function public.notify_evaluation_result(uuid) to service_role;

create or replace function public.notify_released_evaluation_results()
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
    select es.id
    from public.evaluation_scores es
    join public.evaluations e on e.id = es.evaluation_id
    where es.validation_status = 'validated' and es.student_notified_at is null
      and (e.results_visible_at is null or e.results_visible_at <= now())
    limit 500
  loop
    if public.notify_evaluation_result(v_id) then
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$$;

revoke all on function public.notify_released_evaluation_results() from public, anon, authenticated;
grant execute on function public.notify_released_evaluation_results() to service_role;

-- ---------------------------------------------------------------------------
-- 10. Vérification / validation par l'enseignant
-- ---------------------------------------------------------------------------
create or replace function public.review_evaluation_submission(
  p_submission uuid,
  p_questions jsonb default '[]'::jsonb,
  p_comment text default null,
  p_validate boolean default false,
  p_manual_score numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.evaluation_submissions%rowtype;
  e public.evaluations%rowtype;
  es public.evaluation_scores%rowtype;
  q jsonb;
  v_pts numeric;
  v_max_q numeric;
  v_total numeric;
  v_sum_max numeric;
  v_open integer;
  v_raw numeric;
  v_pen numeric := 0;
  v_final numeric;
  v_sync text;
begin
  select * into s from public.evaluation_submissions where id = p_submission;
  if not found or s.status <> 'submitted' then
    raise exception 'Remise introuvable.';
  end if;
  if not public.evaluation_can_review(s.evaluation_id, s.class_id) then
    raise exception 'Accès refusé.';
  end if;
  select * into e from public.evaluations where id = s.evaluation_id;
  select * into es from public.evaluation_scores where submission_id = p_submission for update;
  if not found then
    raise exception 'Note introuvable.';
  end if;
  if es.validation_status = 'validated' then
    raise exception 'Note déjà validée : rouvrez-la pour la modifier.';
  end if;

  perform set_config('fise.change_reason', coalesce(left(p_comment, 300), ''), true);

  if p_questions is not null and jsonb_typeof(p_questions) = 'array' then
    for q in select * from jsonb_array_elements(p_questions) loop
      select r.max_points into v_max_q
      from public.evaluation_question_results r
      where r.submission_id = p_submission and r.question_key = q->>'question_key';
      if not found then
        raise exception 'Question inconnue : %', coalesce(q->>'question_key', '?');
      end if;
      v_pts := nullif(q->>'final_points', '')::numeric;
      if v_pts is not null and (v_pts < 0 or v_pts > v_max_q) then
        raise exception 'Points hors barème pour la question %.', q->>'question_key';
      end if;
      update public.evaluation_question_results r
      set final_points = v_pts,
          teacher_comment = coalesce(nullif(left(q->>'teacher_comment', 1000), ''), r.teacher_comment),
          reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
      where r.submission_id = p_submission and r.question_key = q->>'question_key';
    end loop;
  end if;

  if p_manual_score is not null then
    if p_manual_score < 0 or p_manual_score > e.max_score then
      raise exception 'La note doit être comprise entre 0 et %.', e.max_score;
    end if;
    v_raw := round(p_manual_score, 2);
    v_open := 0;
  else
    select sum(coalesce(r.final_points, case when r.needs_review then null else r.ai_points end)),
           sum(r.max_points),
           count(*) filter (
             where coalesce(r.final_points, case when r.needs_review then null else r.ai_points end) is null)
      into v_total, v_sum_max, v_open
    from public.evaluation_question_results r
    where r.submission_id = p_submission;
    if v_sum_max is null or v_sum_max <= 0 then
      v_open := coalesce(v_open, 1) + 1;
      v_raw := null;
    else
      v_raw := round(coalesce(v_total, 0) / v_sum_max * e.max_score, 2);
    end if;
  end if;

  if s.is_late and e.late_policy = 'accept_penalty' then
    v_pen := e.late_penalty_percent;
  end if;
  v_final := case when v_raw is null then null else round(v_raw * (1 - v_pen / 100.0), 2) end;

  if p_validate then
    if v_open > 0 or v_final is null then
      raise exception 'Validation impossible : % question(s) restent à vérifier.', coalesce(v_open, 1);
    end if;
    update public.evaluation_scores
    set raw_score = v_raw, penalty_percent = v_pen, final_score = v_final,
        validation_status = 'validated', validated_by = auth.uid(), validated_at = now(),
        teacher_comment = coalesce(nullif(left(p_comment, 1000), ''), teacher_comment),
        updated_at = now()
    where id = es.id;
    v_sync := public.sync_evaluation_period_grade(es.student_id, es.subject_id, es.period_id);
    update public.evaluation_scores set grade_sync_status = v_sync where id = es.id;
    perform public.notify_evaluation_result(es.id);
  else
    update public.evaluation_scores
    set raw_score = v_raw, penalty_percent = v_pen,
        teacher_comment = coalesce(nullif(left(p_comment, 1000), ''), teacher_comment),
        updated_at = now()
    where id = es.id;
  end if;

  return jsonb_build_object(
    'validated', p_validate, 'raw_score', v_raw, 'penalty_percent', v_pen,
    'final_score', v_final, 'open_questions', coalesce(v_open, 0), 'grade_sync', v_sync);
end;
$$;

create or replace function public.reopen_evaluation_score(p_submission uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.evaluation_submissions%rowtype;
  es public.evaluation_scores%rowtype;
  v_sync text;
begin
  if p_reason is null or char_length(btrim(p_reason)) < 3 then
    raise exception 'Indiquez le motif de la réouverture.';
  end if;
  select * into s from public.evaluation_submissions where id = p_submission;
  if not found then
    raise exception 'Remise introuvable.';
  end if;
  if not public.evaluation_can_review(s.evaluation_id, s.class_id) then
    raise exception 'Accès refusé.';
  end if;
  select * into es from public.evaluation_scores where submission_id = p_submission for update;
  if not found or es.validation_status <> 'validated' then
    raise exception 'Cette note n''est pas validée.';
  end if;
  perform set_config('fise.change_reason', left(btrim(p_reason), 300), true);
  update public.evaluation_scores
  set validation_status = 'provisional', final_score = null,
      validated_by = null, validated_at = null, student_notified_at = null, updated_at = now()
  where id = es.id;
  v_sync := public.sync_evaluation_period_grade(es.student_id, es.subject_id, es.period_id);
  update public.evaluation_scores set grade_sync_status = v_sync where id = es.id;
end;
$$;

-- Validation en lot des corrections « terminées » (hors celles à vérifier).
create or replace function public.validate_ready_evaluation_scores(p_evaluation uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
  v_ok integer := 0;
  v_fail integer := 0;
begin
  if not public.evaluation_is_owner(p_evaluation) then
    raise exception 'Accès refusé.';
  end if;
  for v_row in
    select es.submission_id
    from public.evaluation_scores es
    where es.evaluation_id = p_evaluation
      and es.validation_status = 'provisional'
      and es.correction_status = 'done'
  loop
    begin
      perform public.review_evaluation_submission(v_row.submission_id, '[]'::jsonb, null, true, null);
      v_ok := v_ok + 1;
    exception when others then
      v_fail := v_fail + 1;
    end;
  end loop;
  return jsonb_build_object('validated', v_ok, 'failed', v_fail);
end;
$$;

revoke all on function public.review_evaluation_submission(uuid, jsonb, text, boolean, numeric) from public, anon;
revoke all on function public.reopen_evaluation_score(uuid, text) from public, anon;
revoke all on function public.validate_ready_evaluation_scores(uuid) from public, anon;
grant execute on function public.review_evaluation_submission(uuid, jsonb, text, boolean, numeric) to authenticated;
grant execute on function public.reopen_evaluation_score(uuid, text) to authenticated;
grant execute on function public.validate_ready_evaluation_scores(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Rappels avant la date limite (idempotents)
-- ---------------------------------------------------------------------------
create table if not exists public.evaluation_reminders_sent (
  evaluation_id uuid not null references public.evaluations(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('h24', 'h1')),
  sent_at timestamptz not null default now(),
  primary key (evaluation_id, student_id, kind)
);

alter table public.evaluation_reminders_sent enable row level security;

create or replace function public.send_evaluation_deadline_reminders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer;
begin
  with targets as (
    select e.id as evaluation_id, cs.student_id, k.kind
    from public.evaluations e
    cross join (values ('h24', interval '24 hours'), ('h1', interval '1 hour')) as k(kind, win)
    join public.evaluation_classes ec on ec.evaluation_id = e.id
    join public.class_students cs on cs.class_id = ec.class_id and cs.is_active
    where e.status = 'published'
      and e.starts_at <= now()
      and e.due_at > now()
      and e.due_at <= now() + k.win
      and (e.due_at - e.starts_at) > k.win
      and not exists (
        select 1 from public.evaluation_submissions s
        where s.evaluation_id = e.id and s.student_id = cs.student_id and s.status = 'submitted'
      )
  ),
  ins as (
    insert into public.evaluation_reminders_sent (evaluation_id, student_id, kind)
    select distinct evaluation_id, student_id, kind from targets
    on conflict do nothing
    returning evaluation_id, student_id, kind
  ),
  notif as (
    insert into public.notifications (user_id, title, body, type)
    select ins.student_id,
           case when ins.kind = 'h1' then 'Dernière heure pour remettre' else 'Rappel : épreuve à remettre' end,
           left(e.title, 160) || ' — à remettre avant le '
             || to_char(e.due_at at time zone 'Africa/Douala', 'DD/MM/YYYY "à" HH24:MI'),
           'evaluation_reminder'
    from ins
    join public.evaluations e on e.id = ins.evaluation_id
    returning 1
  )
  select count(*) into v_n from notif;
  return coalesce(v_n, 0);
end;
$$;

revoke all on function public.send_evaluation_deadline_reminders() from public, anon, authenticated;
grant execute on function public.send_evaluation_deadline_reminders() to service_role;

-- ---------------------------------------------------------------------------
-- 12. RPC de lecture (élève / enseignant) : pas de fuite entre élèves
-- ---------------------------------------------------------------------------
create or replace function public.list_my_evaluations()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_rows jsonb;
begin
  if v_uid is null then
    raise exception 'Session requise.';
  end if;
  select coalesce(jsonb_agg(x.item order by x.due_at desc), '[]'::jsonb) into v_rows
  from (
    select e.due_at,
      jsonb_build_object(
        'id', e.id,
        'title', e.title,
        'instructions', e.instructions,
        'subject_name_fr', sj.name_fr,
        'subject_name_en', sj.name_en,
        'starts_at', e.starts_at,
        'due_at', e.due_at,
        'duration_minutes', e.duration_minutes,
        'late_policy', e.late_policy,
        'late_grace_minutes', e.late_grace_minutes,
        'late_penalty_percent', e.late_penalty_percent,
        'max_score', e.max_score,
        'status', e.status,
        'pdf_name', e.pdf_name,
        'pdf_path', case when now() >= e.starts_at then e.pdf_path else null end,
        'submission', (
          select jsonb_build_object(
            'id', s.id, 'status', s.status, 'submitted_at', s.submitted_at,
            'is_late', s.is_late, 'late_minutes', s.late_minutes, 'photo_count', s.photo_count)
          from public.evaluation_submissions s
          where s.evaluation_id = e.id and s.student_id = v_uid),
        'result', (
          select jsonb_build_object(
            'final_score', es.final_score, 'max_score', es.max_score,
            'penalty_percent', es.penalty_percent, 'comment', es.teacher_comment,
            'questions', coalesce((
              select jsonb_agg(jsonb_build_object(
                'label', coalesce(r.question_label, 'Question ' || r.question_key),
                'points', coalesce(r.final_points, r.ai_points),
                'max_points', r.max_points,
                'feedback', coalesce(r.teacher_comment, r.feedback_fr)
              ) order by r.question_key)
              from public.evaluation_question_results r
              where r.submission_id = es.submission_id), '[]'::jsonb))
          from public.evaluation_scores es
          where es.student_id = v_uid and es.evaluation_id = e.id
            and public.evaluation_result_released(es.submission_id))
      ) as item
    from public.evaluations e
    join public.subjects sj on sj.id = e.subject_id
    where e.status in ('published', 'closed')
      and exists (
        select 1 from public.evaluation_classes ec
        where ec.evaluation_id = e.id and public.is_student_in_class(ec.class_id, v_uid))
  ) x;
  return jsonb_build_object('server_now', now(), 'evaluations', v_rows);
end;
$$;

create or replace function public.list_teacher_evaluations()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'Session requise.';
  end if;
  select coalesce(jsonb_agg(x.item order by x.created_at desc), '[]'::jsonb) into v_rows
  from (
    select e.created_at,
      jsonb_build_object(
        'id', e.id, 'title', e.title, 'status', e.status,
        'subject_name_fr', sj.name_fr, 'subject_name_en', sj.name_en,
        'starts_at', e.starts_at, 'due_at', e.due_at, 'max_score', e.max_score,
        'period_id', e.period_id,
        'classes', coalesce((
          select jsonb_agg(c.display_name order by c.display_name)
          from public.evaluation_classes ec
          join public.school_classes c on c.id = ec.class_id
          where ec.evaluation_id = e.id), '[]'::jsonb),
        'submitted_count', (select count(*) from public.evaluation_submissions s
                            where s.evaluation_id = e.id and s.status = 'submitted'),
        'to_review_count', (select count(*) from public.evaluation_scores es
                            where es.evaluation_id = e.id and es.validation_status = 'provisional'),
        'validated_count', (select count(*) from public.evaluation_scores es
                            where es.evaluation_id = e.id and es.validation_status = 'validated'),
        'error_count', (select count(*) from public.evaluation_scores es
                        where es.evaluation_id = e.id and es.correction_status = 'error')
      ) as item
    from public.evaluations e
    join public.subjects sj on sj.id = e.subject_id
    where e.teacher_id = auth.uid() or public.eval_is_admin()
  ) x;
  return v_rows;
end;
$$;

create or replace function public.list_evaluation_review(p_evaluation uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
begin
  if not public.evaluation_is_owner(p_evaluation) then
    raise exception 'Accès refusé.';
  end if;
  select coalesce(jsonb_agg(x.item order by x.last_name, x.first_name), '[]'::jsonb) into v_rows
  from (
    select p.last_name, p.first_name,
      jsonb_build_object(
        'student_id', p.id,
        'first_name', p.first_name, 'last_name', p.last_name,
        'class_id', c.id, 'class_name', c.display_name,
        'submission_id', s.id,
        'submission_status', coalesce(s.status, 'not_submitted'),
        'submitted_at', s.submitted_at, 'is_late', coalesce(s.is_late, false),
        'late_minutes', coalesce(s.late_minutes, 0), 'photo_count', coalesce(s.photo_count, 0),
        'correction_status', es.correction_status,
        'validation_status', es.validation_status,
        'provisional_score', es.provisional_score,
        'raw_score', es.raw_score,
        'final_score', es.final_score,
        'max_score', e.max_score,
        'review_reasons', cr.review_reasons,
        'last_error', cr.last_error
      ) as item
    from public.evaluations e
    join public.evaluation_classes ec on ec.evaluation_id = e.id
    join public.school_classes c on c.id = ec.class_id
    join public.class_students cs on cs.class_id = c.id and cs.is_active
    join public.profiles p on p.id = cs.student_id
    left join public.evaluation_submissions s
      on s.evaluation_id = e.id and s.student_id = p.id and s.status = 'submitted'
    left join public.evaluation_scores es on es.submission_id = s.id
    left join public.evaluation_corrections cr on cr.submission_id = s.id
    where e.id = p_evaluation
      and public.evaluation_can_review(e.id, c.id)
  ) x;
  return v_rows;
end;
$$;

create or replace function public.get_evaluation_submission_detail(p_submission uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  s public.evaluation_submissions%rowtype;
begin
  select * into s from public.evaluation_submissions where id = p_submission;
  if not found or not public.evaluation_can_review(s.evaluation_id, s.class_id) then
    raise exception 'Accès refusé.';
  end if;
  return jsonb_build_object(
    'submission', jsonb_build_object(
      'id', s.id, 'student_id', s.student_id, 'submitted_at', s.submitted_at,
      'is_late', s.is_late, 'late_minutes', s.late_minutes),
    'student', (select jsonb_build_object('first_name', p.first_name, 'last_name', p.last_name)
                from public.profiles p where p.id = s.student_id),
    'evaluation', (select jsonb_build_object(
                     'id', e.id, 'title', e.title, 'max_score', e.max_score,
                     'late_policy', e.late_policy, 'late_penalty_percent', e.late_penalty_percent)
                   from public.evaluations e where e.id = s.evaluation_id),
    'photos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ph.id, 'storage_path', ph.storage_path, 'position', ph.position,
        'received_at', ph.received_at) order by ph.position, ph.received_at)
      from public.evaluation_photos ph where ph.submission_id = s.id), '[]'::jsonb),
    'questions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'question_key', r.question_key, 'question_label', r.question_label,
        'student_answer', r.student_answer, 'legible', r.legible, 'ambiguous', r.ambiguous,
        'confidence', r.confidence, 'ai_points', r.ai_points, 'max_points', r.max_points,
        'final_points', r.final_points, 'flags', r.flags, 'needs_review', r.needs_review,
        'feedback_fr', r.feedback_fr, 'teacher_comment', r.teacher_comment
      ) order by r.question_key)
      from public.evaluation_question_results r where r.submission_id = s.id), '[]'::jsonb),
    'score', (select jsonb_build_object(
                'provisional_score', es.provisional_score, 'raw_score', es.raw_score,
                'penalty_percent', es.penalty_percent, 'final_score', es.final_score,
                'max_score', es.max_score, 'correction_status', es.correction_status,
                'validation_status', es.validation_status, 'validated_at', es.validated_at,
                'teacher_comment', es.teacher_comment, 'grade_sync_status', es.grade_sync_status)
              from public.evaluation_scores es where es.submission_id = s.id),
    'correction', (select jsonb_build_object(
                     'status', cr.status, 'attempts', cr.attempts, 'last_error', cr.last_error,
                     'review_reasons', cr.review_reasons, 'ai_model', cr.ai_model,
                     'overall_confidence', cr.overall_confidence,
                     'image_quality', cr.extracted->'image_quality')
                   from public.evaluation_corrections cr where cr.submission_id = s.id),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'change_type', h.change_type, 'created_at', h.created_at, 'changed_by', h.changed_by,
        'old_final', h.old_final, 'new_final', h.new_final,
        'old_provisional', h.old_provisional, 'new_provisional', h.new_provisional,
        'new_validation', h.new_validation, 'reason', h.reason
      ) order by h.created_at desc)
      from (select * from public.evaluation_score_history hh
            where hh.submission_id = s.id order by hh.created_at desc limit 20) h), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.list_my_evaluations() from public, anon;
revoke all on function public.list_teacher_evaluations() from public, anon;
revoke all on function public.list_evaluation_review(uuid) from public, anon;
revoke all on function public.get_evaluation_submission_detail(uuid) from public, anon;
grant execute on function public.list_my_evaluations() to authenticated;
grant execute on function public.list_teacher_evaluations() to authenticated;
grant execute on function public.list_evaluation_review(uuid) to authenticated;
grant execute on function public.get_evaluation_submission_detail(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 13. Planification (pg_cron déjà utilisé par publish-fise-evaluation-results)
-- ---------------------------------------------------------------------------
do $$
begin
  create extension if not exists pg_cron with schema pg_catalog;
  perform cron.unschedule(jobid) from cron.job
  where jobname in ('fise-eval-dispatch', 'fise-eval-reminders', 'fise-eval-notify-results');
  perform cron.schedule('fise-eval-dispatch', '* * * * *',
    'select public.dispatch_pending_evaluation_corrections();');
  perform cron.schedule('fise-eval-reminders', '*/10 * * * *',
    'select public.send_evaluation_deadline_reminders();');
  perform cron.schedule('fise-eval-notify-results', '*/5 * * * *',
    'select public.notify_released_evaluation_results();');
exception when others then
  raise notice 'pg_cron non configuré : planifiez manuellement les 3 tâches fise-eval-*. (%)', sqlerrm;
end $$;
