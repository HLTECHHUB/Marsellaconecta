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
