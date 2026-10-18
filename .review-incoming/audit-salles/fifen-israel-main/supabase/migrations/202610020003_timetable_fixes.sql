-- Corrections de l'emploi du temps : lecture enseignant, notifications utiles, conflits.

-- Un enseignant voit tous les créneaux qui lui sont attribués, même sans ligne class_teachers.
drop policy if exists "teachers read own timetable" on public.class_timetable_entries;
create policy "teachers read own timetable"
on public.class_timetable_entries for select to authenticated
using (teacher_id = auth.uid());

-- Pas de notification pour un créneau désactivé ni pour une modification sans effet visible.
create or replace function public.notify_timetable_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare student_id uuid; label text;
begin
  if not new.is_active then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and old.is_active
     and old.class_id = new.class_id
     and old.day_of_week = new.day_of_week
     and old.start_time = new.start_time
     and old.end_time = new.end_time
     and old.subject_fr is not distinct from new.subject_fr
     and old.teacher_id is not distinct from new.teacher_id
     and old.room is not distinct from new.room then
    return new;
  end if;
  label := case when tg_op = 'INSERT' then 'Nouvel emploi du temps' else 'Emploi du temps modifié' end;
  for student_id in
    select cs.student_id from public.class_students cs
    where cs.class_id = new.class_id and cs.is_active
  loop
    insert into public.notifications(user_id, title, body, type)
    values (student_id, label, left(coalesce(new.subject_fr, 'Un créneau a été mis à jour.'), 500), 'timetable');
  end loop;
  if new.teacher_id is not null then
    insert into public.notifications(user_id, title, body, type)
    values (new.teacher_id, label, left(coalesce(new.subject_fr, 'Un créneau a été mis à jour.'), 500), 'timetable');
  end if;
  return new;
end;
$$;

-- Un créneau inactif ne peut plus bloquer ni être bloqué.
create or replace function public.validate_class_timetable_conflict()
returns trigger
language plpgsql
as $$
begin
  if not new.is_active then
    return new;
  end if;
  if exists (
    select 1 from public.class_timetable_entries e
    where e.id <> new.id and e.is_active
      and e.day_of_week = new.day_of_week
      and e.start_time < new.end_time and new.start_time < e.end_time
      and (e.class_id = new.class_id
           or (new.teacher_id is not null and e.teacher_id = new.teacher_id)
           or (nullif(trim(new.room), '') is not null and nullif(trim(e.room), '') = nullif(trim(new.room), ''))))
  then
    raise exception 'Conflit dans l''emploi du temps: classe, enseignant ou salle déjà occupé(e) sur ce créneau.';
  end if;
  return new;
end;
$$;
