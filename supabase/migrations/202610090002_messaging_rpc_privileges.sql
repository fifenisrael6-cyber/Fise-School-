-- Ensure messaging RPCs are never callable with an anonymous session.
revoke all on function public.list_private_messages(uuid) from public, anon;
grant execute on function public.list_private_messages(uuid) to authenticated;

revoke all on function public.list_message_group_messages(uuid) from public, anon;
grant execute on function public.list_message_group_messages(uuid) to authenticated;

revoke all on function public.delete_private_message(uuid, boolean) from public, anon;
grant execute on function public.delete_private_message(uuid, boolean) to authenticated;

revoke all on function public.delete_group_message(uuid, boolean) from public, anon;
grant execute on function public.delete_group_message(uuid, boolean) to authenticated;

revoke all on function public.claim_private_message_view_once(uuid) from public, anon;
grant execute on function public.claim_private_message_view_once(uuid) to authenticated;

revoke all on function public.claim_group_message_view_once(uuid) from public, anon;
grant execute on function public.claim_group_message_view_once(uuid) to authenticated;
