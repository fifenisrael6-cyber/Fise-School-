-- Canonical teacher code: FISE-XXXXXX, shared across all of that teacher's classrooms,
-- groups, payment references and evaluation access.
-- The canonical uniqueness constraint lives in teacher_group_access_codes / teacher_payment_codes.
drop index if exists public.teacher_access_codes_code_key;

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
  if v_user is null then raise exception 'Authentication required'; end if;
  select p.role::text into v_role from public.profiles p where p.id = v_user;
  if v_role is distinct from 'teacher' then raise exception 'Only teachers can manage this code'; end if;

  v_code := translate(v_code, '‐‑‒–—−', '------');
  v_code := regexp_replace(v_code, '^FISE-?', '', 'i');
  if v_code !~ '^[A-Z0-9]{6}$' then
    raise exception 'Use the format FISE- followed by exactly six letters or numbers';
  end if;
  v_code := 'FISE-' || v_code;

  insert into public.teacher_group_access_codes(teacher_id, code, is_active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code, is_active = true, updated_at = now();

  insert into public.teacher_payment_codes(teacher_id, code, active, updated_at)
  values (v_user, v_code, true, now())
  on conflict (teacher_id) do update
    set code = excluded.code, active = true, updated_at = now();

  -- Replace obsolete per-room codes with the teacher's canonical code.
  update public.teacher_access_codes
     set code = v_code, is_active = true, updated_at = now()
   where teacher_id = v_user;

  -- Existing access remains valid after rotating the displayed code.
  update public.teacher_fise_code_memberships
     set code = v_code
   where teacher_id = v_user;

  return v_code;
exception
  when unique_violation then
    raise exception 'This FISE code is already used by another teacher';
end;
$$;
revoke all on function public.set_teacher_fise_code(text) from public, anon;
grant execute on function public.set_teacher_fise_code(text) to authenticated;

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
  select p.role::text into v_role from public.profiles p where p.id = v_user;
  if v_role is distinct from 'teacher' then raise exception 'Only teachers can manage this code'; end if;

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
      exit when not exists (select 1 from public.teacher_group_access_codes c where upper(c.code) = v_code)
            and not exists (select 1 from public.teacher_payment_codes p where upper(p.code) = v_code);
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
  update public.teacher_fise_code_memberships set code = v_code where teacher_id = v_user;
  return v_code;
exception
  when unique_violation then
    raise exception 'The shared FISE code is already assigned to another teacher';
end;
$$;
revoke all on function public.get_or_create_teacher_group_access_code() from public, anon;
grant execute on function public.get_or_create_teacher_group_access_code() to authenticated;

-- The same FISE code now authorizes group and evaluation access for the student's
-- active classroom; legacy IGPGRP / per-group invitation codes no longer work for students.
create or replace function public.join_message_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_code text;
  v_teacher_id uuid;
  v_shared_code text;
  v_student_class uuid;
  v_first_group_id uuid;
  v_access_code_id text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null then raise exception 'Profile not found'; end if;

  v_code := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));
  v_code := translate(v_code, '‐‑‒–—−', '------');
  if v_code !~ '^FISE-?[A-Z0-9]{6}$' then
    raise exception 'Use the teacher FISE code in the format FISE-XXXXXX';
  end if;
  v_code := regexp_replace(v_code, '^FISE-?', 'FISE-', 'i');

  select c.teacher_id, c.code into v_teacher_id, v_shared_code
    from public.teacher_group_access_codes c
   where upper(c.code) = v_code and c.is_active = true
   limit 1;
  if v_teacher_id is null then raise exception 'Invalid or inactive FISE code'; end if;

  if v_role = 'student' then
    select cs.class_id into v_student_class
      from public.class_students cs
     where cs.student_id = auth.uid() and cs.is_active = true
     order by cs.joined_at desc limit 1;
    if v_student_class is null then raise exception 'No active classroom is assigned to this student'; end if;

    insert into public.teacher_fise_code_memberships(student_id, teacher_id, class_id, code, joined_at)
    values (auth.uid(), v_teacher_id, v_student_class, v_shared_code, now())
    on conflict (student_id, teacher_id, class_id)
    do update set code = excluded.code, joined_at = now();

    -- The evaluation RLS path uses teacher_access_memberships. Keep it in sync
    -- with the same FISE code and the student's current classroom.
    insert into public.teacher_access_codes(id, teacher_id, code, class_id, is_active, updated_at)
    values (v_teacher_id::text || ':' || v_student_class::text, v_teacher_id, v_shared_code, v_student_class::text, true, now())
    on conflict (teacher_id, class_id)
    do update set code = excluded.code, is_active = true, updated_at = now()
    returning id into v_access_code_id;

    insert into public.teacher_access_memberships(student_id, teacher_id, class_id, access_code_id, joined_at)
    values (auth.uid(), v_teacher_id, v_student_class, v_access_code_id, now())
    on conflict (student_id, teacher_id, class_id)
    do update set access_code_id = excluded.access_code_id, joined_at = now();

    for v_group in
      select distinct g.* from public.message_groups g
       where g.owner_id = v_teacher_id
         and (g.class_id = v_student_class or exists (
           select 1 from public.message_group_classrooms gc
            where gc.group_id = g.id and gc.class_id = v_student_class
         ))
       order by g.created_at, g.id
    loop
      insert into public.message_group_members(group_id, user_id, role)
      values (v_group.id, auth.uid(), 'student')
      on conflict (group_id, user_id) do nothing;
      if v_first_group_id is null then v_first_group_id := v_group.id; end if;
    end loop;
    return v_first_group_id;
  elsif v_role = 'teacher' then
    if v_teacher_id <> auth.uid() then raise exception 'This code belongs to another teacher'; end if;
    select id into v_first_group_id from public.message_groups
     where owner_id = auth.uid() order by created_at, id limit 1;
    return v_first_group_id;
  elsif v_role = 'admin' then
    raise exception 'Administrators do not join teacher groups with student codes';
  else
    raise exception 'This account cannot join message groups';
  end if;
end;
$function$;
revoke all on function public.join_message_group(text) from public, anon;
grant execute on function public.join_message_group(text) to authenticated;

-- Privacy settings are enforced on the server, not just by hiding the composer.
create or replace function public.get_message_group_settings(p_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_message_group_member(p_group_id) then
    raise exception 'Not a member of this group';
  end if;
  return jsonb_build_object(
    'announcements_only',
    (select g.announcements_only from public.message_groups g where g.id = p_group_id)
  );
end;
$$;

create or replace function public.set_message_group_announcements_only(p_group_id uuid, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.message_groups g
     where g.id = p_group_id and g.owner_id = auth.uid()
  ) then
    raise exception 'Only the group owner can change message permissions';
  end if;
  update public.message_groups
     set announcements_only = coalesce(p_enabled, false)
   where id = p_group_id;
end;
$$;

create or replace function public.remove_message_group_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.message_groups g
     where g.id = p_group_id and g.owner_id = auth.uid()
  ) then raise exception 'Only the group owner can remove members'; end if;
  if p_user_id = auth.uid() then raise exception 'The owner cannot remove themselves; delete the group instead'; end if;
  delete from public.message_group_members
   where group_id = p_group_id and user_id = p_user_id and role = 'student';
end;
$$;

create or replace function public.leave_message_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'student') then
    raise exception 'Only students can leave a group';
  end if;
  delete from public.message_group_members
   where group_id = p_group_id and user_id = auth.uid() and role = 'student';
  if not found then raise exception 'You are not a member of this group'; end if;
end;
$$;

create or replace function public.delete_message_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.message_groups g
     where g.id = p_group_id and g.owner_id = auth.uid()
  ) then raise exception 'Only the group owner can delete this group'; end if;
  delete from public.message_groups where id = p_group_id;
end;
$$;

revoke all on function public.get_message_group_settings(uuid) from public, anon;
revoke all on function public.set_message_group_announcements_only(uuid, boolean) from public, anon;
revoke all on function public.remove_message_group_member(uuid, uuid) from public, anon;
revoke all on function public.leave_message_group(uuid) from public, anon;
revoke all on function public.delete_message_group(uuid) from public, anon;
grant execute on function public.get_message_group_settings(uuid) to authenticated;
grant execute on function public.set_message_group_announcements_only(uuid, boolean) to authenticated;
grant execute on function public.remove_message_group_member(uuid, uuid) to authenticated;
grant execute on function public.leave_message_group(uuid) to authenticated;
grant execute on function public.delete_message_group(uuid) to authenticated;

drop policy if exists "members send group messages" on public.message_group_messages;
create policy "members send group messages"
on public.message_group_messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and public.is_message_group_member(group_id)
  and (
    not exists (select 1 from public.message_groups g where g.id = group_id and g.announcements_only)
    or exists (select 1 from public.message_groups g where g.id = group_id and g.owner_id = auth.uid())
  )
);

-- Announce student joins/leaves in the group conversation so the teacher sees
-- membership changes in real time. Group deletion cascades are deliberately ignored.
create or replace function public.notify_message_group_membership_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group_id uuid;
  v_owner_id uuid;
  v_student_id uuid;
  v_student_name text;
  v_verb text;
begin
  if pg_trigger_depth() > 1 then
    if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
  end if;
  v_group_id := case when TG_OP = 'DELETE' then OLD.group_id else NEW.group_id end;
  v_student_id := case when TG_OP = 'DELETE' then OLD.user_id else NEW.user_id end;
  if (case when TG_OP = 'DELETE' then OLD.role else NEW.role end) <> 'student' then
    if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
  end if;
  select g.owner_id into v_owner_id from public.message_groups g where g.id = v_group_id;
  if v_owner_id is null then
    if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
  end if;
  select trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))
    into v_student_name from public.profiles p where p.id = v_student_id;
  v_verb := case when TG_OP = 'DELETE' then 'a quitté le groupe.' else 'a rejoint le groupe.' end;
  insert into public.message_group_messages(group_id, sender_id, body)
  values (
    v_group_id,
    v_owner_id,
    'ℹ️ ' || coalesce(nullif(trim(v_student_name), ''), 'Un élève') || ' ' || v_verb
  );
  if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
end;
$$;

drop trigger if exists message_group_membership_notifications on public.message_group_members;
create trigger message_group_membership_notifications
after insert or delete on public.message_group_members
for each row execute function public.notify_message_group_membership_change();

-- An answer to an automatic QCM/true-false question is immutable after first choice.
create or replace function public.prevent_qcm_answer_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
  v_question_type text;
begin
  select s.student_id into v_student_id
    from public.assignment_submissions s where s.id = new.submission_id;
  select q.question_type into v_question_type
    from public.assignment_questions q where q.id = new.question_id;

  if auth.uid() = v_student_id
     and v_question_type in ('qcm', 'true_false')
     and old.selected_option is not null
     and new.selected_option is distinct from old.selected_option then
    raise exception 'QCM answer is locked after the first choice';
  end if;
  return new;
end;
$$;

drop trigger if exists lock_qcm_answer_after_choice on public.assignment_answers;
create trigger lock_qcm_answer_after_choice
before update on public.assignment_answers
for each row execute function public.prevent_qcm_answer_change();

notify pgrst, 'reload schema';
