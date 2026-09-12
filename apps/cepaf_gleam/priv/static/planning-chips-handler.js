// Pass-27 Phase 4a · planning-chips-handler.js
//
// Demonstrates the planning-grid.js split pattern (roadmap §6 Phase 4) by
// extracting the chip-row click → status filter wiring as a standalone
// file. Loads BEFORE planning-grid.js so the existing IIFE remains
// authoritative; this module just hooks `data-status` chip clicks to the
// Pass-23 paginated endpoint.
//
// Anti-pattern guarded: [zk-3346fc607a1ef9e6] Stub-That-Lies — handler
// makes a real HTTP request to /api/v1/planning/page and dispatches a
// CustomEvent that planning-grid.js can subscribe to. No-op if neither
// the chip-row nor the planning-grid.js IIFE is present.
//
// SC-FILESIZE-001 · SC-AGUI-UI-013 · SC-MUDA-001

(function() {
  "use strict";

  // Public namespace shared with the planning-grid.js IIFE.
  window.__c3iPlanning = window.__c3iPlanning || {};

  function getActiveStatus() {
    var url = new URL(window.location.href);
    return url.searchParams.get("status") || "all";
  }

  function setActiveChip(status) {
    var chips = document.querySelectorAll(".chip-row .chip");
    chips.forEach(function(c) {
      var match = c.getAttribute("data-status") === status;
      c.classList.toggle("chip-active", match);
    });
  }

  function fetchPaginated(status, offset, limit) {
    var url =
      "/api/v1/planning/page?status=" + encodeURIComponent(status) +
      "&offset=" + (offset || 0) +
      "&limit=" + (limit || 100);
    return fetch(url, { headers: { "Accept": "application/json" } })
      .then(function(r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      });
  }

  function dispatchFilterChanged(status, payload) {
    var ev = new CustomEvent("c3i:planning-filter", {
      detail: { status: status, payload: payload },
    });
    window.dispatchEvent(ev);
  }

  function handleChipClick(e) {
    var btn = e.target.closest(".chip[data-status]");
    if (!btn) return;
    e.preventDefault();
    var status = btn.getAttribute("data-status");
    setActiveChip(status);
    // Update URL without page reload (preserves SPA-like UX).
    var url = new URL(window.location.href);
    url.searchParams.set("status", status);
    window.history.pushState({}, "", url.toString());
    // Fetch paginated payload + dispatch event.
    fetchPaginated(status, 0, 100)
      .then(function(payload) { dispatchFilterChanged(status, payload); })
      .catch(function(err) {
        console.warn("[c3i-chips] paginated fetch failed:", err);
      });
  }

  function init() {
    var row = document.querySelector(".chip-row");
    if (!row) return; // No chip-row in DOM — silent no-op (mirrors freshness-monitor pattern).
    row.addEventListener("click", handleChipClick);
    setActiveChip(getActiveStatus());
    // Re-sync on browser back/forward.
    window.addEventListener("popstate", function() {
      setActiveChip(getActiveStatus());
    });
  }

  // Expose tiny API on the namespace for testability + future planning-grid.js use.
  window.__c3iPlanning.chipsHandler = {
    init: init,
    setActiveChip: setActiveChip,
    fetchPaginated: fetchPaginated,
    getActiveStatus: getActiveStatus,
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
