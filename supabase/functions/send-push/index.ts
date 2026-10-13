// Conecta Marsella — send Web Push notifications (admin only).
// Secrets (Supabase > Edge Functions > Secrets):
//   VAPID_PRIVATE_KEY  — private key (base64url) paired with vapidPublicKey in assets/js/config.js
//   VAPID_PUBLIC_KEY   — the same public key as config.js
//   VAPID_SUBJECT      — mailto:info@hl-techhub.com
import { createClient } from 'jsr:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } });
    const { data: isAdmin } = await asUser.rpc('is_admin');
    if (isAdmin !== true) return json({ error: 'Solo administradores' }, 403);

    const { title, body, url: link, audience } = await req.json();
    if (!title || !body) return json({ error: 'Falta título o mensaje' }, 400);
    if (link && !/^https:\/\//.test(link)) return json({ error: 'Enlace inválido' }, 400);

    const pub = Deno.env.get('VAPID_PUBLIC_KEY'), priv = Deno.env.get('VAPID_PRIVATE_KEY');
    if (!pub || !priv) return json({ error: 'Faltan las llaves VAPID en los secretos de la función' }, 500);
    webpush.setVapidDetails(Deno.env.get('VAPID_SUBJECT') || 'mailto:info@hl-techhub.com', pub, priv);

    const db = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    let { data: subs } = await db.from('push_subscriptions').select('id,endpoint,p256dh,auth,profile_id');
    subs = subs || [];
    if (audience && audience !== 'all') {
      const ids = subs.map((s) => s.profile_id).filter(Boolean);
      const { data: profs } = ids.length ? await db.from('profiles').select('auth_user_id,zona').in('auth_user_id', ids) : { data: [] };
      const zonaOf = new Map((profs || []).map((p) => [p.auth_user_id, p.zona]));
      subs = subs.filter((s) => s.profile_id && (audience === 'registered' || zonaOf.get(s.profile_id) === audience));
    }

    const payload = JSON.stringify({ title: String(title).slice(0, 60), body: String(body).slice(0, 160), url: link || './' });
    let sent = 0, failed = 0; const dead: string[] = [];
    await Promise.all(subs.map(async (s) => {
      try { await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload); sent++; }
      catch (e) { failed++; if (e?.statusCode === 404 || e?.statusCode === 410) dead.push(s.id); }
    }));
    if (dead.length) await db.from('push_subscriptions').delete().in('id', dead);
    await db.from('push_log').insert({ title, body, url: link || null, audience: audience || 'all', sent, failed });
    return json({ sent, failed });
  } catch (e) {
    return json({ error: String(e?.message || e) }, 500);
  }
});
