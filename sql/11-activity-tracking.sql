-- Extra analytics columns: anonymous visitor id, category and page.
alter table public.events_log add column if not exists session_id text, add column if not exists categoria text, add column if not exists pagina text;
create index if not exists events_log_created_idx on public.events_log (created_at desc);
create index if not exists events_log_profile_idx on public.events_log (profile_id, created_at desc);

-- Promotions linked to a business + promo tracking (views/clicks via events_log)
alter table public.promotions add column if not exists business_id uuid references public.businesses(id) on delete set null;
alter table public.events_log add column if not exists promotion_id uuid references public.promotions(id) on delete set null;
create index if not exists events_log_promo_idx on public.events_log (promotion_id) where promotion_id is not null;

-- Cart analytics: which product was added to the cart
alter table public.events_log add column if not exists product_id bigint references public.products(id) on delete set null;
create index if not exists events_log_product_idx on public.events_log (product_id) where product_id is not null;
