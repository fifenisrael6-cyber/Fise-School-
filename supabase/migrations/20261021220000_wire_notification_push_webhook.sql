-- Wire notifications INSERTs to the deployed send-push Edge Function.
-- The webhook secret is generated and stored in Supabase Vault; it is never stored in plain application tables.

do $$
begin
  if not exists (
    select 1 from vault.decrypted_secrets where name = 'fise_push_webhook_secret'
  ) then
    perform vault.create_secret(
      encode(gen_random_bytes(32), 'hex'),
      'fise_push_webhook_secret',
      'Authenticates database-triggered calls to the send-push Edge Function'
    );
  end if;
end;
$$;

create or replace function public.validate_push_webhook_secret(p_secret text)
returns boolean
language sql
security definer
set search_path = public, vault
as $$
  select p_secret is not null and exists (
    select 1
    from vault.decrypted_secrets
    where name = 'fise_push_webhook_secret'
      and decrypted_secret = p_secret
  );
$$;

revoke all on function public.validate_push_webhook_secret(text) from public, anon, authenticated;
grant execute on function public.validate_push_webhook_secret(text) to service_role;

create or replace function public.notify_push_on_notification_insert()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  webhook_secret text;
begin
  select decrypted_secret into webhook_secret
  from vault.decrypted_secrets
  where name = 'fise_push_webhook_secret'
  limit 1;

  if webhook_secret is null then
    raise warning 'Fise School push webhook secret missing from Vault; notification push skipped.';
    return new;
  end if;

  perform net.http_post(
    url := 'https://uftjoubxaayggnwkbfro.supabase.co/functions/v1/send-push',
    body := jsonb_build_object('type', 'INSERT', 'record', to_jsonb(new)),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', webhook_secret
    ),
    timeout_milliseconds := 10000
  );

  return new;
end;
$$;

drop trigger if exists notifications_send_push_after_insert on public.notifications;
create trigger notifications_send_push_after_insert
after insert on public.notifications
for each row execute function public.notify_push_on_notification_insert();
