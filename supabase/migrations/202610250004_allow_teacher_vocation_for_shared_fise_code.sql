-- The teacher code screen saves teacher_vocation; accept that canonical field
-- when checking that a teacher has selected Scientific or Literary.
create or replace function public.get_or_create_teacher_group_access_code()
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := (select auth.uid());
  v_role text;
  v_specialty text;
  v_code text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;

  select p.role,
         lower(trim(coalesce(nullif(p.teacher_vocation, ''),
                             nullif(p.teacher_specialty, ''),
                             nullif(p.teaching_stream, ''))))
    into v_role, v_specialty
  from public.profiles p
  where p.id = v_user;

  if v_role is distinct from 'teacher' then
    raise exception 'Only teachers can manage this code';
  end if;

  if v_specialty in ('scientifique', 'scientifique ') then
    v_specialty := 'scientific';
  elsif v_specialty in ('litteraire', 'littéraire') then
    v_specialty := 'literary';
  end if;

  if coalesce(v_specialty, '') not in ('literary', 'scientific') then
    raise exception 'Choose and save your Literary or Scientific specialty before accessing the FISE code';
  end if;

  select c.code into v_code
  from public.teacher_group_access_codes c
  where c.teacher_id = v_user and c.is_active = true;

  if v_code is null then
    select p.code into v_code
    from public.teacher_payment_codes p
    where p.teacher_id = v_user and p.active = true;
  end if;

  if v_code is null then
    loop
      v_code := 'FISE-' || upper(substr(encode(extensions.gen_random_bytes(8), 'hex'), 1, 6));
      exit when not exists (
        select 1 from public.teacher_group_access_codes c where upper(c.code) = v_code
      ) and not exists (
        select 1 from public.teacher_payment_codes p where upper(p.code) = v_code
      );
    end loop;
  end if;

  insert into public.teacher_group_access_codes(teacher_id, code, is_active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code, is_active = true, updated_at = now();

  insert into public.teacher_payment_codes(teacher_id, code, active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code, active = true, updated_at = now();

  update public.teacher_access_codes
  set code = v_code, is_active = true, updated_at = now()
  where teacher_id = v_user;

  update public.teacher_fise_code_memberships
  set code = v_code
  where teacher_id = v_user;

  return v_code;
exception
  when unique_violation then
    raise exception 'The shared FISE code is already assigned to another teacher';
end;
$function$;

revoke all on function public.get_or_create_teacher_group_access_code() from public, anon;
grant execute on function public.get_or_create_teacher_group_access_code() to authenticated;
notify pgrst, 'reload schema';
