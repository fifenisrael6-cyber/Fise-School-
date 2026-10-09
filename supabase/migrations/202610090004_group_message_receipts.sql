-- Reçus de livraison/lecture des messages des groupes.
create table if not exists public.message_group_message_receipts (
  group_id uuid not null references public.message_groups(id) on delete cascade,
  message_id uuid not null references public.message_group_messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (message_id, user_id)
);

create index if not exists message_group_message_receipts_group_idx
  on public.message_group_message_receipts (group_id, user_id);

alter table public.message_group_message_receipts enable row level security;

drop policy if exists "members read group message receipts" on public.message_group_message_receipts;
create policy "members read group message receipts"
on public.message_group_message_receipts for select to authenticated
using (public.is_message_group_member(group_id));

grant select on public.message_group_message_receipts to authenticated;

create or replace function public.mark_message_group_delivered(p_group_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed integer;
begin
  if not public.is_message_group_member(p_group_id) then
    raise exception 'Not a member of this group';
  end if;

  insert into public.message_group_message_receipts as existing(group_id, message_id, user_id, delivered_at)
  select m.group_id, m.id, (select auth.uid()), now()
  from public.message_group_messages m
  where m.group_id = p_group_id
    and m.sender_id <> (select auth.uid())
  on conflict (message_id, user_id) do update
    set delivered_at = coalesce(existing.delivered_at, excluded.delivered_at)
    where existing.delivered_at is null;

  get diagnostics v_changed = row_count;
  return v_changed;
end;
$$;

create or replace function public.mark_message_group_read(p_group_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed integer;
begin
  if not public.is_message_group_member(p_group_id) then
    raise exception 'Not a member of this group';
  end if;

  insert into public.message_group_message_receipts as existing(
    group_id, message_id, user_id, delivered_at, read_at
  )
  select m.group_id, m.id, (select auth.uid()), now(), now()
  from public.message_group_messages m
  where m.group_id = p_group_id
    and m.sender_id <> (select auth.uid())
  on conflict (message_id, user_id) do update
    set delivered_at = coalesce(existing.delivered_at, excluded.delivered_at),
        read_at = coalesce(existing.read_at, excluded.read_at)
    where existing.delivered_at is null or existing.read_at is null;

  get diagnostics v_changed = row_count;
  return v_changed;
end;
$$;

revoke all on function public.mark_message_group_delivered(uuid) from public;
revoke all on function public.mark_message_group_read(uuid) from public;
grant execute on function public.mark_message_group_delivered(uuid) to authenticated;
grant execute on function public.mark_message_group_read(uuid) to authenticated;

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
  viewed_at timestamptz,
  recipient_count integer,
  delivered_count integer,
  read_count integer
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
         m.created_at, m.view_once, m.viewed_at,
         coalesce((
           select count(*)::integer
           from public.message_group_members gm
           where gm.group_id = m.group_id and gm.user_id <> m.sender_id
         ), 0),
         coalesce((
           select count(*)::integer
           from public.message_group_message_receipts r
           where r.message_id = m.id and r.delivered_at is not null
         ), 0),
         coalesce((
           select count(*)::integer
           from public.message_group_message_receipts r
           where r.message_id = m.id and r.read_at is not null
         ), 0)
  from public.message_group_messages m
  left join public.profiles p on p.id = m.sender_id
  where m.group_id = p_group_id
  order by m.created_at asc;
end;
$$;

revoke all on function public.list_message_group_messages(uuid) from public;
grant execute on function public.list_message_group_messages(uuid) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.message_group_message_receipts;
exception when others then
  null;
end;
$$;

notify pgrst, 'reload schema';
