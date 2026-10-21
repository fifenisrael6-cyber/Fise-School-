-- Avoid storage RLS policies querying the protected FISE membership table directly.
-- Security-definer helpers keep membership rows private while evaluating access safely.
create or replace function public.student_has_active_teacher_membership(p_teacher_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.teacher_fise_code_memberships fm
      join public.class_students cs
        on cs.student_id = fm.student_id
       and cs.class_id = fm.class_id
       and cs.is_active = true
      where fm.student_id = (select auth.uid())
        and fm.teacher_id = p_teacher_id
    );
$function$;

revoke all on function public.student_has_active_teacher_membership(uuid) from public, anon;
grant execute on function public.student_has_active_teacher_membership(uuid) to authenticated;

create or replace function public.can_read_group_attachment(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.message_group_messages m
      join public.message_groups g on g.id = m.group_id
      left join public.message_group_members gm
        on gm.group_id = m.group_id and gm.user_id = (select auth.uid())
      where m.attachment_path = p_object_name
        and m.group_id = split_part(p_object_name, '/', 1)::uuid
        and m.deleted_at is null
        and (not m.view_once or m.sender_id = (select auth.uid()))
        and (
          g.owner_id = (select auth.uid())
          or (
            gm.user_id = (select auth.uid())
            and m.created_at >= gm.joined_at
          )
          or exists (
            select 1
            from public.teacher_fise_code_memberships fm
            join public.class_students cs
              on cs.student_id = fm.student_id
             and cs.class_id = fm.class_id
             and cs.is_active = true
            where fm.student_id = (select auth.uid())
              and fm.teacher_id = g.owner_id
              and m.created_at >= fm.joined_at
              and m.created_at >= coalesce(gm.joined_at, fm.joined_at)
              and (
                fm.class_id = g.class_id
                or exists (
                  select 1 from public.message_group_classrooms gc
                  where gc.group_id = g.id and gc.class_id = fm.class_id
                )
              )
          )
        )
    );
$function$;

revoke all on function public.can_read_group_attachment(text) from public, anon;
grant execute on function public.can_read_group_attachment(text) to authenticated;

drop policy if exists "group members read attachments since joining" on storage.objects;
create policy "group members read attachments since joining"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'group-message-attachments'
  and public.can_read_group_attachment(name)
);

drop policy if exists "authorized users read scheduled exam files" on storage.objects;
create policy "authorized users read scheduled exam files"
on storage.objects
for select
to public
using (
  bucket_id = 'assignment-files'
  and exists (
    select 1
    from public.assignments a
    where a.evaluation_file_path = objects.name
      and (
        public.is_catalog_admin()
        or a.teacher_id = (select auth.uid())
        or (
          a.status in ('published', 'closed')
          and public.is_student_in_class(a.class_id, (select auth.uid()))
          and (a.starts_at is null or statement_timestamp() >= a.starts_at)
          and (a.due_at is null or statement_timestamp() < a.due_at)
          and (
            not exists (
              select 1 from public.profiles teacher_profile
              where teacher_profile.id = a.teacher_id
                and teacher_profile.role = 'teacher'
            )
            or public.student_has_active_teacher_membership(a.teacher_id)
          )
        )
      )
  )
);
