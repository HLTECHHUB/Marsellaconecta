-- Inventory: optional stock quantity per product, reduced automatically when an order is accepted.
alter table public.products add column if not exists stock_qty int check (stock_qty is null or stock_qty >= 0);
alter table public.orders add column if not exists stock_applied boolean not null default false;

create or replace function public.orders_apply_stock() returns trigger language plpgsql security definer set search_path = public as $$
declare v_it jsonb;
begin
  if new.status = 'aceptado' and old.status is distinct from 'aceptado' and not new.stock_applied then
    for v_it in select * from jsonb_array_elements(new.items) loop
      if v_it ? 'product_id' and (v_it->>'product_id') is not null then
        update public.products p
           set stock_qty = greatest(p.stock_qty - coalesce((v_it->>'qty')::int, 0), 0),
               in_stock = greatest(p.stock_qty - coalesce((v_it->>'qty')::int, 0), 0) > 0
         where p.id = (v_it->>'product_id')::bigint and p.stock_qty is not null;
      end if;
    end loop;
    new.stock_applied := true;
  end if;
  return new;
end $$;
drop trigger if exists orders_apply_stock_trg on public.orders;
create trigger orders_apply_stock_trg before update on public.orders for each row execute function public.orders_apply_stock();
