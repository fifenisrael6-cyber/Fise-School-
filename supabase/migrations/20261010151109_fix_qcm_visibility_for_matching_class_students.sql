-- Allow published QCMs attached to a generic level room to reach students
-- enrolled in a matching specific room, without leaking unrelated subjects.
create or replace function public.student_can_access_assignment(
  target_assignment_id uuid,
  target_student_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select target_student_id = auth.uid()
    and exists (
      select 1
      from public.assignments a
      join public.school_classes target_class on target_class.id = a.class_id
      left join public.courses course on course.id = a.course_id
      where a.id = target_assignment_id
        and a.status in ('published', 'closed')
        and (
          exists (
            select 1
            from public.class_students exact_membership
            where exact_membership.class_id = a.class_id
              and exact_membership.student_id = target_student_id
              and exact_membership.is_active
          )
          or (
            target_class.series_id is null
            and target_class.specialty_id is null
            and target_class.exam_level_id is not null
            and coalesce(a.subject_id, course.subject_id) is not null
            and exists (
              select 1
              from public.class_students membership
              join public.school_classes enrolled_class
                on enrolled_class.id = membership.class_id
              where membership.student_id = target_student_id
                and membership.is_active
                and enrolled_class.exam_level_id = target_class.exam_level_id
                and enrolled_class.subsystem = target_class.subsystem
                and enrolled_class.sector = target_class.sector
                and exists (
                  select 1
                  from public.class_subjects cs
                  where cs.class_id = enrolled_class.id
                    and cs.subject_id = coalesce(a.subject_id, course.subject_id)
                    and cs.is_active
                )
            )
          )
        )
    );
$function$;

revoke all on function public.student_can_access_assignment(uuid, uuid) from public, anon;
grant execute on function public.student_can_access_assignment(uuid, uuid) to authenticated;

create or replace function public.can_read_assignment(target_assignment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select public.owns_assignment(target_assignment_id)
      or public.student_can_access_assignment(target_assignment_id, auth.uid());
$function$;

drop policy if exists "students read published class assignments" on public.assignments;
create policy "students read published class assignments"
  on public.assignments
  for select
  to authenticated
  using (
    status in ('published', 'closed')
    and public.student_can_access_assignment(id, auth.uid())
  );
