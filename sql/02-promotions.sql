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
