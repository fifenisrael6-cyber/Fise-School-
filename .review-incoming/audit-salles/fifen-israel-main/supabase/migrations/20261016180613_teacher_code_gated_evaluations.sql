-- Restrict student-visible evaluations to the teachers whose unique access code they joined.
-- The evaluation must still target one of the student's active classes.

CREATE OR REPLACE FUNCTION public.evaluation_is_visible_to_student(p_evaluation uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.evaluations e
    join public.evaluation_classes ec on ec.evaluation_id = e.id
    join public.class_students cs
      on cs.class_id = ec.class_id
     and cs.student_id = auth.uid()
     and cs.is_active
    join public.teacher_access_memberships tam
      on tam.student_id = auth.uid()
     and tam.teacher_id = e.teacher_id
    where e.id = p_evaluation
      and e.status in ('published', 'closed')
  );
$function$;

-- Enforce the same teacher-code authorization when a student starts an
-- evaluation or uploads answer photos.
CREATE OR REPLACE FUNCTION public.evaluation_student_class(p_evaluation uuid, p_student uuid)
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  select ec.class_id
  from public.evaluation_classes ec
  join public.evaluations e on e.id = ec.evaluation_id
  join public.class_students cs
    on cs.class_id = ec.class_id
   and cs.student_id = p_student
   and cs.is_active
  join public.teacher_access_memberships tam
    on tam.student_id = p_student
   and tam.teacher_id = e.teacher_id
  where ec.evaluation_id = p_evaluation
    and p_student = auth.uid()
    and e.status = 'published'
  order by cs.joined_at desc
  limit 1;
$function$;

-- Private PDF access follows the same visibility rule.
CREATE OR REPLACE FUNCTION public.evaluation_paper_readable(p_path text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.evaluations e
    where e.pdf_path = p_path
      and (
        public.eval_is_admin()
        or e.teacher_id = auth.uid()
        or (
          e.status in ('published', 'closed')
          and now() >= e.starts_at
          and public.evaluation_is_visible_to_student(e.id)
        )
      )
  );
$function$;

-- Publication notifications only go to students who joined this teacher's code.
CREATE OR REPLACE FUNCTION public.evaluations_notify_published()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  if old.status = 'draft' and new.status = 'published' then
    insert into public.notifications (user_id, title, body, type)
    select distinct cs.student_id,
           'Nouvelle épreuve disponible',
           left(new.title, 160) || ' — à remettre avant le '
             || to_char(new.due_at at time zone 'Africa/Douala', 'DD/MM/YYYY "à" HH24:MI'),
           'evaluation_new'
    from public.evaluation_classes ec
    join public.class_students cs
      on cs.class_id = ec.class_id
     and cs.is_active
    join public.teacher_access_memberships tam
      on tam.student_id = cs.student_id
     and tam.teacher_id = new.teacher_id
    where ec.evaluation_id = new.id;
  end if;
  return new;
end;
$function$;

-- Deadline reminders only go to students who joined the evaluation teacher's code.
CREATE OR REPLACE FUNCTION public.send_evaluation_deadline_reminders()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_n integer;
begin
  with targets as (
    select e.id as evaluation_id, cs.student_id, k.kind
    from public.evaluations e
    cross join (values ('h24', interval '24 hours'), ('h1', interval '1 hour')) as k(kind, win)
    join public.evaluation_classes ec on ec.evaluation_id = e.id
    join public.class_students cs on cs.class_id = ec.class_id and cs.is_active
    join public.teacher_access_memberships tam
      on tam.student_id = cs.student_id
     and tam.teacher_id = e.teacher_id
    where e.status = 'published'
      and e.starts_at <= now()
      and e.due_at > now()
      and e.due_at <= now() + k.win
      and (e.due_at - e.starts_at) > k.win
      and not exists (
        select 1 from public.evaluation_submissions s
        where s.evaluation_id = e.id and s.student_id = cs.student_id and s.status = 'submitted'
      )
  ),
  ins as (
    insert into public.evaluation_reminders_sent (evaluation_id, student_id, kind)
    select distinct evaluation_id, student_id, kind from targets
    on conflict do nothing
    returning evaluation_id, student_id, kind
  ),
  notif as (
    insert into public.notifications (user_id, title, body, type)
    select ins.student_id,
           case when ins.kind = 'h1' then 'Dernière heure pour remettre' else 'Rappel : épreuve à remettre' end,
           left(e.title, 160) || ' — à remettre avant le '
             || to_char(e.due_at at time zone 'Africa/Douala', 'DD/MM/YYYY "à" HH24:MI'),
           'evaluation_reminder'
    from ins
    join public.evaluations e on e.id = ins.evaluation_id
    returning 1
  )
  select count(*) into v_n from notif;
  return coalesce(v_n, 0);
end;
$function$;
