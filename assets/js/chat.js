// Order chat: a bottom-sheet conversation between the neighbor and the business.
import { supabase } from './supabase.js';

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const hhmm = (d) => new Date(d).toLocaleTimeString('es-SV', { timeZone: 'America/El_Salvador', hour: '2-digit', minute: '2-digit' });
const seenKey = (id) => 'mc_chat_seen_' + id;
let css = false, state = null;
export const blockedReason = (t) => (/(\d[\s\-.()+_/]*){7,}/.test(t) || /((cero|uno|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve)[\s\-.,]*){6,}/i.test(t) || /(wa\.me|t\.me|https?:\/\/|www\.)/i.test(t))
  ? 'No se permiten números de teléfono ni enlaces en el chat.' : '';

function injectCss() {
  if (css) return; css = true;
  const st = document.createElement('style');
  st.textContent = `
  .mcc-ov{position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:900;display:flex;align-items:flex-end;justify-content:center}
  .mcc-box{background:#fff;width:100%;max-width:520px;height:82vh;border-radius:20px 20px 0 0;display:flex;flex-direction:column;font-family:system-ui,-apple-system,'Segoe UI',sans-serif;color:#2d2622}
  @media(min-width:641px){.mcc-ov{align-items:center}.mcc-box{border-radius:20px;height:70vh}}
  .mcc-head{display:flex;justify-content:space-between;align-items:center;padding:14px 16px;border-bottom:1px solid #e8e2db}
  .mcc-head b{font-size:1rem}.mcc-head small{display:block;color:#6b6560;font-size:.75rem;font-weight:400}
  .mcc-x{background:none;border:none;font-size:1.5rem;cursor:pointer;color:#6b6560}
  .mcc-list{flex:1;overflow-y:auto;padding:14px;display:flex;flex-direction:column;gap:8px;background:#faf7f2}
  .mcc-empty{margin:auto;color:#6b6560;font-size:.88rem;text-align:center;padding:20px}
  .mcc-b{max-width:82%;padding:9px 12px;border-radius:16px;font-size:.93rem;line-height:1.4;word-wrap:break-word;white-space:pre-wrap}
  .mcc-b small{display:block;font-size:.68rem;opacity:.65;margin-top:3px}
  .mcc-me{align-self:flex-end;background:#1b6b4a;color:#fff;border-bottom-right-radius:5px}
  .mcc-them{align-self:flex-start;background:#fff;border:1px solid #e8e2db;border-bottom-left-radius:5px}
  .mcc-rep{background:none;border:none;color:#b3261e;font-size:.68rem;cursor:pointer;padding:0 0 0 6px}
  .mcc-form{display:flex;gap:8px;padding:10px 12px calc(10px + env(safe-area-inset-bottom));border-top:1px solid #e8e2db}
  .mcc-form input{flex:1;padding:12px 14px;border:1.5px solid #e8e2db;border-radius:22px;font:inherit;font-size:16px;outline:none}
  .mcc-form button{background:#c65d3b;color:#fff;border:none;border-radius:22px;padding:0 18px;font:inherit;font-weight:700;cursor:pointer}
  .mcc-note{font-size:.72rem;color:#6b6560;text-align:center;padding:6px 12px;background:#fff4e5}`;
  document.head.appendChild(st);
}

export async function unreadCount(orderId, myAuthId) {
  const since = Number(localStorage.getItem(seenKey(orderId)) || 0);
  const { data } = await supabase.from('order_messages').select('created_at,sender_auth_id').eq('order_id', orderId).order('created_at', { ascending: false }).limit(30);
  return (data || []).filter((m) => m.sender_auth_id !== myAuthId && new Date(m.created_at).getTime() > since).length;
}

export async function openOrderChat(orderId, title) {
  injectCss(); closeChat();
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) { alert('Inicia sesión para usar el chat.'); return; }
  const me = session.user.id;
  const { data: ord } = await supabase.from('orders').select('status').eq('id', orderId).maybeSingle();
  const closed = !ord || ['rechazado', 'completado'].includes(ord.status);
  const ov = document.createElement('div'); ov.className = 'mcc-ov';
  ov.innerHTML = `<div class="mcc-box"><div class="mcc-head"><div><b>💬 ${esc(title || 'Chat del pedido')}</b><small>Solo tú y el otro participante ven esta conversación</small></div><button class="mcc-x" aria-label="Cerrar">✕</button></div>
    <div class="mcc-list" id="mccList"><div class="mcc-empty">Cargando…</div></div>
    ${closed ? '<div class="mcc-note">🔒 Este pedido ya se completó o no está disponible. El chat está cerrado.</div>' : '<div class="mcc-note">Por seguridad no se permiten números de teléfono ni enlaces. Usen este chat hasta completar el pedido.</div><form class="mcc-form" id="mccForm"><input id="mccIn" maxlength="500" placeholder="Escribe un mensaje…" autocomplete="off"><button type="submit">Enviar</button></form>'}</div>`;
  document.body.appendChild(ov);
  ov.addEventListener('click', (e) => { if (e.target === ov) closeChat(); });
  ov.querySelector('.mcc-x').onclick = closeChat;
  const list = ov.querySelector('#mccList'); const shown = new Set();
  state = { ov, timer: null, channel: null };

  const add = (m) => {
    if (shown.has(m.id)) return; shown.add(m.id);
    list.querySelector('.mcc-empty')?.remove();
    const mine = m.sender_auth_id === me;
    const el = document.createElement('div'); el.className = 'mcc-b ' + (mine ? 'mcc-me' : 'mcc-them');
    el.innerHTML = esc(m.body) + `<small>${hhmm(m.created_at)}${mine ? '' : '<button class="mcc-rep" title="Reportar">⚑ Reportar</button>'}</small>`;
    const rep = el.querySelector('.mcc-rep');
    if (rep) rep.onclick = async () => { if (!confirm('¿Reportar este mensaje al administrador?')) return; const { error } = await supabase.rpc('report_order_message', { p_message_id: m.id }); rep.textContent = error ? '' : '✓ Reportado'; };
    list.appendChild(el); list.scrollTop = list.scrollHeight;
    localStorage.setItem(seenKey(orderId), String(Date.now()));
  };
  const load = async () => {
    const { data } = await supabase.from('order_messages').select('*').eq('order_id', orderId).order('created_at', { ascending: true }).limit(200);
    (data || []).forEach(add);
    if (!shown.size && !list.querySelector('.mcc-empty')) return;
    if (!shown.size) list.innerHTML = '<div class="mcc-empty">Aún no hay mensajes.<br>Escribe el primero 👋</div>';
  };
  await load();
  try { state.channel = supabase.channel('chat-' + orderId).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'order_messages', filter: 'order_id=eq.' + orderId }, (p) => add(p.new)).subscribe(); } catch (_) {}
  state.timer = setInterval(load, 7000); // fallback if realtime is unavailable

  const form = ov.querySelector('#mccForm'); if (!form) return;
  form.onsubmit = async (e) => {
    e.preventDefault();
    const inp = ov.querySelector('#mccIn'); const body = inp.value.trim(); if (!body) return;
    const why = blockedReason(body); if (why) { alert(why); return; }
    inp.value = ''; inp.focus();
    const { data: id, error } = await supabase.rpc('send_order_message', { p_order_id: orderId, p_body: body });
    if (error) { alert('No se pudo enviar: ' + error.message); inp.value = body; return; }
    await load();
    supabase.functions.invoke('order-push', { body: { order_id: orderId, event: 'message' } }).catch(() => {});
  };
}

export function closeChat() {
  if (!state) return;
  clearInterval(state.timer); try { if (state.channel) supabase.removeChannel(state.channel); } catch (_) {}
  state.ov.remove(); state = null;
}
