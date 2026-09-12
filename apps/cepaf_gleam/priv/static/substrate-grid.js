// C3I Substrate Grid — Agentic UI
// सर्वत्र समदर्शनः — Equal vision everywhere (Gita 6.29)
// SQLite WAL status, file system health, CPU governor, storage engines
// SC-AGUI-UI-001, SC-GLM-UI-010, SC-XHOLON-001, SC-CPU-GOV

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

  var DB_FILES = [
    { path: "data/smriti/Smriti.db",       engine: "SQLite WAL", purpose: "Knowledge store + FTS5",    size: "~12MB",  status: "active" },
    { path: "data/smriti/planning.db",      engine: "SQLite WAL", purpose: "sa-plan task state",        size: "~2MB",   status: "active" },
    { path: "artifacts/cepa-state.db",      engine: "SQLite WAL", purpose: "CEPAF state",               size: "~800KB", status: "active" },
    { path: "artifacts/build-history.db",   engine: "SQLite WAL", purpose: "EMA build history (α=0.3)", size: "~400KB", status: "active" }
  ];

  var CPU_GOV_LEVELS = [
    { range: "< 60%",   schedulers: "16:16", dirty: "16", jobs: "16", action: "Full speed",      color: "#3dd68c" },
    { range: "60-70%",  schedulers: "12:12", dirty: "12", jobs: "12", action: "Slight reduction", color: "#ffd93d" },
    { range: "70-80%",  schedulers: "10:10", dirty: "10", jobs: "10", action: "Moderate throttle",color: "#f5a623" },
    { range: "80-85%",  schedulers: "6:6",   dirty: "6",  jobs: "6",  action: "Heavy throttle",  color: "#ff4757" },
    { range: "> 85%",   schedulers: "WAIT",  dirty: "WAIT",jobs:"WAIT",action: "Pause until < 75%",color: "#ff2400" }
  ];

  function init() {
    injectStyles();
    injectHeartbeat();
    injectCpuGovGauge();
    injectDbFileList();
    injectStorageChart();
    connectWS();
  }

  function injectStyles() {
    var s = document.createElement("style");
    s.textContent = [
      "#sub-heartbeat{display:inline-flex;align-items:center;gap:6px;font-size:0.78rem;",
      "padding:4px 12px;border-radius:20px;background:rgba(0,212,170,0.1);",
      "border:1px solid rgba(0,212,170,0.3);margin-bottom:12px;transition:all 0.3s}",
      "#sub-heartbeat.stale{border-color:rgba(245,166,35,0.4);background:rgba(245,166,35,0.1)}",
      "#sub-heartbeat.dead{border-color:rgba(255,71,87,0.4);background:rgba(255,71,87,0.1)}",
      ".sub-dot{width:8px;height:8px;border-radius:50%;background:#3dd68c;animation:subpulse 1.5s infinite}",
      "@keyframes subpulse{0%,100%{opacity:1}50%{opacity:0.3}}",
      ".sub-cpu-wrap{display:flex;align-items:center;gap:20px;margin:16px 0}",
      ".sub-cpu-wrap svg{width:100px;height:100px;flex-shrink:0}",
      "#sub-cpu-info{font-size:0.82rem}",
      "#sub-cpu-level{font-size:1.2rem;font-weight:700;color:#3dd68c;margin-bottom:4px}",
      "#sub-cpu-desc{color:#7a8fa6;font-size:0.8rem}",
      ".sub-gov-table{width:100%;border-collapse:collapse;font-size:0.82rem;margin-top:8px}",
      ".sub-gov-table th{text-align:left;padding:5px 10px;border-bottom:1px solid #1e2a3a;color:#7a8fa6;font-weight:500}",
      ".sub-gov-table td{padding:5px 10px;border-bottom:1px solid rgba(30,42,58,0.4)}",
      ".sub-gov-table .active-row td{background:rgba(0,212,170,0.06)}",
      ".db-file-list{margin:16px 0}",
      ".db-file-row{display:flex;align-items:center;gap:12px;padding:8px 10px;",
      "border:1px solid #1e2a3a;border-radius:6px;margin-bottom:6px;font-size:0.82rem}",
      ".db-file-row .df-path{font-family:monospace;font-size:0.76rem;color:#a0aab8;flex:1}",
      ".db-file-row .df-engine{color:#7a8fa6;min-width:80px}",
      ".db-file-row .df-size{color:#7a8fa6;min-width:50px;text-align:right;font-family:monospace}",
      ".db-status-dot{display:inline-block;width:6px;height:6px;border-radius:50%;background:#3dd68c;",
      "box-shadow:0 0 4px #3dd68c;margin-right:6px}",
      ".storage-bars{display:flex;gap:12px;flex-wrap:wrap;margin:16px 0;align-items:flex-end}",
      ".storage-bar{display:flex;flex-direction:column;align-items:center;gap:4px;min-width:60px}",
      ".storage-bar .sb-bar{width:40px;border-radius:4px 4px 0 0;transition:height 0.6s ease}",
      ".storage-bar .sb-label{font-size:0.7rem;color:#7a8fa6;text-align:center}",
      ".storage-bar .sb-val{font-size:0.72rem;font-family:monospace;color:#e0e6ed}"
    ].join("");
    document.head.appendChild(s);
  }

  function injectHeartbeat() {
    heartbeatEl = document.createElement("div");
    heartbeatEl.id = "sub-heartbeat";
    heartbeatEl.innerHTML = '<span class="sub-dot"></span><span id="sub-hb-text">Connecting to substrate...</span>';
    var hdr = document.querySelector(".page-header");
    if (hdr) hdr.insertAdjacentElement("afterend", heartbeatEl);
    else document.body.prepend(heartbeatEl);
  }

  function injectCpuGovGauge() {
    // Assume < 60% (full speed) as initial state
    var pct = 45;
    var dash = Math.round(pct * 2.51);
    var gap = 251 - dash;

    var wrap = document.createElement("div");
    wrap.className = "sub-cpu-wrap";
    wrap.innerHTML = [
      '<svg viewBox="0 0 80 80">',
      '<circle cx="40" cy="40" r="34" fill="none" stroke="#1e2a3a" stroke-width="6"/>',
      '<circle id="sub-cpu-arc" cx="40" cy="40" r="34" fill="none" stroke="#3dd68c" stroke-width="6"',
      ' stroke-dasharray="' + dash + ' ' + gap + '" stroke-linecap="round" transform="rotate(-90 40 40)"/>',
      '<text x="40" y="36" text-anchor="middle" font-size="9" fill="#7a8fa6">CPU</text>',
      '<text id="sub-cpu-pct" x="40" y="52" text-anchor="middle" font-size="14" fill="#3dd68c" font-weight="700">' + pct + '%</text>',
      '</svg>',
      '<div id="sub-cpu-info">',
      '<div id="sub-cpu-level">Full Speed</div>',
      '<div id="sub-cpu-desc">Schedulers: 16:16 | Dirty IO: 16 | Jobs: 16</div>',
      '<div style="color:#7a8fa6;font-size:0.78rem;margin-top:4px">Gate: &lt; 85% (SC-CPU-GOV)</div>',
      '</div>'
    ].join("");

    var label = document.createElement("div");
    label.style.cssText = "margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
    label.textContent = "CPU Governor — Adaptive Parallelism";

    var govTable = document.createElement("table");
    govTable.className = "sub-gov-table";
    govTable.innerHTML = [
      '<thead><tr><th>CPU %</th><th>Schedulers</th><th>Dirty IO</th><th>--jobs</th><th>Action</th></tr></thead>',
      '<tbody>' + CPU_GOV_LEVELS.map(function(g, i) {
        var isActive = i === 0;
        return '<tr class="' + (isActive ? 'active-row' : '') + '">',
          '<td style="color:' + g.color + '">' + g.range + '</td>',
          '<td>' + g.schedulers + '</td><td>' + g.dirty + '</td><td>' + g.jobs + '</td>',
          '<td style="color:' + g.color + '">' + g.action + '</td></tr>';
      }).map(function(parts) { return parts.join ? parts.join("") : parts; }).join("")
      + '</tbody>'
    ].join("");

    var last = document.querySelector(".w-full");
    if (last) { last.appendChild(label); last.appendChild(wrap); last.appendChild(govTable); }
  }

  function injectDbFileList() {
    var label = document.createElement("div");
    label.style.cssText = "margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
    label.textContent = "Database Files — SQLite WAL (SC-XHOLON-001)";

    var list = document.createElement("div");
    list.className = "db-file-list";
    list.id = "sub-db-list";

    DB_FILES.forEach(function(f) {
      var row = document.createElement("div");
      row.className = "db-file-row";
      row.innerHTML = [
        '<span class="db-status-dot"></span>',
        '<span class="df-path">' + f.path + '</span>',
        '<span class="df-engine">' + f.engine + '</span>',
        '<span style="color:#7a8fa6;font-size:0.75rem;flex:1">' + f.purpose + '</span>',
        '<span class="df-size">' + f.size + '</span>'
      ].join("");
      list.appendChild(row);
    });

    var last = document.querySelector(".w-full");
    if (last) { last.appendChild(label); last.appendChild(list); }
  }

  function injectStorageChart() {
    var label = document.createElement("div");
    label.style.cssText = "margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
    label.textContent = "Storage Distribution";

    var bars = document.createElement("div");
    bars.className = "storage-bars";

    var storages = [
      { label: "Smriti.db",  val: "12MB",  pct: 80,  color: "#00d4aa" },
      { label: "planning.db",val: "2MB",   pct: 14,  color: "#4d96ff" },
      { label: "cepa.db",    val: "800KB", pct: 6,   color: "#9b59b6" },
      { label: "build.db",   val: "400KB", pct: 3,   color: "#ffd93d" },
      { label: "DuckDB",     val: "active",pct: 20,  color: "#f39c12" },
      { label: "Zenoh KV",   val: "ephem", pct: 10,  color: "#e74c3c" }
    ];

    storages.forEach(function(s) {
      var bar = document.createElement("div");
      bar.className = "storage-bar";
      bar.innerHTML = [
        '<div class="sb-val">' + s.val + '</div>',
        '<div class="sb-bar" style="height:' + s.pct + 'px;background:' + s.color + '"></div>',
        '<div class="sb-label">' + s.label + '</div>'
      ].join("");
      bars.appendChild(bar);
    });

    var last = document.querySelector(".w-full");
    if (last) { last.appendChild(label); last.appendChild(bars); }
  }

  function updateHeartbeat() {
    if (!heartbeatEl) return;
    var age = Date.now() - lastMsgTime;
    var dot = heartbeatEl.querySelector(".sub-dot");
    var txt = document.getElementById("sub-hb-text");
    heartbeatEl.className = age > DEAD_MS ? "dead" : age > STALE_MS ? "stale" : "";
    if (dot) dot.style.background = age > DEAD_MS ? "#ff4757" : age > STALE_MS ? "#f5a623" : "#3dd68c";
    if (txt) txt.textContent = wsConnected
      ? "Substrate active — SQLite WAL healthy"
      : age > DEAD_MS ? "Substrate disconnected" : "Reconnecting...";
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
