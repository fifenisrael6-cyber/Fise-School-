-- These SECURITY DEFINER notification workers are invoked by trusted database scheduling only.
revoke all on function public.notify_evaluation_result(uuid) from public, anon, authenticated;
revoke all on function public.notify_released_evaluation_results() from public, anon, authenticated;
