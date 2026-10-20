-- Private messaging requires the same active classroom FISE membership as groups and evaluations.
create or replace function public.can_message(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and target_user_id is not null
    and target_user_id <> (select auth.uid())
    and exists (
      select 1
      from public.profiles me
      join public.profiles them on them.id = target_user_id
      where me.id = (select auth.uid())
        and (
          (me.role = 'student' and them.role = 'teacher' and exists (
            select 1
            from public.teacher_fise_code_memberships fm
            join public.class_students cs
              on cs.student_id = fm.student_id
             and cs.class_id = fm.class_id
             and cs.is_active
            where fm.student_id = me.id and fm.teacher_id = them.id
          ))
          or
          (me.role = 'teacher' and them.role = 'student' and exists (
            select 1
            from public.teacher_fise_code_memberships fm
            join public.class_students cs
              on cs.student_id = fm.student_id
             and cs.class_id = fm.class_id
             and cs.is_active
            where fm.student_id = them.id and fm.teacher_id = me.id
          ))
          or (me.role = 'admin' and them.role in ('student', 'teacher'))
        )
    );
$$;

create or replace function public.list_private_message_contacts()
returns table(id uuid, first_name text, last_name text, role text, class_name text, avatar_path text)
language sql
stable
security definer
set search_path = 'public'
as $$
  select distinct on (p.id)
    p.id, p.first_name, p.last_name, p.role,
    c.display_name as class_name, p.avatar_path
  from public.teacher_fise_code_memberships fm
  join public.class_students cs
    on cs.student_id = fm.student_id
   and cs.class_id = fm.class_id
   and cs.is_active
  join public.school_classes c on c.id = fm.class_id
  join public.profiles p
    on p.id = case
      when fm.student_id = auth.uid() then fm.teacher_id
      else fm.student_id
    end
  where fm.student_id = auth.uid() or fm.teacher_id = auth.uid()
  order by p.id, c.display_name;
$$;

create or replace function public.list_private_messages(target_user_id uuid)
returns setof public.private_messages
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_since timestamptz;
  r public.private_messages%rowtype;
  v_res jsonb;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if not public.can_message(target_user_id) then
    raise exception 'The teacher FISE code is required for private messaging';
  end if;

  select value_ts into v_since from public.quota_config where key = 'msg_recv_since';

  if not public.has_full_access() then
    for r in
      select m.* from public.private_messages m
      where m.sender_id = target_user_id and m.recipient_id = v_uid
        and m.created_at >= coalesce(v_since, now())
        and not public.has_active_grant('msg_recv', m.id::text)
      order by m.created_at desc
      limit 50
    loop
      v_res := public.consume_feature_quota('msg_recv', r.id::text);
      exit when not coalesce((v_res ->> 'allowed')::boolean, false);
    end loop;
  end if;

  for r in
    select m.* from public.private_messages m
    where (m.sender_id = v_uid and m.recipient_id = target_user_id)
       or (m.sender_id = target_user_id and m.recipient_id = v_uid)
    order by m.created_at
  loop
    if r.recipient_id = v_uid and not public.can_read_received_message(r.id, r.created_at) then
      r.body := '__PREMIUM_LOCKED__';
      r.attachment_path := null;
      r.attachment_name := null;
    end if;
    return next r;
  end loop;
  return;
end;
$function$;

drop policy if exists "participants read private messages" on public.private_messages;
create policy "participants read private messages"
on public.private_messages for select to authenticated
using (
  (sender_id = auth.uid() and public.can_message(recipient_id))
  or
  (recipient_id = auth.uid()
    and public.can_message(sender_id)
    and public.can_read_received_message(id, created_at))
);

revoke all on function public.can_message(uuid) from public, anon;
revoke all on function public.list_private_message_contacts() from public, anon;
revoke all on function public.list_private_messages(uuid) from public, anon;
grant execute on function public.can_message(uuid) to authenticated;
grant execute on function public.list_private_message_contacts() to authenticated;
grant execute on function public.list_private_messages(uuid) to authenticated;
notify pgrst, 'reload schema';
