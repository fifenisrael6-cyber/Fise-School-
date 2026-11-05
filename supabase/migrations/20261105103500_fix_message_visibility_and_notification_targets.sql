-- Keep private-message hide-for-me state consistent in every remote refresh.
-- RLS remains enabled and the existing authenticated RPC boundary is preserved.
create or replace function public.list_private_messages(target_user_id uuid)
returns setof public.private_messages
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_since timestamptz;
  r public.private_messages%rowtype;
  v_res jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;
  if not public.can_message(target_user_id) then
    raise exception 'The teacher FISE code is required for private messaging';
  end if;

  select value_ts into v_since
  from public.quota_config
  where key = 'msg_recv_since';

  if not public.has_full_access() then
    for r in
      select m.*
      from public.private_messages m
      where m.sender_id = target_user_id
        and m.recipient_id = v_uid
        and m.created_at >= coalesce(v_since, now())
        and not (v_uid = any(coalesce(m.hidden_for, '{}'::uuid[])))
        and not public.has_active_grant('msg_recv', m.id::text)
      order by m.created_at desc
      limit 50
    loop
      v_res := public.consume_feature_quota('msg_recv', r.id::text);
      exit when not coalesce((v_res ->> 'allowed')::boolean, false);
    end loop;
  end if;

  for r in
    select m.*
    from public.private_messages m
    where (
        (m.sender_id = v_uid and m.recipient_id = target_user_id)
        or (m.sender_id = target_user_id and m.recipient_id = v_uid)
      )
      and not (v_uid = any(coalesce(m.hidden_for, '{}'::uuid[])))
    order by m.created_at
  loop
    if r.recipient_id = v_uid
       and not public.can_read_received_message(r.id, r.created_at) then
      r.body := '__PREMIUM_LOCKED__';
      r.attachment_path := null;
      r.attachment_name := null;
    end if;
    return next r;
  end loop;
  return;
end;
$function$;

-- Populate deep-link targets for notifications whose existing producer only
-- supplied a type/title/body. Existing explicit targets are never overwritten.
create or replace function public.enrich_notification_target()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_id uuid;
  v_key text;
begin
  if new.target_type is not null and new.target_id is not null then
    return new;
  end if;

  case
    when lower(coalesce(new.type, '')) in ('evaluation_new', 'evaluation_reminder', 'evaluation_receipt', 'evaluation_review', 'evaluation_result') then
      v_key := split_part(coalesce(new.body, ''), ' — ', 1);
      select e.id into v_id
      from public.evaluations e
      where left(e.title, 160) = v_key
        and (
          e.teacher_id = new.user_id
          or exists (
            select 1
            from public.evaluation_classes ec
            join public.class_students cs
              on cs.class_id = ec.class_id
             and cs.student_id = new.user_id
             and cs.is_active
            join public.teacher_access_memberships tam
              on tam.student_id = cs.student_id
             and tam.teacher_id = e.teacher_id
            where ec.evaluation_id = e.id
          )
        )
      order by e.created_at desc
      limit 1;
      if v_id is not null then
        new.target_type := 'evaluation';
        new.target_id := v_id;
      end if;

    when lower(coalesce(new.type, '')) = 'assignment' then
      select a.id into v_id
      from public.assignments a
      where coalesce(nullif(a.title_fr, ''), a.title_en, '') = new.body
        and a.status in ('published', 'closed')
        and exists (
          select 1 from public.class_students cs
          where cs.class_id = a.class_id
            and cs.student_id = new.user_id
            and cs.is_active
        )
      order by a.created_at desc
      limit 1;
      if v_id is not null then
        new.target_type := 'assignment';
        new.target_id := v_id;
      end if;

    when lower(coalesce(new.type, '')) = 'submission' then
      select a.id into v_id
      from public.assignments a
      join public.assignment_submissions s on s.assignment_id = a.id
      where a.teacher_id = new.user_id
        and coalesce(nullif(a.title_fr, ''), a.title_en, '') = new.body
        and s.status = 'submitted'
      order by s.submitted_at desc nulls last
      limit 1;
      if v_id is not null then
        new.target_type := 'assignment';
        new.target_id := v_id;
      end if;

    when lower(coalesce(new.type, '')) = 'course' then
      v_key := split_part(coalesce(new.body, ''), ' : ', 1);
      select c.id into v_id
      from public.courses c
      where c.status = 'published'
        and (
          left(c.title_fr, 160) = left(v_key, 160)
          or left(c.title_en, 160) = left(v_key, 160)
        )
        and (
          c.teacher_id = new.user_id
          or exists (
            select 1 from public.class_students cs
            where cs.class_id = c.class_id
              and cs.student_id = new.user_id
              and cs.is_active
          )
        )
      order by c.published_at desc nulls last, c.created_at desc
      limit 1;
      if v_id is not null then
        new.target_type := 'course';
        new.target_id := v_id;
      end if;

    when lower(coalesce(new.type, '')) = 'timetable' then
      select t.id into v_id
      from public.class_timetable_entries t
      where t.subject_fr = new.body
        and (
          t.teacher_id = new.user_id
          or exists (
            select 1 from public.class_students cs
            where cs.class_id = t.class_id
              and cs.student_id = new.user_id
              and cs.is_active
          )
        )
      order by t.updated_at desc
      limit 1;
      if v_id is not null then
        new.target_type := 'timetable';
        new.target_id := v_id;
      end if;

    when lower(coalesce(new.type, '')) = 'bulletin' then
      select gp.id into v_id
      from public.grade_periods gp
      where gp.label_fr = new.body
        and exists (
          select 1 from public.grades g
          where g.period_id = gp.id
            and g.student_id = new.user_id
        )
      order by gp.created_at desc
      limit 1;
      if v_id is not null then
        new.target_type := 'bulletin_period';
        new.target_id := v_id;
      end if;

    when lower(coalesce(new.type, '')) = 'message' then
      select pm.sender_id into v_id
      from public.private_messages pm
      join public.profiles p on p.id = pm.sender_id
      where pm.recipient_id = new.user_id
        and trim(concat(p.first_name, ' ', p.last_name)) = new.title
      order by pm.created_at desc
      limit 1;
      if v_id is not null then
        new.target_type := 'private_message';
        new.target_id := v_id;
      end if;
    else
      null;
  end case;

  return new;
end;
$function$;

drop trigger if exists notifications_enrich_target on public.notifications;
create trigger notifications_enrich_target
before insert or update of target_type, target_id
on public.notifications
for each row
execute function public.enrich_notification_target();

revoke all on function public.enrich_notification_target() from public, anon, authenticated;

-- Backfill target identifiers where the source can be resolved unambiguously.
update public.notifications
set target_type = target_type
where target_type is null or target_id is null;
