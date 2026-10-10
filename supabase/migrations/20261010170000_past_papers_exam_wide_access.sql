-- Annales: access is based on the exam selected, not on the teacher's followed classrooms.
-- A student can read a published paper when their profile or active class is linked
-- to the paper's exam. Teachers can still read papers they uploaded; admins retain access.

create or replace function public.can_read_past_paper(p_paper_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_catalog_admin()
    or exists (
      select 1
      from public.past_papers pp
      where pp.id = p_paper_id
        and pp.is_published
        and (
          pp.created_by = auth.uid()
          or (
            pp.exam_id is not null
            and (
              exists (
                select 1
                from public.profiles p
                where p.id = auth.uid()
                  and p.role = 'student'
                  and p.exam_id = pp.exam_id
                  and (pp.subsystem is null or p.subsystem = pp.subsystem)
              )
              or exists (
                select 1
                from public.profiles p
                join public.exam_levels el
                  on el.id = p.exam_level_id
                 and el.exam_id = pp.exam_id
                where p.id = auth.uid()
                  and p.role = 'student'
                  and (pp.subsystem is null or p.subsystem = pp.subsystem)
              )
              or exists (
                select 1
                from public.class_students cs
                join public.school_classes sc
                  on sc.id = cs.class_id
                 and sc.is_active
                join public.exam_levels el
                  on el.id = sc.exam_level_id
                 and el.exam_id = pp.exam_id
                where cs.student_id = auth.uid()
                  and cs.is_active
                  and (pp.subsystem is null or sc.subsystem = pp.subsystem)
              )
            )
          )
          -- Compatibility for older admin-created papers without an exam selection:
          -- preserve their existing class-target access instead of exposing them globally.
          or (
            pp.exam_id is null
            and exists (
              select 1
              from public.past_paper_classes t
              join public.class_students cs
                on cs.class_id = t.class_id
               and cs.student_id = auth.uid()
               and cs.is_active
              where t.paper_id = pp.id
            )
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
