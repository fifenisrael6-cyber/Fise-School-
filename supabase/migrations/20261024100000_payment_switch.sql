-- Contrôle centralisé du mode de paiement Notch Pay.
-- Par défaut désactivé : activer explicitement après les tests depuis Supabase SQL Editor.
create table if not exists public.payment_settings (
  id boolean primary key default true check (id = true),
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into public.payment_settings (id, enabled)
values (true, false)
on conflict (id) do nothing;

alter table public.payment_settings enable row level security;
revoke all on public.payment_settings from anon, authenticated;
grant select, insert, update, delete on public.payment_settings to service_role;

comment on table public.payment_settings is
'Contrôle serveur du paiement Notch Pay. Activation: UPDATE public.payment_settings SET enabled=true, updated_at=now() WHERE id=true; désactivation: enabled=false.';

