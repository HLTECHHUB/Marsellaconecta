-- Order requests: the neighbor sends a request, the business accepts/rejects,
-- and only after acceptance does the neighbor send the normal WhatsApp message.
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  items jsonb not null,
  total numeric not null default 0,
  customer_name text,
  status text not null default 'pendiente' check (status in ('pendiente','aceptado','rechazado')),
  created_at timestamptz not null default now(),
  responded_at timestamptz
);
create index if not exists orders_business_idx on public.orders (business_id, created_at desc);
create index if not exists orders_customer_idx on public.orders (customer_profile_id, created_at desc);
alter table public.orders enable row level security;

drop policy if exists "orders_customer_read" on public.orders;
create policy "orders_customer_read" on public.orders for select to authenticated using (
  customer_profile_id in (select id from public.profiles where auth_user_id = auth.uid()));
drop policy if exists "orders_owner_read" on public.orders;
create policy "orders_owner_read" on public.orders for select to authenticated using (
  business_id in (select b.id from public.businesses b join public.profiles p on p.id = b.owner_profile_id where p.auth_user_id = auth.uid()));
drop policy if exists "orders_admin_read" on public.orders;
create policy "orders_admin_read" on public.orders for select to authenticated using (public.is_admin());

-- Neighbor creates a request (no direct insert allowed).
create or replace function public.create_order(p_business_id uuid, p_items jsonb, p_total numeric)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_profile uuid; v_id uuid; v_name text;
begin
  select id, nullif(trim(coalesce(nombre,'') || ' ' || coalesce(apellido,'')), '') into v_profile, v_name from public.profiles where auth_user_id = auth.uid();
  if v_profile is null then raise exception 'Debes iniciar sesión'; end if;
  if not exists (select 1 from public.businesses where id = p_business_id) then raise exception 'Negocio no encontrado'; end if;
  insert into public.orders (business_id, customer_profile_id, items, total, customer_name)
  values (p_business_id, v_profile, p_items, coalesce(p_total, 0), v_name) returning id into v_id;
  return v_id;
end $$;
grant execute on function public.create_order(uuid, jsonb, numeric) to authenticated;

-- Business owner (or admin) accepts or rejects a pending request.
create or replace function public.respond_order(p_order_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_status not in ('aceptado','rechazado') then raise exception 'Estado inválido'; end if;
  update public.orders o set status = p_status, responded_at = now()
   where o.id = p_order_id and o.status = 'pendiente'
     and (public.is_admin() or o.business_id in (
           select b.id from public.businesses b join public.profiles p on p.id = b.owner_profile_id where p.auth_user_id = auth.uid()));
  if not found then raise exception 'No se pudo actualizar el pedido'; end if;
end $$;
grant execute on function public.respond_order(uuid, text) to authenticated;
