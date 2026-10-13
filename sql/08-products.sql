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
