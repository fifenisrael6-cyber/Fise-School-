-- SQL NULL must not bypass specialty checks. Block code retrieval/rotation and
-- subject assignment if a teacher has not saved Literary or Scientific.
create or replace function public.get_or_create_teacher_group_access_code()
returns text language plpgsql security definer set search_path=''
as $function$
declare
  v_user uuid := (select auth.uid()); v_role text; v_specialty text; v_code text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select p.role,lower(trim(coalesce(nullif(p.teacher_specialty,''),p.teaching_stream,'')))
    into v_role,v_specialty from public.profiles p where p.id=v_user;
  if v_role is distinct from 'teacher' then raise exception 'Only teachers can manage this code'; end if;
  if coalesce(v_specialty,'') not in ('literary','litteraire','littéraire','scientific','scientifique') then
    raise exception 'Choose and save your Literary or Scientific specialty before accessing the FISE code';
  end if;
  select c.code into v_code from public.teacher_group_access_codes c where c.teacher_id=v_user and c.is_active=true;
  if v_code is null then select p.code into v_code from public.teacher_payment_codes p where p.teacher_id=v_user and p.active=true; end if;
  if v_code is null then
    loop
      v_code:='FISE-'||upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,6));
      exit when not exists(select 1 from public.teacher_group_access_codes c where upper(c.code)=v_code)
        and not exists(select 1 from public.teacher_payment_codes p where upper(p.code)=v_code);
    end loop;
  end if;
  insert into public.teacher_group_access_codes(teacher_id,code,is_active,updated_at) values(v_user,v_code,true,now())
    on conflict(teacher_id) do update set code=excluded.code,is_active=true,updated_at=now();
  insert into public.teacher_payment_codes(teacher_id,code,active,updated_at) values(v_user,v_code,true,now())
    on conflict(teacher_id) do update set code=excluded.code,active=true,updated_at=now();
  update public.teacher_access_codes set code=v_code,is_active=true,updated_at=now() where teacher_id=v_user;
  update public.teacher_fise_code_memberships set code=v_code where teacher_id=v_user;
  return v_code;
exception when unique_violation then raise exception 'The shared FISE code is already assigned to another teacher';
end;
$function$;
revoke all on function public.get_or_create_teacher_group_access_code() from public,anon;
grant execute on function public.get_or_create_teacher_group_access_code() to authenticated;

create or replace function public.set_teacher_fise_code(p_code text)
returns text language plpgsql security definer set search_path=''
as $function$
declare
  v_user uuid := (select auth.uid()); v_role text; v_specialty text;
  v_code text := upper(regexp_replace(trim(coalesce(p_code,'')),'[[:space:]]+','','g'));
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select p.role,lower(trim(coalesce(nullif(p.teacher_specialty,''),p.teaching_stream,'')))
    into v_role,v_specialty from public.profiles p where p.id=v_user;
  if v_role is distinct from 'teacher' then raise exception 'Only teachers can manage this code'; end if;
  if coalesce(v_specialty,'') not in ('literary','litteraire','littéraire','scientific','scientifique') then
    raise exception 'Choose and save your Literary or Scientific specialty before changing the FISE code';
  end if;
  v_code:=translate(v_code,'‐‑‒–—−','------');
  v_code:=regexp_replace(v_code,'^FISE-?','','i');
  if v_code !~ '^[A-Z0-9]{6}$' then raise exception 'Use the format FISE- followed by exactly six letters or numbers'; end if;
  v_code:='FISE-'||v_code;
  insert into public.teacher_group_access_codes(teacher_id,code,is_active,updated_at) values(v_user,v_code,true,now())
    on conflict(teacher_id) do update set code=excluded.code,is_active=true,updated_at=now();
  insert into public.teacher_payment_codes(teacher_id,code,active,updated_at) values(v_user,v_code,true,now())
    on conflict(teacher_id) do update set code=excluded.code,active=true,updated_at=now();
  update public.teacher_access_codes set code=v_code,is_active=true,updated_at=now() where teacher_id=v_user;
  update public.teacher_fise_code_memberships set code=v_code where teacher_id=v_user;
  return v_code;
exception when unique_violation then raise exception 'This FISE code is already used by another teacher';
end;
$function$;
revoke all on function public.set_teacher_fise_code(text) from public,anon;
grant execute on function public.set_teacher_fise_code(text) to authenticated;

create or replace function public.list_class_addable_subjects(p_class_id uuid)
returns setof public.subjects language plpgsql stable security definer set search_path='public'
as $function$
declare v_stream text;
begin
  if not public.teacher_can_manage_class(p_class_id,auth.uid()) then raise exception 'Teacher is not assigned to this class'; end if;
  select p.teaching_stream into v_stream from public.profiles p where p.id=auth.uid() and p.role='teacher';
  if coalesce(v_stream,'') not in ('literary','scientific') then raise exception 'Choose and save your Literary or Scientific specialty first'; end if;
  return query select s.* from public.subjects s join public.school_classes c on c.id=p_class_id
  where s.is_active and s.subsystem=c.subsystem and s.sector=c.sector and s.teaching_stream in ('general',v_stream)
  and not exists(select 1 from public.class_subjects cs where cs.class_id=p_class_id and cs.subject_id=s.id and cs.is_active)
  order by s.name_fr;
end;
$function$;

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
  if v_subject.teaching_stream not in ('general',v_stream) then raise exception 'Subject does not match the teacher specialty'; end if;
  select coalesce(max(position),0)+1 into v_pos from public.class_subjects where class_id=p_class_id;
  insert into public.class_subjects(class_id,subject_id,is_compulsory,option_group,position,is_active)
  values(p_class_id,p_subject_id,false,'Option',v_pos,true)
  on conflict(class_id,subject_id) do update set is_active=true;
end;
$function$;
notify pgrst,'reload schema';