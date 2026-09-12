// C3I Device Health Grid — Agentic UI
// सर्वत्र समदर्शनः — Equal vision everywhere
// WebSocket /ws/dashboard, heartbeat indicator, staleness monitor
// SC-AGUI-UI-001..015, SC-GLM-UI-001, SC-SIL4-001
(function () {
  "use strict";

  var WS_PATH = "/ws/dashboard";
  var PING_INTERVAL_MS = 1000;
  var STALE_MS = 3000;
  var DEAD_MS = 10000;
  var RECONNECT_BASE_MS = 1000;
  var RECONNECT_MAX_MS = 30000;

  var ws = null;
  var pingTimer = null;
  var reconnectDelay = RECONNECT_BASE_MS;
  var lastMsgTime = Date.now();

  // ── Heartbeat indicator ──────────────────────────────────────────
  function updateHeartbeat() {
    var dot = document.getElementById("health-grid-heartbeat");
    if (!dot) return;
    var elapsed = Date.now() - lastMsgTime;
    if (elapsed < STALE_MS) {
      dot.style.background = "#3dd68c";
      dot.title = "Live";
    } else if (elapsed < DEAD_MS) {
      dot.style.background = "#f5a623";
      dot.title = "Stale (" + Math.round(elapsed / 1000) + "s)";
    } else {
      dot.style.background = "#ff4757";
      dot.title = "Disconnected";
    }
  }

  // ── Staleness monitor ────────────────────────────────────────────
  function checkStaleness() {
    var elapsed = Date.now() - lastMsgTime;
    var banner = document.getElementById("health-grid-stale-banner");
    if (!banner) return;
    banner.style.display = elapsed > DEAD_MS ? "block" : "none";
  }

  // ── WebSocket ────────────────────────────────────────────────────
  function clearPing() {
    if (pingTimer) { clearInterval(pingTimer); pingTimer = null; }
  }

  function initWS() {
    clearPing();
    var protocol = location.protocol === "https:" ? "wss:" : "ws:";
    try {
      ws = new WebSocket(protocol + "//" + location.host + WS_PATH);
    } catch (e) {
      setTimeout(initWS, reconnectDelay);
      return;
    }

    ws.onopen = function () {
      lastMsgTime = Date.now();
      reconnectDelay = RECONNECT_BASE_MS;
      pingTimer = setInterval(function () {
        if (ws && ws.readyState === 1) ws.send("ping");
      }, PING_INTERVAL_MS);
    };

    ws.onmessage = function () {
      lastMsgTime = Date.now();
    };

    ws.onclose = function () {
      clearPing();
      reconnectDelay = Math.min(reconnectDelay * 2, RECONNECT_MAX_MS);
      setTimeout(initWS, reconnectDelay);
    };

    ws.onerror = function () {
      ws.close();
    };
  }

  // ── CSS injection ────────────────────────────────────────────────
  var style = document.createElement("style");
  style.textContent = [
    "#health-grid-heartbeat{display:inline-block;width:9px;height:9px;border-radius:50%;background:#3dd68c;transition:background 0.3s;vertical-align:middle;margin-right:4px}",
    "#health-grid-stale-banner{display:none;background:#ff475722;border:1px solid #ff4757;border-radius:6px;padding:6px 12px;color:#ff4757;font-size:0.82rem;margin:8px 0}"
  ].join("");
  document.head.appendChild(style);

  // ── Bootstrap ────────────────────────────────────────────────────
  setInterval(updateHeartbeat, 500);
  setInterval(checkStaleness, 2000);
  initWS();
})();
