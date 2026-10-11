-- Notifications pour les nouvelles ressources de cours.
-- Cette migration est appliquée à Supabase et conservée dans le dépôt.
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
  select c.class_id, c.status, coalesce(nullif(c.title_fr, ''), nullif(c.title_en, ''), 'Nouveau cours')
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
    when lower(coalesce(new.resource_type, '')) like '%qcm%' then 'QCM'
    else 'document'
  end;

  for v_student_id in
    select cs.student_id
    from public.class_students cs
    where cs.class_id = v_class_id and cs.is_active = true
  loop
    insert into public.notifications(user_id, title, body, type)
    values (
      v_student_id,
      'Nouveau contenu de cours',
      left(v_course_title || ' : ' || v_resource_label || ' ajouté — ' ||
        coalesce(nullif(new.title_fr, ''), nullif(new.title_en, ''),
                 nullif(new.file_name, ''), 'ouvre le cours pour le consulter'), 500),
      'course'
    );
  end loop;

  return new;
end;
$function$;

drop trigger if exists course_resource_added_notification on public.course_resources;
create trigger course_resource_added_notification
after insert on public.course_resources
for each row execute function public.notify_course_resource_added();

revoke all on function public.notify_course_resource_added() from public;
revoke all on function public.notify_course_resource_added() from anon, authenticated;
