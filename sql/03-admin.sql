-- ============================================================
-- Marsella Conecta — Admin dashboard add-on
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
