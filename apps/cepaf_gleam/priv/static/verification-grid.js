// C3I Verification Grid — Agentic UI
// सर्वत्र समदर्शनः — Equal vision everywhere (Gita 6.29)
// PROMETHEUS proof status, SIL-6 compliance gates, fractal L0 coverage
// SC-AGUI-UI-001, SC-GLM-UI-010, SC-PROM-001, SC-VER-001

(function() {
  "use strict";

  var WS_PATH = "/ws/dashboard";
  var STALE_MS = 3000;
  var DEAD_MS = 10000;
  var lastMsgTime = Date.now();
  var ws = null;
  var wsConnected = false;
  var reconnectDelay = 1000;
  var pingTimer = null;
  var heartbeatEl = null;

  // ── Fractal layer colors (L0 is primary for verification) ──
  var LAYER_COLORS = {
    "L0": "#ff6b6b", "L1": "#ffd93d", "L2": "#6bcb77", "L3": "#4d96ff",
    "L4": "#9b59b6", "L5": "#00d4aa", "L6": "#e74c3c", "L7": "#f39c12"
  };

  // ── Static verification data (augmented by WS push) ──
  var PROOF_GATES = [
    { gate: "Shannon Entropy H", value: "2.67 bits", target: ">= 2.5 bits", status: "PASS", layer: "L5" },
    { gate: "CCM Coverage",      value: "0.77",      target: ">= 0.90",     status: "WARN", layer: "L2" },
    { gate: "ITQS Score",        value: "0.74",      target: ">= 0.85",     status: "WARN", layer: "L2" },
    { gate: "Quorum 2oo3",       value: "active",    target: "SIL-4",       status: "PASS", layer: "L0" },
    { gate: "Psi-0 Existence",   value: "PASS",      target: "invariant",   status: "PASS", layer: "L0" },
    { gate: "Psi-3 Verification",value: "PASS",      target: "hash chain",  status: "PASS", layer: "L0" },
    { gate: "Ed25519 Attest",    value: "STUB",      target: "L7 NYI",      status: "STUB", layer: "L7" },
    { gate: "Gleam Tests",       value: "1721",      target: "0 failures",  status: "PASS", layer: "L2" }
  ];

  function init() {
    injectStyles();
    injectHeartbeat();
    injectProofRings();
    injectFractalSection();
    connectWS();
  }

  function injectStyles() {
    var s = document.createElement("style");
    s.textContent = [
      "#ver-heartbeat{display:inline-flex;align-items:center;gap:6px;font-size:0.78rem;",
      "padding:4px 12px;border-radius:20px;background:rgba(0,212,170,0.1);",
      "border:1px solid rgba(0,212,170,0.3);margin-bottom:12px;transition:all 0.3s}",
      "#ver-heartbeat.stale{border-color:rgba(245,166,35,0.4);background:rgba(245,166,35,0.1)}",
      "#ver-heartbeat.dead{border-color:rgba(255,71,87,0.4);background:rgba(255,71,87,0.1)}",
      ".ver-dot{width:8px;height:8px;border-radius:50%;background:#3dd68c;animation:verpulse 1.5s infinite}",
      "@keyframes verpulse{0%,100%{opacity:1}50%{opacity:0.3}}",
      ".proof-rings{display:flex;flex-wrap:wrap;gap:16px;margin:12px 0 20px}",
      ".proof-ring{display:flex;flex-direction:column;align-items:center;gap:4px}",
      ".proof-ring svg{width:80px;height:80px}",
      ".proof-ring .ring-label{font-size:0.72rem;color:#7a8fa6;text-align:center;max-width:80px}",
      ".proof-ring .ring-val{font-size:0.85rem;font-weight:600;color:#e0e6ed}",
      ".fractal-bar{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}",
      ".fl-chip{padding:4px 10px;border-radius:12px;font-size:0.72rem;font-weight:600;",
      "border:1px solid rgba(255,255,255,0.1);cursor:default}",
      ".gate-status-PASS{color:#3dd68c}.gate-status-WARN{color:#f5a623}.gate-status-STUB{color:#7a8fa6}",
      "#ver-gate-table{width:100%;border-collapse:collapse;font-size:0.83rem;margin-top:8px}",
      "#ver-gate-table th{text-align:left;padding:6px 10px;border-bottom:1px solid #1e2a3a;color:#7a8fa6;font-weight:500}",
      "#ver-gate-table td{padding:6px 10px;border-bottom:1px solid rgba(30,42,58,0.5)}",
      "#ver-gate-table tr:hover td{background:rgba(0,212,170,0.04)}"
    ].join("");
    document.head.appendChild(s);
  }

  function injectHeartbeat() {
    heartbeatEl = document.createElement("div");
    heartbeatEl.id = "ver-heartbeat";
    heartbeatEl.innerHTML = '<span class="ver-dot"></span><span id="ver-hb-text">Connecting to mesh...</span>';
    var hdr = document.querySelector(".page-header");
    if (hdr) hdr.insertAdjacentElement("afterend", heartbeatEl);
    else document.body.prepend(heartbeatEl);
  }

  function injectProofRings() {
    var container = document.createElement("div");
    container.className = "proof-rings";
    container.id = "ver-rings";

    var rings = [
      { id: "ring-shannon", label: "Shannon H", value: "2.67", color: "#3dd68c", pct: 89 },
      { id: "ring-ccm",     label: "CCM",        value: "0.77",  color: "#f5a623", pct: 77 },
      { id: "ring-itqs",    label: "ITQS",        value: "0.74",  color: "#f5a623", pct: 74 },
      { id: "ring-psi",     label: "Psi Gates",   value: "5/6",   color: "#ff6b6b", pct: 83 }
    ];

    rings.forEach(function(r) {
      var dash = Math.round(r.pct * 2.51);
      var gap  = 251 - dash;
      container.innerHTML += [
        '<div class="proof-ring">',
        '<svg viewBox="0 0 80 80">',
        '<circle cx="40" cy="40" r="34" fill="none" stroke="#1e2a3a" stroke-width="6"/>',
        '<circle cx="40" cy="40" r="34" fill="none" stroke="' + r.color + '" stroke-width="6"',
        ' stroke-dasharray="' + dash + ' ' + gap + '" stroke-linecap="round"',
        ' transform="rotate(-90 40 40)"/>',
        '</svg>',
        '<span class="ring-val">' + r.value + '</span>',
        '<span class="ring-label">' + r.label + '</span>',
        '</div>'
      ].join("");
    });

    var section = document.querySelector(".section-body") || document.querySelector(".w-full");
    if (section) section.insertBefore(container, section.firstChild);
  }

  function injectFractalSection() {
    var container = document.createElement("div");
    container.innerHTML = [
      '<div style="margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">',
      'Fractal Layer Coverage</div>',
      '<div class="fractal-bar" id="ver-fractal-bar">' + renderFractalChips() + '</div>',
      '<table id="ver-gate-table">',
      '<thead><tr><th>Proof Gate</th><th>Value</th><th>Target</th><th>Status</th><th>Layer</th></tr></thead>',
      '<tbody>' + renderGateRows() + '</tbody>',
      '</table>'
    ].join("");
    var last = document.querySelector(".w-full");
    if (last) last.appendChild(container);
  }

  function renderFractalChips() {
    return Object.keys(LAYER_COLORS).map(function(l) {
      return '<span class="fl-chip" style="color:' + LAYER_COLORS[l] +
        ';border-color:' + LAYER_COLORS[l] + '33">' + l + '</span>';
    }).join("");
  }

  function renderGateRows() {
    return PROOF_GATES.map(function(g) {
      var lc = LAYER_COLORS[g.layer] || "#7a8fa6";
      return '<tr><td>' + g.gate + '</td><td style="font-family:monospace">' +
        g.value + '</td><td style="color:#7a8fa6">' + g.target +
        '</td><td class="gate-status-' + g.status + '">' + g.status +
        '</td><td><span style="color:' + lc + ';font-weight:600">' + g.layer + '</span></td></tr>';
    }).join("");
  }

  function updateHeartbeat() {
    if (!heartbeatEl) return;
    var age = Date.now() - lastMsgTime;
    var dot = heartbeatEl.querySelector(".ver-dot");
    var txt = document.getElementById("ver-hb-text");
    heartbeatEl.className = age > DEAD_MS ? "dead" : age > STALE_MS ? "stale" : "";
    if (dot) dot.style.background = age > DEAD_MS ? "#ff4757" : age > STALE_MS ? "#f5a623" : "#3dd68c";
    if (txt) txt.textContent = wsConnected
      ? "Mesh live — verification active"
      : age > DEAD_MS ? "Mesh disconnected" : "Reconnecting...";
  }

  function connectWS() {
    if (ws) { try { ws.close(); } catch(e) {} }
    var proto = location.protocol === "https:" ? "wss:" : "ws:";
    ws = new WebSocket(proto + "//" + location.host + WS_PATH);

    ws.onopen = function() {
      wsConnected = true; reconnectDelay = 1000; lastMsgTime = Date.now();
      pingTimer = setInterval(function() {
        if (ws && ws.readyState === 1) ws.send("ping");
      }, 1000);
    };

    ws.onmessage = function(e) {
      lastMsgTime = Date.now();
      try {
        var d = JSON.parse(e.data);
        if (d.type === "update" || d.type === "connected") updateFromWS(d);
      } catch(_) {}
      updateHeartbeat();
    };

    ws.onclose = function() {
      wsConnected = false; clearInterval(pingTimer);
      setTimeout(connectWS, Math.min(reconnectDelay, 30000));
      reconnectDelay *= 2;
    };

    ws.onerror = function() { ws.close(); };
    setInterval(updateHeartbeat, 1000);
  }

  function updateFromWS(d) {
    // Update quorum status from system health if available
    if (d.status) {
      try {
        var status = typeof d.status === "string" ? JSON.parse(d.status) : d.status;
        if (status.quorum_healthy === false) {
          var row = document.querySelector("#ver-gate-table tbody tr:nth-child(4) td:nth-child(4)");
          if (row) { row.textContent = "FAIL"; row.className = "gate-status-WARN"; }
        }
      } catch(_) {}
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
