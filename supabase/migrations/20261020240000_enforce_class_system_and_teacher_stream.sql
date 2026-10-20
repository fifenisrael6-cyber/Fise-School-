-- Keep student and teacher memberships aligned with the actual school system.
-- Students cannot be assigned to a class from another subsystem or sector.
create or replace function public.enforce_school_membership_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_role text;
  v_profile_subsystem text;
  v_profile_sector text;
  v_class_subsystem text;
  v_class_sector text;
  v_stream text;
begin
  select role, subsystem::text, sector::text, teaching_stream
    into v_role, v_profile_subsystem, v_profile_sector, v_stream
  from public.profiles where id = case when tg_table_name = 'class_students' then new.student_id else new.teacher_id end;

  select subsystem::text, sector::text
    into v_class_subsystem, v_class_sector
  from public.school_classes where id = new.class_id;

  if v_class_subsystem is null then
    raise exception 'Classroom not found or missing subsystem';
  end if;

  if tg_table_name = 'class_students' then
    if v_role <> 'student' then raise exception 'Only students can be enrolled in student classrooms'; end if;
    if v_profile_subsystem is not null and v_profile_subsystem <> v_class_subsystem then
      raise exception 'Student cannot join a classroom from another subsystem';
    end if;
    if v_profile_sector is not null and v_profile_sector <> v_class_sector then
      raise exception 'Student cannot join a classroom from another education sector';
    end if;
  else
    if v_role <> 'teacher' then raise exception 'Only teachers can be assigned to classrooms'; end if;
    if v_profile_subsystem is not null and v_profile_subsystem <> v_class_subsystem then
      raise exception 'Teacher cannot be assigned to a classroom from another subsystem';
    end if;
    if v_stream is not null and lower(trim(v_stream)) in ('littéraire','litteraire','literary','scientifique','scientific') then
      -- Stream is a teacher's single profile attribute; prevent conflicting stream values
      -- from being stored by normalizing the field, rather than assigning two streams.
      if lower(trim(v_stream)) in ('littéraire','litteraire','literary') then
        update public.profiles set teaching_stream = 'literary'
        where id = new.teacher_id and teaching_stream is distinct from 'literary';
      elsif lower(trim(v_stream)) in ('scientifique','scientific') then
        update public.profiles set teaching_stream = 'scientific'
        where id = new.teacher_id and teaching_stream is distinct from 'scientific';
      end if;
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists enforce_class_student_scope on public.class_students;
create trigger enforce_class_student_scope
before insert or update of class_id, student_id on public.class_students
for each row execute function public.enforce_school_membership_scope();

drop trigger if exists enforce_class_teacher_scope on public.class_teachers;
create trigger enforce_class_teacher_scope
before insert or update of class_id, teacher_id on public.class_teachers
for each row execute function public.enforce_school_membership_scope();

-- A teacher may have only one declared pedagogical stream at a time.
create or replace function public.enforce_single_teacher_stream()
returns trigger
language plpgsql
set search_path = public
as $function$
declare
  v text;
begin
  if new.role = 'teacher' and new.teaching_stream is not null then
    v := lower(trim(new.teaching_stream));
    if v in ('littéraire','litteraire','literary') then new.teaching_stream := 'literary'; end if;
    if v in ('scientifique','scientific') then new.teaching_stream := 'scientific'; end if;
    if lower(trim(new.teaching_stream)) not in ('literary','scientific','general','technical','') then
      raise exception 'Choose only one teaching stream: literary or scientific';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists enforce_single_teacher_stream on public.profiles;
create trigger enforce_single_teacher_stream
before insert or update of role, teaching_stream on public.profiles
for each row execute function public.enforce_single_teacher_stream();
