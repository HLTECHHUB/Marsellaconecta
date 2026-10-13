// Shared Web Push helpers (opt-in on this device).
import { supabase } from './supabase.js';
import { CONFIG } from './config.js';

const VAPID = CONFIG.vapidPublicKey || 'BE050g6DLdrcEqjsSqPfLWzB7seV8eN_OP9YeDXLXUPbWz1eicR6f_A__jNDu7xyV4LaeM8nungqj0PU86c27Yw';
const isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const isStandalone = () => window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
const b64ToU8 = (b) => { const p = '='.repeat((4 - b.length % 4) % 4); const r = atob((b + p).replace(/-/g, '+').replace(/_/g, '/')); return Uint8Array.from([...r].map((c) => c.charCodeAt(0))); };

async function registration() {
  let reg = await navigator.serviceWorker.getRegistration();
  if (!reg) reg = await navigator.serviceWorker.register(new URL('../../sw.js', import.meta.url).href);
  return navigator.serviceWorker.ready;
}

// 'unsupported' | 'needs-install' (iPhone, not added to home screen) | 'denied' | 'on' | 'off'
export async function pushState() {
  if (!('serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window)) return 'unsupported';
  if (isIOS && !isStandalone()) return 'needs-install';
  if (Notification.permission === 'denied') return 'denied';
  try { const reg = await registration(); return (await reg.pushManager.getSubscription()) ? 'on' : 'off'; } catch (_) { return 'off'; }
}

export async function enablePush() {
  if ((await Notification.requestPermission()) !== 'granted') throw new Error('Permission denied');
  const reg = await registration();
  const sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64ToU8(VAPID) });
  const j = sub.toJSON();
  const { error } = await supabase.rpc('save_push_subscription', { p_endpoint: j.endpoint, p_p256dh: j.keys.p256dh, p_auth: j.keys.auth });
  if (error) { await sub.unsubscribe(); throw error; }
  return true;
}

export async function disablePush() {
  const reg = await registration();
  const sub = await reg.pushManager.getSubscription();
  if (sub) { await supabase.rpc('delete_push_subscription', { p_endpoint: sub.endpoint }); await sub.unsubscribe(); }
}

// Re-link this device to whoever is signed in right now (so the right person gets the alerts).
export async function relinkPush() {
  try {
    const reg = await registration(); const sub = await reg.pushManager.getSubscription(); if (!sub) return;
    const j = sub.toJSON();
    await supabase.rpc('save_push_subscription', { p_endpoint: j.endpoint, p_p256dh: j.keys.p256dh, p_auth: j.keys.auth });
  } catch (_) {}
}
