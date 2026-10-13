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

-- Optional link to the business's own WhatsApp catalog (wa.me/c/...)
alter table public.businesses add column if not exists whatsapp_catalog_url text;

-- Zona (Marsella 1 / Marsella 2) on profiles, price of each cart add, trigger passes zona through
alter table public.profiles add column if not exists zona text;
alter table public.events_log add column if not exists valor numeric(10,2);
create or replace function public.handle_new_user()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  update public.profiles set auth_user_id = new.id, migrated = false
   where lower(email) = lower(new.email) and auth_user_id is null;
  if not found then
    insert into public.profiles (auth_user_id, email, nombre, apellido, whatsapp, quartier, zona, source)
    values (new.id, new.email,
      coalesce(new.raw_user_meta_data->>'nombre',''), coalesce(new.raw_user_meta_data->>'apellido',''),
      coalesce(new.raw_user_meta_data->>'whatsapp',''), coalesce(new.raw_user_meta_data->>'quartier',''),
      coalesce(new.raw_user_meta_data->>'zona',''),
      coalesce(new.raw_user_meta_data->>'source',''));
  end if;
  return new;
end;
$function$;
