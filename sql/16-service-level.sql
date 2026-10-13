-- Service level (response time) + "modify" flow with preset messages. Run after 15-chat-rules.sql.
alter table public.businesses add column if not exists response_minutes int not null default 30 check (response_minutes between 5 and 1440);
alter table public.orders add column if not exists due_at timestamptz;
alter table public.orders add column if not exists business_note text;
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check check (status in ('pendiente','aceptado','rechazado','completado','modificado','cancelado'));

-- Shared rule: no phone numbers / links in free text.
create or replace function public.chat_text_blocked(t text) returns boolean language sql immutable as $$
  select t ~ '(\d[\s\-\.\(\)\+_/]*){7,}'
      or t ~* '((cero|uno|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve)[\s\-\.,]*){6,}'
      or t ~* '(wa\.me|t\.me|https?://|www\.)';
$$;

-- New orders get a due time based on the business's response time.
create or replace function public.create_order(p_business_id uuid, p_items jsonb, p_total numeric)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_profile uuid; v_id uuid; v_name text; v_min int;
begin
  select id, nullif(trim(coalesce(nombre,'') || ' ' || coalesce(apellido,'')), '') into v_profile, v_name from public.profiles where auth_user_id = auth.uid();
  if v_profile is null then raise exception 'Debes iniciar sesión'; end if;
  select response_minutes into v_min from public.businesses where id = p_business_id;
  if v_min is null then raise exception 'Negocio no encontrado'; end if;
  insert into public.orders (business_id, customer_profile_id, items, total, customer_name, due_at)
  values (p_business_id, v_profile, p_items, coalesce(p_total, 0), v_name, now() + make_interval(mins => v_min)) returning id into v_id;
  return v_id;
end $$;
grant execute on function public.create_order(uuid, jsonb, numeric) to authenticated;

-- Business proposes changes (preset message + optional note); the neighbor must accept or cancel.
create or replace function public.modify_order(p_order_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_note text := trim(coalesce(p_note, '')); v_biz uuid;
begin
  if v_note = '' then raise exception 'Escribe o elige un mensaje'; end if;
  if public.chat_text_blocked(v_note) then raise exception 'No se permiten números de teléfono ni enlaces'; end if;
  update public.orders o set status = 'modificado', business_note = left(v_note, 300), responded_at = coalesce(o.responded_at, now())
   where o.id = p_order_id and o.status = 'pendiente'
     and (public.is_admin() or o.business_id in (
           select b.id from public.businesses b join public.profiles p on p.id = b.owner_profile_id where p.auth_user_id = auth.uid()));
  if not found then raise exception 'No se pudo modificar el pedido'; end if;
  insert into public.order_messages (order_id, sender_auth_id, sender_role, body)
  values (p_order_id, auth.uid(), 'negocio', left('✏️ Cambios propuestos: ' || v_note, 500));
end $$;
grant execute on function public.modify_order(uuid, text) to authenticated;

-- Neighbor answers the proposal: accept the changes, or cancel the order.
create or replace function public.answer_modification(p_order_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.orders o set status = case when p_accept then 'aceptado' else 'cancelado' end
   where o.id = p_order_id and o.status = 'modificado'
     and o.customer_profile_id in (select id from public.profiles where auth_user_id = auth.uid());
  if not found then raise exception 'No se pudo responder'; end if;
end $$;
grant execute on function public.answer_modification(uuid, boolean) to authenticated;

-- Chat is closed for rejected / completed / cancelled orders; reuse the shared text rule.
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
  elsif exists (select 1 from public.orders o join public.businesses b on b.id = o.business_id join public.profiles p on p.id = b.owner_profile_id where o.id = p_order_id and p.auth_user_id = auth.uid()) then v_role := 'negocio';
  else raise exception 'No participas en este pedido'; end if;
  insert into public.order_messages (order_id, sender_auth_id, sender_role, body)
  values (p_order_id, auth.uid(), v_role, left(v_body, 500)) returning id into v_id;
  return v_id;
end $$;
grant execute on function public.send_order_message(uuid, text) to authenticated;
