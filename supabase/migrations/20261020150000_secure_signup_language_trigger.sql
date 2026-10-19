-- The signup metadata synchronizer is trigger-only. Prevent direct calls through
-- the exposed public schema; auth.users trigger execution continues to work.
revoke execute on function public.sync_signup_language_option() from public;
revoke execute on function public.sync_signup_language_option() from anon;
revoke execute on function public.sync_signup_language_option() from authenticated;
