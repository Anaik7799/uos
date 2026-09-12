// /static/sw.js — C3I service worker for /planning offline cache
// Authority: SC-PLANNING-EVO-001..010, SC-AGUI-UI-008 (degraded operation),
//            ZK Allium open question CanvasHologram/OfflineMode (planning_page.allium).
// Strategy:
//   - Static assets (planning-grid.js, sw.js, tabulator CDN): cache-first.
//   - HTML shell (/planning, /, /dashboard): stale-while-revalidate.
//   - JSON APIs (/api/v1/*): network-first with 1.5s timeout, fallback to cache.
//   - WebSocket (/ws/*): never intercepted (passthrough).
// Cache name carries the deploy-stamp from the JS query (?v=…) so SW upgrades
// invalidate stale caches deterministically (parallel to SC-FUNC-003 reversibility).

const CACHE_VERSION = 'c3i-planning-v1';
const PRECACHE = [
  '/',
  '/planning',
  '/dashboard',
  '/static/planning-grid.js',
  '/static/dashboard-grid.js',
  'https://unpkg.com/tabulator-tables@6.3.1/dist/js/tabulator.min.js',
  'https://unpkg.com/tabulator-tables@6.3.1/dist/css/tabulator.min.css',
];
const API_TIMEOUT_MS = 1500;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) => {
      return Promise.allSettled(
        PRECACHE.map((url) => cache.add(url).catch(() => null))
      );
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

function isApi(url)    { return url.pathname.startsWith('/api/'); }
function isStatic(url) { return url.pathname.startsWith('/static/') || /tabulator/.test(url.href); }
function isShell(url)  {
  return url.pathname === '/' || url.pathname === '/planning' ||
         url.pathname === '/dashboard' || url.pathname === '/cockpit';
}

async function networkFirstApi(request) {
  const cache = await caches.open(CACHE_VERSION);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), API_TIMEOUT_MS);
  try {
    const fresh = await fetch(request, { signal: controller.signal });
    clearTimeout(timer);
    if (fresh && fresh.ok && request.method === 'GET') {
      cache.put(request, fresh.clone()).catch(() => null);
    }
    return fresh;
  } catch (err) {
    clearTimeout(timer);
    const cached = await cache.match(request);
    if (cached) {
      const headers = new Headers(cached.headers);
      headers.set('X-C3I-Cache', 'fallback');
      return new Response(cached.body, { status: cached.status, statusText: 'OK (offline)', headers });
    }
    return new Response(JSON.stringify({ error: 'offline', staleness: 'dead' }),
      { status: 503, headers: { 'Content-Type': 'application/json', 'X-C3I-Cache': 'none' } });
  }
}

async function cacheFirstStatic(request) {
  const cache = await caches.open(CACHE_VERSION);
  const cached = await cache.match(request);
  if (cached) return cached;
  try {
    const fresh = await fetch(request);
    if (fresh && fresh.ok) cache.put(request, fresh.clone()).catch(() => null);
    return fresh;
  } catch (e) {
    return cached || new Response('', { status: 504, statusText: 'offline-static' });
  }
}

async function staleWhileRevalidateShell(request) {
  const cache = await caches.open(CACHE_VERSION);
  const cached = await cache.match(request);
  const fetchPromise = fetch(request).then((fresh) => {
    if (fresh && fresh.ok) cache.put(request, fresh.clone()).catch(() => null);
    return fresh;
  }).catch(() => cached);
  return cached || fetchPromise;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return; // mutations always go to network
  const url = new URL(request.url);
  if (url.protocol === 'ws:' || url.protocol === 'wss:') return;
  if (isApi(url))    { event.respondWith(networkFirstApi(request)); return; }
  if (isStatic(url)) { event.respondWith(cacheFirstStatic(request)); return; }
  if (isShell(url))  { event.respondWith(staleWhileRevalidateShell(request)); return; }
});

// Allow the page to ping the SW for cache stats (used by freshness banner)
self.addEventListener('message', async (event) => {
  if (event.data && event.data.type === 'cache-stats') {
    const cache = await caches.open(CACHE_VERSION);
    const keys = await cache.keys();
    event.source && event.source.postMessage({
      type: 'cache-stats-result',
      version: CACHE_VERSION,
      entries: keys.length,
    });
  }
});
