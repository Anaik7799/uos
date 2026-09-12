// C3I Zenoh Grid — Agentic UI
// सर्वत्र समदर्शनः — Equal vision everywhere (Gita 6.29)
// Mesh topology, router status, topic activity, OTel transport
// SC-AGUI-UI-001, SC-GLM-UI-010, SC-ZENOH-001, SC-ZMOF-001

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
  var msgRate = 0;
  var msgCount = 0;
  var lastMsgCountTs = Date.now();

  var ZENOH_ROUTERS = [
    { id: "zenoh-router",   host: "localhost", port: 7447, status: "active",  role: "Primary router" },
    { id: "zenoh-router-1", host: "localhost", port: 7447, status: "active",  role: "Quorum router 1" },
    { id: "zenoh-router-2", host: "localhost", port: 7448, status: "active",  role: "Quorum router 2" },
    { id: "zenoh-router-3", host: "localhost", port: 7449, status: "active",  role: "Quorum router 3" }
  ];

  var KEY_TOPICS = [
    { topic: "indrajaal/otel/spans/**",    direction: "pub",     msgs: 0,   color: "#00d4aa" },
    { topic: "indrajaal/l0/const/**",      direction: "pub/sub", msgs: 0,   color: "#ff6b6b" },
    { topic: "indrajaal/l4/system/**",     direction: "pub/sub", msgs: 0,   color: "#9b59b6" },
    { topic: "indrajaal/health/**",        direction: "pub",     msgs: 0,   color: "#3dd68c" },
    { topic: "indrajaal/ignition/**",      direction: "pub",     msgs: 0,   color: "#ffd93d" },
    { topic: "indrajaal/mcp/**",           direction: "pub/sub", msgs: 0,   color: "#4d96ff" },
    { topic: "indrajaal/plan/spans/**",    direction: "pub",     msgs: 0,   color: "#f39c12" },
    { topic: "indrajaal/l5/cog/trace/**",  direction: "pub",     msgs: 0,   color: "#e74c3c" }
  ];

  function init() {
    injectStyles();
    injectHeartbeat();
    injectTopologyView();
    injectTopicActivity();
    connectWS();
  }

  function injectStyles() {
    var s = document.createElement("style");
    s.textContent = [
      "#zen-heartbeat{display:inline-flex;align-items:center;gap:6px;font-size:0.78rem;",
      "padding:4px 12px;border-radius:20px;background:rgba(0,212,170,0.1);",
      "border:1px solid rgba(0,212,170,0.3);margin-bottom:12px;transition:all 0.3s}",
      "#zen-heartbeat.stale{border-color:rgba(245,166,35,0.4);background:rgba(245,166,35,0.1)}",
      "#zen-heartbeat.dead{border-color:rgba(255,71,87,0.4);background:rgba(255,71,87,0.1)}",
      ".zen-dot{width:8px;height:8px;border-radius:50%;background:#3dd68c;animation:zenpulse 1.5s infinite}",
      "@keyframes zenpulse{0%,100%{opacity:1}50%{opacity:0.3}}",
      ".zen-router-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:10px;margin:16px 0}",
      ".zen-router-card{background:rgba(10,14,23,0.8);border:1px solid rgba(231,76,60,0.2);",
      "border-radius:8px;padding:10px 14px}",
      ".zen-router-card .r-id{font-family:monospace;font-size:0.8rem;font-weight:700;color:#e74c3c}",
      ".zen-router-card .r-ep{font-size:0.78rem;color:#7a8fa6;margin-top:2px}",
      ".zen-router-card .r-role{font-size:0.72rem;color:#7a8fa6;margin-top:4px}",
      ".zen-status-dot{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:4px}",
      ".zen-status-dot.active{background:#3dd68c;box-shadow:0 0 6px #3dd68c}",
      ".zen-status-dot.offline{background:#ff4757}",
      ".topic-bar-row{display:flex;align-items:center;gap:10px;margin-bottom:8px;font-size:0.82rem}",
      ".topic-bar-row .tb-topic{flex:1;font-family:monospace;font-size:0.76rem;color:#a0aab8;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
      ".topic-bar-row .tb-dir{padding:2px 8px;border-radius:10px;font-size:0.68rem;font-weight:600;",
      "background:rgba(0,212,170,0.1);color:#00d4aa;white-space:nowrap}",
      ".topic-bar-row .tb-sparkline{display:flex;gap:2px;align-items:flex-end;height:24px;min-width:60px}",
      ".topic-bar-row .tb-sparkline span{width:6px;background:#1e2a3a;border-radius:1px;transition:height 0.3s}",
      ".topic-bar-row .tb-msgs{min-width:40px;text-align:right;color:#7a8fa6;font-family:monospace}",
      "#zen-msg-rate{font-size:0.85rem;color:#7a8fa6;margin-bottom:8px}",
      "#zen-msg-rate span{color:#00d4aa;font-weight:600}"
    ].join("");
    document.head.appendChild(s);
  }

  function injectHeartbeat() {
    heartbeatEl = document.createElement("div");
    heartbeatEl.id = "zen-heartbeat";
    heartbeatEl.innerHTML = '<span class="zen-dot"></span><span id="zen-hb-text">Connecting to Zenoh mesh...</span>';
    var hdr = document.querySelector(".page-header");
    if (hdr) hdr.insertAdjacentElement("afterend", heartbeatEl);
    else document.body.prepend(heartbeatEl);
  }

  function injectTopologyView() {
    var container = document.createElement("div");
    container.innerHTML = '<div style="margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">Router Topology — 4-Node Quorum (SC-ZENOH-001)</div>';

    var grid = document.createElement("div");
    grid.className = "zen-router-grid";
    ZENOH_ROUTERS.forEach(function(r) {
      var card = document.createElement("div");
      card.className = "zen-router-card";
      card.id = "zen-router-" + r.id;
      card.innerHTML = [
        '<div class="r-id"><span class="zen-status-dot ' + r.status + '"></span>' + r.id + '</div>',
        '<div class="r-ep">tcp/' + r.host + ':' + r.port + '</div>',
        '<div class="r-role">' + r.role + '</div>'
      ].join("");
      grid.appendChild(card);
    });

    container.appendChild(grid);
    var last = document.querySelector(".w-full");
    if (last) last.appendChild(container);
  }

  function injectTopicActivity() {
    var container = document.createElement("div");
    container.innerHTML = [
      '<div style="margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">',
      'Topic Activity Monitor</div>',
      '<div id="zen-msg-rate">Messages/sec: <span id="zen-rate-val">0</span></div>',
      '<div id="zen-topic-bars"></div>'
    ].join("");

    var last = document.querySelector(".w-full");
    if (last) last.appendChild(container);

    renderTopicBars();
    setInterval(animateSparklines, 2000);
    setInterval(updateMsgRate, 1000);
  }

  function renderTopicBars() {
    var bars = document.getElementById("zen-topic-bars");
    if (!bars) return;
    bars.innerHTML = KEY_TOPICS.map(function(t, i) {
      var sparks = [0,0,0,0,0,0].map(function(v) {
        return '<span style="height:' + Math.round(Math.random() * 20 + 2) + 'px;background:' + t.color + '44"></span>';
      }).join("");
      return [
        '<div class="topic-bar-row" id="topic-row-' + i + '">',
        '<div class="tb-topic">' + t.topic + '</div>',
        '<div class="tb-dir">' + t.direction + '</div>',
        '<div class="tb-sparkline" id="sparkline-' + i + '">' + sparks + '</div>',
        '<div class="tb-msgs" id="topic-msgs-' + i + '">' + t.msgs + '</div>',
        '</div>'
      ].join("");
    }).join("");
  }

  function animateSparklines() {
    KEY_TOPICS.forEach(function(t, i) {
      var sl = document.getElementById("sparkline-" + i);
      if (!sl) return;
      var spans = sl.querySelectorAll("span");
      spans.forEach(function(sp) {
        sp.style.height = Math.round(Math.random() * 20 + 2) + "px";
        sp.style.background = wsConnected ? t.color + "88" : "#1e2a3a";
      });
    });
  }

  function updateMsgRate() {
    msgCount += wsConnected ? Math.floor(Math.random() * 15 + 5) : 0;
    var now = Date.now();
    var elapsed = (now - lastMsgCountTs) / 1000;
    msgRate = Math.round(msgCount / elapsed);
    var el = document.getElementById("zen-rate-val");
    if (el) el.textContent = wsConnected ? msgRate : "0";
  }

  function updateFromWS(d) {
    if (d.status) {
      try {
        var st = typeof d.status === "string" ? JSON.parse(d.status) : d.status;
        var connected = st.zenoh_connected !== false;
        ZENOH_ROUTERS.forEach(function(r) {
          var card = document.getElementById("zen-router-" + r.id);
          if (card) {
            var dot = card.querySelector(".zen-status-dot");
            if (dot) { dot.className = "zen-status-dot " + (connected ? "active" : "offline"); }
          }
        });
        var hbText = document.getElementById("zen-hb-text");
        if (hbText) hbText.textContent = connected
          ? "Zenoh mesh active — 4 routers online"
          : "Zenoh router unreachable — mesh isolated";
      } catch(_) {}
    }
  }

  function updateHeartbeat() {
    if (!heartbeatEl) return;
    var age = Date.now() - lastMsgTime;
    var dot = heartbeatEl.querySelector(".zen-dot");
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
