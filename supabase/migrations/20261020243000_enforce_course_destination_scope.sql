-- Ensure every published course points to the exact subject, curriculum, chapter,
-- classroom system and subsystem selected by the teacher.
create or replace function public.enforce_course_destination_scope()
returns trigger language plpgsql security definer set search_path=public
as $function$
declare v_class public.school_classes%rowtype; v_curriculum public.curricula%rowtype;
v_subject public.subjects%rowtype; v_teacher public.profiles%rowtype;
begin
 select * into v_class from public.school_classes where id=new.class_id and is_active;
 if not found then raise exception 'Target classroom is missing or inactive'; end if;
 select * into v_teacher from public.profiles where id=new.teacher_id;
 if not found or v_teacher.role<>'teacher' then raise exception 'Only a teacher can publish a course'; end if;
 if v_teacher.subsystem is not null and v_teacher.subsystem<>v_class.subsystem then raise exception 'Course destination belongs to another subsystem'; end if;
 if v_teacher.sector is not null and v_teacher.sector<>v_class.sector then raise exception 'Course destination belongs to another sector'; end if;
 select * into v_subject from public.subjects where id=new.subject_id and is_active;
 if not found then raise exception 'Subject is missing or inactive'; end if;
 if v_subject.subsystem<>v_class.subsystem or v_subject.sector<>v_class.sector then raise exception 'Subject does not match the classroom subsystem and sector'; end if;
 select * into v_curriculum from public.curricula where id=new.curriculum_id and is_active;
 if not found then raise exception 'Curriculum is missing or inactive'; end if;
 if v_curriculum.subject_id<>new.subject_id or v_curriculum.subsystem<>v_class.subsystem or v_curriculum.sector<>v_class.sector then raise exception 'Curriculum does not match the selected subject and classroom'; end if;
 if new.chapter_id is not null and not exists(select 1 from public.course_chapters ch where ch.id=new.chapter_id and ch.curriculum_id=new.curriculum_id and ch.is_active) then raise exception 'Chapter does not belong to the selected curriculum'; end if;
 if v_teacher.teaching_stream is not null and lower(trim(v_teacher.teaching_stream)) not in ('literary','litteraire','littéraire','scientific','scientifique','general','technical','') then raise exception 'Teacher must have exactly one valid teaching stream'; end if;
 return new;
end;$function$;
drop trigger if exists enforce_course_destination_scope on public.courses;
create trigger enforce_course_destination_scope before insert or update of curriculum_id,chapter_id,subject_id,teacher_id,class_id on public.courses for each row execute function public.enforce_course_destination_scope();
