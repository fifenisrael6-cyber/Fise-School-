-- The unique FISE code authorizes only group membership, payments and evaluations.
-- Ordinary classroom publications remain governed by classroom membership.

create table if not exists public.teacher_fise_code_memberships (
  student_id uuid not null references public.profiles(id) on delete cascade,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.school_classes(id) on delete cascade,
  code text not null check (code ~ '^FISE-[A-Z0-9]{6}$'),
  joined_at timestamptz not null default now(),
  primary key (student_id, teacher_id, class_id)
);
create index if not exists teacher_fise_code_memberships_teacher_class_idx
  on public.teacher_fise_code_memberships (teacher_id, class_id);
alter table public.teacher_fise_code_memberships enable row level security;
revoke all on table public.teacher_fise_code_memberships from public, anon, authenticated;

-- Preserve access for existing students who already joined a teacher's groups.
insert into public.teacher_fise_code_memberships (student_id, teacher_id, class_id, code)
select distinct gm.user_id, g.owner_id, cs.class_id, tac.code
from public.message_group_members gm
join public.message_groups g on g.id = gm.group_id
join public.teacher_group_access_codes tac on tac.teacher_id = g.owner_id and tac.is_active = true
join public.class_students cs
  on cs.student_id = gm.user_id and cs.is_active
 and (cs.class_id = g.class_id or exists (
   select 1 from public.message_group_classrooms gc
   where gc.group_id = g.id and gc.class_id = cs.class_id
 ))
join public.profiles student_profile on student_profile.id = gm.user_id and student_profile.role = 'student'
where gm.role = 'student'
on conflict (student_id, teacher_id, class_id) do nothing;

create or replace function public.evaluation_is_visible_to_student(p_evaluation uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.evaluations e
    join public.evaluation_classes ec on ec.evaluation_id = e.id
    join public.class_students cs on cs.class_id = ec.class_id
      and cs.student_id = auth.uid() and cs.is_active
    join public.teacher_fise_code_memberships fm on fm.student_id = cs.student_id
      and fm.teacher_id = e.teacher_id and fm.class_id = ec.class_id
    where e.id = p_evaluation and e.status in ('published', 'closed')
  );
$$;

create or replace function public.evaluation_student_class(p_evaluation uuid, p_student uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select ec.class_id
  from public.evaluation_classes ec
  join public.evaluations e on e.id = ec.evaluation_id
  join public.class_students cs on cs.class_id = ec.class_id
    and cs.student_id = p_student and cs.is_active
  join public.teacher_fise_code_memberships fm on fm.student_id = p_student
    and fm.teacher_id = e.teacher_id and fm.class_id = ec.class_id
  where ec.evaluation_id = p_evaluation and p_student = auth.uid() and e.status = 'published'
  order by cs.joined_at desc limit 1;
$$;

create or replace function public.list_my_evaluations()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_rows jsonb;
begin
  if v_uid is null then raise exception 'Session requise.'; end if;
  select coalesce(jsonb_agg(x.item order by x.due_at desc), '[]'::jsonb) into v_rows
  from (
    select e.due_at,
      jsonb_build_object(
        'id', e.id, 'title', e.title, 'instructions', e.instructions,
        'subject_name_fr', sj.name_fr, 'subject_name_en', sj.name_en,
        'starts_at', e.starts_at, 'due_at', e.due_at, 'duration_minutes', e.duration_minutes,
        'late_policy', e.late_policy, 'late_grace_minutes', e.late_grace_minutes,
        'late_penalty_percent', e.late_penalty_percent, 'max_score', e.max_score,
        'status', e.status, 'pdf_name', e.pdf_name,
        'pdf_path', case when now() >= e.starts_at then e.pdf_path else null end,
        'submission', (
          select jsonb_build_object('id', s.id, 'status', s.status, 'submitted_at', s.submitted_at,
            'is_late', s.is_late, 'late_minutes', s.late_minutes, 'photo_count', s.photo_count)
          from public.evaluation_submissions s
          where s.evaluation_id = e.id and s.student_id = v_uid
        ),
        'result', (
          select jsonb_build_object(
            'final_score', es.final_score, 'max_score', es.max_score,
            'penalty_percent', es.penalty_percent, 'comment', es.teacher_comment,
            'questions', coalesce((
              select jsonb_agg(jsonb_build_object(
                'label', coalesce(r.question_label, 'Question ' || r.question_key),
                'points', coalesce(r.final_points, r.ai_points), 'max_points', r.max_points,
                'feedback', coalesce(r.teacher_comment, r.feedback_fr)
              ) order by r.question_key)
              from public.evaluation_question_results r where r.submission_id = es.submission_id
            ), '[]'::jsonb)
          )
          from public.evaluation_scores es
          where es.student_id = v_uid and es.evaluation_id = e.id
            and public.evaluation_result_released(es.submission_id)
        )
      ) as item
    from public.evaluations e
    join public.subjects sj on sj.id = e.subject_id
    where e.status in ('published', 'closed')
      and exists (select 1 from public.evaluation_classes ec
        where ec.evaluation_id = e.id and public.is_student_in_class(ec.class_id, v_uid))
      and public.evaluation_is_visible_to_student(e.id)
  ) x;
  return jsonb_build_object('server_now', now(), 'evaluations', v_rows);
end;
$$;

create or replace function public.join_message_group(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_group public.message_groups%rowtype;
  v_role text;
  v_code text;
  v_teacher_id uuid;
  v_shared_code text;
  v_student_class uuid;
  v_first_group_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null then raise exception 'Profile not found'; end if;
  v_code := upper(regexp_replace(trim(coalesce(p_code, '')), '[[:space:]]+', '', 'g'));

  if v_code ~ '^(FISE|GPR|GRP)-?[A-Z0-9]{6}$' then
    v_code := regexp_replace(v_code, '^(FISE|GPR|GRP)-?', '');
    select c.teacher_id, c.code into v_teacher_id, v_shared_code
    from public.teacher_group_access_codes c
    where upper(regexp_replace(c.code, '^FISE-', '')) = v_code and c.is_active = true
    limit 1;
    if v_teacher_id is not null then
      if v_role = 'student' then
        select cs.class_id into v_student_class from public.class_students cs
        where cs.student_id = auth.uid() and cs.is_active = true
        order by cs.joined_at desc limit 1;
        if v_student_class is null then raise exception 'No active classroom is assigned to this student'; end if;

        insert into public.teacher_fise_code_memberships (student_id, teacher_id, class_id, code, joined_at)
        values (auth.uid(), v_teacher_id, v_student_class, v_shared_code, now())
        on conflict (student_id, teacher_id, class_id)
        do update set code = excluded.code, joined_at = now();

        for v_group in
          select distinct g.* from public.message_groups g
          where g.owner_id = v_teacher_id and (
            g.class_id = v_student_class or exists (
              select 1 from public.message_group_classrooms gc
              where gc.group_id = g.id and gc.class_id = v_student_class
            )
          ) order by g.created_at, g.id
        loop
          insert into public.message_group_members(group_id, user_id, role)
          values (v_group.id, auth.uid(), 'student') on conflict (group_id, user_id) do nothing;
          if v_first_group_id is null then v_first_group_id := v_group.id; end if;
        end loop;
        return v_first_group_id;
      elsif v_role = 'teacher' then
        if v_teacher_id <> auth.uid() then raise exception 'This code belongs to another teacher'; end if;
        select id into v_first_group_id from public.message_groups where owner_id = auth.uid()
        order by created_at, id limit 1;
        return v_first_group_id;
      elsif v_role <> 'admin' then
        raise exception 'This account cannot join message groups';
      end if;
    end if;
  end if;

  -- Legacy per-group invitation codes remain supported, but do not authorize evaluations.
  select * into v_group from public.message_groups g
  where upper(regexp_replace(g.invite_code, '^(FISE|GPR|GRP)[ -]*', '', 'i')) =
        upper(regexp_replace(trim(coalesce(p_code, '')), '^(FISE|GPR|GRP)[ -]*', '', 'i'))
  limit 1;
  if not found then raise exception 'Invalid invitation code'; end if;
  if v_role = 'student' and not (
    (v_group.class_id is not null and public.is_student_in_class(v_group.class_id, auth.uid()))
    or exists (select 1 from public.message_group_classrooms gc
      where gc.group_id = v_group.id and public.is_student_in_class(gc.class_id, auth.uid()))
  ) then raise exception 'This group is not assigned to your classroom'; end if;
  insert into public.message_group_members(group_id, user_id, role)
  values (v_group.id, auth.uid(), case when v_role = 'student' then 'student' else 'teacher' end)
  on conflict (group_id, user_id) do nothing;
  return v_group.id;
end;
$$;

revoke all on function public.evaluation_is_visible_to_student(uuid) from public, anon;
grant execute on function public.evaluation_is_visible_to_student(uuid) to authenticated;
revoke all on function public.evaluation_student_class(uuid, uuid) from public, anon;
grant execute on function public.evaluation_student_class(uuid, uuid) to authenticated;
revoke all on function public.list_my_evaluations() from public, anon;
grant execute on function public.list_my_evaluations() to authenticated;
revoke all on function public.join_message_group(text) from public, anon;
grant execute on function public.join_message_group(text) to authenticated;
notify pgrst, 'reload schema';
