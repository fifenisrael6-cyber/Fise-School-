-- Fise School — photos de profil visibles dans la messagerie (privée et groupes).
-- À appliquer après 20261017110000_content_protection_and_received_quota.sql.

-- 1. Les utilisateurs connectés peuvent lire les photos de profil (bucket privé, URL signées).
drop policy if exists "authenticated read profile photos" on storage.objects;
create policy "authenticated read profile photos" on storage.objects
for select to authenticated
using (bucket_id = 'profile-photos');

-- 2. Contacts privés : ajoute avatar_path
drop function if exists public.list_private_message_contacts();
create or replace function public.list_private_message_contacts()
returns table (id uuid, first_name text, last_name text, role text, class_name text, avatar_path text)
language sql stable security definer set search_path = public
as $$
  select distinct on (p.id)
    p.id, p.first_name, p.last_name, p.role, c.display_name as class_name, p.avatar_path
  from public.class_students cs
  join public.class_teachers ct on ct.class_id = cs.class_id
  join public.school_classes c on c.id = cs.class_id
  join public.profiles p
    on p.id = case when cs.student_id = auth.uid() then ct.teacher_id else cs.student_id end
  where cs.is_active and ct.is_active
    and (cs.student_id = auth.uid() or ct.teacher_id = auth.uid())
  order by p.id, c.display_name;
$$;
revoke all on function public.list_private_message_contacts() from public, anon;
grant execute on function public.list_private_message_contacts() to authenticated;

-- 3. Messages de groupe : ajoute sender_avatar_path (reste identique par ailleurs)
drop function if exists public.list_message_group_messages(uuid);
create or replace function public.list_message_group_messages(p_group_id uuid)
returns table (
  id uuid,
  sender_id uuid,
  sender_name text,
  sender_role text,
  sender_avatar_path text,
  body text,
  attachment_path text,
  attachment_name text,
  attachment_type text,
  created_at timestamptz,
  view_once boolean,
  viewed_by_me boolean,
  deleted_at timestamptz,
  delivered_count bigint,
  read_count bigint,
  recipient_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_joined_at timestamptz;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select member.joined_at into v_joined_at
  from public.message_group_members member
  where member.group_id = p_group_id
    and member.user_id = (select auth.uid());

  if v_joined_at is null then
    raise exception 'Not a member of this group';
  end if;

  return query
  select m.id,
    m.sender_id,
    trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')),
    p.role::text,
    p.avatar_path,
    case when m.deleted_at is null then m.body else '' end,
    case when m.deleted_at is null then m.attachment_path else null end,
    case when m.deleted_at is null then m.attachment_name else null end,
    case when m.deleted_at is null then m.attachment_type else null end,
    m.created_at,
    m.view_once,
    exists (
      select 1 from public.message_group_message_views v
      where v.message_id = m.id and v.user_id = (select auth.uid())
    ),
    m.deleted_at,
    (select count(*) from public.message_group_message_receipts r
      where r.message_id = m.id and r.delivered_at is not null and r.user_id <> m.sender_id),
    (select count(*) from public.message_group_message_receipts r
      where r.message_id = m.id and r.read_at is not null and r.user_id <> m.sender_id),
    (select count(*) from public.message_group_members gm
      where gm.group_id = p_group_id and gm.user_id <> m.sender_id)
  from public.message_group_messages m
  left join public.profiles p on p.id = m.sender_id
  where m.group_id = p_group_id
    and m.created_at >= v_joined_at
    and not ((select auth.uid()) = any(coalesce(m.hidden_for, '{}'::uuid[])))
  order by m.created_at asc;
end;
$$;
revoke all on function public.list_message_group_messages(uuid) from public, anon;
grant execute on function public.list_message_group_messages(uuid) to authenticated;
