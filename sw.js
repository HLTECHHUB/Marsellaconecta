// Marsella Conecta service worker: makes the site installable and keeps the shell available offline.
// Data (Supabase), CDN modules and fonts are never cached here — they always go to the network.
const CACHE = 'marsella-shell-v1';
const SHELL = ['./', './index.html', './manifest.webmanifest', './assets/icons/icon-192.png', './assets/icons/icon-512.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== location.origin) return;
  // Pages: network first, fall back to the cached copy when offline.
  if (req.mode === 'navigate') {
    e.respondWith(fetch(req).then((r) => { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); return r; }).catch(() => caches.match(req).then((r) => r || caches.match('./index.html'))));
    return;
  }
  // Own static files: serve cached, refresh in the background.
  e.respondWith(caches.match(req).then((hit) => {
    const net = fetch(req).then((r) => { if (r.ok) { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); } return r; }).catch(() => hit);
    return hit || net;
  }));
});
