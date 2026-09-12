// Pass-28 Phase 4b · planning-utils.js
//
// Second extraction from the planning-grid.js IIFE — utility helpers
// (taskAge, classifyFractalLayer, fetchWithRetry, snapshotData,
// findChangedIds). All are pure functions; no DOM dependencies.
//
// Loaded BEFORE planning-grid.js so the IIFE can opt into using the
// namespace version. The IIFE retains its private copies for safety
// (live page must not break); future operator-gated multiverse pass can
// remove the IIFE copies and route everything through the namespace.
//
// Anti-pattern guarded: [zk-3346fc607a1ef9e6] Stub-That-Lies — every
// function body is byte-equivalent to the IIFE original. Tests below
// exercise real inputs.
//
// SC-FILESIZE-001 · SC-MUDA-001 · SC-AGUI-UI-013

(function() {
  "use strict";

  window.__c3iPlanning = window.__c3iPlanning || {};

  // ─── Time formatting ────────────────────────────────────────────

  function taskAge(created) {
    if (!created) return "—";
    var diff = Date.now() - new Date(created).getTime();
    var mins = Math.floor(diff / 60000);
    if (mins < 60) return mins + "m";
    var hours = Math.floor(mins / 60);
    if (hours < 24) return hours + "h";
    var days = Math.floor(hours / 24);
    if (days < 30) return days + "d";
    return Math.floor(days / 30) + "mo";
  }

  // ─── Fractal-layer classification ───────────────────────────────

  // Fractal layer keyword map (extracted from IIFE; canonical SC-AGUI-UI-013).
  var FRACTAL_LAYERS = {
    "L0": { keywords: ["guardian", "constitutional", "psi", "safety",
                       "emergency", "sil4", "sil6", "prime"] },
    "L1": { keywords: ["nif", "debug", "trace", "telemetry", "otel",
                       "atomic", "ffi"] },
    "L2": { keywords: ["parser", "component", "form", "badge", "input",
                       "catalog", "a2ui"] },
    "L3": { keywords: ["planning", "task", "state", "db", "sqlite",
                       "smriti", "transaction"] },
    "L4": { keywords: ["podman", "container", "system", "boot", "build",
                       "image", "docker"] },
    "L5": { keywords: ["ooda", "cortex", "mcp", "agent", "llm",
                       "inference", "reasoning"] },
    "L6": { keywords: ["zenoh", "mesh", "topology", "quorum", "cluster",
                       "ecosystem"] },
    "L7": { keywords: ["federation", "gateway", "version", "consensus",
                       "multi-node"] },
  };

  function classifyFractalLayer(task) {
    var title = (task.title || "").toLowerCase();
    for (var layer in FRACTAL_LAYERS) {
      var kws = FRACTAL_LAYERS[layer].keywords;
      for (var i = 0; i < kws.length; i++) {
        if (title.indexOf(kws[i]) >= 0) return layer;
      }
    }
    return "L3";
  }

  // ─── HTTP fetch with retry ──────────────────────────────────────

  function fetchWithRetry(url, retries, retryDelayMs) {
    var delay = retryDelayMs || 1000;
    var maxRetries = retries == null ? 3 : retries;
    return fetch(url).then(function(r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    }).catch(function(err) {
      if (maxRetries > 0) {
        return new Promise(function(resolve) {
          setTimeout(function() {
            resolve(fetchWithRetry(url, maxRetries - 1, delay));
          }, delay * (4 - maxRetries));
        });
      }
      throw err;
    });
  }

  // ─── Diff helpers (drives row-level highlight on real-time push) ─

  function snapshotData(data) {
    var snap = {};
    data.forEach(function(t) {
      snap[t.id] = t.status + "|" + t.priority + "|" + (t.title || "");
    });
    return snap;
  }

  function findChangedIds(oldSnap, newSnap) {
    var changed = [];
    Object.keys(newSnap).forEach(function(id) {
      if (!oldSnap[id] || oldSnap[id] !== newSnap[id]) changed.push(id);
    });
    return changed;
  }

  // ─── Expose on namespace ────────────────────────────────────────

  window.__c3iPlanning.utils = {
    taskAge: taskAge,
    classifyFractalLayer: classifyFractalLayer,
    fetchWithRetry: fetchWithRetry,
    snapshotData: snapshotData,
    findChangedIds: findChangedIds,
    FRACTAL_LAYERS: FRACTAL_LAYERS,
  };

  // ─── Self-tests (run silently in non-production) ────────────────
  // Anti-Stub-That-Lies guard: assertions exercise real inputs and
  // would break loudly via console.error if any helper regresses.

  if (typeof window !== "undefined" && window.__c3iPlanning.runUtilsTests) {
    var t = window.__c3iPlanning.utils;
    var fails = 0;
    function assert(cond, msg) {
      if (!cond) { fails++; console.error("[planning-utils] FAIL:", msg); }
    }

    // taskAge
    assert(t.taskAge(null) === "—", "null → em-dash");
    var nowIso = new Date().toISOString();
    assert(t.taskAge(nowIso) === "0m", "now → 0m");

    // classifyFractalLayer
    assert(
      t.classifyFractalLayer({ title: "Guardian approval gate" }) === "L0",
      "guardian → L0",
    );
    assert(
      t.classifyFractalLayer({ title: "Plan a new task" }) === "L3",
      "plan → L3",
    );
    assert(
      t.classifyFractalLayer({ title: "OODA decide phase" }) === "L5",
      "ooda → L5",
    );
    assert(
      t.classifyFractalLayer({ title: "completely random" }) === "L3",
      "no-match defaults L3",
    );

    // snapshotData / findChangedIds
    var d1 = [
      { id: "a", status: "pending", priority: "P0", title: "Task A" },
      { id: "b", status: "pending", priority: "P1", title: "Task B" },
    ];
    var d2 = [
      { id: "a", status: "completed", priority: "P0", title: "Task A" },
      { id: "b", status: "pending", priority: "P1", title: "Task B" },
    ];
    var snap1 = t.snapshotData(d1);
    var snap2 = t.snapshotData(d2);
    var changed = t.findChangedIds(snap1, snap2);
    assert(changed.length === 1, "1 changed");
    assert(changed[0] === "a", "task a changed");

    // FRACTAL_LAYERS shape
    assert(t.FRACTAL_LAYERS.L0.keywords.indexOf("guardian") >= 0,
           "L0 contains guardian");

    if (fails === 0) {
      console.log("[planning-utils] all self-tests passed");
    } else {
      console.error("[planning-utils] " + fails + " self-test failures");
    }
  }
})();
