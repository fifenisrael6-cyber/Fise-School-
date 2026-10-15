-- Fise School : évaluations automatisées (1/3)
-- Épreuves PDF publiées par l'enseignant, remises par photographies, stockage privé, RLS.
--
-- Additive uniquement : cette migration ne modifie ni `assignments` (QCM / devoirs),
-- ni les forums, messages, paiements, cours. Elle réutilise :
--   school_classes, class_students, class_subjects, subjects, profiles, grade_periods,
--   notifications (le webhook send-push existant envoie déjà les push),
--   is_admin(), is_catalog_admin(), is_student_in_class(), teacher_can_manage_class().

-- ---------------------------------------------------------------------------
-- 0. Aides d'autorisation
-- ---------------------------------------------------------------------------
create or replace function public.eval_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or public.is_catalog_admin();
$$;

revoke all on function public.eval_is_admin() from public, anon;
grant execute on function public.eval_is_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Épreuves
-- ---------------------------------------------------------------------------
create table if not exists public.evaluations (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  period_id uuid references public.grade_periods(id) on delete set null,
  title text not null check (char_length(btrim(title)) between 3 and 200),
  instructions text,
  pdf_path text,
  pdf_name text,
  starts_at timestamptz not null,
  due_at timestamptz not null,
  duration_minutes integer check (duration_minutes is null or duration_minutes between 1 and 1440),
  -- Règles de remise tardive propres à l'épreuve.
  --   reject         : aucune remise après la date limite (+ tolérance d'envoi)
  --   accept_flagged : remise acceptée mais signalée « en retard »
  --   accept_penalty : remise acceptée, pénalité appliquée à la validation
  late_policy text not null default 'reject'
    check (late_policy in ('reject', 'accept_flagged', 'accept_penalty')),
  late_grace_minutes integer not null default 5 check (late_grace_minutes between 0 and 120),
  late_penalty_percent numeric(5,2) not null default 0
    check (late_penalty_percent >= 0 and late_penalty_percent <= 100),
  max_score numeric(6,2) not null default 20 check (max_score > 0),
  -- Poids de l'épreuve dans la moyenne de la matière pour la période.
  weight numeric(5,2) not null default 1 check (weight > 0),
  -- Les élèves ne voient leur résultat validé qu'à partir de cette date (null = dès la validation).
  results_visible_at timestamptz,
  status text not null default 'draft' check (status in ('draft', 'published', 'closed')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint evaluations_window_valid check (due_at > starts_at)
);

create index if not exists evaluations_teacher_idx on public.evaluations(teacher_id, status);
create index if not exists evaluations_period_idx on public.evaluations(period_id, subject_id);
create index if not exists evaluations_due_idx on public.evaluations(status, due_at);

-- Barème et critères de correction : jamais visibles des élèves (table séparée).
create table if not exists public.evaluation_keys (
  evaluation_id uuid primary key references public.evaluations(id) on delete cascade,
  -- [{ "key": "1", "label": "Exercice 1", "points": 4 }, ...]
  scheme jsonb not null default '[]'::jsonb,
  criteria text,
  updated_at timestamptz not null default now(),
  constraint evaluation_keys_scheme_is_array check (jsonb_typeof(scheme) = 'array')
);

-- Classes (ou filières ayant le même programme) destinataires de l'épreuve.
create table if not exists public.evaluation_classes (
  evaluation_id uuid not null references public.evaluations(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (evaluation_id, class_id)
);

create index if not exists evaluation_classes_class_idx on public.evaluation_classes(class_id);

-- ---------------------------------------------------------------------------
-- 2. Remises et photographies
-- ---------------------------------------------------------------------------
create table if not exists public.evaluation_submissions (
  id uuid primary key default gen_random_uuid(),
  evaluation_id uuid not null references public.evaluations(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  status text not null default 'draft' check (status in ('draft', 'submitted')),
  first_photo_at timestamptz,
  -- Date et heure de réception, fixées par le serveur (jamais par l'application).
  submitted_at timestamptz,
  is_late boolean not null default false,
  late_minutes integer not null default 0,
  photo_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint evaluation_submissions_one_per_student unique (evaluation_id, student_id)
);

create index if not exists evaluation_submissions_student_idx on public.evaluation_submissions(student_id);
create index if not exists evaluation_submissions_class_idx on public.evaluation_submissions(class_id, evaluation_id);

create table if not exists public.evaluation_photos (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.evaluation_submissions(id) on delete cascade,
  evaluation_id uuid not null references public.evaluations(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  storage_path text not null unique,
  position integer not null default 1 check (position between 1 and 40),
  received_at timestamptz not null default now()
);

create index if not exists evaluation_photos_submission_idx on public.evaluation_photos(submission_id, position);

-- ---------------------------------------------------------------------------
-- 3. Fonctions utilitaires (security definer, search_path figé)
-- ---------------------------------------------------------------------------
-- Première salle active de l'élève parmi les salles cibles de l'épreuve.
create or replace function public.evaluation_student_class(p_evaluation uuid, p_student uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select ec.class_id
  from public.evaluation_classes ec
  join public.class_students cs
    on cs.class_id = ec.class_id and cs.student_id = p_student and cs.is_active
  where ec.evaluation_id = p_evaluation
  order by cs.joined_at desc
  limit 1;
$$;

-- L'utilisateur peut-il corriger / consulter les remises de cette épreuve pour cette salle ?
create or replace function public.evaluation_can_review(p_evaluation uuid, p_class uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.eval_is_admin()
    or exists (
      select 1 from public.evaluations e
      where e.id = p_evaluation
        and e.teacher_id = auth.uid()
        and public.teacher_can_manage_class(p_class, auth.uid())
    );
$$;

create or replace function public.evaluation_is_owner(p_evaluation uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.eval_is_admin()
    or exists (select 1 from public.evaluations e where e.id = p_evaluation and e.teacher_id = auth.uid());
$$;

create or replace function public.evaluation_is_visible_to_student(p_evaluation uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.evaluations e
    join public.evaluation_classes ec on ec.evaluation_id = e.id
    where e.id = p_evaluation
      and e.status in ('published', 'closed')
      and public.is_student_in_class(ec.class_id, auth.uid())
  );
$$;

revoke all on function public.evaluation_student_class(uuid, uuid) from public, anon;
revoke all on function public.evaluation_can_review(uuid, uuid) from public, anon;
revoke all on function public.evaluation_is_owner(uuid) from public, anon;
revoke all on function public.evaluation_is_visible_to_student(uuid) from public, anon;
grant execute on function public.evaluation_student_class(uuid, uuid) to authenticated;
grant execute on function public.evaluation_can_review(uuid, uuid) to authenticated;
grant execute on function public.evaluation_is_owner(uuid) to authenticated;
grant execute on function public.evaluation_is_visible_to_student(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Garde-fous sur les épreuves
-- ---------------------------------------------------------------------------
create or replace function public.evaluations_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_has_classes boolean;
begin
  new.updated_at := now();

  -- Appels serveur (service_role / postgres) : aucune restriction supplémentaire.
  if auth.uid() is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if not public.eval_is_admin() then
      select p.role into v_role from public.profiles p where p.id = auth.uid();
      if v_role is distinct from 'teacher' then
        raise exception 'Seul un enseignant ou un administrateur peut créer une épreuve.';
      end if;
      if new.teacher_id is distinct from auth.uid() then
        raise exception 'Une épreuve ne peut être créée qu''en votre nom.';
      end if;
    end if;
    if new.status <> 'draft' then
      raise exception 'Une épreuve est d''abord enregistrée en brouillon, puis publiée.';
    end if;
    new.published_at := null;
    return new;
  end if;

  -- UPDATE
  if new.teacher_id is distinct from old.teacher_id then
    raise exception 'Le propriétaire d''une épreuve ne peut pas être modifié.';
  end if;

  if old.status = 'draft' and new.status = 'published' then
    if nullif(btrim(coalesce(new.pdf_path, '')), '') is null then
      raise exception 'Le fichier PDF de l''épreuve est obligatoire pour publier.';
    end if;
    if new.due_at <= now() then
      raise exception 'La date limite doit être dans le futur pour publier.';
    end if;
    select exists (select 1 from public.evaluation_classes ec where ec.evaluation_id = new.id)
      into v_has_classes;
    if not v_has_classes then
      raise exception 'Choisissez au moins une classe destinataire.';
    end if;
    new.published_at := now();
    return new;
  end if;

  if old.status in ('published', 'closed') then
    if new.status = 'draft' then
      raise exception 'Une épreuve publiée ne peut pas revenir en brouillon.';
    end if;
    if old.status = 'closed' and new.status <> 'closed' then
      raise exception 'Une épreuve clôturée ne peut pas être rouverte.';
    end if;
    -- Éléments figés après publication.
    if new.subject_id is distinct from old.subject_id
       or new.pdf_path is distinct from old.pdf_path
       or new.starts_at is distinct from old.starts_at
       or new.max_score is distinct from old.max_score
       or new.weight is distinct from old.weight
       or new.period_id is distinct from old.period_id
       or new.late_policy is distinct from old.late_policy
       or new.late_grace_minutes is distinct from old.late_grace_minutes
       or new.late_penalty_percent is distinct from old.late_penalty_percent then
      raise exception 'Matière, fichier, début, barème, période et règles de retard sont figés après publication.';
    end if;
    if new.due_at < old.due_at then
      raise exception 'La date limite ne peut qu''être prolongée après publication.';
    end if;
    new.published_at := old.published_at;
  end if;
  return new;
end;
$$;

drop trigger if exists evaluations_guard_trg on public.evaluations;
create trigger evaluations_guard_trg
before insert or update on public.evaluations
for each row execute function public.evaluations_guard();

-- Contrôle des classes cibles : salle suivie par l'enseignant, matière du programme de la salle.
create or replace function public.evaluation_classes_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.evaluations%rowtype;
  v_eval uuid;
begin
  if tg_op = 'DELETE' then
    v_eval := old.evaluation_id;
  else
    v_eval := new.evaluation_id;
  end if;

  select * into e from public.evaluations where id = v_eval;
  if not found or auth.uid() is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if e.status <> 'draft' then
    raise exception 'Les classes destinataires sont figées après publication.';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  if not public.eval_is_admin() and not public.teacher_can_manage_class(new.class_id, auth.uid()) then
    raise exception 'Vous ne gérez pas cette classe.';
  end if;
  if not exists (
    select 1 from public.school_classes c where c.id = new.class_id and c.is_active
  ) then
    raise exception 'Cette classe n''est pas active.';
  end if;
  if not exists (
    select 1 from public.class_subjects cs
    where cs.class_id = new.class_id and cs.subject_id = e.subject_id and cs.is_active
  ) then
    raise exception 'La matière de l''épreuve n''appartient pas au programme de cette classe.';
  end if;
  return new;
end;
$$;

drop trigger if exists evaluation_classes_guard_trg on public.evaluation_classes;
create trigger evaluation_classes_guard_trg
before insert or delete on public.evaluation_classes
for each row execute function public.evaluation_classes_guard();

-- Notification « nouvelle épreuve disponible » : une seule fois, à la publication.
create or replace function public.evaluations_notify_published()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'draft' and new.status = 'published' then
    insert into public.notifications (user_id, title, body, type)
    select distinct cs.student_id,
           'Nouvelle épreuve disponible',
           left(new.title, 160) || ' — à remettre avant le '
             || to_char(new.due_at at time zone 'Africa/Douala', 'DD/MM/YYYY "à" HH24:MI'),
           'evaluation_new'
    from public.evaluation_classes ec
    join public.class_students cs on cs.class_id = ec.class_id and cs.is_active
    where ec.evaluation_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists evaluations_notify_published_trg on public.evaluations;
create trigger evaluations_notify_published_trg
after update of status on public.evaluations
for each row execute function public.evaluations_notify_published();

-- ---------------------------------------------------------------------------
-- 5. RLS
-- ---------------------------------------------------------------------------
alter table public.evaluations enable row level security;
alter table public.evaluation_keys enable row level security;
alter table public.evaluation_classes enable row level security;
alter table public.evaluation_submissions enable row level security;
alter table public.evaluation_photos enable row level security;

-- evaluations
drop policy if exists "evaluations read" on public.evaluations;
create policy "evaluations read" on public.evaluations
for select to authenticated
using (
  public.eval_is_admin()
  or teacher_id = auth.uid()
  or (status in ('published', 'closed') and public.evaluation_is_visible_to_student(id))
);

drop policy if exists "evaluations teacher insert" on public.evaluations;
create policy "evaluations teacher insert" on public.evaluations
for insert to authenticated
with check (public.eval_is_admin() or teacher_id = auth.uid());

drop policy if exists "evaluations owner update" on public.evaluations;
create policy "evaluations owner update" on public.evaluations
for update to authenticated
using (public.eval_is_admin() or teacher_id = auth.uid())
with check (public.eval_is_admin() or teacher_id = auth.uid());

drop policy if exists "evaluations owner delete draft" on public.evaluations;
create policy "evaluations owner delete draft" on public.evaluations
for delete to authenticated
using ((public.eval_is_admin() or teacher_id = auth.uid()) and status = 'draft');

-- evaluation_keys : jamais lisibles par les élèves
drop policy if exists "evaluation keys owner all" on public.evaluation_keys;
create policy "evaluation keys owner all" on public.evaluation_keys
for all to authenticated
using (public.evaluation_is_owner(evaluation_id))
with check (public.evaluation_is_owner(evaluation_id));

-- evaluation_classes
drop policy if exists "evaluation classes read" on public.evaluation_classes;
create policy "evaluation classes read" on public.evaluation_classes
for select to authenticated
using (
  public.evaluation_is_owner(evaluation_id)
  or (public.evaluation_is_visible_to_student(evaluation_id)
      and public.is_student_in_class(class_id, auth.uid()))
);

drop policy if exists "evaluation classes owner write" on public.evaluation_classes;
create policy "evaluation classes owner write" on public.evaluation_classes
for insert to authenticated
with check (public.evaluation_is_owner(evaluation_id));

drop policy if exists "evaluation classes owner delete" on public.evaluation_classes;
create policy "evaluation classes owner delete" on public.evaluation_classes
for delete to authenticated
using (public.evaluation_is_owner(evaluation_id));

-- Remises et photos : lecture seule côté client ; les écritures passent par les RPC.
drop policy if exists "evaluation submissions read" on public.evaluation_submissions;
create policy "evaluation submissions read" on public.evaluation_submissions
for select to authenticated
using (student_id = auth.uid() or public.evaluation_can_review(evaluation_id, class_id));

drop policy if exists "evaluation photos read" on public.evaluation_photos;
create policy "evaluation photos read" on public.evaluation_photos
for select to authenticated
using (student_id = auth.uid() or public.evaluation_can_review(evaluation_id, class_id));

-- ---------------------------------------------------------------------------
-- 6. Stockage privé
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('evaluation-papers', 'evaluation-papers', false, 26214400, array['application/pdf'])
on conflict (id) do update
set public = false, file_size_limit = 26214400, allowed_mime_types = array['application/pdf'];

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('evaluation-photos', 'evaluation-photos', false, 10485760,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = false, file_size_limit = 10485760,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

-- Extraction sûre de « {evaluation_id}/{student_id}/{fichier} ».
create or replace function public.evaluation_photo_path_parts(
  p_path text,
  out evaluation_id uuid,
  out student_id uuid
)
language plpgsql
immutable
set search_path = public
as $$
begin
  if p_path ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$' then
    evaluation_id := split_part(p_path, '/', 1)::uuid;
    student_id := split_part(p_path, '/', 2)::uuid;
  end if;
end;
$$;

-- Un élève peut-il déposer / supprimer ce fichier maintenant ?
create or replace function public.evaluation_student_can_upload(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_eval uuid;
  v_student uuid;
  e public.evaluations%rowtype;
begin
  select pp.evaluation_id, pp.student_id into v_eval, v_student
  from public.evaluation_photo_path_parts(p_path) pp;
  if v_eval is null or v_student is distinct from auth.uid() then
    return false;
  end if;
  select * into e from public.evaluations where id = v_eval;
  if not found or e.status <> 'published' then
    return false;
  end if;
  if now() < e.starts_at then
    return false;
  end if;
  if public.evaluation_student_class(v_eval, v_student) is null then
    return false;
  end if;
  if exists (
    select 1 from public.evaluation_submissions s
    where s.evaluation_id = v_eval and s.student_id = v_student and s.status = 'submitted'
  ) then
    return false;
  end if;
  if e.late_policy = 'reject'
     and now() >= e.due_at + make_interval(mins => e.late_grace_minutes) then
    return false;
  end if;
  return true;
end;
$$;

create or replace function public.evaluation_can_read_photo(p_path text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_eval uuid;
  v_student uuid;
  v_class uuid;
begin
  select pp.evaluation_id, pp.student_id into v_eval, v_student
  from public.evaluation_photo_path_parts(p_path) pp;
  if v_eval is null then
    return false;
  end if;
  if v_student = auth.uid() then
    return true;
  end if;
  select s.class_id into v_class
  from public.evaluation_submissions s
  where s.evaluation_id = v_eval and s.student_id = v_student;
  if v_class is null then
    return public.evaluation_is_owner(v_eval);
  end if;
  return public.evaluation_can_review(v_eval, v_class);
end;
$$;

create or replace function public.evaluation_paper_readable(p_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.evaluations e
    where e.pdf_path = p_path
      and (
        public.eval_is_admin()
        or e.teacher_id = auth.uid()
        or (
          e.status in ('published', 'closed')
          and now() >= e.starts_at
          and exists (
            select 1 from public.evaluation_classes ec
            where ec.evaluation_id = e.id and public.is_student_in_class(ec.class_id, auth.uid())
          )
        )
      )
  );
$$;

revoke all on function public.evaluation_student_can_upload(text) from public, anon;
revoke all on function public.evaluation_can_read_photo(text) from public, anon;
revoke all on function public.evaluation_paper_readable(text) from public, anon;
grant execute on function public.evaluation_student_can_upload(text) to authenticated;
grant execute on function public.evaluation_can_read_photo(text) to authenticated;
grant execute on function public.evaluation_paper_readable(text) to authenticated;

-- PDF des épreuves : dossier = identifiant de l'enseignant propriétaire.
drop policy if exists "eval papers teacher insert" on storage.objects;
create policy "eval papers teacher insert" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'evaluation-papers'
  and (
    public.eval_is_admin()
    or (
      (storage.foldername(name))[1] = auth.uid()::text
      and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher')
    )
  )
);

drop policy if exists "eval papers read" on storage.objects;
create policy "eval papers read" on storage.objects
for select to authenticated
using (
  bucket_id = 'evaluation-papers'
  and (public.eval_is_admin() or (storage.foldername(name))[1] = auth.uid()::text
       or public.evaluation_paper_readable(name))
);

drop policy if exists "eval papers owner delete" on storage.objects;
create policy "eval papers owner delete" on storage.objects
for delete to authenticated
using (
  bucket_id = 'evaluation-papers'
  and (public.eval_is_admin() or (storage.foldername(name))[1] = auth.uid()::text)
);

-- Photographies des élèves : « {evaluation}/{élève}/{fichier} ».
drop policy if exists "eval photos student insert" on storage.objects;
create policy "eval photos student insert" on storage.objects
for insert to authenticated
with check (bucket_id = 'evaluation-photos' and public.evaluation_student_can_upload(name));

drop policy if exists "eval photos read" on storage.objects;
create policy "eval photos read" on storage.objects
for select to authenticated
using (bucket_id = 'evaluation-photos' and public.evaluation_can_read_photo(name));

drop policy if exists "eval photos student delete" on storage.objects;
create policy "eval photos student delete" on storage.objects
for delete to authenticated
using (bucket_id = 'evaluation-photos' and public.evaluation_student_can_upload(name));

-- ---------------------------------------------------------------------------
-- 7. RPC élève : démarrer, enregistrer une photo, retirer une photo
-- ---------------------------------------------------------------------------
create or replace function public.start_evaluation_submission(p_evaluation uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  e public.evaluations%rowtype;
  v_class uuid;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Session requise.';
  end if;
  select * into e from public.evaluations where id = p_evaluation;
  if not found or e.status <> 'published' then
    raise exception 'Épreuve indisponible.';
  end if;
  v_class := public.evaluation_student_class(p_evaluation, v_uid);
  if v_class is null then
    raise exception 'Cette épreuve n''est pas destinée à votre classe.';
  end if;
  if now() < e.starts_at then
    raise exception 'L''épreuve n''a pas encore commencé.';
  end if;

  select s.id into v_id
  from public.evaluation_submissions s
  where s.evaluation_id = p_evaluation and s.student_id = v_uid;
  if v_id is not null then
    return v_id;
  end if;

  if e.late_policy = 'reject'
     and now() >= e.due_at + make_interval(mins => e.late_grace_minutes) then
    raise exception 'DEADLINE_PASSED';
  end if;

  insert into public.evaluation_submissions (evaluation_id, student_id, class_id, subject_id)
  values (p_evaluation, v_uid, v_class, e.subject_id)
  on conflict (evaluation_id, student_id) do nothing;

  select s.id into v_id
  from public.evaluation_submissions s
  where s.evaluation_id = p_evaluation and s.student_id = v_uid;
  return v_id;
end;
$$;

create or replace function public.register_evaluation_photo(
  p_evaluation uuid,
  p_path text,
  p_position integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_sub public.evaluation_submissions%rowtype;
  v_parts record;
  v_photo uuid;
begin
  if v_uid is null then
    raise exception 'Session requise.';
  end if;
  select * into v_sub
  from public.evaluation_submissions s
  where s.evaluation_id = p_evaluation and s.student_id = v_uid
  for update;
  if not found then
    raise exception 'Démarrez d''abord la remise.';
  end if;
  if v_sub.status <> 'draft' then
    raise exception 'La remise est déjà envoyée et ne peut plus être modifiée.';
  end if;

  select * into v_parts from public.evaluation_photo_path_parts(p_path);
  if v_parts.evaluation_id is distinct from p_evaluation or v_parts.student_id is distinct from v_uid then
    raise exception 'Chemin de fichier invalide.';
  end if;
  if not public.evaluation_student_can_upload(p_path) then
    raise exception 'Dépôt refusé : fenêtre de remise fermée.';
  end if;
  if not exists (
    select 1 from storage.objects o where o.bucket_id = 'evaluation-photos' and o.name = p_path
  ) then
    raise exception 'Fichier introuvable dans le stockage : renvoyez la photographie.';
  end if;
  if v_sub.photo_count >= 20 then
    raise exception 'Maximum 20 photographies par remise.';
  end if;

  insert into public.evaluation_photos
    (submission_id, evaluation_id, student_id, class_id, subject_id, storage_path, position)
  values
    (v_sub.id, p_evaluation, v_uid, v_sub.class_id, v_sub.subject_id, p_path,
     greatest(1, least(40, coalesce(p_position, 1))))
  on conflict (storage_path) do nothing
  returning id into v_photo;

  if v_photo is null then
    select id into v_photo from public.evaluation_photos where storage_path = p_path;
    return v_photo;
  end if;

  update public.evaluation_submissions
  set photo_count = (select count(*) from public.evaluation_photos where submission_id = v_sub.id),
      first_photo_at = coalesce(first_photo_at, now()),
      updated_at = now()
  where id = v_sub.id;
  return v_photo;
end;
$$;

create or replace function public.remove_evaluation_photo(p_photo uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_photo public.evaluation_photos%rowtype;
  v_status text;
begin
  select * into v_photo from public.evaluation_photos where id = p_photo and student_id = v_uid;
  if not found then
    raise exception 'Photographie introuvable.';
  end if;
  select status into v_status from public.evaluation_submissions where id = v_photo.submission_id for update;
  if v_status <> 'draft' then
    raise exception 'La remise est déjà envoyée.';
  end if;
  delete from public.evaluation_photos where id = p_photo;
  update public.evaluation_submissions
  set photo_count = (select count(*) from public.evaluation_photos where submission_id = v_photo.submission_id),
      updated_at = now()
  where id = v_photo.submission_id;
end;
$$;

revoke all on function public.start_evaluation_submission(uuid) from public, anon;
revoke all on function public.register_evaluation_photo(uuid, text, integer) from public, anon;
revoke all on function public.remove_evaluation_photo(uuid) from public, anon;
grant execute on function public.start_evaluation_submission(uuid) to authenticated;
grant execute on function public.register_evaluation_photo(uuid, text, integer) to authenticated;
grant execute on function public.remove_evaluation_photo(uuid) to authenticated;
