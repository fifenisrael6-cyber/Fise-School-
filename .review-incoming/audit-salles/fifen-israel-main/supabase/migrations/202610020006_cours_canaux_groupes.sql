-- Fise School — cours publiés par salle (style canal), QCM sans cours obligatoire,
-- matières de base par salle et groupes de messages avec code d'invitation.

-- ============================================================
-- 1. Cours simplifiés : programme / chapitre deviennent facultatifs
-- ============================================================
alter table public.courses alter column curriculum_id drop not null;
alter table public.courses alter column chapter_id drop not null;

-- ============================================================
-- 2. Matières de base automatiques pour chaque salle
-- ============================================================
create or replace function public.apply_base_subjects_to_class(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.class_subjects (class_id, subject_id, is_compulsory, option_group, position, is_active)
  select c.id, s.id, true, null,
         row_number() over (partition by c.id order by s.code) - 1, true
  from public.school_classes c
  join public.subjects s
    on s.is_active
   and s.subsystem = c.subsystem
   and s.sector = c.sector
  where c.id = p_class_id
    and c.is_active
    and (
      (c.subsystem = 'francophone' and c.sector = 'general' and s.code in
        ('francais','anglais','mathematiques','histoire','geographie','education_civique'))
      or (c.subsystem = 'anglophone' and c.sector = 'general' and s.code in
        ('english_language','french_language','mathematics_en','history_en','geography_en','citizenship_en'))
      or (c.subsystem = 'francophone' and c.sector = 'technical' and s.code in
        ('technical_math','technical_science','dessin_technique','technologie','entrepreneuriat','technical_english'))
      or (c.subsystem = 'anglophone' and c.sector = 'technical' and s.code in
        ('technical_french','technical_communication','technical_math_en','technical_science_en','workshop_practice'))
    )
  on conflict (class_id, subject_id) do nothing;
end;
$$;

revoke all on function public.apply_base_subjects_to_class(uuid) from public;

create or replace function public.trg_apply_base_subjects()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.apply_base_subjects_to_class(new.id);
  return new;
end;
$$;

drop trigger if exists school_classes_apply_base_subjects on public.school_classes;
create trigger school_classes_apply_base_subjects
after insert on public.school_classes
for each row execute function public.trg_apply_base_subjects();

-- Salles déjà existantes : on complète sans toucher aux réglages de l'administrateur.
do $$
declare
  r record;
begin
  for r in select id from public.school_classes where is_active loop
    perform public.apply_base_subjects_to_class(r.id);
  end loop;
end;
$$;

-- ============================================================
-- 3. L'enseignant peut ajouter une matière à sa salle
-- ============================================================
create or replace function public.list_class_addable_subjects(p_class_id uuid)
returns setof public.subjects
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.teacher_can_manage_class(p_class_id, auth.uid()) then
    raise exception 'Teacher is not assigned to this class';
  end if;

  return query
  select s.*
  from public.subjects s
  join public.school_classes c on c.id = p_class_id
  where s.is_active
    and s.subsystem = c.subsystem
    and s.sector = c.sector
    and not exists (
      select 1 from public.class_subjects cs
      where cs.class_id = p_class_id
        and cs.subject_id = s.id
        and cs.is_active
    )
  order by s.name_fr;
end;
$$;

create or replace function public.teacher_add_class_subject(p_class_id uuid, p_subject_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class public.school_classes%rowtype;
  v_subject public.subjects%rowtype;
  v_pos integer;
begin
  if not public.teacher_can_manage_class(p_class_id, auth.uid()) then
    raise exception 'Teacher is not assigned to this class';
  end if;

  select * into v_class from public.school_classes where id = p_class_id and is_active;
  select * into v_subject from public.subjects where id = p_subject_id and is_active;

  if v_class.id is null or v_subject.id is null then
    raise exception 'Class or subject not found';
  end if;

  if v_subject.subsystem is distinct from v_class.subsystem
     or v_subject.sector is distinct from v_class.sector then
    raise exception 'Subject does not match the class subsystem and sector';
  end if;

  select coalesce(max(position), 0) + 1 into v_pos
  from public.class_subjects where class_id = p_class_id;

  insert into public.class_subjects (class_id, subject_id, is_compulsory, option_group, position, is_active)
  values (p_class_id, p_subject_id, false, 'Option', v_pos, true)
  on conflict (class_id, subject_id) do update set is_active = true;
end;
$$;

revoke all on function public.list_class_addable_subjects(uuid) from public;
revoke all on function public.teacher_add_class_subject(uuid, uuid) from public;
grant execute on function public.list_class_addable_subjects(uuid) to authenticated;
grant execute on function public.teacher_add_class_subject(uuid, uuid) to authenticated;

-- ============================================================
-- 4. QCM publiés directement dans une salle + matière (sans cours)
-- ============================================================
alter table public.assignments
  add column if not exists subject_id uuid references public.subjects(id) on delete set null;
alter table public.assignments alter column course_id drop not null;

update public.assignments a
set subject_id = c.subject_id
from public.courses c
where a.course_id = c.id and a.subject_id is null;

create index if not exists assignments_class_subject_idx
  on public.assignments (class_id, subject_id, status);

create or replace function public.validate_assignment_context()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_course public.courses%rowtype;
begin
  if new.course_id is not null then
    select * into v_course from public.courses where id = new.course_id;

    if not found or v_course.status = 'archived' then
      raise exception 'Assignment course is not available';
    end if;

    if new.class_id is distinct from v_course.class_id then
      raise exception 'Assignment class must match the course class';
    end if;

    if new.teacher_id is distinct from v_course.teacher_id and not public.is_admin() then
      raise exception 'Assignment teacher must own the selected course';
    end if;

    new.subject_id := v_course.subject_id;
  else
    if new.subject_id is null then
      raise exception 'Assignment subject is required when no course is selected';
    end if;

    if not exists (
      select 1 from public.class_subjects cs
      where cs.class_id = new.class_id
        and cs.subject_id = new.subject_id
        and cs.is_active
    ) then
      raise exception 'Subject does not belong to the selected class';
    end if;
  end if;

  if not public.is_admin()
     and not public.teacher_can_manage_class(new.class_id, new.teacher_id) then
    raise exception 'Teacher is not assigned to the selected class';
  end if;

  if new.lesson_id is not null and not exists (
    select 1 from public.lessons l
    where l.id = new.lesson_id
      and l.course_id = new.course_id
  ) then
    raise exception 'Assignment lesson must belong to the selected course';
  end if;

  return new;
end;
$$;

-- ============================================================
-- 5. Groupes de messages (style WhatsApp) avec code d'invitation
-- ============================================================
create table if not exists public.message_groups (
  id uuid primary key default gen_random_uuid(),
  class_id uuid references public.school_classes(id) on delete set null,
  name text not null,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  invite_code text not null unique,
  created_at timestamptz not null default now(),
  constraint message_groups_name_not_blank check (length(trim(name)) > 0)
);

create table if not exists public.message_group_members (
  group_id uuid not null references public.message_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'student' check (role in ('teacher', 'student')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.message_group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.message_groups(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null default '',
  attachment_path text,
  attachment_name text,
  attachment_type text,
  created_at timestamptz not null default now(),
  constraint message_group_messages_body_or_attachment
    check (length(trim(body)) > 0 or attachment_path is not null)
);

create index if not exists message_group_messages_group_idx
  on public.message_group_messages (group_id, created_at);
create index if not exists message_group_members_user_idx
  on public.message_group_members (user_id);

create or replace function public.is_message_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.message_group_members m
    where m.group_id = p_group_id and m.user_id = auth.uid()
  );
$$;

revoke all on function public.is_message_group_member(uuid) from public;
grant execute on function public.is_message_group_member(uuid) to authenticated;

alter table public.message_groups enable row level security;
alter table public.message_group_members enable row level security;
alter table public.message_group_messages enable row level security;

drop policy if exists "members read groups" on public.message_groups;
create policy "members read groups"
on public.message_groups for select to authenticated
using (public.is_message_group_member(id));

drop policy if exists "members read group members" on public.message_group_members;
create policy "members read group members"
on public.message_group_members for select to authenticated
using (public.is_message_group_member(group_id));

drop policy if exists "owner removes or member leaves" on public.message_group_members;
create policy "owner removes or member leaves"
on public.message_group_members for delete to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.message_groups g
    where g.id = group_id and g.owner_id = auth.uid()
  )
);

drop policy if exists "members read group messages" on public.message_group_messages;
create policy "members read group messages"
on public.message_group_messages for select to authenticated
using (public.is_message_group_member(group_id));

drop policy if exists "members send group messages" on public.message_group_messages;
create policy "members send group messages"
on public.message_group_messages for insert to authenticated
with check (sender_id = auth.uid() and public.is_message_group_member(group_id));

create or replace function public.generate_group_invite_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_code text;
begin
  loop
    v_code := 'GRP-' || upper(substr(md5(gen_random_uuid()::text), 1, 6));
    exit when not exists (select 1 from public.message_groups where invite_code = v_code);
  end loop;
  return v_code;
end;
$$;

revoke all on function public.generate_group_invite_code() from public;

create or replace function public.create_message_group(p_name text, p_class_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role in ('teacher', 'admin')) then
    raise exception 'Only a teacher can create a group';
  end if;

  if p_class_id is not null and not public.teacher_can_manage_class(p_class_id, auth.uid()) then
    raise exception 'Teacher is not assigned to this class';
  end if;

  insert into public.message_groups (class_id, name, owner_id, invite_code)
  values (p_class_id, trim(p_name), auth.uid(), public.generate_group_invite_code())
  returning id into v_id;

  insert into public.message_group_members (group_id, user_id, role)
  values (v_id, auth.uid(), 'teacher');

  return v_id;
end;
$$;

create or replace function public.regenerate_message_group_code(p_group_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if not exists (
    select 1 from public.message_groups where id = p_group_id and owner_id = auth.uid()
  ) then
    raise exception 'Only the group owner can change the invitation code';
  end if;

  v_code := public.generate_group_invite_code();
  update public.message_groups set invite_code = v_code where id = p_group_id;
  return v_code;
end;
$$;

create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.message_groups%rowtype;
  v_role text;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null then
    raise exception 'Profile not found';
  end if;

  select * into v_group
  from public.message_groups
  where invite_code = upper(trim(p_code));

  if not found then
    raise exception 'Invalid invitation code';
  end if;

  insert into public.message_group_members (group_id, user_id, role)
  values (v_group.id, auth.uid(), case when v_role = 'student' then 'student' else 'teacher' end)
  on conflict (group_id, user_id) do nothing;

  return v_group.id;
end;
$$;

create or replace function public.list_my_message_groups()
returns table (
  id uuid,
  name text,
  class_id uuid,
  class_name text,
  owner_id uuid,
  invite_code text,
  member_count bigint,
  last_body text,
  last_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    g.id,
    g.name,
    g.class_id,
    c.display_name,
    g.owner_id,
    case when g.owner_id = auth.uid() then g.invite_code else null end,
    (select count(*) from public.message_group_members m2 where m2.group_id = g.id),
    (select case
              when length(trim(lm.body)) > 0 then lm.body
              else coalesce(lm.attachment_name, 'Pièce jointe')
            end
     from public.message_group_messages lm
     where lm.group_id = g.id
     order by lm.created_at desc
     limit 1),
    (select max(lm.created_at) from public.message_group_messages lm where lm.group_id = g.id)
  from public.message_groups g
  join public.message_group_members me on me.group_id = g.id and me.user_id = auth.uid()
  left join public.school_classes c on c.id = g.class_id
  order by coalesce(
    (select max(lm.created_at) from public.message_group_messages lm where lm.group_id = g.id),
    g.created_at
  ) desc;
$$;

create or replace function public.list_message_group_messages(p_group_id uuid)
returns table (
  id uuid,
  sender_id uuid,
  sender_name text,
  sender_role text,
  body text,
  attachment_path text,
  attachment_name text,
  attachment_type text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_message_group_member(p_group_id) then
    raise exception 'Not a member of this group';
  end if;

  return query
  select m.id, m.sender_id,
         trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')),
         p.role::text,
         m.body, m.attachment_path, m.attachment_name, m.attachment_type, m.created_at
  from public.message_group_messages m
  left join public.profiles p on p.id = m.sender_id
  where m.group_id = p_group_id
  order by m.created_at asc;
end;
$$;

create or replace function public.list_message_group_members(p_group_id uuid)
returns table (user_id uuid, full_name text, role text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_message_group_member(p_group_id) then
    raise exception 'Not a member of this group';
  end if;

  return query
  select m.user_id,
         trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')),
         m.role
  from public.message_group_members m
  left join public.profiles p on p.id = m.user_id
  where m.group_id = p_group_id
  order by m.role desc, 2;
end;
$$;

revoke all on function public.create_message_group(text, uuid) from public;
revoke all on function public.regenerate_message_group_code(uuid) from public;
revoke all on function public.join_message_group(text) from public;
revoke all on function public.list_my_message_groups() from public;
revoke all on function public.list_message_group_messages(uuid) from public;
revoke all on function public.list_message_group_members(uuid) from public;
grant execute on function public.create_message_group(text, uuid) to authenticated;
grant execute on function public.regenerate_message_group_code(uuid) to authenticated;
grant execute on function public.join_message_group(text) to authenticated;
grant execute on function public.list_my_message_groups() to authenticated;
grant execute on function public.list_message_group_messages(uuid) to authenticated;
grant execute on function public.list_message_group_members(uuid) to authenticated;

-- Pièces jointes des groupes (dossier = identifiant du groupe)
insert into storage.buckets (id, name, public)
values ('group-message-attachments', 'group-message-attachments', false)
on conflict (id) do nothing;

drop policy if exists "group members read attachments" on storage.objects;
create policy "group members read attachments"
on storage.objects for select to authenticated
using (
  bucket_id = 'group-message-attachments'
  and public.is_message_group_member((storage.foldername(name))[1]::uuid)
);

drop policy if exists "group members upload attachments" on storage.objects;
create policy "group members upload attachments"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'group-message-attachments'
  and public.is_message_group_member((storage.foldername(name))[1]::uuid)
);

-- Messages en temps réel
do $$
begin
  alter publication supabase_realtime add table public.message_group_messages;
exception when others then
  null;
end;
$$;
