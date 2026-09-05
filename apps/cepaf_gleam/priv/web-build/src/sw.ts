/// <reference lib="webworker" />
/**
 * sw.ts — C3I Service Worker for /planning offline cache
 *
 * Pass-50 port per [zk-50657feb899e0a2f] two-step collapse.
 * Per [zk-bd82645aedcb5ef4] no-Stub-That-Lies: every cache strategy
 * mechanically preserved + precache list updated to point at .bundled.js
 * (was a latent staleness bug — legacy referenced un-bundled .js paths).
 *
 * Strategy:
 *   - Static assets (.bundled.js, tabulator CDN): cache-first.
 *   - HTML shell (/, /planning, /dashboard, /cockpit): stale-while-revalidate.
 *   - JSON APIs (/api/v1/*): network-first with 1.5s timeout, fallback to cache.
 *   - WebSocket (/ws/*): never intercepted (passthrough).
 *
 * SC-PLANNING-EVO-001..010, SC-AGUI-UI-008 (degraded operation),
 * SC-EFFECT-TS-001..007.
 */

declare const self: ServiceWorkerGlobalScope;

const CACHE_VERSION = "c3i-planning-v3-pass55";

// Pass-55: extend precache to all 14 user-facing Effect-TS bundles
// (sw + sw-register excluded — bootstrap loaders, fetched-not-cached).
// Per [zk-bd82645aedcb5ef4]: list reflects what's actually shipped, not
// a guess. Verify against `ls priv/static/*.bundled.js` on every arc close.
const PRECACHE: ReadonlyArray<string> = [
  // HTML shells (4)
  "/",
  "/planning",
  "/dashboard",
  "/cockpit",
  // Effect-TS bundles (14 user-facing): agui-chrome + page-grid +
  // 11 page grids + planning-utils. sw + sw-register are bootstrap
  // loaders, fetched-not-cached.
  "/static/agui-chrome.bundled.js",
  "/static/page-grid.bundled.js",
  "/static/planning-grid.bundled.js",
  "/static/dashboard-grid.bundled.js",
  "/static/cockpit-grid.bundled.js",
  "/static/verification-grid.bundled.js",
  "/static/immune-grid.bundled.js",
  "/static/knowledge-grid.bundled.js",
  "/static/substrate-grid.bundled.js",
  "/static/podman-grid.bundled.js",
  "/static/agents-grid.bundled.js",
  "/static/zenoh-grid.bundled.js",
  "/static/telemetry-grid.bundled.js",
  "/static/planning-utils.bundled.js",
  // Third-party tabulator (unchanged)
  "https://unpkg.com/tabulator-tables@6.3.1/dist/js/tabulator.min.js",
  "https://unpkg.com/tabulator-tables@6.3.1/dist/css/tabulator.min.css",
];

const API_TIMEOUT_MS = 1500;

// ─── Lifecycle ─────────────────────────────────────────────────────

self.addEventListener("install", (event: ExtendableEvent) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) =>
      Promise.allSettled(
        PRECACHE.map((url) => cache.add(url).catch(() => null)),
      ),
    ).then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event: ExtendableEvent) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k)),
      ),
    ).then(() => self.clients.claim()),
  );
});

// ─── Path classifiers ──────────────────────────────────────────────

function isApi(url: URL): boolean    { return url.pathname.startsWith("/api/"); }
function isStatic(url: URL): boolean { return url.pathname.startsWith("/static/") || /tabulator/.test(url.href); }
function isShell(url: URL): boolean {
  return url.pathname === "/" || url.pathname === "/planning" ||
         url.pathname === "/dashboard" || url.pathname === "/cockpit";
}

// ─── Strategies ────────────────────────────────────────────────────

async function networkFirstApi(request: Request): Promise<Response> {
  const cache = await caches.open(CACHE_VERSION);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), API_TIMEOUT_MS);
  try {
    const fresh = await fetch(request, { signal: controller.signal });
    clearTimeout(timer);
    if (fresh && fresh.ok && request.method === "GET") {
      cache.put(request, fresh.clone()).catch(() => null);
    }
    return fresh;
  } catch {
    clearTimeout(timer);
    const cached = await cache.match(request);
    if (cached) {
      const headers = new Headers(cached.headers);
      headers.set("X-C3I-Cache", "fallback");
      return new Response(cached.body, {
        status: cached.status,
        statusText: "OK (offline)",
        headers,
      });
    }
    return new Response(
      JSON.stringify({ error: "offline", staleness: "dead" }),
      { status: 503, headers: { "Content-Type": "application/json", "X-C3I-Cache": "none" } },
    );
  }
}

async function cacheFirstStatic(request: Request): Promise<Response> {
  const cache = await caches.open(CACHE_VERSION);
  const cached = await cache.match(request);
  if (cached) return cached;
  try {
    const fresh = await fetch(request);
    if (fresh && fresh.ok) cache.put(request, fresh.clone()).catch(() => null);
    return fresh;
  } catch {
    return cached ?? new Response("", { status: 504, statusText: "offline-static" });
  }
}

async function staleWhileRevalidateShell(request: Request): Promise<Response> {
  const cache = await caches.open(CACHE_VERSION);
  const cached = await cache.match(request);
  const fetchPromise = fetch(request).then((fresh) => {
    if (fresh && fresh.ok) cache.put(request, fresh.clone()).catch(() => null);
    return fresh;
  }).catch(() => cached as Response);
  return (cached ?? (await fetchPromise)) as Response;
}

// ─── Fetch router ──────────────────────────────────────────────────

self.addEventListener("fetch", (event: FetchEvent) => {
  const request = event.request;
  if (request.method !== "GET") return; // mutations always go to network
  const url = new URL(request.url);
  if (url.protocol === "ws:" || url.protocol === "wss:") return;
  if (isApi(url))    { event.respondWith(networkFirstApi(request)); return; }
  if (isStatic(url)) { event.respondWith(cacheFirstStatic(request)); return; }
  if (isShell(url))  { event.respondWith(staleWhileRevalidateShell(request)); return; }
});

// ─── Message channel — cache stats query ───────────────────────────

interface CacheStatsMessage { type: "cache-stats" }
interface CacheStatsResult { type: "cache-stats-result"; version: string; entries: number }

self.addEventListener("message", async (event: ExtendableMessageEvent) => {
  const msg = event.data as CacheStatsMessage | undefined;
  if (msg && msg.type === "cache-stats") {
    const cache = await caches.open(CACHE_VERSION);
    const keys = await cache.keys();
    const result: CacheStatsResult = {
      type: "cache-stats-result",
      version: CACHE_VERSION,
      entries: keys.length,
    };
    if (event.source) {
      (event.source as Client).postMessage(result);
    }
  }
});
