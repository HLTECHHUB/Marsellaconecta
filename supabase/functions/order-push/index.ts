// Marsella Conecta — push notifications for order requests.
//   event "new":      the neighbor who made the order notifies the business owner.
//   event "message":  a chat message; goes to the other person in the order.
//   event "modify":   the business proposes changes; notifies the neighbor.
//   event "answer":   the neighbor accepts/cancels after a modification; notifies the business.
//   event "response": the business owner (or an admin) notifies the neighbor of accept/reject.
// Secrets: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (same as send-push).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const SITE = 'https://marsella.hl-techhub.com/';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
const money = (n: number) => '$' + Number(n || 0).toFixed(2);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } });
    const { data: u } = await asUser.auth.getUser();
    const uid = u?.user?.id;
    if (!uid) return json({ error: 'No autenticado' }, 401);
    const { order_id, event } = await req.json();
    if (!order_id || !['new', 'response', 'message', 'modify', 'answer'].includes(event)) return json({ error: 'Datos inválidos' }, 400);

    const db = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: order } = await db.from('orders').select('*').eq('id', order_id).maybeSingle();
    if (!order) return json({ error: 'Pedido no encontrado' }, 404);
    const { data: biz } = await db.from('businesses').select('nombre,owner_profile_id').eq('id', order.business_id).maybeSingle();
    const { data: owner } = biz?.owner_profile_id ? await db.from('profiles').select('auth_user_id').eq('id', biz.owner_profile_id).maybeSingle() : { data: null };
    const { data: cust } = await db.from('profiles').select('auth_user_id').eq('id', order.customer_profile_id).maybeSingle();

    let target: string | null | undefined, payload: Record<string, string>;
    const count = Array.isArray(order.items) ? order.items.reduce((s: number, i: any) => s + (Number(i.qty) || 0), 0) : 0;
    if (event === 'message') {
      const fromCust = cust?.auth_user_id === uid, fromOwner = owner?.auth_user_id === uid;
      if (!fromCust && !fromOwner) return json({ error: 'No permitido' }, 403);
      const { data: last } = await db.from('order_messages').select('body,created_at').eq('order_id', order.id).eq('sender_auth_id', uid).order('created_at', { ascending: false }).limit(2);
      if (!last || !last.length) return json({ notified: 0, reason: 'sin mensaje' });
      // Don't spam: skip the push if the same person already wrote within the last 45 seconds.
      if (last.length > 1 && new Date(last[0].created_at).getTime() - new Date(last[1].created_at).getTime() < 45000) return json({ notified: 0, skipped: true });
      target = fromCust ? owner?.auth_user_id : cust?.auth_user_id;
      const who = fromCust ? (order.customer_name || 'Un vecino') : (biz?.nombre || 'El negocio');
      payload = { title: '💬 ' + who, body: String(last[0].body).slice(0, 100), url: fromCust ? SITE + 'pages/pedidos.html?order=' + order.id : SITE + '?pedido=' + order.id + '&chat=1', tag: 'chat-' + order.id };
    } else if (event === 'modify') {
      if ((owner?.auth_user_id !== uid) || order.status !== 'modificado') return json({ error: 'No permitido' }, 403);
      target = cust?.auth_user_id;
      payload = { title: '✏️ ' + (biz?.nombre || 'El negocio') + ' propone cambios', body: String(order.business_note || 'Revisa los cambios a tu pedido.').slice(0, 110), url: SITE + '?pedido=' + order.id, tag: 'order-' + order.id };
    } else if (event === 'answer') {
      if (cust?.auth_user_id !== uid || !['aceptado', 'cancelado'].includes(order.status)) return json({ error: 'No permitido' }, 403);
      target = owner?.auth_user_id;
      payload = order.status === 'aceptado'
        ? { title: '✅ El vecino aceptó los cambios', body: `${order.customer_name || 'El vecino'} aceptó los cambios. Ya puedes preparar el pedido.`, url: SITE + 'pages/pedidos.html?order=' + order.id, tag: 'order-' + order.id }
        : { title: 'Pedido cancelado', body: `${order.customer_name || 'El vecino'} canceló el pedido tras los cambios.`, url: SITE + 'pages/pedidos.html', tag: 'order-' + order.id };
    } else if (event === 'new') {
      if (cust?.auth_user_id !== uid || order.status !== 'pendiente') return json({ error: 'No permitido' }, 403);
      target = owner?.auth_user_id;
      payload = { title: '🛒 Nuevo pedido para ti', body: `${order.customer_name || 'Un vecino'} pidió ${count} producto(s) por ${money(order.total)}. Toca para aceptar o rechazar.`, url: SITE + 'pages/pedidos.html', tag: 'order-' + order.id };
    } else {
      const { data: isAdmin } = await asUser.rpc('is_admin');
      if ((owner?.auth_user_id !== uid && isAdmin !== true) || order.status === 'pendiente') return json({ error: 'No permitido' }, 403);
      target = cust?.auth_user_id;
      payload = order.status === 'aceptado'
        ? { title: '✅ ¡Tu pedido fue aceptado!', body: `${biz?.nombre || 'El negocio'} aceptó tu pedido. Toca para enviarlo por WhatsApp.`, url: SITE + '?pedido=' + order.id, tag: 'order-' + order.id }
        : { title: 'Pedido no disponible', body: `${biz?.nombre || 'El negocio'} no tiene disponible tu pedido por ahora.`, url: SITE + '?pedido=' + order.id, tag: 'order-' + order.id };
    }
    if (!target) return json({ notified: 0, devices: 0, reason: 'El destinatario no tiene cuenta vinculada' });

    const pub = Deno.env.get('VAPID_PUBLIC_KEY'), priv = Deno.env.get('VAPID_PRIVATE_KEY');
    if (!pub || !priv) return json({ error: 'Faltan las llaves VAPID' }, 500);
    webpush.setVapidDetails(Deno.env.get('VAPID_SUBJECT') || 'mailto:info@hl-techhub.com', pub, priv);

    const { data: subs } = await db.from('push_subscriptions').select('id,endpoint,p256dh,auth').eq('profile_id', target);
    let sent = 0; const dead: string[] = [];
    await Promise.all((subs || []).map(async (s) => {
      try { await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, JSON.stringify(payload)); sent++; }
      catch (e) { if (e?.statusCode === 404 || e?.statusCode === 410) dead.push(s.id); }
    }));
    if (dead.length) await db.from('push_subscriptions').delete().in('id', dead);
    return json({ notified: sent, devices: (subs || []).length });
  } catch (e) {
    return json({ error: String(e?.message || e) }, 500);
  }
});
