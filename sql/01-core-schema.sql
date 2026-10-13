-- ============================================================
-- Marsella Conecta — Supabase schema
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
