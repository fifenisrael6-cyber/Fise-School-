-- Private messages use the same teacher-owned FISE code as groups and evaluations.
create or replace function public.unlock_teacher_private_messages(p_code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student uuid := (select auth.uid());
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  v_suffix text;
  v_teacher uuid;
  v_canonical_code text;
  v_class uuid;
  v_access_code_id text;
begin
  if v_student is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.profiles p where p.id = v_student and p.role = 'student') then
    raise exception 'Only students can unlock a teacher';
  end if;

  v_code := translate(v_code, '‐‑‒–—−', '------');
  if v_code !~ '^FISE-?[A-Z0-9]{6}$' then return false; end if;
  v_suffix := regexp_replace(v_code, '^FISE-?', '', 'i');

  select c.teacher_id, c.code
    into v_teacher, v_canonical_code
    from public.teacher_group_access_codes c
   where upper(regexp_replace(trim(c.code), '^FISE-?', '', 'i')) = v_suffix
     and c.is_active = true
   limit 1;
  if v_teacher is null then return false; end if;

  select cs.class_id into v_class
    from public.class_students cs
   where cs.student_id = v_student and cs.is_active = true
   order by cs.joined_at desc limit 1;
  if v_class is null then return false; end if;

  if not public.teacher_can_manage_class(v_class, v_teacher)
     and not exists (
       select 1 from public.message_groups g
        where g.owner_id = v_teacher
          and (g.class_id = v_class or exists (
            select 1 from public.message_group_classrooms gc
             where gc.group_id = g.id and gc.class_id = v_class
          ))
     )
     and not exists (
       select 1 from public.assignments a
        where a.teacher_id = v_teacher and a.class_id = v_class
          and a.status in ('published', 'closed')
     ) then
    return false;
  end if;

  insert into public.teacher_access_codes(id, teacher_id, code, class_id, is_active, updated_at)
  values (v_teacher::text || ':' || v_class::text, v_teacher, v_canonical_code, v_class::text, true, now())
  on conflict (teacher_id, class_id)
  do update set code = excluded.code, is_active = true, updated_at = now()
  returning id into v_access_code_id;

  insert into public.teacher_fise_code_memberships(student_id, teacher_id, class_id, code, joined_at)
  values (v_student, v_teacher, v_class, v_canonical_code, now())
  on conflict (student_id, teacher_id, class_id)
  do update set code = excluded.code, joined_at = now();

  insert into public.teacher_access_memberships(student_id, teacher_id, class_id, access_code_id, joined_at)
  values (v_student, v_teacher, v_class, v_access_code_id, now())
  on conflict (student_id, teacher_id, class_id)
  do update set access_code_id = excluded.access_code_id, joined_at = now();

  insert into public.message_group_members(group_id, user_id, role)
  select distinct g.id, v_student, 'student'
    from public.message_groups g
   where g.owner_id = v_teacher
     and (g.class_id = v_class or exists (
       select 1 from public.message_group_classrooms gc
        where gc.group_id = g.id and gc.class_id = v_class
     ))
  on conflict (group_id, user_id) do nothing;

  return true;
end;
$$;
revoke all on function public.unlock_teacher_private_messages(text) from public, anon;
grant execute on function public.unlock_teacher_private_messages(text) to authenticated;
notify pgrst, 'reload schema';
