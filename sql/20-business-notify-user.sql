-- Business order notifications: the owner can pick which registered user receives and handles the
-- order alerts for a business (default: the owner). The chosen user can accept / reject / modify /
-- complete orders and chat as the business, exactly like the owner.

create table if not exists public.business_notify (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.business_notify enable row level security;
-- no direct policies: access only through the functions below

-- Business ids the signed-in user handles orders for (owner, or the user chosen by the owner).
-- Note: when a user is chosen, the owner stops receiving that business's order alerts but can still change the choice.
create or replace function public.my_business_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select b.id from public.businesses b join public.profiles p on p.id = b.owner_profile_id
   where p.auth_user_id = auth.uid() and not exists (select 1 from public.business_notify n where n.business_id = b.id)
  union
  select n.business_id from public.business_notify n join public.profiles p on p.id = n.profile_id where p.auth_user_id = auth.uid()
$$;
grant execute on function public.my_business_ids() to authenticated;

drop policy if exists "orders_owner_read" on public.orders;
create policy "orders_owner_read" on public.orders for select to authenticated using (business_id in (select public.my_business_ids()));
drop policy if exists "order_messages_read" on public.order_messages;
create policy "order_messages_read" on public.order_messages for select to authenticated using (
  public.is_admin() or exists (
    select 1 from public.orders o where o.id = order_id and (
      o.customer_profile_id in (select id from public.profiles where auth_user_id = auth.uid())
      or o.business_id in (select public.my_business_ids()))));

-- Owner reads / sets the chosen user. Pass an empty email to go back to the owner.
create or replace function public.get_business_notify(p_business_id uuid)
returns table (email text, nombre text) language sql stable security definer set search_path = public as $$
  select p.email, trim(coalesce(p.nombre,'') || ' ' || coalesce(p.apellido,''))
    from public.business_notify n join public.profiles p on p.id = n.profile_id
   where n.business_id = p_business_id
     and exists (select 1 from public.businesses b join public.profiles o on o.id = b.owner_profile_id where b.id = p_business_id and o.auth_user_id = auth.uid())
$$;
grant execute on function public.get_business_notify(uuid) to authenticated;

create or replace function public.set_business_notify(p_business_id uuid, p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare v_pid uuid; v_name text; v_email text := lower(trim(coalesce(p_email,'')));
begin
  if not exists (select 1 from public.businesses b join public.profiles o on o.id = b.owner_profile_id
                  where b.id = p_business_id and o.auth_user_id = auth.uid()) then
    raise exception 'Solo el dueño del negocio puede cambiar esto';
  end if;
  if v_email = '' then
    delete from public.business_notify where business_id = p_business_id;
    return 'Las notificaciones vuelven a ti.';
  end if;
  select id, trim(coalesce(nombre,'') || ' ' || coalesce(apellido,'')) into v_pid, v_name
    from public.profiles where lower(email) = v_email limit 1;
  if v_pid is null then raise exception 'Ese correo no tiene una cuenta en Conecta Marsella. Pídele que se registre primero.'; end if;
  insert into public.business_notify (business_id, profile_id) values (p_business_id, v_pid)
  on conflict (business_id) do update set profile_id = excluded.profile_id, created_at = now();
  return 'Listo: ' || coalesce(nullif(v_name,''), v_email) || ' recibirá los pedidos.';
end $$;
grant execute on function public.set_business_notify(uuid, text) to authenticated;

create or replace function public.respond_order(p_order_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_status not in ('aceptado','rechazado') then raise exception 'Estado inválido'; end if;
  update public.orders o set status = p_status, responded_at = now()
   where o.id = p_order_id and o.status = 'pendiente'
     and (public.is_admin() or o.business_id in (
           select public.my_business_ids()));
  if not found then raise exception 'No se pudo actualizar el pedido'; end if;
end $$;
grant execute on function public.respond_order(uuid, text) to authenticated;

create or replace function public.report_order_message(p_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.order_messages m set reported = true
   where m.id = p_message_id and m.sender_auth_id <> auth.uid()
     and exists (
       select 1 from public.orders o where o.id = m.order_id and (
         o.customer_profile_id in (select id from public.profiles where auth_user_id = auth.uid())
         or o.business_id in (select public.my_business_ids())));
  if not found then raise exception 'No se pudo reportar'; end if;
end $$;
grant execute on function public.report_order_message(uuid) to authenticated;

create or replace function public.complete_order(p_order_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.orders o set status = 'completado', responded_at = coalesce(o.responded_at, now())
   where o.id = p_order_id and o.status = 'aceptado' and (
     public.is_admin()
     or o.customer_profile_id in (select id from public.profiles where auth_user_id = auth.uid())
     or o.business_id in (select public.my_business_ids()));
  if not found then raise exception 'No se pudo completar el pedido'; end if;
end $$;
grant execute on function public.complete_order(uuid) to authenticated;

create or replace function public.send_order_message(p_order_id uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_role text; v_id uuid; v_status text; v_body text := trim(coalesce(p_body, ''));
begin
  if v_body = '' then raise exception 'Mensaje vacío'; end if;
  if public.chat_text_blocked(v_body) then raise exception 'No se permiten números de teléfono ni enlaces en el chat'; end if;
  select o.status into v_status from public.orders o where o.id = p_order_id;
  if v_status is null then raise exception 'Pedido no encontrado'; end if;
  if v_status in ('rechazado','completado','cancelado') then raise exception 'Este chat ya está cerrado'; end if;
  if exists (select 1 from public.orders o join public.profiles p on p.id = o.customer_profile_id where o.id = p_order_id and p.auth_user_id = auth.uid()) then v_role := 'cliente';
  elsif exists (select 1 from public.orders o where o.id = p_order_id and o.business_id in (select public.my_business_ids())) then v_role := 'negocio';
  else raise exception 'No participas en este pedido'; end if;
  insert into public.order_messages (order_id, sender_auth_id, sender_role, body)
  values (p_order_id, auth.uid(), v_role, left(v_body, 500)) returning id into v_id;
  return v_id;
end $$;
grant execute on function public.send_order_message(uuid, text) to authenticated;

create or replace function public.modify_order(p_order_id uuid, p_note text, p_items jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_o public.orders; v_note text := trim(coalesce(p_note, '')); v_it jsonb; v_oq int; v_q int;
        v_new jsonb := '[]'::jsonb; v_total numeric := 0; v_changed boolean := false;
begin
  select * into v_o from public.orders where id = p_order_id and status = 'pendiente' for update;
  if not found then raise exception 'No se pudo modificar el pedido'; end if;
  if not (public.is_admin() or v_o.business_id in (
        select public.my_business_ids())) then
    raise exception 'No se pudo modificar el pedido';
  end if;
  for v_it in select * from jsonb_array_elements(v_o.items) loop
    v_oq := coalesce((v_it->>'qty')::int, 0); v_q := v_oq;
    if p_items is not null then
      v_q := coalesce((select (e->>'qty')::int from jsonb_array_elements(p_items) e where e->>'product_id' = v_it->>'product_id' limit 1), v_oq);
    end if;
    v_q := greatest(0, least(v_q, v_oq));            -- only decreases are allowed
    if v_q <> v_oq then v_changed := true; end if;
    if v_q > 0 then
      v_new := v_new || jsonb_build_array(jsonb_set(v_it, '{qty}', to_jsonb(v_q)));
      v_total := v_total + coalesce((v_it->>'price')::numeric, 0) * v_q;
    end if;
  end loop;
  if jsonb_array_length(v_new) = 0 then raise exception 'Para quitar todo el pedido usa Rechazar'; end if;
  if v_note = '' and v_changed then v_note := 'Ajustamos las cantidades de tu pedido según lo que tenemos disponible.'; end if;
  if v_note = '' then raise exception 'Cambia una cantidad o elige un mensaje'; end if;
  if public.chat_text_blocked(v_note) then raise exception 'No se permiten números de teléfono ni enlaces'; end if;
  update public.orders set status = 'modificado', business_note = left(v_note, 300), modified_at = now(),
         responded_at = coalesce(responded_at, now()),
         proposed_items = case when v_changed then v_new else null end,
         proposed_total = case when v_changed then v_total else null end
   where id = p_order_id;
end $$;
grant execute on function public.modify_order(uuid, text, jsonb) to authenticated;
