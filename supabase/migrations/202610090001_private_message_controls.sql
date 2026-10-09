-- Fise School: sécurisation de la liste des contacts privés et suppression contrôlée.
-- Les groupes et leurs pièces jointes restent protégés par les règles RLS existantes.

create or replace function public.list_private_message_contacts()
returns table (id uuid, first_name text, last_name text, role text, class_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct on (p.id)
    p.id, p.first_name, p.last_name, p.role, c.display_name as class_name
  from public.class_students cs
  join public.class_teachers ct on ct.class_id = cs.class_id
  join public.school_classes c on c.id = cs.class_id
  join public.profiles p
    on p.id = case when cs.student_id = (select auth.uid())
                   then ct.teacher_id else cs.student_id end
  where cs.is_active and ct.is_active
    and (cs.student_id = (select auth.uid()) or ct.teacher_id = (select auth.uid()))
    and public.can_message(p.id)
  order by p.id, c.display_name;
$$;

revoke all on function public.list_private_message_contacts() from public;
grant execute on function public.list_private_message_contacts() to authenticated;

create or replace function public.list_private_messages(target_user_id uuid)
returns setof public.private_messages
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;
  if target_user_id is null or not public.can_message(target_user_id) then
    raise exception 'Private messaging is not allowed for this contact';
  end if;

  return query
  select m.*
  from public.private_messages m
  where (m.sender_id = (select auth.uid()) and m.recipient_id = target_user_id)
     or (m.sender_id = target_user_id and m.recipient_id = (select auth.uid()))
  order by m.created_at;
end;
$$;

revoke all on function public.list_private_messages(uuid) from public;
grant execute on function public.list_private_messages(uuid) to authenticated;

create or replace function public.delete_private_message(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  -- Un utilisateur ne peut supprimer que les messages qu'il a envoyés.
  delete from public.private_messages
  where id = p_message_id and sender_id = (select auth.uid());

  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'Message not found or not owned by current user';
  end if;
end;
$$;

revoke all on function public.delete_private_message(uuid) from public;
grant execute on function public.delete_private_message(uuid) to authenticated;

create or replace function public.delete_message_group_message(p_message_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  delete from public.message_group_messages m
  where m.id = p_message_id
    and (
      m.sender_id = (select auth.uid())
      or exists (
        select 1
        from public.message_groups g
        where g.id = m.group_id and g.owner_id = (select auth.uid())
      )
    );

  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    raise exception 'Message not found or deletion not authorized';
  end if;
end;
$$;

revoke all on function public.delete_message_group_message(uuid) from public;
grant execute on function public.delete_message_group_message(uuid) to authenticated;
