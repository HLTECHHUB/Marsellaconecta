-- ============================================================
-- Marsella Conecta — Business images add-on
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
