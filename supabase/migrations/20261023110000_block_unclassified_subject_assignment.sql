-- Do not let SQL NULL bypass the teacher specialty check for newly added subjects.
create or replace function public.teacher_add_class_subject(p_class_id uuid,p_subject_id uuid)
returns void language plpgsql security definer set search_path='public'
as $function$
declare v_class public.school_classes%rowtype; v_subject public.subjects%rowtype; v_pos integer; v_stream text;
begin
  if not public.teacher_can_manage_class(p_class_id,auth.uid()) then raise exception 'Teacher is not assigned to this class'; end if;
  select p.teaching_stream into v_stream from public.profiles p where p.id=auth.uid() and p.role='teacher';
  if coalesce(v_stream,'') not in ('literary','scientific') then raise exception 'Choose and save your Literary or Scientific specialty first'; end if;
  select * into v_class from public.school_classes where id=p_class_id and is_active;
  select * into v_subject from public.subjects where id=p_subject_id and is_active;
  if v_class.id is null or v_subject.id is null then raise exception 'Class or subject not found'; end if;
  if v_subject.subsystem is distinct from v_class.subsystem or v_subject.sector is distinct from v_class.sector then
    raise exception 'Subject does not match the class subsystem and sector';
  end if;
  if coalesce(v_subject.teaching_stream,'') not in ('general',v_stream) then raise exception 'Subject does not match the teacher specialty'; end if;
  select coalesce(max(position),0)+1 into v_pos from public.class_subjects where class_id=p_class_id;
  insert into public.class_subjects(class_id,subject_id,is_compulsory,option_group,position,is_active)
  values(p_class_id,p_subject_id,false,'Option',v_pos,true)
  on conflict(class_id,subject_id) do update set is_active=true;
end;
$function$;
notify pgrst,'reload schema';