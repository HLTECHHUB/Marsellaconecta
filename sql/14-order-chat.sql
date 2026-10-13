-- In-app chat between a neighbor and a business, scoped to an order.
create table if not exists public.order_messages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  sender_auth_id uuid not null,
  sender_role text not null check (sender_role in ('cliente','negocio')),
  body text not null check (char_length(body) between 1 and 500),
  reported boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists order_messages_order_idx on public.order_messages (order_id, created_at);
alter table public.order_messages enable row level security;

-- Only the two people in the order (and admins) can read the conversation.
drop policy if exists "order_messages_read" on public.order_messages;
create policy "order_messages_read" on public.order_messages for select to authenticated using (
  public.is_admin() or exists (
    select 1 from public.orders o where o.id = order_id and (
      o.customer_profile_id in (select id from public.profiles where auth_user_id = auth.uid())
      or o.business_id in (select b.id from public.businesses b join public.profiles p on p.id = b.owner_profile_id where p.auth_user_id = auth.uid())
    )));

create or replace function public.send_order_message(p_order_id uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_role text; v_id uuid; v_status text; v_body text := trim(coalesce(p_body, ''));
begin
  if v_body = '' then raise exception 'Mensaje vacío'; end if;
  select o.status into v_status from public.orders o where o.id = p_order_id;
  if v_status is null then raise exception 'Pedido no encontrado'; end if;
  if v_status = 'rechazado' then raise exception 'Este pedido ya no está disponible'; end if;
  if exists (select 1 from public.orders o join public.profiles p on p.id = o.customer_profile_id where o.id = p_order_id and p.auth_user_id = auth.uid()) then v_role := 'cliente';
  elsif exists (select 1 from public.orders o join public.businesses b on b.id = o.business_id join public.profiles p on p.id = b.owner_profile_id where o.id = p_order_id and p.auth_user_id = auth.uid()) then v_role := 'negocio';
  else raise exception 'No participas en este pedido'; end if;
  insert into public.order_messages (order_id, sender_auth_id, sender_role, body)
  values (p_order_id, auth.uid(), v_role, left(v_body, 500)) returning id into v_id;
  return v_id;
end $$;
grant execute on function public.send_order_message(uuid, text) to authenticated;

-- The other person in the chat can report a message for admin review.
create or replace function public.report_order_message(p_message_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.order_messages m set reported = true
   where m.id = p_message_id and m.sender_auth_id <> auth.uid()
     and exists (
       select 1 from public.orders o where o.id = m.order_id and (
         o.customer_profile_id in (select id from public.profiles where auth_user_id = auth.uid())
         or o.business_id in (select b.id from public.businesses b join public.profiles p on p.id = b.owner_profile_id where p.auth_user_id = auth.uid())));
  if not found then raise exception 'No se pudo reportar'; end if;
end $$;
grant execute on function public.report_order_message(uuid) to authenticated;

-- Live updates.
alter publication supabase_realtime add table public.order_messages;
