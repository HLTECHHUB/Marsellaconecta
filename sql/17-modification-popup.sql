-- Modifications are no longer posted in the chat; they are shown to the neighbor as a pop-up.
alter table public.orders add column if not exists modified_at timestamptz;
alter table public.orders add column if not exists answered_at timestamptz;

create or replace function public.modify_order(p_order_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_note text := trim(coalesce(p_note, ''));
begin
  if v_note = '' then raise exception 'Escribe o elige un mensaje'; end if;
  if public.chat_text_blocked(v_note) then raise exception 'No se permiten números de teléfono ni enlaces'; end if;
  update public.orders o set status = 'modificado', business_note = left(v_note, 300), modified_at = now(), responded_at = coalesce(o.responded_at, now())
   where o.id = p_order_id and o.status = 'pendiente'
     and (public.is_admin() or o.business_id in (
           select b.id from public.businesses b join public.profiles p on p.id = b.owner_profile_id where p.auth_user_id = auth.uid()));
  if not found then raise exception 'No se pudo modificar el pedido'; end if;
end $$;
grant execute on function public.modify_order(uuid, text) to authenticated;

create or replace function public.answer_modification(p_order_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.orders o set status = case when p_accept then 'aceptado' else 'cancelado' end, answered_at = now()
   where o.id = p_order_id and o.status = 'modificado'
     and o.customer_profile_id in (select id from public.profiles where auth_user_id = auth.uid());
  if not found then raise exception 'No se pudo responder'; end if;
end $$;
grant execute on function public.answer_modification(uuid, boolean) to authenticated;

-- Remove the old "cambios propuestos" lines from existing chats.
delete from public.order_messages where body like '✏️ Cambios propuestos:%';
