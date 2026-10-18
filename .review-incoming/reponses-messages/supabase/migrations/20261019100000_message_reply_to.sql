-- Fise School — répondre à un message précis (citation façon WhatsApp).
-- À appliquer après 20261018100100_ensure_assignment_files_bucket.sql.

-- 1. Colonne « message cité » (facultative) sur les messages privés et de groupe.
alter table public.private_messages
  add column if not exists reply_to_id uuid
  references public.private_messages(id) on delete set null;

alter table public.message_group_messages
  add column if not exists reply_to_id uuid
  references public.message_group_messages(id) on delete set null;

create index if not exists private_messages_reply_to_idx
  on public.private_messages (reply_to_id) where reply_to_id is not null;
create index if not exists message_group_messages_reply_to_idx
  on public.message_group_messages (reply_to_id) where reply_to_id is not null;

-- 2. Sécurité : on ne peut citer qu'un message de la même conversation.
create or replace function public.check_private_message_reply()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.reply_to_id is null then
    return new;
  end if;
  if not exists (
    select 1 from public.private_messages q
    where q.id = new.reply_to_id
      and ((q.sender_id = new.sender_id and q.recipient_id = new.recipient_id)
        or (q.sender_id = new.recipient_id and q.recipient_id = new.sender_id))
  ) then
    raise exception 'Invalid reply target';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_check_private_message_reply on public.private_messages;
create trigger trg_check_private_message_reply
before insert on public.private_messages
for each row execute function public.check_private_message_reply();

create or replace function public.check_group_message_reply()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.reply_to_id is null then
    return new;
  end if;
  if not exists (
    select 1 from public.message_group_messages q
    where q.id = new.reply_to_id and q.group_id = new.group_id
  ) then
    raise exception 'Invalid reply target';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_check_group_message_reply on public.message_group_messages;
create trigger trg_check_group_message_reply
before insert on public.message_group_messages
for each row execute function public.check_group_message_reply();

-- 3. Messages privés : list_private_messages renvoie déjà toute la ligne (reply_to_id inclus),
--    rien à changer.

-- 4. Messages de groupe : même fonction qu'avant, avec reply_to_id en plus.
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
  recipient_count bigint,
  reply_to_id uuid
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
      where gm.group_id = p_group_id and gm.user_id <> m.sender_id),
    m.reply_to_id
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
