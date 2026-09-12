// C3I Agents Grid — Agentic UI
// सर्वत्र समदर्शनः — Equal vision everywhere (Gita 6.29)
// Agent hierarchy, OODA supervision, worker status, 25-agent biomorphic mesh
// SC-AGUI-UI-001, SC-GLM-UI-010, SC-AGENT-001, SC-OODA-001

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

  var AGENT_HIERARCHY = [
    { id: "EXEC-001", role: "Orchestrator",      model: "claude-opus-4",    layer: "L5", color: "#00d4aa", status: "active",  children: ["SUP-CTX","SUP-DOM","SUP-TST","SUP-QUA"] },
    { id: "SUP-CTX",  role: "Context Supervisor", model: "claude-sonnet-4",  layer: "L5", color: "#4d96ff", status: "active",  children: ["W-COMPILE-1","W-COMPILE-2","W-EXPLORE-1","W-DOC-1"] },
    { id: "SUP-DOM",  role: "Domain Supervisor",  model: "claude-sonnet-4",  layer: "L3", color: "#9b59b6", status: "active",  children: ["W-FIX-1","W-FIX-2","W-CREDO-1","W-CREDO-2"] },
    { id: "SUP-TST",  role: "Test Supervisor",    model: "claude-sonnet-4",  layer: "L4", color: "#ffd93d", status: "active",  children: ["W-TEST-1","W-TEST-2","W-TEST-3"] },
    { id: "SUP-QUA",  role: "Quality Supervisor", model: "claude-sonnet-4",  layer: "L0", color: "#ff6b6b", status: "active",  children: ["W-SAFETY-1","W-STAMP-1","W-FORMAT-1"] },
    { id: "W-COMPILE-1", role: "Compile Worker",  model: "claude-haiku",     layer: "L4", color: "#7a8fa6", status: "idle",   children: [] },
    { id: "W-COMPILE-2", role: "Compile Worker",  model: "claude-haiku",     layer: "L4", color: "#7a8fa6", status: "idle",   children: [] },
    { id: "W-EXPLORE-1", role: "Explore Worker",  model: "claude-haiku",     layer: "L3", color: "#7a8fa6", status: "idle",   children: [] },
    { id: "W-DOC-1",     role: "Doc Worker",      model: "claude-haiku",     layer: "L3", color: "#7a8fa6", status: "idle",   children: [] },
    { id: "W-FIX-1",     role: "Fix Worker",      model: "claude-haiku",     layer: "L2", color: "#7a8fa6", status: "idle",   children: [] },
    { id: "W-FIX-2",     role: "Fix Worker",      model: "claude-haiku",     layer: "L2", color: "#7a8fa6", status: "idle",   children: [] },
    { id: "W-CREDO-1",   role: "Credo Worker",    model: "claude-haiku",     layer: "L2", color: "#7a8fa6", status: "idle",   children: [] },
    { id: "W-CREDO-2",   role: "Credo Worker",    model: "claude-haiku",     layer: "L2", color: "#7a8fa6", status: "idle",   children: [] },
    { id: "W-TEST-1",    role: "Test Worker",     model: "claude-haiku",     layer: "L4", color: "#7a8fa6", status: "idle",   children: [] },
    { id: "W-TEST-2",    role: "Test Worker",     model: "claude-haiku",     layer: "L4", color: "#7a8fa6", status: "idle",   children: [] },
    { id: "W-TEST-3",    role: "Test Worker",     model: "claude-haiku",     layer: "L4", color: "#7a8fa6", status: "idle",   children: [] },
    { id: "W-SAFETY-1",  role: "Safety Worker",   model: "claude-haiku",     layer: "L0", color: "#ff6b6b", status: "idle",   children: [] },
    { id: "W-STAMP-1",   role: "STAMP Worker",    model: "claude-haiku",     layer: "L0", color: "#ff6b6b", status: "idle",   children: [] },
    { id: "W-FORMAT-1",  role: "Format Worker",   model: "claude-haiku",     layer: "L2", color: "#7a8fa6", status: "idle",   children: [] }
  ];

  var LAYER_COLORS = {
    "L0":"#ff6b6b","L1":"#ffd93d","L2":"#6bcb77","L3":"#4d96ff",
    "L4":"#9b59b6","L5":"#00d4aa","L6":"#e74c3c","L7":"#f39c12"
  };

  function init() {
    injectStyles();
    injectHeartbeat();
    injectHierarchyView();
    injectOodaRing();
    connectWS();
  }

  function injectStyles() {
    var s = document.createElement("style");
    s.textContent = [
      "#agt-heartbeat{display:inline-flex;align-items:center;gap:6px;font-size:0.78rem;",
      "padding:4px 12px;border-radius:20px;background:rgba(0,212,170,0.1);",
      "border:1px solid rgba(0,212,170,0.3);margin-bottom:12px;transition:all 0.3s}",
      "#agt-heartbeat.stale{border-color:rgba(245,166,35,0.4);background:rgba(245,166,35,0.1)}",
      "#agt-heartbeat.dead{border-color:rgba(255,71,87,0.4);background:rgba(255,71,87,0.1)}",
      ".agt-dot{width:8px;height:8px;border-radius:50%;background:#3dd68c;animation:agtpulse 1.5s infinite}",
      "@keyframes agtpulse{0%,100%{opacity:1}50%{opacity:0.3}}",
      "#agt-hierarchy{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:10px;margin:16px 0}",
      ".agt-card{background:rgba(10,14,23,0.8);border:1px solid #1e2a3a;border-radius:8px;",
      "padding:10px 14px;transition:border-color 0.2s}",
      ".agt-card:hover{border-color:rgba(0,212,170,0.3)}",
      ".agt-card .a-id{font-family:monospace;font-size:0.78rem;font-weight:700}",
      ".agt-card .a-role{font-size:0.78rem;color:#7a8fa6;margin-top:2px}",
      ".agt-card .a-model{font-size:0.72rem;color:#7a8fa6;margin-top:4px;font-style:italic}",
      ".agt-status{display:inline-block;padding:2px 8px;border-radius:10px;font-size:0.7rem;font-weight:600;margin-top:4px}",
      ".agt-status.active{background:rgba(61,214,140,0.15);color:#3dd68c}",
      ".agt-status.idle{background:rgba(122,143,166,0.15);color:#7a8fa6}",
      ".agt-status.busy{background:rgba(245,166,35,0.15);color:#f5a623}",
      ".ooda-ring-section{display:flex;align-items:center;gap:20px;margin:16px 0}",
      ".ooda-ring-section svg{width:100px;height:100px;flex-shrink:0}",
      "#agt-ooda-info{font-size:0.82rem;color:#7a8fa6}",
      "#agt-ooda-phase{font-size:1.2rem;font-weight:700;color:#00d4aa;margin-bottom:4px}"
    ].join("");
    document.head.appendChild(s);
  }

  function injectHeartbeat() {
    heartbeatEl = document.createElement("div");
    heartbeatEl.id = "agt-heartbeat";
    heartbeatEl.innerHTML = '<span class="agt-dot"></span><span id="agt-hb-text">Connecting to agent mesh...</span>';
    var hdr = document.querySelector(".page-header");
    if (hdr) hdr.insertAdjacentElement("afterend", heartbeatEl);
    else document.body.prepend(heartbeatEl);
  }

  function injectHierarchyView() {
    var container = document.createElement("div");
    container.innerHTML = '<div style="margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">Agent Hierarchy — 25-Agent Biomorphic Mesh</div>';
    var grid = document.createElement("div");
    grid.id = "agt-hierarchy";

    AGENT_HIERARCHY.forEach(function(a) {
      var lc = LAYER_COLORS[a.layer] || "#7a8fa6";
      var card = document.createElement("div");
      card.className = "agt-card";
      card.dataset.agentId = a.id;
      card.innerHTML = [
        '<div class="a-id" style="color:' + lc + '">' + a.id + '</div>',
        '<div class="a-role">' + a.role + '</div>',
        '<div class="a-model">' + a.model + '</div>',
        '<div><span class="agt-status ' + a.status + '">' + a.status.toUpperCase() + '</span>',
        ' <span style="color:' + lc + ';font-size:0.7rem;margin-left:4px">' + a.layer + '</span></div>'
      ].join("");
      grid.appendChild(card);
    });

    container.appendChild(grid);
    var last = document.querySelector(".w-full");
    if (last) last.appendChild(container);
  }

  function injectOodaRing() {
    var phases = ["Observe","Orient","Decide","Act"];
    var colors = ["#4d96ff","#ffd93d","#f5a623","#3dd68c"];
    var section = document.createElement("div");
    section.className = "ooda-ring-section";
    section.innerHTML = [
      '<svg viewBox="0 0 100 100" id="agt-ooda-svg">',
      '<circle cx="50" cy="50" r="40" fill="none" stroke="#1e2a3a" stroke-width="4"/>',
      phases.map(function(p,i) {
        var angle = i * 90 - 90;
        var rad = angle * Math.PI / 180;
        var x = 50 + 40 * Math.cos(rad);
        var y = 50 + 40 * Math.sin(rad);
        return '<circle id="ooda-node-' + i + '" cx="' + x + '" cy="' + y + '" r="8"' +
          ' fill="' + colors[i] + '" opacity="0.5"/>';
      }).join("") +
      '<text x="50" y="46" text-anchor="middle" font-size="9" fill="#7a8fa6">OODA</text>',
      '<text id="agt-ooda-txt" x="50" y="60" text-anchor="middle" font-size="9" fill="#00d4aa">< 100ms</text>',
      '</svg>',
      '<div id="agt-ooda-info">',
      '<div id="agt-ooda-phase">Observe</div>',
      '<div>Cycle budget: &lt;100ms (AOR-CAE-001)</div>',
      '<div style="margin-top:4px">Agent step: &lt;30ms | Knowledge: &lt;1ms</div>',
      '<div style="margin-top:4px">Cortex: &lt;50ms | Strategy: &lt;1s</div>',
      '</div>'
    ].join("");

    var last = document.querySelector(".w-full");
    if (last) {
      var label = document.createElement("div");
      label.style.cssText = "margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
      label.textContent = "OODA Cycle Monitor";
      last.appendChild(label);
      last.appendChild(section);
    }

    // Animate OODA ring
    var phase = 0;
    setInterval(function() {
      for (var i = 0; i < 4; i++) {
        var node = document.getElementById("ooda-node-" + i);
        if (node) node.setAttribute("opacity", i === phase ? "1" : "0.2");
      }
      var phaseEl = document.getElementById("agt-ooda-phase");
      if (phaseEl) phaseEl.textContent = ["Observe","Orient","Decide","Act"][phase];
      phase = (phase + 1) % 4;
    }, 800);
  }

  function updateHeartbeat() {
    if (!heartbeatEl) return;
    var age = Date.now() - lastMsgTime;
    var dot = heartbeatEl.querySelector(".agt-dot");
    var txt = document.getElementById("agt-hb-text");
    heartbeatEl.className = age > DEAD_MS ? "dead" : age > STALE_MS ? "stale" : "";
    if (dot) dot.style.background = age > DEAD_MS ? "#ff4757" : age > STALE_MS ? "#f5a623" : "#3dd68c";
    if (txt) txt.textContent = wsConnected
      ? "Agent mesh active — 25 agents monitored"
      : age > DEAD_MS ? "Agent mesh disconnected" : "Reconnecting...";
  }

  function updateFromWS(d) {
    if (!d) return;
    // Highlight active agents from system status
    if (d.type === "connected" || d.type === "update") {
      document.querySelectorAll(".agt-card").forEach(function(card) {
        var id = card.dataset.agentId;
        if (id && id.startsWith("EXEC") || (id && id.startsWith("SUP"))) {
          card.querySelector(".agt-status").textContent = "ACTIVE";
          card.querySelector(".agt-status").className = "agt-status active";
        }
      });
    }
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
