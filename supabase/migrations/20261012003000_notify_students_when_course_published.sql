-- Notify students when a teacher or admin publishes a course.
-- Media are often uploaded while the course is still a draft, so the
-- resource-insert trigger alone cannot notify students in that workflow.
create or replace function public.notify_students_course_published()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_student_id uuid;
  v_course_title text;
begin
  if new.status is distinct from 'published' then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.status = 'published' then
    return new;
  end if;

  if new.class_id is null then
    return new;
  end if;

  v_course_title := coalesce(nullif(new.title_fr, ''), nullif(new.title_en, ''), 'Nouveau cours');

  for v_student_id in
    select cs.student_id
    from public.class_students cs
    where cs.class_id = new.class_id
      and cs.is_active = true
  loop
    insert into public.notifications(
      user_id, title, body, type, target_type, target_id
    )
    values (
      v_student_id,
      'Nouveau cours disponible',
      left(v_course_title || ' est disponible dans vos cours.', 500),
      'course',
      'course',
      new.id
    );
  end loop;

  return new;
end;
$function$;

drop trigger if exists courses_notify_students_on_publish on public.courses;
create trigger courses_notify_students_on_publish
after insert or update of status on public.courses
for each row
execute function public.notify_students_course_published();

revoke all on function public.notify_students_course_published() from public, anon, authenticated;
