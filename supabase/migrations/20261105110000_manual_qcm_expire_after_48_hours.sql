-- Manual teacher QCM behave like WhatsApp statuses: visible for 48 hours after publication.
-- This flag is explicit so normal assignments and official evaluations are never expired.

alter table public.assignments
  add column if not exists is_manual_qcm boolean not null default false,
  add column if not exists expires_at timestamptz;

create index if not exists idx_assignments_manual_qcm_expiry
  on public.assignments (expires_at)
  where is_manual_qcm = true and expires_at is not null;

create or replace function public.set_manual_qcm_expiry()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.is_manual_qcm and new.status = 'published' and new.expires_at is null then
    new.published_at := coalesce(new.published_at, now());
    new.expires_at := new.published_at + interval '48 hours';
  elsif not new.is_manual_qcm then
    new.expires_at := null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_set_manual_qcm_expiry on public.assignments;
create trigger trg_set_manual_qcm_expiry
before insert or update of status, is_manual_qcm, published_at
on public.assignments
for each row
execute function public.set_manual_qcm_expiry();

create or replace function public.delete_expired_manual_qcms()
returns bigint
language plpgsql
set search_path = public, pg_temp
as $$
declare
  deleted_count bigint;
begin
  delete from public.assignments
  where is_manual_qcm = true
    and expires_at is not null
    and expires_at <= now();

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function public.delete_expired_manual_qcms() from public, anon, authenticated;
grant execute on function public.delete_expired_manual_qcms() to postgres;

select cron.schedule(
  'expire-manual-qcm-48h',
  '* * * * *',
  'select public.delete_expired_manual_qcms();'
);
