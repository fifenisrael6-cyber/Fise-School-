-- Repair legacy students who are already members of a teacher's group but
-- are missing the canonical FISE membership used by evaluations and private chat.
-- Only backfill when the student still has an active enrollment in that exact
-- classroom and the group belongs to the same teacher/classroom.
insert into public.teacher_fise_code_memberships
  (student_id, teacher_id, class_id, code, joined_at)
select distinct
  gm.user_id,
  g.owner_id,
  cs.class_id,
  tac.code,
  least(gm.joined_at, now())
from public.message_group_members gm
join public.message_groups g
  on g.id = gm.group_id
join public.profiles student
  on student.id = gm.user_id
 and student.role = 'student'
join public.class_students cs
  on cs.student_id = gm.user_id
 and cs.is_active = true
join public.teacher_group_access_codes tac
  on tac.teacher_id = g.owner_id
 and tac.is_active = true
where (
    g.class_id = cs.class_id
    or exists (
      select 1
      from public.message_group_classrooms gc
      where gc.group_id = g.id
        and gc.class_id = cs.class_id
    )
  )
on conflict (student_id, teacher_id, class_id)
do update set
  code = excluded.code,
  joined_at = coalesce(public.teacher_fise_code_memberships.joined_at, excluded.joined_at);

-- Keep the teacher's private-message contact list and published evaluation
-- access consistent for students who were already in a group before the
-- canonical FISE membership was repaired.
notify pgrst, 'reload schema';
