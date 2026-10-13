-- Ensure private chat delivery/read receipts use authorized RPCs.
-- The client should not depend on direct UPDATE access to private_messages.
create or replace function public.mark_private_messages_delivered(p_sender_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_count integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;
  if p_sender_id is null or not public.can_message(p_sender_id) then
    raise exception 'Not authorized to access this private conversation';
  end if;

  update public.private_messages
     set delivered_at = coalesce(delivered_at, now())
   where sender_id = p_sender_id
     and recipient_id = (select auth.uid())
     and delivered_at is null;

  get diagnostics changed_count = row_count;
  return changed_count;
end;
$$;

create or replace function public.mark_private_messages_read(p_sender_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_count integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;
  if p_sender_id is null or not public.can_message(p_sender_id) then
    raise exception 'Not authorized to access this private conversation';
  end if;

  update public.private_messages
     set delivered_at = coalesce(delivered_at, now()),
         read_at = coalesce(read_at, now())
   where sender_id = p_sender_id
     and recipient_id = (select auth.uid())
     and read_at is null;

  get diagnostics changed_count = row_count;
  return changed_count;
end;
$$;

revoke all on function public.mark_private_messages_delivered(uuid) from public, anon;
revoke all on function public.mark_private_messages_read(uuid) from public, anon;
grant execute on function public.mark_private_messages_delivered(uuid) to authenticated;
grant execute on function public.mark_private_messages_read(uuid) to authenticated;
