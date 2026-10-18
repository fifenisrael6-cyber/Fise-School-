-- ============================================================================
-- Fise School / Cyber — protection côté serveur des contenus gratuits/payants,
-- quota de messages reçus, classification des enseignants, expiration.
-- À appliquer APRÈS 20261017100000_premium_quota_and_payment_hardening.sql.
-- ATTENTION : un push sur main applique cette migration automatiquement.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Aides d'accès
-- ---------------------------------------------------------------------------
-- Enseignants/admins : jamais limités. Élèves : Premium actif.
create or replace function public.has_full_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select p.role <> 'student' from public.profiles p where p.id = auth.uid()), false)
      or public.is_student_premium(auth.uid());
$$;

-- Droit déjà accordé dans la fenêtre de 24 h courante (ouverture légitime d'une ressource)
create or replace function public.has_active_grant(p_feature text, p_resource_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.feature_quota_grants g
    join public.feature_quota_windows w
      on w.user_id = g.user_id and w.feature = g.feature and w.window_start = g.window_start
    where g.user_id = auth.uid()
      and g.feature = p_feature
      and g.resource_id = p_resource_id
      and w.window_start + interval '24 hours' > now()
  );
$$;

create or replace function public.can_access_gated(p_feature text, p_resource_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_full_access() or public.has_active_grant(p_feature, p_resource_id);
$$;

revoke all on function public.has_full_access() from public, anon;
revoke all on function public.has_active_grant(text, text) from public, anon;
revoke all on function public.can_access_gated(text, text) from public, anon;
grant execute on function public.has_full_access() to authenticated;
grant execute on function public.has_active_grant(text, text) to authenticated;
grant execute on function public.can_access_gated(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Contenus de chapitre (leçons), exercices, QCM : lecture réservée aux droits valides.
--    Le catalogue (cours, chapitres, titres de quiz) reste gratuit.
-- ---------------------------------------------------------------------------
drop policy if exists "students read published chapter content" on public.chapter_content_items;
create policy "students read published chapter content"
on public.chapter_content_items for select to authenticated
using (
  is_published
  and public.student_can_access_chapter(chapter_id)
  and public.can_access_gated('lesson', chapter_id::text)
);

drop policy if exists "students read published chapter exercises" on public.chapter_exercises;
create policy "students read published chapter exercises"
on public.chapter_exercises for select to authenticated
using (
  is_published
  and public.student_can_access_chapter(chapter_id)
  and public.can_access_gated('lesson', chapter_id::text)
);

drop policy if exists "students read questions of accessible quizzes" on public.chapter_quiz_questions;
create policy "students read questions of accessible quizzes"
on public.chapter_quiz_questions for select to authenticated
using (
  exists (
    select 1 from public.chapter_quizzes q
    where q.id = quiz_id and q.is_published
      and public.student_can_access_chapter(q.chapter_id)
  )
  and public.can_access_gated('qcm', quiz_id::text)
);

-- Fichiers (PDF, audio, vidéo, images) des chapitres
drop policy if exists "read published chapter content files" on storage.objects;
create policy "read published chapter content files" on storage.objects
for select to authenticated
using (
  bucket_id = 'chapter-content'
  and (
    public.is_catalog_admin()
    or exists (
      select 1 from public.chapter_content_items c
      where c.storage_path = storage.objects.name
        and c.is_published
        and public.student_can_access_chapter(c.chapter_id)
        and public.can_access_gated('lesson', c.chapter_id::text)
    )
  )
);

-- ---------------------------------------------------------------------------
-- 3. Annales (fichiers) : accès seulement après ouverture autorisée ou Premium
-- ---------------------------------------------------------------------------
drop policy if exists "authenticated read past papers storage" on storage.objects;
create policy "authenticated read past papers storage"
on storage.objects for select to authenticated
using (
  bucket_id = 'past-papers'
  and (
    public.has_full_access()
    or exists (
      select 1 from public.past_papers pp
      where pp.file_path = storage.objects.name
        and public.has_active_grant('annale', pp.id::text)
    )
  )
);

-- ---------------------------------------------------------------------------
-- 4. Pièces jointes de cours (course-resources) : droit sur une leçon du cours ou Premium
-- ---------------------------------------------------------------------------
drop policy if exists "course members read course resources storage" on storage.objects;
create policy "course members read course resources storage"
on storage.objects for select to authenticated
using (
  bucket_id = 'course-resources'
  and (
    exists (
      select 1 from public.courses c
      where c.id = (storage.foldername(name))[1]::uuid
        and (c.teacher_id = auth.uid() or public.is_catalog_admin())
    )
    or (
      public.is_course_student((storage.foldername(name))[1]::uuid)
      and (
        public.has_full_access()
        or exists (
          select 1 from public.lessons l
          where l.course_id = (storage.foldername(name))[1]::uuid
            and public.has_active_grant('lesson', l.id::text)
        )
      )
    )
  )
);

-- ---------------------------------------------------------------------------
-- 5. Pièces jointes de messagerie : téléversement réservé au Premium (élèves)
-- ---------------------------------------------------------------------------
drop policy if exists "private message attachments sender upload" on storage.objects;
create policy "private message attachments sender upload"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'private-message-attachments'
  and owner_id = auth.uid()::text
  and split_part(name, '/', 1) = auth.uid()::text
  and public.has_full_access()
);

drop policy if exists "group members upload attachments" on storage.objects;
create policy "group members upload attachments"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'group-message-attachments'
  and public.is_message_group_member((storage.foldername(name))[1]::uuid)
  and public.has_full_access()
);

-- ---------------------------------------------------------------------------
-- 6. Messages privés reçus : 2 / 24 h pour un élève gratuit (messages reçus après activation)
-- ---------------------------------------------------------------------------
create table if not exists public.quota_config (
  key text primary key,
  value_ts timestamptz not null
);
alter table public.quota_config enable row level security;
revoke all on public.quota_config from anon, authenticated;
insert into public.quota_config (key, value_ts) values ('msg_recv_since', now())
on conflict (key) do nothing;

create or replace function public.can_read_received_message(p_id uuid, p_created timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_full_access()
      or p_created < (select value_ts from public.quota_config where key = 'msg_recv_since')
      or public.has_active_grant('msg_recv', p_id::text);
$$;
revoke all on function public.can_read_received_message(uuid, timestamptz) from public, anon;
grant execute on function public.can_read_received_message(uuid, timestamptz) to authenticated;

drop policy if exists "participants read private messages" on public.private_messages;
create policy "participants read private messages" on public.private_messages
for select to authenticated
using (
  sender_id = auth.uid()
  or (recipient_id = auth.uid() and public.can_read_received_message(id, created_at))
);

-- Liste : débloque les messages reçus les plus récents dans la limite du quota,
-- les autres sont renvoyés verrouillés (corps masqué, sans pièce jointe).
create or replace function public.list_private_messages(target_user_id uuid)
returns setof public.private_messages
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_since timestamptz;
  r public.private_messages%rowtype;
  v_res jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select value_ts into v_since from public.quota_config where key = 'msg_recv_since';

  if not public.has_full_access() then
    for r in
      select m.* from public.private_messages m
      where m.sender_id = target_user_id and m.recipient_id = v_uid
        and m.created_at >= coalesce(v_since, now())
        and not public.has_active_grant('msg_recv', m.id::text)
      order by m.created_at desc
      limit 50
    loop
      v_res := public.consume_feature_quota('msg_recv', r.id::text);
      exit when not coalesce((v_res ->> 'allowed')::boolean, false);
    end loop;
  end if;

  for r in
    select m.* from public.private_messages m
    where (m.sender_id = v_uid and m.recipient_id = target_user_id)
       or (m.sender_id = target_user_id and m.recipient_id = v_uid)
    order by m.created_at
  loop
    if r.recipient_id = v_uid and not public.can_read_received_message(r.id, r.created_at) then
      r.body := '__PREMIUM_LOCKED__';
      r.attachment_path := null;
      r.attachment_name := null;
    end if;
    return next r;
  end loop;
  return;
end;
$$;
revoke all on function public.list_private_messages(uuid) from public, anon;
grant execute on function public.list_private_messages(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Classification des enseignants (administrateur uniquement)
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_teacher_stream(p_teacher_id uuid, p_stream text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(public.is_catalog_admin(), false) then
    raise exception 'Administrator access required';
  end if;
  if p_stream is not null and p_stream not in ('scientific', 'literary') then
    raise exception 'Invalid stream';
  end if;
  update public.profiles set teaching_stream = p_stream
  where id = p_teacher_id and role = 'teacher';
  if not found then raise exception 'Teacher not found'; end if;
end;
$$;
revoke all on function public.admin_set_teacher_stream(uuid, text) from public, anon;
grant execute on function public.admin_set_teacher_stream(uuid, text) to authenticated;

-- Empêche un utilisateur de modifier lui-même sa classification (revenu enseignant)
create or replace function public.protect_teaching_stream()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.teaching_stream is distinct from old.teaching_stream
     and auth.uid() is not null
     and not coalesce(public.is_catalog_admin(), false) then
    new.teaching_stream := old.teaching_stream;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_protect_teaching_stream on public.profiles;
create trigger trg_protect_teaching_stream
  before update on public.profiles
  for each row execute function public.protect_teaching_stream();

-- ---------------------------------------------------------------------------
-- 8. Expiration Premium : nettoyage planifié si pg_cron est disponible
--    (la lecture contrôle déjà expires_at ; ceci synchronise seulement profiles.subscription_plan)
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('expire-student-subscriptions', '*/30 * * * *',
                          'select public.expire_student_subscriptions()');
  end if;
exception when others then
  raise notice 'pg_cron scheduling skipped: %', sqlerrm;
end $$;
