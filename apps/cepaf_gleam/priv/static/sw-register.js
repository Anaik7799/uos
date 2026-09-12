// /static/sw-register.js — registers /static/sw.js for /planning + dashboard
// Loaded by the Lustre shell as a sibling to planning-grid.js. Pure registration —
// no UI side-effects, no DOM mutation. Authority: SC-PLANNING-EVO-001..010.
(function () {
  if (!('serviceWorker' in navigator)) return;
  if (location.protocol !== 'https:' && location.hostname !== 'localhost' &&
      location.hostname !== '127.0.0.1' && !location.hostname.endsWith('.tail55d152.ts.net')) {
    // Browsers require https or trusted host; skip silently.
    return;
  }
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('/static/sw.js', { scope: '/' })
      .then(function (reg) {
        // Expose for diagnostics (used by the freshness banner offline pill)
        window.__c3i_sw = reg;
        if (reg && reg.active) {
          try {
            reg.active.postMessage({ type: 'cache-stats' });
          } catch (_) {}
        }
      })
      .catch(function (err) {
        // Non-fatal; degrade silently. Page still works without offline cache.
        if (window.console) console.warn('[c3i-sw] registration failed', err && err.message);
      });
    navigator.serviceWorker.addEventListener('message', function (e) {
      if (e.data && e.data.type === 'cache-stats-result' && window.console) {
        console.info('[c3i-sw]', e.data.version, e.data.entries, 'cached');
      }
    });
  });
})();
