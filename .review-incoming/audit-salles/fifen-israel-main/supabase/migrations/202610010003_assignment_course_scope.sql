-- Keep assignments attached to the exact classroom/course selected by the teacher.
-- This is the database-side counterpart of the Salle -> Cours UI.

create or replace function public.validate_assignment_context()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_course public.courses%rowtype;
begin
  select * into v_course
  from public.courses
  where id = new.course_id;

  if not found or v_course.status = 'archived' then
    raise exception 'Assignment course is not available';
  end if;

  if new.class_id is distinct from v_course.class_id then
    raise exception 'Assignment class must match the course class';
  end if;

  if new.teacher_id is distinct from v_course.teacher_id and not public.is_admin() then
    raise exception 'Assignment teacher must own the selected course';
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

revoke all on function public.validate_assignment_context() from public;
grant execute on function public.validate_assignment_context() to authenticated;

drop trigger if exists assignments_validate_context on public.assignments;
create trigger assignments_validate_context
before insert or update on public.assignments
for each row
execute function public.validate_assignment_context();
