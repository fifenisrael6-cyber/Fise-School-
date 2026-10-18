-- Fise School: jetons d'appareils pour les notifications push (Firebase Cloud Messaging).

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null default 'android',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user_idx on public.device_tokens(user_id);

alter table public.device_tokens enable row level security;

drop policy if exists "users read own device tokens" on public.device_tokens;
create policy "users read own device tokens"
on public.device_tokens for select to authenticated using (user_id = auth.uid());

drop policy if exists "users insert own device tokens" on public.device_tokens;
create policy "users insert own device tokens"
on public.device_tokens for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "users update own device tokens" on public.device_tokens;
create policy "users update own device tokens"
on public.device_tokens for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "users delete own device tokens" on public.device_tokens;
create policy "users delete own device tokens"
on public.device_tokens for delete to authenticated using (user_id = auth.uid());

-- Un jeton appartient à l'appareil, pas au compte : quand un autre compte se connecte
-- sur le même appareil, le jeton lui est réattribué.
create or replace function public.register_device_token(p_token text, p_platform text default 'android')
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Session requise.';
  end if;
  insert into public.device_tokens(user_id, token, platform)
  values (auth.uid(), p_token, coalesce(nullif(p_platform, ''), 'android'))
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end;
$$;
revoke all on function public.register_device_token(text, text) from public;
grant execute on function public.register_device_token(text, text) to authenticated;
