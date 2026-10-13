-- Order numbers: every order gets a short number (#1001, #1002, ...) shown to the neighbor and the business.
create sequence if not exists public.order_number_seq start with 1001;
alter table public.orders add column if not exists order_number bigint;
-- Number the existing orders oldest-first.
update public.orders o set order_number = n.num
  from (select id, nextval('public.order_number_seq') as num from (select id from public.orders where order_number is null order by created_at, id) s) n
 where o.id = n.id and o.order_number is null;
alter table public.orders alter column order_number set default nextval('public.order_number_seq');
create unique index if not exists orders_order_number_key on public.orders (order_number);
