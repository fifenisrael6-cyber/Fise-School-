-- Add safe per-notification destinations and allow users to delete only their own notifications.
alter table public.notifications
  add column if not exists target_type text,
  add column if not exists target_id uuid;

create index if not exists notifications_target_idx
  on public.notifications (user_id, target_type, target_id)
  where target_id is not null;

drop policy if exists "users delete own notifications" on public.notifications;
create policy "users delete own notifications"
  on public.notifications for delete to authenticated
  using (user_id = auth.uid());

create or replace function public.notify_course_resource_added()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_class_id uuid;
  v_course_status text;
  v_course_title text;
  v_resource_label text;
  v_student_id uuid;
begin
  select c.class_id, c.status,
         coalesce(nullif(c.title_fr, ''), nullif(c.title_en, ''), 'Nouveau cours')
    into v_class_id, v_course_status, v_course_title
  from public.courses c
  where c.id = new.course_id;

  if not found or v_course_status is distinct from 'published' or v_class_id is null then
    return new;
  end if;

  v_resource_label := case
    when lower(coalesce(new.mime_type, '')) = 'application/pdf'
      or lower(coalesce(new.file_extension, '')) = 'pdf' then 'PDF'
    when lower(coalesce(new.mime_type, '')) like 'image/%' then 'photo'
    when lower(coalesce(new.mime_type, '')) like 'video/%' then 'vidéo'
    when lower(coalesce(new.mime_type, '')) like 'audio/%'
      or lower(coalesce(new.resource_type, '')) = 'audio' then 'audio'
    when lower(coalesce(new.resource_type, '')) like '%qcm%' then 'QCM'
    else 'document'
  end;

  for v_student_id in
    select cs.student_id
    from public.class_students cs
    where cs.class_id = v_class_id and cs.is_active = true
  loop
    insert into public.notifications(user_id, title, body, type, target_type, target_id)
    values (
      v_student_id,
      'Nouveau contenu de cours',
      left(v_course_title || ' : ' || v_resource_label || ' ajouté — ' ||
        coalesce(nullif(new.title_fr, ''), nullif(new.title_en, ''),
                 nullif(new.file_name, ''), 'ouvre le cours pour le consulter'), 500),
      'course',
      'course',
      new.course_id
    );
  end loop;

  return new;
end;
$function$;

revoke all on function public.notify_course_resource_added() from public;
revoke all on function public.notify_course_resource_added() from anon, authenticated;
