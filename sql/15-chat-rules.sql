-- Chat rules: no phone numbers/links in messages; chat stays open until the order is completed.
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check check (status in ('pendiente','aceptado','rechazado','completado'));

create or replace function public.send_order_message(p_order_id uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_role text; v_id uuid; v_status text; v_body text := trim(coalesce(p_body, ''));
begin
  if v_body = '' then raise exception 'Mensaje vacío'; end if;
  -- 7+ digits (even split by spaces, dashes, dots, parentheses), spelled-out digits, or links
  if v_body ~ '(\d[\s\-\.\(\)\+_/]*){7,}'
     or v_body ~* '((cero|uno|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve)[\s\-\.,]*){6,}'
     or v_body ~* '(wa\.me|t\.me|https?://|www\.)' then
    raise exception 'No se permiten números de teléfono ni enlaces en el chat';
  end if;
  select o.status into v_status from public.orders o where o.id = p_order_id;
  if v_status is null then raise exception 'Pedido no encontrado'; end if;
  if v_status in ('rechazado','completado') then raise exception 'Este chat ya está cerrado'; end if;
  if exists (select 1 from public.orders o join public.profiles p on p.id = o.customer_profile_id where o.id = p_order_id and p.auth_user_id = auth.uid()) then v_role := 'cliente';
  elsif exists (select 1 from public.orders o join public.businesses b on b.id = o.business_id join public.profiles p on p.id = b.owner_profile_id where o.id = p_order_id and p.auth_user_id = auth.uid()) then v_role := 'negocio';
  else raise exception 'No participas en este pedido'; end if;
  insert into public.order_messages (order_id, sender_auth_id, sender_role, body)
  values (p_order_id, auth.uid(), v_role, left(v_body, 500)) returning id into v_id;
  return v_id;
end $$;
grant execute on function public.send_order_message(uuid, text) to authenticated;

-- Either the business or the neighbor can mark an accepted order as completed (closes the chat).
create or replace function public.complete_order(p_order_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.orders o set status = 'completado', responded_at = coalesce(o.responded_at, now())
   where o.id = p_order_id and o.status = 'aceptado' and (
     public.is_admin()
     or o.customer_profile_id in (select id from public.profiles where auth_user_id = auth.uid())
     or o.business_id in (select b.id from public.businesses b join public.profiles p on p.id = b.owner_profile_id where p.auth_user_id = auth.uid()));
  if not found then raise exception 'No se pudo completar el pedido'; end if;
end $$;
grant execute on function public.complete_order(uuid) to authenticated;
