create or replace function public.private_pair_blocked(p_other_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (
  select 1 from public.private_message_blocks b
  where (b.blocker_id = (select auth.uid()) and b.blocked_id = p_other_user_id)
     or (b.blocker_id = p_other_user_id and b.blocked_id = (select auth.uid()))
); $$;
revoke all on function public.private_pair_blocked(uuid) from public;
grant execute on function public.private_pair_blocked(uuid) to authenticated;

create or replace function public.unlock_teacher_private_messages(p_code text)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_student uuid := (select auth.uid()); v_code text := trim(p_code); v_teacher uuid; v_class uuid; v_code_id text;
begin
  if v_student is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.profiles where id=v_student and role='student') then raise exception 'Only students can unlock a teacher'; end if;
  if lower(v_code) like 'fise%' then v_code := substring(v_code from 5); end if;
  select t.id,t.teacher_id,t.class_id::uuid into v_code_id,v_teacher,v_class
  from public.teacher_access_codes t
  where lower(trim(t.code))=lower(v_code) and t.is_active=true limit 1;
  if v_code_id is null then return false; end if;
  if not exists (select 1 from public.class_students cs where cs.student_id=v_student and cs.class_id=v_class and cs.is_active) then return false; end if;
  insert into public.teacher_access_memberships(student_id,teacher_id,class_id,access_code_id)
  values(v_student,v_teacher,v_class,v_code_id)
  on conflict(student_id,teacher_id,class_id) do update set access_code_id=excluded.access_code_id;
  return true;
end; $$;
revoke all on function public.unlock_teacher_private_messages(text) from public;
grant execute on function public.unlock_teacher_private_messages(text) to authenticated;

create or replace function public.can_message(target_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select (select auth.uid()) is not null
and target_user_id is not null and target_user_id <> (select auth.uid())
and not public.private_pair_blocked(target_user_id)
and exists (
  select 1 from public.profiles me join public.profiles them on them.id=target_user_id
  where me.id=(select auth.uid()) and (
    (me.role='student' and them.role='teacher' and exists(
      select 1 from public.teacher_access_memberships tam
      where tam.student_id=me.id and tam.teacher_id=them.id
      and tam.class_id in (select cs.class_id from public.class_students cs where cs.student_id=me.id and cs.is_active)
    ))
    or
    (me.role='teacher' and them.role='student' and exists(
      select 1 from public.teacher_access_memberships tam
      where tam.student_id=them.id and tam.teacher_id=me.id
      and tam.class_id in (select ct.class_id from public.class_teachers ct where ct.teacher_id=me.id and ct.is_active)
    ))
    or (me.role='admin' and them.role in ('student','teacher'))
  )
); $$;
revoke all on function public.can_message(uuid) from public;
grant execute on function public.can_message(uuid) to authenticated;

drop policy if exists "participants read private messages" on public.private_messages;
create policy "participants read private messages" on public.private_messages for select to authenticated
using ((sender_id=(select auth.uid()) or recipient_id=(select auth.uid()))
  and public.can_message(case when sender_id=(select auth.uid()) then recipient_id else sender_id end));

drop policy if exists "members send private messages" on public.private_messages;
create policy "members send private messages" on public.private_messages for insert to authenticated
with check(sender_id=(select auth.uid()) and public.can_message(recipient_id));

create or replace function public.mark_private_messages_delivered(p_sender_id uuid)
returns integer language plpgsql security definer set search_path=''
as $$ declare n integer; begin
update public.private_messages set delivered_at=coalesce(delivered_at,now())
where sender_id=p_sender_id and recipient_id=(select auth.uid()) and delivered_at is null and public.can_message(p_sender_id);
get diagnostics n=row_count; return n; end; $$;

create or replace function public.mark_private_messages_read(p_sender_id uuid)
returns integer language plpgsql security definer set search_path=''
as $$ declare n integer; begin
update public.private_messages set delivered_at=coalesce(delivered_at,now()),read_at=coalesce(read_at,now())
where sender_id=p_sender_id and recipient_id=(select auth.uid()) and read_at is null and public.can_message(p_sender_id);
get diagnostics n=row_count; return n; end; $$;

revoke all on function public.mark_private_messages_delivered(uuid) from public;
revoke all on function public.mark_private_messages_read(uuid) from public;
grant execute on function public.mark_private_messages_delivered(uuid) to authenticated;
grant execute on function public.mark_private_messages_read(uuid) to authenticated;

create or replace function public.block_private_message_user(p_user_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ begin
if p_user_id is null or p_user_id=(select auth.uid()) then raise exception 'Invalid user'; end if;
if not public.can_message(p_user_id) then raise exception 'User is not an authorized private-message contact'; end if;
insert into public.private_message_blocks(blocker_id,blocked_id) values((select auth.uid()),p_user_id) on conflict do nothing;
end; $$;
create or replace function public.unblock_private_message_user(p_user_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ begin delete from public.private_message_blocks where blocker_id=(select auth.uid()) and blocked_id=p_user_id; end; $$;
revoke all on function public.block_private_message_user(uuid) from public;
revoke all on function public.unblock_private_message_user(uuid) from public;
grant execute on function public.block_private_message_user(uuid) to authenticated;
grant execute on function public.unblock_private_message_user(uuid) to authenticated;