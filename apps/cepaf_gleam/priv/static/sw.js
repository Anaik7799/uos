// INV-FRESH-4100-01: live corpus and control APIs are never intercepted.
const CACHE_VERSION = 'c3i-planning-v2-20261031';
self.addEventListener('install', () => { self.skipWaiting(); });
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(
    keys.filter(key => key !== CACHE_VERSION).map(key => caches.delete(key))
  )).then(() => self.clients.claim()));
});
function bypass(path) {
  return ['/api/', '/ag-ui/', '/mcp', '/wiki', '/zk', '/adrs', '/knowledge', '/docs', '/files']
    .some(prefix => path.startsWith(prefix)) || path === '/km' || path.startsWith('/km/') ||
    path === '/sw.js' || path === '/static/sw.js';
}
async function networkFirst(request) {
  const cache = await caches.open(CACHE_VERSION);
  try {
    const response = await fetch(request);
    if (response.ok) await cache.put(request, response.clone());
    return response;
  } catch (error) {
    return await cache.match(request) || new Response('Offline', { status: 503 });
  }
}
self.addEventListener('fetch', event => {
  const path = new URL(event.request.url).pathname;
  if (event.request.method !== 'GET' || bypass(path)) return;
  if (['/', '/planning', '/dashboard', '/cockpit'].includes(path)) {
    event.respondWith(networkFirst(event.request));
  }
});
