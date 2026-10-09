-- Fise School: médias à consultation unique pour la messagerie privée et les groupes.
-- Les URLs signées sont courtes pour limiter leur réutilisation après ouverture.
alter table public.private_messages
  add column if not exists view_once boolean not null default false,
  add column if not exists viewed_at timestamptz;

alter table public.message_group_messages
  add column if not exists view_once boolean not null default false,
  add column if not exists viewed_at timestamptz;

create or replace function public.mark_private_message_viewed_once(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  update public.private_messages m
     set viewed_at = coalesce(m.viewed_at, now())
   where m.id = p_message_id
     and m.recipient_id = (select auth.uid())
     and m.sender_id <> (select auth.uid())
     and m.view_once = true
     and m.viewed_at is null
     and public.can_message(m.sender_id);

  get diagnostics v_changed = row_count;
  return v_changed > 0;
end;
$$;

create or replace function public.mark_group_message_viewed_once(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  update public.message_group_messages m
     set viewed_at = coalesce(m.viewed_at, now())
   where m.id = p_message_id
     and m.sender_id <> (select auth.uid())
     and m.view_once = true
     and m.viewed_at is null
     and public.is_message_group_member(m.group_id);

  get diagnostics v_changed = row_count;
  return v_changed > 0;
end;
$$;

revoke all on function public.mark_private_message_viewed_once(uuid) from public;
revoke all on function public.mark_group_message_viewed_once(uuid) from public;
grant execute on function public.mark_private_message_viewed_once(uuid) to authenticated;
grant execute on function public.mark_group_message_viewed_once(uuid) to authenticated;

-- Une fois le média consommé, aucun nouveau lien signé ne peut être créé
-- pour le destinataire. Les liens déjà émis expirent au plus tard après 60 s
-- lorsqu'ils sont créés par l'application pour une consultation unique.
drop policy if exists "private message attachments participants read" on storage.objects;
create policy "private message attachments participants read"
on storage.objects for select to authenticated
using (
  bucket_id = 'private-message-attachments'
  and exists (
    select 1 from public.private_messages pm
    where pm.attachment_path = name
      and (pm.sender_id = (select auth.uid()) or pm.recipient_id = (select auth.uid()))
      and not (
        pm.view_once = true
        and pm.viewed_at is not null
        and pm.sender_id <> (select auth.uid())
      )
  )
);

drop policy if exists "group members read attachments" on storage.objects;
create policy "group members read attachments"
on storage.objects for select to authenticated
using (
  bucket_id = 'group-message-attachments'
  and public.is_message_group_member((storage.foldername(name))[1]::uuid)
  and not exists (
    select 1 from public.message_group_messages gm
    where gm.attachment_path = name
      and gm.view_once = true
      and gm.viewed_at is not null
      and gm.sender_id <> (select auth.uid())
  )
);

-- Étendre la réponse de la RPC des groupes avec les métadonnées de consultation.
drop function if exists public.list_message_group_messages(uuid);
create function public.list_message_group_messages(p_group_id uuid)
returns table (
  id uuid,
  sender_id uuid,
  sender_name text,
  sender_role text,
  body text,
  attachment_path text,
  attachment_name text,
  attachment_type text,
  created_at timestamptz,
  view_once boolean,
  viewed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_message_group_member(p_group_id) then
    raise exception 'Not a member of this group';
  end if;

  return query
  select m.id, m.sender_id,
         trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')),
         p.role::text,
         m.body, m.attachment_path, m.attachment_name, m.attachment_type,
         m.created_at, m.view_once, m.viewed_at
  from public.message_group_messages m
  left join public.profiles p on p.id = m.sender_id
  where m.group_id = p_group_id
  order by m.created_at asc;
end;
$$;

revoke all on function public.list_message_group_messages(uuid) from public;
grant execute on function public.list_message_group_messages(uuid) to authenticated;
