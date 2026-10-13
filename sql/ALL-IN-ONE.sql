-- ===== sql/00-legacy-reset.sql =====
-- 00: remove the empty legacy tables (verified 0 rows) that conflict with this schema
drop table if exists public.analytics_events cascade;
drop table if exists public.featured_businesses cascade;
drop table if exists public.products cascade;
drop table if exists public.product_categories cascade;
drop table if exists public.promotions cascade;
drop table if exists public.events_log cascade;
drop table if exists public.businesses cascade;
drop table if exists public.profiles cascade;
drop table if exists public.users cascade;


-- ===== sql/01-core-schema.sql =====
-- ============================================================
-- Conecta Marsella — Supabase schema
-- Run this once in Supabase Studio: Project > SQL Editor > New query
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- PROFILES (neighbors / community users)
-- Public-safe row per user. Linked to auth.users via auth_user_id.
-- Migrated rows start with auth_user_id = null until the person
-- signs up again with a new password (see trigger below).
-- ------------------------------------------------------------
create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  nombre text,
  apellido text,
  email text not null unique,
  whatsapp text,
  quartier text,
  source text,
  estado text not null default 'Activo',
  migrated boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- A user can see and edit only their own profile.
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = auth_user_id);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = auth_user_id)
  with check (auth.uid() = auth_user_id);

-- No insert policy for anon/authenticated on purpose: profile rows
-- are created only by the handle_new_user trigger (below) or by
-- the one-time migration script running with the service_role key.

-- ------------------------------------------------------------
-- BUSINESSES (public directory listing — safe columns only)
-- ------------------------------------------------------------
create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  owner_profile_id uuid references public.profiles(id) on delete set null,
  nombre text not null,
  categoria text,
  sub_categoria text,
  barrio text,
  telefono text,
  descripcion text,
  estado text not null default 'Pendiente Validacion',
  estrellas numeric(2,1) default 0,
  horario text,
  plan text not null default 'Gratuito',
  origen text,
  created_at timestamptz not null default now()
);

alter table public.businesses enable row level security;

-- Public directory can read anything except explicitly rejected listings.
create policy "businesses_select_public"
  on public.businesses for select
  using (estado <> 'Rechazado');

-- Anyone (including anonymous visitors) can submit a new business.
create policy "businesses_insert_public"
  on public.businesses for insert
  with check (true);

-- Owners can edit their own listing once claimed/linked.
create policy "businesses_update_owner"
  on public.businesses for update
  using (
    owner_profile_id in (
      select id from public.profiles where auth_user_id = auth.uid()
    )
  )
  with check (
    owner_profile_id in (
      select id from public.profiles where auth_user_id = auth.uid()
    )
  );

-- New submissions always start as "Pendiente Validacion" no matter
-- what the client sends — only an admin (service_role, in Supabase
-- Studio) can flip a listing to "Activo". Owner edits also get
-- re-queued for review rather than silently going live.
create or replace function public.enforce_business_review_status()
returns trigger as $$
begin
  if tg_op = 'INSERT' then
    new.estado := 'Pendiente Validacion';
  elsif tg_op = 'UPDATE' and auth.role() <> 'service_role' then
    new.estado := old.estado; -- non-admins can't change status themselves
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_business_review_status
  before insert or update on public.businesses
  for each row execute function public.enforce_business_review_status();

-- ------------------------------------------------------------
-- BUSINESS_PRIVATE (sensitive owner details — write-only for the
-- public, readable only by admins via the Supabase dashboard /
-- service_role key). Never exposed to the frontend for reading.
-- ------------------------------------------------------------
create table public.business_private (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  propietario text,
  dui text,
  email text,
  created_at timestamptz not null default now()
);

alter table public.business_private enable row level security;

-- Public can insert (once, alongside the business row) but never read.
create policy "business_private_insert_public"
  on public.business_private for insert
  with check (true);

-- No select policy for anon/authenticated -> default deny.
-- service_role bypasses RLS entirely, so admins can still read it
-- from the Supabase Studio Table Editor.

-- ------------------------------------------------------------
-- EVENTS_LOG (lightweight analytics — replaces the old
-- "user_event_log" Apps Script writes). Write-only for clients.
-- ------------------------------------------------------------
create table public.events_log (
  id bigint generated always as identity primary key,
  profile_id uuid references public.profiles(id) on delete set null,
  evento_tipo text not null,
  valor_busqueda text,
  negocio_nombre text,
  created_at timestamptz not null default now()
);

alter table public.events_log enable row level security;

create policy "events_log_insert_public"
  on public.events_log for insert
  with check (true);

-- No select policy -> only service_role (admin) can read analytics.

-- ------------------------------------------------------------
-- Auth link/migration trigger.
-- Runs after every new Supabase Auth signup. If a migrated profile
-- with the same email already exists (auth_user_id still null),
-- it gets linked to the new auth account instead of creating a
-- duplicate row. Otherwise a fresh profile row is created.
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger as $$
begin
  update public.profiles
     set auth_user_id = new.id,
         migrated = false
   where lower(email) = lower(new.email)
     and auth_user_id is null;

  if not found then
    insert into public.profiles (auth_user_id, email, nombre, apellido, whatsapp, quartier, source)
    values (
      new.id, new.email,
      coalesce(new.raw_user_meta_data->>'nombre', ''),
      coalesce(new.raw_user_meta_data->>'apellido', ''),
      coalesce(new.raw_user_meta_data->>'whatsapp', ''),
      coalesce(new.raw_user_meta_data->>'quartier', ''),
      coalesce(new.raw_user_meta_data->>'source', '')
    );
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- Helpful indexes
-- ------------------------------------------------------------
create index idx_businesses_categoria on public.businesses(categoria);
create index idx_businesses_estado on public.businesses(estado);
create index idx_profiles_email on public.profiles(lower(email));


-- ===== sql/02-promotions.sql =====
-- ============================================================
-- Conecta Marsella — Promotions add-on
-- Run this AFTER supabase-schema.sql, once, in Supabase Studio
-- SQL Editor. Adds a curated promotions/banner system.
-- ============================================================

create table public.promotions (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descripcion text,
  negocio_nombre text,
  imagen_url text,
  cta_text text not null default 'Ver Promoción',
  cta_url text,
  expira_at timestamptz,
  activo boolean not null default true,
  orden int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.promotions enable row level security;

-- Public can read active promotions only.
create policy "promotions_select_public"
  on public.promotions for select
  using (activo = true);

-- No insert/update/delete policy for anon/authenticated on purpose —
-- promotions are curated by you (the admin) through the Supabase
-- Studio Table Editor, or with the service_role key. This is paid/
-- managed placement, not public-submitted content.

-- ------------------------------------------------------------
-- Storage bucket for promo images (public read, admin-only write)
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('promo-images', 'promo-images', true)
on conflict (id) do nothing;

create policy "promo_images_public_read"
  on storage.objects for select
  using (bucket_id = 'promo-images');

-- No insert/update/delete policy for anon/authenticated -> uploads
-- happen only through Supabase Studio's Storage tab (as the admin)
-- or a script using the service_role key. That keeps randoms from
-- uploading arbitrary files to your bucket.


-- ===== sql/03-admin.sql =====
-- ============================================================
-- Conecta Marsella — Admin dashboard add-on
-- Run this AFTER supabase-schema.sql and promotions-schema.sql,
-- once, in the Supabase Studio SQL Editor.
--
-- This adds a real "admin" role (not just a hidden webpage) —
-- every table's Row Level Security is updated so admin-level
-- reads/writes are only possible for accounts you explicitly
-- register as an admin below.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Admins table — who is allowed into the dashboard
-- ------------------------------------------------------------
create table public.admins (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  created_at timestamptz not null default now()
);

alter table public.admins enable row level security;

-- You can check your own admin status from the client (used by
-- admin.html to decide whether to show the dashboard).
create policy "admins_select_self"
  on public.admins for select
  using (id = auth.uid());

-- No insert/update/delete policy for anon/authenticated — admins
-- are added only by you, running SQL directly (see step 5 below).

-- Helper function other policies use to check "is this user an admin?"
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (select 1 from public.admins where id = auth.uid());
$$;

grant execute on function public.is_admin() to anon, authenticated;

-- ------------------------------------------------------------
-- 2. BUSINESSES — admins can see/edit/delete everything,
--    including "Rechazado" listings the public policy hides.
-- ------------------------------------------------------------
create policy "businesses_select_admin"
  on public.businesses for select
  using (public.is_admin());

create policy "businesses_update_admin"
  on public.businesses for update
  using (public.is_admin())
  with check (public.is_admin());

create policy "businesses_delete_admin"
  on public.businesses for delete
  using (public.is_admin());

-- Let admins actually set estado (Activo/Rechazado) when they
-- approve or reject a listing from the dashboard — the existing
-- trigger only allowed service_role to do that.
create or replace function public.enforce_business_review_status()
returns trigger as $$
begin
  if tg_op = 'INSERT' then
    if not public.is_admin() then
      new.estado := 'Pendiente Validacion';
    end if;
  elsif tg_op = 'UPDATE' and auth.role() <> 'service_role' and not public.is_admin() then
    new.estado := old.estado;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ------------------------------------------------------------
-- 3. BUSINESS_PRIVATE — admins can read/update the sensitive
--    owner details (propietario, DUI, email) to review listings.
-- ------------------------------------------------------------
create policy "business_private_select_admin"
  on public.business_private for select
  using (public.is_admin());

create policy "business_private_update_admin"
  on public.business_private for update
  using (public.is_admin())
  with check (public.is_admin());

-- ------------------------------------------------------------
-- 4. PROFILES — admins can view and edit neighbor accounts
--    (e.g. correct a typo, suspend an account).
-- ------------------------------------------------------------
create policy "profiles_select_admin"
  on public.profiles for select
  using (public.is_admin());

create policy "profiles_update_admin"
  on public.profiles for update
  using (public.is_admin())
  with check (public.is_admin());

-- ------------------------------------------------------------
-- 5. PROMOTIONS — admins can create/edit/delete banner items
--    directly from the dashboard (previously Studio-only).
-- ------------------------------------------------------------
create policy "promotions_insert_admin"
  on public.promotions for insert
  with check (public.is_admin());

create policy "promotions_update_admin"
  on public.promotions for update
  using (public.is_admin())
  with check (public.is_admin());

create policy "promotions_delete_admin"
  on public.promotions for delete
  using (public.is_admin());

-- ------------------------------------------------------------
-- 6. STORAGE — admins can upload/replace/delete promo images
--    straight from the dashboard (previously Studio-only).
-- ------------------------------------------------------------
create policy "promo_images_admin_insert"
  on storage.objects for insert
  with check (bucket_id = 'promo-images' and public.is_admin());

create policy "promo_images_admin_update"
  on storage.objects for update
  using (bucket_id = 'promo-images' and public.is_admin());

create policy "promo_images_admin_delete"
  on storage.objects for delete
  using (bucket_id = 'promo-images' and public.is_admin());

-- ------------------------------------------------------------
-- 7. Make yourself an admin.
--
-- First create your own login if you don't already have one:
--   Supabase Studio > Authentication > Users > Add User
--   (set an email + password, tick "Auto Confirm User")
--
-- Then copy that user's UUID from the Users list and run:
--
--   insert into public.admins (id, email)
--   values ('PASTE-YOUR-USER-UUID-HERE', 'your@email.com');
--
-- Repeat the insert for any other admin accounts you want.
-- ------------------------------------------------------------


-- ===== sql/04-admin-stats.sql =====
-- ============================================================
-- Conecta Marsella — Admin stats add-on
-- Run this once, in Supabase Studio SQL Editor, AFTER
-- admin-schema.sql. Just adds one policy: admins can read the
-- events_log table (searches, logins, business clicks, etc.)
-- to power the new Estadísticas tab in admin.html.
-- ============================================================

create policy "events_log_select_admin"
  on public.events_log for select
  using (public.is_admin());


-- ===== sql/05-business-images.sql =====
-- ============================================================
-- Conecta Marsella — Business images add-on
-- Run this once, in Supabase Studio SQL Editor, AFTER
-- supabase-schema.sql and admin-schema.sql.
-- ============================================================

alter table public.businesses add column if not exists imagen_url text;

-- Public bucket for business photos (submitted at registration,
-- or added later by an admin).
insert into storage.buckets (id, name, public)
values ('business-images', 'business-images', true)
on conflict (id) do nothing;

create policy "business_images_public_read"
  on storage.objects for select
  using (bucket_id = 'business-images');

-- Anyone can upload a photo when registering a business — this
-- matches the existing public submission policy on the businesses
-- table itself (new listings already require admin approval before
-- they go live, so a bad photo just gets caught in that same review).
create policy "business_images_public_insert"
  on storage.objects for insert
  with check (bucket_id = 'business-images');

-- Only admins can replace or remove an existing photo (e.g. to
-- swap out a low-quality submitted image).
create policy "business_images_admin_update"
  on storage.objects for update
  using (bucket_id = 'business-images' and public.is_admin());

create policy "business_images_admin_delete"
  on storage.objects for delete
  using (bucket_id = 'business-images' and public.is_admin());


-- ===== sql/06-claim-business.sql =====
-- ============================================================
-- Conecta Marsella — Business claim add-on
-- Run this once, in Supabase Studio SQL Editor, AFTER
-- supabase-schema.sql and admin-schema.sql.
--
-- Lets a logged-in neighbor "claim" a business listing by
-- confirming the email address that was entered when the
-- business was originally registered — without ever exposing
-- that private email to the browser. The check happens entirely
-- inside this function on the database side.
-- ============================================================

create or replace function public.claim_business(p_business_id uuid, p_claim_email text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_match boolean;
begin
  select id into v_profile_id from public.profiles where auth_user_id = auth.uid();
  if v_profile_id is null then
    raise exception 'No se encontró un perfil de vecino para esta cuenta. Crea tu cuenta de vecino primero.';
  end if;

  select exists (
    select 1 from public.business_private
    where business_id = p_business_id
      and lower(email) = lower(trim(p_claim_email))
  ) into v_match;

  if not v_match then
    return false;
  end if;

  update public.businesses
     set owner_profile_id = v_profile_id
   where id = p_business_id
     and owner_profile_id is null;

  return found;
end;
$$;

grant execute on function public.claim_business(uuid, text) to authenticated;


-- ===== sql/07-notify-trigger.sql =====
-- ============================================================
-- Conecta Marsella — Notify webhook (SQL version)
-- Run this AFTER deploying the notify-new-business Edge Function
-- (see NOTIFY-SETUP.md steps 1-3 first — you still need Resend +
-- the function deployed + secrets set for this to actually send
-- an email). This step just wires up the trigger, replacing the
-- "Database > Webhooks" dashboard step if you can't find that UI.
-- ============================================================

create extension if not exists pg_net;

create or replace function public.trigger_notify_new_business()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://tlvnolvfrujhlrffdmeb.supabase.co/functions/v1/notify-new-business',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRsdm5vbHZmcnVqaGxyZmZkbWViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxMDk2NTcsImV4cCI6MjEwNTY4NTY1N30.DZNqaSBGb2-Y6w3mcLSVZ98W0jQxohBgbUls0AqoHfE'
    ),
    body := jsonb_build_object('record', to_jsonb(new))
  );
  return new;
end;
$$;

create trigger on_business_created_notify
  after insert on public.businesses
  for each row execute function public.trigger_notify_new_business();

-- ------------------------------------------------------------
-- To test: submit a business through register.html, then check:
--   select * from net._http_response order by created desc limit 5;
-- status_code 200 means it worked. Anything else (or no rows)
-- means the function call itself failed — check Edge Functions >
-- notify-new-business > Logs in Studio for the actual error.
-- ------------------------------------------------------------


-- ===== sql/08-products.sql =====
-- Products marketplace (ported from the original HLTECHHUB build) on top of the Auth/RLS core.
create table if not exists public.product_categories (
  id serial primary key, name text not null, icon text, "order" int default 0
);
create table if not exists public.products (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  product_category_id int references public.product_categories(id),
  description text,
  price numeric(10,2) check (price >= 0),
  in_stock boolean not null default true,
  image_url text,
  created_at timestamptz not null default now()
);
create table if not exists public.featured_businesses (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  is_active boolean not null default true,
  featured_order int default 0
);
create index if not exists products_business_idx on public.products(business_id);

alter table public.product_categories enable row level security;
alter table public.products enable row level security;
alter table public.featured_businesses enable row level security;

create policy "categories_public_read" on public.product_categories for select using (true);
create policy "categories_admin_write" on public.product_categories for all using (public.is_admin()) with check (public.is_admin());

create policy "products_public_read" on public.products for select using (true);
create policy "products_owner_insert" on public.products for insert to authenticated with check (
  exists (select 1 from public.businesses b join public.profiles p on p.id = b.owner_profile_id
          where b.id = business_id and p.auth_user_id = auth.uid()) or public.is_admin());
create policy "products_owner_update" on public.products for update to authenticated using (
  exists (select 1 from public.businesses b join public.profiles p on p.id = b.owner_profile_id
          where b.id = business_id and p.auth_user_id = auth.uid()) or public.is_admin());
create policy "products_owner_delete" on public.products for delete to authenticated using (
  exists (select 1 from public.businesses b join public.profiles p on p.id = b.owner_profile_id
          where b.id = business_id and p.auth_user_id = auth.uid()) or public.is_admin());

create policy "featured_public_read" on public.featured_businesses for select using (is_active);
create policy "featured_admin_write" on public.featured_businesses for all using (public.is_admin()) with check (public.is_admin());

insert into storage.buckets (id, name, public) values ('marsella-products','marsella-products', true) on conflict do nothing;
create policy "product_images_public_read" on storage.objects for select using (bucket_id = 'marsella-products');
create policy "product_images_auth_upload" on storage.objects for insert to authenticated with check (bucket_id = 'marsella-products');
create policy "product_images_admin_delete" on storage.objects for delete using (bucket_id = 'marsella-products' and public.is_admin());

insert into public.product_categories (name, icon, "order") values
 ('Comida y bebida','🍽️',1),('Ropa y accesorios','👕',2),('Hogar','🏠',3),('Belleza y salud','💄',4),('Servicios','🛠️',5),('Otros','📦',6)
on conflict do nothing;
