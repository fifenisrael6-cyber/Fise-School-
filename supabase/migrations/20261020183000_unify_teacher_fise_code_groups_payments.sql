-- Keep one canonical teacher FISE code synchronized between group access and payments.
-- Existing group invitation codes remain in the database for backward compatibility.
create or replace function public.set_teacher_fise_code(p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_role text;
  v_code text := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id = v_user;

  if v_role is distinct from 'teacher' then
    raise exception 'Only teachers can manage this code';
  end if;

  v_code := translate(v_code, '‐‑‒–—−', '------');
  v_code := regexp_replace(v_code, '^FISE-?', '', 'i');
  if v_code !~ '^[A-Z0-9]{6}$' then
    raise exception 'Use the format FISE- followed by exactly six letters or numbers';
  end if;
  v_code := 'FISE-' || v_code;

  -- Update both canonical stores in the same transaction. A duplicate in either
  -- table rolls the whole operation back, so the two services cannot drift apart.
  insert into public.teacher_group_access_codes
    (teacher_id, code, is_active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code, is_active = true, updated_at = now();

  insert into public.teacher_payment_codes
    (teacher_id, code, active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code, active = true, updated_at = now();

  return v_code;
exception
  when unique_violation then
    raise exception 'This FISE code is already used by another teacher';
end;
$$;

revoke all on function public.set_teacher_fise_code(text) from public, anon;
grant execute on function public.set_teacher_fise_code(text) to authenticated;

-- Keep the automatic-code path synchronized too, including older app versions.
create or replace function public.get_or_create_teacher_group_access_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_role text;
  v_code text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;

  select p.role::text into v_role
  from public.profiles p where p.id = v_user;
  if v_role is distinct from 'teacher' then
    raise exception 'Only teachers can manage this code';
  end if;

  select c.code into v_code
  from public.teacher_group_access_codes c
  where c.teacher_id = v_user and c.is_active = true;

  if v_code is null then
    -- Prefer an existing active payment code so existing teacher-facing
    -- payment references continue to resolve to the same teacher.
    select p.code into v_code
    from public.teacher_payment_codes p
    where p.teacher_id = v_user and p.active = true;

    if v_code is null then
      loop
        v_code := 'FISE-' || upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 6));
        exit when not exists (
          select 1 from public.teacher_group_access_codes c where upper(c.code) = v_code
        ) and not exists (
          select 1 from public.teacher_payment_codes p where upper(p.code) = v_code
        );
      end loop;
    end if;

    insert into public.teacher_group_access_codes
      (teacher_id, code, is_active, updated_at)
    values (v_user, v_code, true, now())
    on conflict (teacher_id) do update
      set code = excluded.code, is_active = true, updated_at = now();
  end if;

  insert into public.teacher_payment_codes
    (teacher_id, code, active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code, active = true, updated_at = now();

  return v_code;
exception
  when unique_violation then
    raise exception 'The shared FISE code is already assigned to another teacher';
end;
$$;

revoke all on function public.get_or_create_teacher_group_access_code() from public, anon;
grant execute on function public.get_or_create_teacher_group_access_code() to authenticated;

notify pgrst, 'reload schema';
