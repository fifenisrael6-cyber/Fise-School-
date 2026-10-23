-- Restore access to common curriculum subjects when a teacher has not yet saved
-- a literary/scientific specialty. Stream-specific subjects remain restricted.
create or replace function public.list_teacher_class_subjects(p_class_id uuid)
returns table(subject_id uuid,is_compulsory boolean,option_group text,"position" integer,subjects jsonb)
language sql stable security definer set search_path='public'
as $function$
select cs.subject_id,cs.is_compulsory,cs.option_group,cs.position,to_jsonb(s)
from public.class_subjects cs
join public.school_classes c on c.id=cs.class_id
join public.subjects s on s.id=cs.subject_id
where cs.class_id=p_class_id and cs.is_active and c.is_active
and (public.is_admin() or public.is_teacher_assigned(c.id,auth.uid()) or exists(
  select 1 from public.profiles p where p.id=auth.uid() and p.role='teacher' and p.subsystem=c.subsystem and p.sector=c.sector))
and (not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='teacher')
  or public.is_admin()
  or exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='teacher'
    and (
      s.teaching_stream='general'
      or (p.teaching_stream in ('literary','scientific') and s.teaching_stream=p.teaching_stream)
    )))
order by cs.position,s.name_fr;
$function$;

create or replace function public.list_class_addable_subjects(p_class_id uuid)
returns setof public.subjects language plpgsql stable security definer set search_path='public'
as $function$
declare v_stream text; v_class public.school_classes%rowtype;
begin
  if not public.teacher_can_manage_class(p_class_id,auth.uid()) then
    raise exception 'Teacher is not assigned to this class';
  end if;
  select * into v_class from public.school_classes where id=p_class_id and is_active;
  if v_class.id is null then raise exception 'Class not found or inactive'; end if;
  select p.teaching_stream into v_stream from public.profiles p where p.id=auth.uid() and p.role='teacher';
  return query
    select s.* from public.subjects s
    where s.is_active
      and s.subsystem=v_class.subsystem and s.sector=v_class.sector
      and (
        s.teaching_stream='general'
        or (v_stream in ('literary','scientific') and s.teaching_stream=v_stream)
      )
      and not exists(select 1 from public.class_subjects cs where cs.class_id=p_class_id and cs.subject_id=s.id and cs.is_active)
    order by s.name_fr;
end;
$function$;

create or replace function public.teacher_add_class_subject(p_class_id uuid,p_subject_id uuid)
returns void language plpgsql security definer set search_path='public'
as $function$
declare v_class public.school_classes%rowtype; v_subject public.subjects%rowtype; v_pos integer; v_stream text;
begin
  if not public.teacher_can_manage_class(p_class_id,auth.uid()) then
    raise exception 'Teacher is not assigned to this class';
  end if;
  select * into v_class from public.school_classes where id=p_class_id and is_active;
  select * into v_subject from public.subjects where id=p_subject_id and is_active;
  if v_class.id is null or v_subject.id is null then raise exception 'Class or subject not found'; end if;
  if v_subject.subsystem is distinct from v_class.subsystem or v_subject.sector is distinct from v_class.sector then
    raise exception 'Subject does not match the class subsystem and sector';
  end if;
  select p.teaching_stream into v_stream from public.profiles p where p.id=auth.uid() and p.role='teacher';
  if v_subject.teaching_stream <> 'general'
    and (v_stream not in ('literary','scientific') or v_subject.teaching_stream is distinct from v_stream) then
    raise exception 'Save your Literary or Scientific specialty before adding a specialty-specific subject';
  end if;
  select coalesce(max(position),0)+1 into v_pos from public.class_subjects where class_id=p_class_id;
  insert into public.class_subjects(class_id,subject_id,is_compulsory,option_group,position,is_active)
  values(p_class_id,p_subject_id,false,'Option',v_pos,true)
  on conflict(class_id,subject_id) do update set is_active=true;
end;
$function$;
notify pgrst,'reload schema';
