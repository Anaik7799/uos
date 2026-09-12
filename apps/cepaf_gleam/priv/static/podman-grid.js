// C3I Podman Grid — Agentic UI
// सर्वत्र समदर्शनः — Equal vision everywhere (Gita 6.29)
// Container genome, health status, build history, apoptosis monitoring
// SC-AGUI-UI-001, SC-GLM-UI-010, SC-CNT-001, SC-SIL4-001

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

  // 16-container SIL-6 genome (matches CLAUDE.md §2)
  var GENOME = [
    { id: "db-prod",        category: "Database",      status: "running",   cpu: 0.05, mem: 0.35, tier: 2 },
    { id: "obs-prod",       category: "Observability", status: "running",   cpu: 0.08, mem: 0.28, tier: 3 },
    { id: "ex-app-1",       category: "ElixirApp",     status: "running",   cpu: 0.22, mem: 0.41, tier: 6 },
    { id: "cepaf-bridge",   category: "FsharpBridge",  status: "running",   cpu: 0.05, mem: 0.15, tier: 5 },
    { id: "cortex",         category: "FsharpCortex",  status: "running",   cpu: 0.31, mem: 0.55, tier: 5 },
    { id: "zenoh-router",   category: "ZenohRouter",   status: "running",   cpu: 0.02, mem: 0.08, tier: 1 },
    { id: "ollama",         category: "AiCompute",     status: "running",   cpu: 0.15, mem: 0.60, tier: 6 },
    { id: "mojo",           category: "MlRunner",      status: "running",   cpu: 0.12, mem: 0.45, tier: 7 },
    { id: "zenoh-router-1", category: "ZenohRouter",   status: "running",   cpu: 0.02, mem: 0.08, tier: 4 },
    { id: "zenoh-router-2", category: "ZenohRouter",   status: "running",   cpu: 0.02, mem: 0.08, tier: 4 },
    { id: "zenoh-router-3", category: "ZenohRouter",   status: "running",   cpu: 0.02, mem: 0.08, tier: 4 },
    { id: "ex-app-2",       category: "ElixirApp",     status: "running",   cpu: 0.18, mem: 0.38, tier: 7 },
    { id: "ex-app-3",       category: "ElixirApp",     status: "running",   cpu: 0.19, mem: 0.40, tier: 7 },
    { id: "chaya",          category: "ElixirApp",     status: "apoptotic", cpu: 0.08, mem: 0.20, tier: 6 },
    { id: "ml-runner-1",    category: "MlRunner",      status: "running",   cpu: 0.25, mem: 0.70, tier: 7 },
    { id: "ml-runner-2",    category: "MlRunner",      status: "apoptotic", cpu: 0.23, mem: 0.68, tier: 7 }
  ];

  var CATEGORY_COLORS = {
    "ElixirApp":     "#00d4aa", "FsharpBridge": "#4d96ff", "FsharpCortex": "#9b59b6",
    "ZenohRouter":   "#e74c3c", "Database":     "#f39c12", "Observability": "#ffd93d",
    "AiCompute":     "#6bcb77", "MlRunner":     "#ff6b6b"
  };

  function init() {
    injectStyles();
    injectHeartbeat();
    injectGenomeGrid();
    injectHealthRings();
    connectWS();
  }

  function injectStyles() {
    var s = document.createElement("style");
    s.textContent = [
      "#pod-heartbeat{display:inline-flex;align-items:center;gap:6px;font-size:0.78rem;",
      "padding:4px 12px;border-radius:20px;background:rgba(0,212,170,0.1);",
      "border:1px solid rgba(0,212,170,0.3);margin-bottom:12px;transition:all 0.3s}",
      "#pod-heartbeat.stale{border-color:rgba(245,166,35,0.4);background:rgba(245,166,35,0.1)}",
      "#pod-heartbeat.dead{border-color:rgba(255,71,87,0.4);background:rgba(255,71,87,0.1)}",
      ".pod-dot{width:8px;height:8px;border-radius:50%;background:#3dd68c;animation:podpulse 1.5s infinite}",
      "@keyframes podpulse{0%,100%{opacity:1}50%{opacity:0.3}}",
      "#pod-genome-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:8px;margin:16px 0}",
      ".pod-container-card{background:rgba(10,14,23,0.8);border:1px solid #1e2a3a;",
      "border-radius:8px;padding:10px 12px;transition:all 0.2s}",
      ".pod-container-card:hover{border-color:rgba(0,212,170,0.3);transform:translateY(-1px)}",
      ".pod-container-card.apoptotic{border-color:rgba(255,71,87,0.3);background:rgba(255,71,87,0.04)}",
      ".pod-container-card .c-id{font-family:monospace;font-size:0.78rem;font-weight:700}",
      ".pod-container-card .c-cat{font-size:0.7rem;color:#7a8fa6;margin-top:2px}",
      ".pod-container-card .c-bars{margin-top:8px;display:flex;flex-direction:column;gap:4px}",
      ".mini-bar{display:flex;align-items:center;gap:6px;font-size:0.68rem}",
      ".mini-bar .mb-label{color:#7a8fa6;min-width:24px}",
      ".mini-bar .mb-track{flex:1;height:4px;background:#1e2a3a;border-radius:2px;overflow:hidden}",
      ".mini-bar .mb-fill{height:100%;border-radius:2px;transition:width 0.8s}",
      ".mini-bar .mb-val{color:#7a8fa6;min-width:28px;text-align:right}",
      ".pod-status-dot{display:inline-block;width:6px;height:6px;border-radius:50%;margin-right:4px}",
      ".pod-status-dot.running{background:#3dd68c;box-shadow:0 0 4px #3dd68c}",
      ".pod-status-dot.apoptotic{background:#ff4757;animation:apoblink 1s infinite}",
      "@keyframes apoblink{0%,100%{opacity:1}50%{opacity:0.3}}",
      ".pod-health-rings{display:flex;gap:16px;flex-wrap:wrap;margin:16px 0;align-items:center}",
      ".pod-health-ring{display:flex;flex-direction:column;align-items:center;gap:4px}",
      ".pod-health-ring svg{width:80px;height:80px}",
      ".pod-health-ring .hr-label{font-size:0.72rem;color:#7a8fa6;text-align:center}"
    ].join("");
    document.head.appendChild(s);
  }

  function injectHeartbeat() {
    heartbeatEl = document.createElement("div");
    heartbeatEl.id = "pod-heartbeat";
    var running = GENOME.filter(function(c) { return c.status === "running"; }).length;
    heartbeatEl.innerHTML = '<span class="pod-dot"></span><span id="pod-hb-text">' +
      running + '/16 containers running — mesh healthy</span>';
    var hdr = document.querySelector(".page-header");
    if (hdr) hdr.insertAdjacentElement("afterend", heartbeatEl);
    else document.body.prepend(heartbeatEl);
  }

  function injectHealthRings() {
    var running = GENOME.filter(function(c) { return c.status === "running"; }).length;
    var healthy = running;
    var total = GENOME.length;
    var pct = Math.round(healthy * 100 / total);
    var dash = Math.round(pct * 2.51);
    var gap = 251 - dash;

    var avgCpu = GENOME.reduce(function(a, c) { return a + c.cpu; }, 0) / total;
    var cpuPct = Math.round(avgCpu * 100);
    var cpuDash = Math.round(cpuPct * 2.51);
    var cpuGap = 251 - cpuDash;

    var container = document.createElement("div");
    container.className = "pod-health-rings";
    container.innerHTML = [
      ringHTML("ring-health", pct + "%", "#3dd68c", dash, gap, "Health"),
      ringHTML("ring-cpu",    cpuPct + "%", cpuPct > 80 ? "#ff4757" : cpuPct > 60 ? "#f5a623" : "#00d4aa", cpuDash, cpuGap, "CPU avg"),
      ringHTML("ring-quorum", "2oo3", "#ff6b6b", 209, 42, "Quorum SIL-4")
    ].join("");

    var label = document.createElement("div");
    label.style.cssText = "margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
    label.textContent = "Genome Health";

    var last = document.querySelector(".w-full");
    if (last) { last.appendChild(label); last.appendChild(container); }
  }

  function ringHTML(id, val, color, dash, gap, label) {
    return [
      '<div class="pod-health-ring">',
      '<svg viewBox="0 0 80 80">',
      '<circle cx="40" cy="40" r="34" fill="none" stroke="#1e2a3a" stroke-width="6"/>',
      '<circle cx="40" cy="40" r="34" fill="none" stroke="' + color + '" stroke-width="6"',
      ' stroke-dasharray="' + dash + ' ' + gap + '" stroke-linecap="round"',
      ' transform="rotate(-90 40 40)"/>',
      '<text x="40" y="46" text-anchor="middle" font-size="12" fill="' + color + '" font-weight="700" id="' + id + '">' + val + '</text>',
      '</svg>',
      '<span class="hr-label">' + label + '</span>',
      '</div>'
    ].join("");
  }

  function injectGenomeGrid() {
    var label = document.createElement("div");
    label.style.cssText = "margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
    label.textContent = "16-Container SIL-6 Genome — Live Status";

    var grid = document.createElement("div");
    grid.id = "pod-genome-grid";

    GENOME.forEach(function(c) {
      var color = CATEGORY_COLORS[c.category] || "#7a8fa6";
      var isApo = c.status === "apoptotic";
      var card = document.createElement("div");
      card.className = "pod-container-card" + (isApo ? " apoptotic" : "");
      card.id = "pod-card-" + c.id;
      card.innerHTML = [
        '<div class="c-id" style="color:' + color + '">',
        '<span class="pod-status-dot ' + c.status + '"></span>' + c.id + '</div>',
        '<div class="c-cat">T' + c.tier + ' · ' + c.category + '</div>',
        '<div class="c-bars">',
        '<div class="mini-bar"><span class="mb-label">CPU</span>',
        '<div class="mb-track"><div class="mb-fill" style="width:' + Math.round(c.cpu * 100) + '%;background:' + color + '"></div></div>',
        '<span class="mb-val">' + Math.round(c.cpu * 100) + '%</span></div>',
        '<div class="mini-bar"><span class="mb-label">MEM</span>',
        '<div class="mb-track"><div class="mb-fill" style="width:' + Math.round(c.mem * 100) + '%;background:' + color + '88"></div></div>',
        '<span class="mb-val">' + Math.round(c.mem * 100) + '%</span></div>',
        '</div>'
      ].join("");
      grid.appendChild(card);
    });

    var last = document.querySelector(".w-full");
    if (last) { last.appendChild(label); last.appendChild(grid); }
  }

  function updateFromWS(d) {
    if (!d || !d.status) return;
    try {
      var st = typeof d.status === "string" ? JSON.parse(d.status) : d.status;
      var healthyCount = st.healthy_count || 0;
      var totalCount = st.container_count || 16;
      var pct = totalCount > 0 ? Math.round(healthyCount * 100 / totalCount) : 100;
      var ring = document.getElementById("ring-health");
      if (ring) ring.textContent = pct + "%";
      var txt = document.getElementById("pod-hb-text");
      if (txt) txt.textContent = healthyCount + "/" + totalCount + " containers running";
    } catch(_) {}
  }

  function updateHeartbeat() {
    if (!heartbeatEl) return;
    var age = Date.now() - lastMsgTime;
    var dot = heartbeatEl.querySelector(".pod-dot");
    heartbeatEl.className = age > DEAD_MS ? "dead" : age > STALE_MS ? "stale" : "";
    if (dot) dot.style.background = age > DEAD_MS ? "#ff4757" : age > STALE_MS ? "#f5a623" : "#3dd68c";
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
      try { updateFromWS(JSON.parse(e.data)); } catch(_) {}
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

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
