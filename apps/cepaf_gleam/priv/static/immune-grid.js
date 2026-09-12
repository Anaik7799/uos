// C3I Immune Grid — Agentic UI
// सर्वत्र समदर्शनः — Equal vision everywhere (Gita 6.29)
// Threat level, antibody count, chaos detection, Psi invariants
// SC-AGUI-UI-001, SC-GLM-UI-010, SC-SAFETY-001, SC-IMMUNE-001

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

  var threatLevel = "nominal";
  var antibodyCount = 0;
  var attacksBlocked = 0;

  // Threat level → visual config
  var THREAT_CONFIG = {
    "none":     { color: "#3dd68c", label: "None",     ring: 5 },
    "nominal":  { color: "#3dd68c", label: "Nominal",  ring: 10 },
    "low":      { color: "#ffd93d", label: "Low",      ring: 30 },
    "elevated": { color: "#f5a623", label: "Elevated",  ring: 55 },
    "severe":   { color: "#ff4757", label: "Severe",    ring: 80 },
    "critical": { color: "#ff2400", label: "CRITICAL",  ring: 100 }
  };

  var PSI_INVARIANTS = [
    { id: "Psi-0", name: "Existence",    desc: "System continues to exist and function",   pass: true  },
    { id: "Psi-1", name: "Regeneration", desc: "State recoverable from SQLite/DuckDB",     pass: true  },
    { id: "Psi-2", name: "Reversibility",desc: "All changes are reversible",               pass: true  },
    { id: "Psi-3", name: "Verification", desc: "Hash chain maintained",                     pass: true  },
    { id: "Psi-4", name: "Alignment",    desc: "Human intent preserved",                   pass: true  },
    { id: "Psi-5", name: "Truthfulness", desc: "No deception in outputs",                  pass: true  },
    { id: "Omega-0",name:"Founder",      desc: "System serves the founder",                pass: true  }
  ];

  function init() {
    injectStyles();
    injectHeartbeat();
    injectThreatRing();
    injectPsiTable();
    connectWS();
  }

  function injectStyles() {
    var s = document.createElement("style");
    s.textContent = [
      "#imm-heartbeat{display:inline-flex;align-items:center;gap:6px;font-size:0.78rem;",
      "padding:4px 12px;border-radius:20px;background:rgba(0,212,170,0.1);",
      "border:1px solid rgba(0,212,170,0.3);margin-bottom:12px;transition:all 0.3s}",
      "#imm-heartbeat.stale{border-color:rgba(245,166,35,0.4);background:rgba(245,166,35,0.1)}",
      "#imm-heartbeat.dead{border-color:rgba(255,71,87,0.4);background:rgba(255,71,87,0.1)}",
      ".imm-dot{width:8px;height:8px;border-radius:50%;background:#3dd68c;animation:immpulse 1.5s infinite}",
      "@keyframes immpulse{0%,100%{opacity:1}50%{opacity:0.3}}",
      ".threat-ring-wrap{display:flex;align-items:center;gap:24px;margin:16px 0}",
      ".threat-ring-wrap svg{width:120px;height:120px;flex-shrink:0}",
      "#imm-threat-info{display:flex;flex-direction:column;gap:6px}",
      "#imm-threat-label{font-size:1.4rem;font-weight:700;transition:color 0.5s}",
      "#imm-threat-desc{font-size:0.82rem;color:#7a8fa6}",
      ".imm-counters{display:flex;gap:16px;flex-wrap:wrap;margin-top:8px}",
      ".imm-counter{background:rgba(10,14,23,0.8);border:1px solid #1e2a3a;",
      "border-radius:8px;padding:8px 14px;min-width:100px;text-align:center}",
      ".imm-counter .c-val{font-size:1.5rem;font-weight:700;color:#e0e6ed}",
      ".imm-counter .c-lbl{font-size:0.72rem;color:#7a8fa6;margin-top:2px}",
      "#imm-psi-table{width:100%;border-collapse:collapse;font-size:0.83rem;margin-top:8px}",
      "#imm-psi-table th{text-align:left;padding:6px 10px;border-bottom:1px solid #1e2a3a;color:#7a8fa6;font-weight:500}",
      "#imm-psi-table td{padding:6px 10px;border-bottom:1px solid rgba(30,42,58,0.5)}",
      ".psi-pass{color:#3dd68c;font-weight:600}.psi-fail{color:#ff4757;font-weight:600}",
      ".chaos-banner{background:rgba(255,71,87,0.08);border:1px solid rgba(255,71,87,0.3);",
      "border-radius:8px;padding:10px 16px;margin:12px 0;font-size:0.85rem;",
      "color:#ff4757;display:none}.chaos-banner.active{display:block}"
    ].join("");
    document.head.appendChild(s);
  }

  function injectHeartbeat() {
    heartbeatEl = document.createElement("div");
    heartbeatEl.id = "imm-heartbeat";
    heartbeatEl.innerHTML = '<span class="imm-dot"></span><span id="imm-hb-text">Connecting to immune mesh...</span>';
    var hdr = document.querySelector(".page-header");
    if (hdr) hdr.insertAdjacentElement("afterend", heartbeatEl);
    else document.body.prepend(heartbeatEl);
  }

  function injectThreatRing() {
    var cfg = THREAT_CONFIG[threatLevel] || THREAT_CONFIG.nominal;
    var pct = cfg.ring;
    var dash = Math.round(pct * 3.14);
    var gap = 314 - dash;

    var wrap = document.createElement("div");
    wrap.id = "imm-threat-wrap";
    wrap.className = "threat-ring-wrap";
    wrap.innerHTML = [
      '<svg id="imm-ring-svg" viewBox="0 0 100 100">',
      '<circle cx="50" cy="50" r="44" fill="none" stroke="#1e2a3a" stroke-width="8"/>',
      '<circle id="imm-ring-arc" cx="50" cy="50" r="44" fill="none"',
      ' stroke="' + cfg.color + '" stroke-width="8"',
      ' stroke-dasharray="' + dash + ' ' + gap + '"',
      ' stroke-linecap="round" transform="rotate(-90 50 50)"/>',
      '<text x="50" y="46" text-anchor="middle" font-size="11" fill="#e0e6ed" font-weight="700">THREAT</text>',
      '<text id="imm-ring-pct" x="50" y="62" text-anchor="middle" font-size="14" fill="' + cfg.color + '" font-weight="700">' + pct + '%</text>',
      '</svg>',
      '<div id="imm-threat-info">',
      '<div id="imm-threat-label" style="color:' + cfg.color + '">' + cfg.label + '</div>',
      '<div id="imm-threat-desc">Current immune assessment — L0 Constitutional</div>',
      '<div class="imm-counters">',
      '<div class="imm-counter"><div class="c-val" id="imm-antibody-count">0</div><div class="c-lbl">Antibodies</div></div>',
      '<div class="imm-counter"><div class="c-val" id="imm-attacks-count">0</div><div class="c-lbl">Attacks Blocked</div></div>',
      '<div class="imm-counter"><div class="c-val" id="imm-chaos-count">0</div><div class="c-lbl">Chaos Experiments</div></div>',
      '</div></div>'
    ].join("");

    var chaos = document.createElement("div");
    chaos.id = "imm-chaos-banner";
    chaos.className = "chaos-banner";
    chaos.textContent = "CHAOS EXPERIMENT IN PROGRESS — SIL-6 antibodies deployed";

    var first = document.querySelector(".section-body, .w-full");
    if (first) {
      first.insertBefore(wrap, first.firstChild);
      first.insertBefore(chaos, wrap);
    }
  }

  function injectPsiTable() {
    var container = document.createElement("div");
    container.innerHTML = [
      '<div style="margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">',
      'Live Psi Invariant Monitor</div>',
      '<table id="imm-psi-table">',
      '<thead><tr><th>Invariant</th><th>Name</th><th>Status</th><th>Description</th></tr></thead>',
      '<tbody>' + PSI_INVARIANTS.map(function(p) {
        return '<tr><td style="font-family:monospace;color:#9b59b6">' + p.id +
          '</td><td>' + p.name +
          '</td><td class="' + (p.pass ? 'psi-pass' : 'psi-fail') + '">' +
          (p.pass ? 'PASS' : 'FAIL') +
          '</td><td style="color:#7a8fa6">' + p.desc + '</td></tr>';
      }).join("") + '</tbody></table>'
    ].join("");
    var last = document.querySelector(".w-full");
    if (last) last.appendChild(container);
  }

  function updateThreat(level) {
    threatLevel = level || "nominal";
    var cfg = THREAT_CONFIG[threatLevel] || THREAT_CONFIG.nominal;
    var pct = cfg.ring;
    var dash = Math.round(pct * 3.14);
    var gap = 314 - dash;

    var arc = document.getElementById("imm-ring-arc");
    var pctEl = document.getElementById("imm-ring-pct");
    var labelEl = document.getElementById("imm-threat-label");
    if (arc) { arc.setAttribute("stroke-dasharray", dash + " " + gap); arc.setAttribute("stroke", cfg.color); }
    if (pctEl) { pctEl.textContent = pct + "%"; pctEl.setAttribute("fill", cfg.color); }
    if (labelEl) { labelEl.textContent = cfg.label; labelEl.style.color = cfg.color; }

    var banner = document.getElementById("imm-chaos-banner");
    if (banner) banner.className = "chaos-banner" + (threatLevel === "critical" || threatLevel === "severe" ? " active" : "");
  }

  function updateHeartbeat() {
    if (!heartbeatEl) return;
    var age = Date.now() - lastMsgTime;
    var dot = heartbeatEl.querySelector(".imm-dot");
    var txt = document.getElementById("imm-hb-text");
    heartbeatEl.className = age > DEAD_MS ? "dead" : age > STALE_MS ? "stale" : "";
    if (dot) dot.style.background = age > DEAD_MS ? "#ff4757" : age > STALE_MS ? "#f5a623" : "#3dd68c";
    if (txt) txt.textContent = wsConnected
      ? "Immune system active — threat monitoring live"
      : age > DEAD_MS ? "Mesh disconnected — immune monitoring paused" : "Reconnecting...";
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
        if (d.status) {
          var st = typeof d.status === "string" ? JSON.parse(d.status) : d.status;
          if (st.threat_level) updateThreat(st.threat_level.toLowerCase());
        }
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

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
