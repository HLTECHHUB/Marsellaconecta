-- "Modificar" can now change the order itself: the business lowers quantities or removes items,
-- the neighbor sees the proposed order in the pop-up, and accepting applies the change.
alter table public.orders add column if not exists proposed_items jsonb;
alter table public.orders add column if not exists proposed_total numeric;
alter table public.orders add column if not exists original_items jsonb;
alter table public.orders add column if not exists original_total numeric;

drop function if exists public.modify_order(uuid, text);
create or replace function public.modify_order(p_order_id uuid, p_note text, p_items jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_o public.orders; v_note text := trim(coalesce(p_note, '')); v_it jsonb; v_oq int; v_q int;
        v_new jsonb := '[]'::jsonb; v_total numeric := 0; v_changed boolean := false;
begin
  select * into v_o from public.orders where id = p_order_id and status = 'pendiente' for update;
  if not found then raise exception 'No se pudo modificar el pedido'; end if;
  if not (public.is_admin() or v_o.business_id in (
        select b.id from public.businesses b join public.profiles p on p.id = b.owner_profile_id where p.auth_user_id = auth.uid())) then
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

create or replace function public.answer_modification(p_order_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.orders o set
      status = case when p_accept then 'aceptado' else 'cancelado' end,
      answered_at = now(),
      original_items = case when p_accept and o.proposed_items is not null then coalesce(o.original_items, o.items) else o.original_items end,
      original_total = case when p_accept and o.proposed_items is not null then coalesce(o.original_total, o.total) else o.original_total end,
      items = case when p_accept and o.proposed_items is not null then o.proposed_items else o.items end,
      total = case when p_accept and o.proposed_items is not null then o.proposed_total else o.total end
   where o.id = p_order_id and o.status = 'modificado'
     and o.customer_profile_id in (select id from public.profiles where auth_user_id = auth.uid());
  if not found then raise exception 'No se pudo responder'; end if;
end $$;
grant execute on function public.answer_modification(uuid, boolean) to authenticated;
