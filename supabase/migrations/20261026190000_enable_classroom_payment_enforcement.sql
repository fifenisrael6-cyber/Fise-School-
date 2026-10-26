-- Activate the paid-access rules requested for classroom-scoped Premium.
-- The switches remain configurable in Supabase for a future controlled test period.
delete from public.quota_config where key = 'fise_testing_mode';

update public.payment_settings
set enabled = true, updated_at = now()
where id = true;

update public.payment_runtime_settings
set enabled = true, updated_at = now()
where id = true;
