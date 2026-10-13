-- Web Push notifications -------------------------------------------------
-- Devices that opted in, the log of sent notifications, and the VAPID keys.
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  profile_id uuid,
  created_at timestamptz not null default now()
);
create table if not exists public.push_log (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  url text,
  audience text,
  sent int default 0,
  failed int default 0,
  created_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
alter table public.push_log enable row level security;

drop policy if exists "admin reads subs" on public.push_subscriptions;
create policy "admin reads subs" on public.push_subscriptions for select using (public.is_admin());
drop policy if exists "admin reads push log" on public.push_log;
create policy "admin reads push log" on public.push_log for select using (public.is_admin());

-- Anyone (signed in or not) can register their own device; upsert by endpoint.
create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.push_subscriptions(endpoint, p256dh, auth, profile_id)
  values (p_endpoint, p_p256dh, p_auth, auth.uid())
  on conflict (endpoint) do update
    set p256dh = excluded.p256dh, auth = excluded.auth,
        profile_id = coalesce(auth.uid(), public.push_subscriptions.profile_id);
end $$;
grant execute on function public.save_push_subscription(text,text,text) to anon, authenticated;

create or replace function public.delete_push_subscription(p_endpoint text)
returns void language sql security definer set search_path = public as $$
  delete from public.push_subscriptions where endpoint = p_endpoint;
$$;
grant execute on function public.delete_push_subscription(text) to anon, authenticated;

-- Sending is done by the `send-push` edge function (service role); the VAPID private key lives in its secrets.
