-- Fise School: (1) l'enseignant choisit les salles qu'il suit,
--              (2) l'admin diffuse chaque annale dans une ou plusieurs salles.

-- ------------------------------------------------------------
-- 1. Salles suivies par l'enseignant
-- ------------------------------------------------------------

create or replace function public.list_classes_for_teacher_choice()
returns table (id uuid, name text, display_name text, is_selected boolean)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.name,
    c.display_name,
    exists (
      select 1 from public.class_teachers ct
      where ct.class_id = c.id and ct.teacher_id = auth.uid() and ct.is_active
    ) as is_selected
  from public.school_classes c
  join public.profiles p on p.id = auth.uid() and p.role = 'teacher'
  where c.is_active
    and (p.subsystem is null or p.subsystem = c.subsystem)
    and (p.sector is null or p.sector = c.sector)
  order by c.display_name;
$$;

revoke all on function public.list_classes_for_teacher_choice() from public;
grant execute on function public.list_classes_for_teacher_choice() to authenticated;

create or replace function public.teacher_set_my_classes(p_class_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_class uuid;
  v_count integer := 0;
begin
  if v_uid is null or not public.check_profile_role(v_uid, 'teacher') then
    raise exception 'Only teachers can choose their classes';
  end if;

  -- Retire les salles décochées.
  update public.class_teachers
  set is_active = false
  where teacher_id = v_uid
    and is_active
    and not (class_id = any (coalesce(p_class_ids, '{}'::uuid[])));

  -- Ajoute les salles cochées (seulement celles compatibles avec le profil).
  for v_class in
    select c.id
    from public.school_classes c
    join public.profiles p on p.id = v_uid
    where c.id = any (coalesce(p_class_ids, '{}'::uuid[]))
      and c.is_active
      and (p.subsystem is null or p.subsystem = c.subsystem)
      and (p.sector is null or p.sector = c.sector)
  loop
    if not exists (
      select 1 from public.class_teachers
      where teacher_id = v_uid and class_id = v_class and is_active
    ) then
      insert into public.class_teachers (class_id, teacher_id, is_active)
      values (v_class, v_uid, true);
    end if;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.teacher_set_my_classes(uuid[]) from public;
grant execute on function public.teacher_set_my_classes(uuid[]) to authenticated;

-- ------------------------------------------------------------
-- 2. Diffusion des annales par salle
-- ------------------------------------------------------------

create table if not exists public.past_paper_classes (
  paper_id uuid not null references public.past_papers(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (paper_id, class_id)
);

create index if not exists past_paper_classes_class_idx
  on public.past_paper_classes (class_id);

alter table public.past_paper_classes enable row level security;

drop policy if exists "admins manage past paper classes" on public.past_paper_classes;
create policy "admins manage past paper classes"
on public.past_paper_classes for all to authenticated
using (public.is_catalog_admin())
with check (public.is_catalog_admin());

-- Une annale sans salle ciblée reste visible par tous (comportement existant).
create or replace function public.can_read_past_paper(p_paper_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_catalog_admin()
    or (
      exists (
        select 1 from public.past_papers pp
        where pp.id = p_paper_id and pp.is_published
      )
      and (
        not exists (
          select 1 from public.past_paper_classes t where t.paper_id = p_paper_id
        )
        or exists (
          select 1
          from public.past_paper_classes t
          join public.class_students cs
            on cs.class_id = t.class_id
           and cs.student_id = auth.uid()
           and cs.is_active
          where t.paper_id = p_paper_id
        )
        or exists (
          select 1
          from public.past_paper_classes t
          join public.class_teachers ct
            on ct.class_id = t.class_id
           and ct.teacher_id = auth.uid()
           and ct.is_active
          where t.paper_id = p_paper_id
        )
      )
    );
$$;

revoke all on function public.can_read_past_paper(uuid) from public;
grant execute on function public.can_read_past_paper(uuid) to authenticated;

drop policy if exists "read published past papers" on public.past_papers;
create policy "read published past papers"
on public.past_papers for select to authenticated
using (public.can_read_past_paper(id));
