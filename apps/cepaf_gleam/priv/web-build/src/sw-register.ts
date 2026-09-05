/**
 * sw-register.ts — Effect-TS service-worker registration
 *
 * Pass-39 migration from priv/static/sw-register.js. Pure registration,
 * no UI side-effects. Per [zk-50657feb899e0a2f] two-step collapse:
 * ships alongside legacy .js; switchover via shell.gleam <script src>.
 *
 * Per [zk-bd82645aedcb5ef4] anti-Stub-That-Lies: register() is a real
 * Promise wrapped in Effect.tryPromise; failures surface as Cause traces.
 *
 * Authority: SC-PLANNING-EVO-001..010, SC-EFFECT-TS-001..007.
 */

import { Effect, pipe } from "effect";

interface CacheStatsMsg {
  type: string;
  version?: unknown;
  entries?: unknown;
}

const isAllowedHost = (h: string): boolean =>
  location.protocol === "https:" ||
  h === "localhost" ||
  h === "127.0.0.1" ||
  h.endsWith(".tail55d152.ts.net");

const registerSw = Effect.tryPromise({
  try: () =>
    navigator.serviceWorker.register("/static/sw.bundled.js", { scope: "/" }).then((reg) => {
      // Expose for diagnostics (used by freshness-banner offline pill).
      (window as unknown as { __c3i_sw?: ServiceWorkerRegistration }).__c3i_sw = reg;
      if (reg.active) {
        try {
          reg.active.postMessage({ type: "cache-stats" });
        } catch {
          // Browser may reject postMessage in some states — non-fatal.
        }
      }
      return reg;
    }),
  catch: (e) => new Error(String(e)),
});

const onMessage = (e: MessageEvent<CacheStatsMsg>) => {
  if (e.data && e.data.type === "cache-stats-result" && typeof console !== "undefined") {
    console.info("[c3i-sw]", e.data.version, e.data.entries, "cached");
  }
};

const main = () => {
  if (!("serviceWorker" in navigator)) return;
  if (!isAllowedHost(location.hostname)) return;

  window.addEventListener("load", () => {
    Effect.runPromise(
      pipe(
        registerSw,
        Effect.catchAll((err) =>
          Effect.sync(() => {
            // Non-fatal; page still works without offline cache.
            if (typeof console !== "undefined") {
              console.warn("[c3i-sw] registration failed", err.message);
            }
          }),
        ),
      ),
    ).catch(() => undefined);

    navigator.serviceWorker.addEventListener("message", onMessage);
  });
};

main();
