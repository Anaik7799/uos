// C3I Cockpit Grid v2.0 — Dark Cockpit Operator Primary View
// अन्धकारात् प्रकाशं प्राप्नोति — From darkness one reaches light
// Features: Dark Cockpit 5-mode, WebSocket /ws/dashboard, alarm panel,
//           L0-L7 fractal status, Gemma AI chat, responsive mobile-first,
//           heartbeat indicator, view toggle, Ctrl+K search
// SC-HMI-010, SC-AGUI-UI-001..015, SC-GLM-UI-001, SC-ZENOH-001
(function () {
  "use strict";

  // ═══════════════════════════════════════════════════════════════
  // Configuration
  // ═══════════════════════════════════════════════════════════════
  var WS_PATH = "/ws/dashboard"; // REUSE dashboard socket
  var ALARMS_API = "/api/v1/cockpit/alarms";
  var MODE_API = "/api/v1/cockpit/mode";
  var NIF_SEARCH_API = "/api/v1/ai/chat";
  var GEMMA3_URL = "http://localhost:11434/api/chat";
  var GEMMA4_URL = "http://localhost:11435/api/chat";
  var PING_INTERVAL_MS = 1000;
  var ALARM_REFRESH_MS = 5000;
  var STALE_MS = 3000;
  var DEAD_MS = 10000;
  var RECONNECT_BASE_MS = 1000;
  var RECONNECT_MAX_MS = 30000;

  // State
  var ws = null;
  var pingTimer = null;
  var reconnectDelay = RECONNECT_BASE_MS;
  var lastMsgTime = Date.now();
  var currentMode = "dark";
  var alarmFilter = "ALL";
  var allAlarms = [];
  var chatHistory = [];
  var currentView = "grid";

  // ═══════════════════════════════════════════════════════════════
  // Inject CSS (glassmorphism, responsive, animations)
  // ═══════════════════════════════════════════════════════════════
  var styleEl = document.createElement("style");
  styleEl.textContent = [
    // Cockpit header
    ".cockpit-header{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;padding:1rem 0 0.5rem}",
    ".cockpit-header-right{display:flex;align-items:center;gap:12px;flex-wrap:wrap}",
    ".cockpit-mode-badge{font-size:1.1rem;font-weight:800;letter-spacing:2px;padding:4px 14px;border:2px solid currentColor;border-radius:6px;font-family:'JetBrains Mono',monospace;transition:all 0.5s ease}",
    ".cockpit-heartbeat{display:flex;align-items:center;gap:5px;font-size:0.77rem;color:#7a8fa6}",
    "#cockpit-hb-dot{display:inline-block;width:9px;height:9px;border-radius:50%;transition:all 0.3s}",
    ".heartbeat-live{background:#3dd68c!important;box-shadow:0 0 8px rgba(61,214,140,0.7);animation:hbPulse 1.6s ease-in-out infinite}",
    ".heartbeat-stale{background:#f5a623!important;box-shadow:0 0 4px rgba(245,166,35,0.4)}",
    ".heartbeat-dead{background:#ff4757!important}",
    "@keyframes hbPulse{0%,100%{opacity:1}50%{opacity:0.35}}",

    // 5-mode strip
    ".cockpit-mode-strip{display:flex;gap:8px;flex-wrap:wrap;margin:0.5rem 0 1rem}",
    ".cockpit-mode-pill{display:flex;align-items:center;gap:6px;padding:6px 14px;border:1.5px solid #1e2a3a;border-radius:20px;font-size:0.73rem;font-weight:700;letter-spacing:1px;cursor:pointer;transition:all 0.25s;min-height:36px;user-select:none}",
    ".cockpit-mode-pill:hover{background:rgba(255,255,255,0.04);transform:translateY(-1px)}",
    ".cockpit-mode-pill.active-pill{background:rgba(0,0,0,0.35);box-shadow:0 2px 8px rgba(0,0,0,0.4)}",
    ".pill-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0;transition:box-shadow 0.3s}",

    // Alarm toolbar + list
    ".cockpit-alarm-toolbar{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:6px}",
    ".alarm-filter-chips{display:flex;gap:4px;flex-wrap:wrap}",
    ".alarm-chip{padding:4px 12px;border:1px solid #1e2a3a;border-radius:12px;font-size:0.71rem;font-weight:700;cursor:pointer;background:transparent;color:#7a8fa6;transition:all 0.2s;min-height:28px}",
    ".alarm-chip:hover{border-color:#00d4aa;color:#e0e6ed}",
    ".alarm-chip-active{background:rgba(0,212,170,0.12);border-color:#00d4aa;color:#00d4aa}",
    ".alarm-count{font-size:0.74rem;color:#7a8fa6;font-family:'JetBrains Mono',monospace}",
    ".cockpit-alarm-list{min-height:60px;border:1px solid #1e2a3a;border-radius:6px;padding:6px}",
    ".alarm-empty-state{display:flex;align-items:center;gap:10px;padding:1rem;font-size:0.84rem}",
    ".alarm-empty-icon{font-size:1.3rem;color:#3dd68c;opacity:0.5}",
    ".alarm-empty-text{color:#7a8fa6}",
    ".alarm-row{display:flex;align-items:center;gap:10px;padding:8px 10px;border-bottom:1px solid #1e2a3a;font-size:0.81rem;animation:fadeSlideIn 0.28s ease;transition:background 0.2s}",
    ".alarm-row:last-child{border-bottom:none}",
    ".alarm-row:hover{background:rgba(0,212,170,0.04)}",
    ".alarm-level-badge{padding:2px 8px;border-radius:4px;font-size:0.67rem;font-weight:800;letter-spacing:0.4px;min-width:44px;text-align:center;flex-shrink:0}",
    ".alarm-level-critical{background:rgba(255,71,87,0.22);color:#ff4757;border:1px solid rgba(255,71,87,0.5)}",
    ".alarm-level-warning{background:rgba(255,165,2,0.18);color:#ffa502}",
    ".alarm-level-caution{background:rgba(253,203,110,0.18);color:#fdcb6e}",
    ".alarm-level-advisory{background:rgba(116,185,255,0.13);color:#74b9ff}",
    ".alarm-level-normal{background:rgba(61,214,140,0.1);color:#3dd68c}",
    ".alarm-source{font-size:0.69rem;color:#7a8fa6;font-family:'JetBrains Mono',monospace;min-width:88px;flex-shrink:0}",
    ".alarm-message{flex:1;color:#e0e6ed}",
    ".alarm-ack-btn{padding:2px 8px;border:1px solid #1e2a3a;border-radius:4px;background:transparent;color:#7a8fa6;font-size:0.67rem;cursor:pointer;min-height:24px;transition:all 0.2s;flex-shrink:0}",
    ".alarm-ack-btn:hover{border-color:#00d4aa;color:#00d4aa}",
    ".alarm-acked{opacity:0.35;pointer-events:none}",

    // Node list
    ".cockpit-node-list{display:flex;flex-direction:column;gap:3px}",
    ".cockpit-node-row{display:flex;align-items:center;gap:10px;padding:6px 8px;border-radius:4px;font-size:0.79rem;transition:background 0.15s}",
    ".cockpit-node-row:hover{background:rgba(0,212,170,0.04)}",
    ".node-status-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}",
    ".node-name{flex:1;font-family:'JetBrains Mono',monospace;color:#e0e6ed;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
    ".node-cpu,.node-mem{font-size:0.7rem;color:#7a8fa6;min-width:68px;flex-shrink:0}",
    ".node-status-label{font-size:0.68rem;font-weight:700;min-width:78px;text-align:right;flex-shrink:0}",

    // Dual panel
    ".cockpit-dual-panel{display:grid;grid-template-columns:1fr 1fr;gap:1rem;margin:0.75rem 0}",
    ".cockpit-panel-half{}",
    ".ooda-meta-row{display:flex;flex-direction:column;gap:3px;margin-top:8px;padding:8px;border-top:1px solid #1e2a3a}",

    // Fractal layer strip
    ".fractal-layer-strip{display:flex;gap:6px;flex-wrap:wrap;margin:0.5rem 0}",
    ".fractal-layer-badge{display:flex;flex-direction:column;align-items:center;padding:10px 14px;background:var(--card-bg,#141922);border:1px solid var(--border,#1e2a3a);border-radius:8px;min-width:96px;cursor:pointer;transition:all 0.22s}",
    ".fractal-layer-badge:hover{transform:translateY(-2px);box-shadow:0 4px 14px rgba(0,0,0,0.35)}",
    ".flb-layer{font-size:1.05rem;font-weight:800;font-family:'JetBrains Mono',monospace}",
    ".flb-name{font-size:0.6rem;color:#7a8fa6;margin-top:2px;text-align:center}",
    ".flb-status{font-size:0.67rem;font-weight:700;margin-top:4px}",
    ".flb-Healthy{color:#3dd68c}.flb-Degraded{color:#f5a623}.flb-Critical{color:#ff4757}",

    // Bottom strip
    ".cockpit-bottom-strip{display:flex;gap:1rem;align-items:flex-start;flex-wrap:wrap;margin:0.75rem 0}",
    ".cockpit-view-controls{flex:1;min-width:220px}",
    ".cockpit-search-bar{margin-top:8px}",
    ".cockpit-search-input{width:100%;padding:9px 12px;background:var(--card-bg,#141922);border:1px solid var(--border,#1e2a3a);border-radius:6px;color:var(--text,#e0e6ed);font-size:0.84rem;outline:none;min-height:44px;box-sizing:border-box;transition:border-color 0.2s}",
    ".cockpit-search-input:focus{border-color:#00d4aa}",
    ".view-toggle{display:flex;gap:4px;background:rgba(10,14,23,0.6);backdrop-filter:blur(8px);border:1px solid rgba(30,42,58,0.6);border-radius:8px;padding:4px;overflow-x:auto;-webkit-overflow-scrolling:touch}",
    ".view-btn{padding:8px 14px;border:none;background:transparent;color:#7a8fa6;border-radius:6px;cursor:pointer;font-size:0.79rem;font-weight:600;transition:all 0.2s;white-space:nowrap;min-height:44px;display:flex;align-items:center}",
    ".view-btn:hover{color:#e0e6ed;background:rgba(0,212,170,0.06)}",
    ".view-btn.active{background:rgba(0,212,170,0.12);color:#00d4aa}",

    // AI chat widget
    ".cockpit-ai-chat{min-width:270px;max-width:330px;background:var(--card-bg,#141922);border:1px solid var(--border,#1e2a3a);border-radius:8px;overflow:hidden}",
    ".ai-chat-header{display:flex;justify-content:space-between;align-items:center;padding:10px 14px;border-bottom:1px solid var(--border,#1e2a3a)}",
    ".ai-model-label{font-size:0.73rem;color:#7a8fa6}",
    ".ai-chat-toggle{padding:4px 12px;border:1px solid #00d4aa;border-radius:4px;background:transparent;color:#00d4aa;font-size:0.73rem;cursor:pointer;min-height:32px;transition:all 0.2s}",
    ".ai-chat-toggle:hover{background:rgba(0,212,170,0.12)}",
    ".ai-chat-panel{padding:10px}",
    ".ai-messages{min-height:72px;max-height:180px;overflow-y:auto;margin-bottom:8px}",
    ".ai-msg{padding:6px 10px;border-radius:6px;font-size:0.76rem;margin-bottom:5px;line-height:1.5;word-break:break-word}",
    ".ai-msg-user{background:rgba(0,212,170,0.09);color:#e0e6ed;text-align:right}",
    ".ai-msg-bot{background:rgba(20,25,34,0.8);border:1px solid #1e2a3a;color:#e0e6ed}",
    ".ai-msg-thinking{color:#7a8fa6;font-style:italic}",
    ".ai-input-row{display:flex;gap:6px}",
    ".ai-input{flex:1;padding:6px 10px;background:rgba(10,14,23,0.8);border:1px solid #1e2a3a;border-radius:4px;color:#e0e6ed;font-size:0.76rem;outline:none;min-height:34px;transition:border-color 0.2s}",
    ".ai-input:focus{border-color:#00d4aa}",
    ".ai-send-btn{padding:6px 12px;background:rgba(0,212,170,0.13);border:1px solid #00d4aa;border-radius:4px;color:#00d4aa;font-size:0.73rem;cursor:pointer;min-height:34px;transition:all 0.2s}",
    ".ai-send-btn:hover{background:rgba(0,212,170,0.24)}",

    // Emergency pulse
    ".cockpit-mode-emergency{animation:emergencyPulse 1s ease-in-out infinite}",
    "@keyframes emergencyPulse{0%,100%{filter:brightness(1)}50%{filter:brightness(1.14)}}",
    "@keyframes fadeSlideIn{0%{opacity:0;transform:translateY(-5px)}100%{opacity:1;transform:translateY(0)}}",

    // Responsive: mobile-first
    "@media(max-width:767px){",
      ".cockpit-dual-panel{grid-template-columns:1fr!important}",
      ".cockpit-bottom-strip{flex-direction:column}",
      ".cockpit-ai-chat{max-width:100%;width:100%}",
      ".fractal-layer-badge{min-width:76px;padding:7px 9px}",
      ".cockpit-mode-strip{gap:4px}",
      ".cockpit-mode-pill{padding:5px 10px}",
    "}",
    "@media(min-width:768px){.cockpit-dual-panel{grid-template-columns:1fr 1fr}}",
    "@media(min-width:1024px){.cockpit-ai-chat{max-width:340px}}",
  ].join("");
  document.head.appendChild(styleEl);

  // ═══════════════════════════════════════════════════════════════
  // WebSocket — reuse /ws/dashboard (same data, cockpit presentation)
  // ═══════════════════════════════════════════════════════════════
  function connectWS() {
    try {
      var protocol = location.protocol === "https:" ? "wss:" : "ws:";
      ws = new WebSocket(protocol + "//" + location.host + WS_PATH);
    } catch (e) { scheduleReconnect(); return; }

    ws.onopen = function () {
      reconnectDelay = RECONNECT_BASE_MS;
      startPing();
      setHb("live");
    };
    ws.onmessage = function (ev) {
      lastMsgTime = Date.now();
      setHb("live");
      try {
        var d = JSON.parse(ev.data);
        if (d.type === "heartbeat" || d.seq !== undefined) return;
        if (d.dark_cockpit_mode) applyMode(d.dark_cockpit_mode);
        if (d.ooda_phase) syncOodaRing(d.ooda_phase);
      } catch (_) {}
    };
    ws.onerror = function () { setHb("dead"); };
    ws.onclose = function () { stopPing(); setHb("dead"); scheduleReconnect(); };
  }

  function startPing() {
    stopPing();
    pingTimer = setInterval(function () {
      if (ws && ws.readyState === WebSocket.OPEN) ws.send("ping");
    }, PING_INTERVAL_MS);
  }
  function stopPing() { if (pingTimer) { clearInterval(pingTimer); pingTimer = null; } }
  function scheduleReconnect() {
    setTimeout(connectWS, reconnectDelay);
    reconnectDelay = Math.min(reconnectDelay * 2, RECONNECT_MAX_MS);
  }

  // ═══════════════════════════════════════════════════════════════
  // Heartbeat indicator (SC-DMS-001)
  // ═══════════════════════════════════════════════════════════════
  function setHb(state) {
    var dot = document.getElementById("cockpit-hb-dot");
    var lbl = document.getElementById("cockpit-hb-label");
    if (!dot || !lbl) return;
    dot.className = "heartbeat-" + state;
    lbl.textContent = state === "live" ? "LIVE" : state === "stale" ? "STALE" : "DEAD";
  }

  setInterval(function () {
    var age = Date.now() - lastMsgTime;
    if (age > DEAD_MS) setHb("dead");
    else if (age > STALE_MS) setHb("stale");
  }, 1000);

  // ═══════════════════════════════════════════════════════════════
  // Dark Cockpit 5-mode (SC-HMI-010)
  // ═══════════════════════════════════════════════════════════════
  var MODE_COLORS = {
    dark: "#3dd68c", dim: "#f5a623", normal: "#e0e6ed",
    bright: "#ffd93d", emergency: "#ff4757"
  };
  var ALL_MODES = ["dark", "dim", "normal", "bright", "emergency"];

  function applyMode(mode) {
    if (!MODE_COLORS[mode]) return;
    currentMode = mode;

    // Badge
    var badge = document.getElementById("cockpit-mode-badge");
    if (badge) {
      badge.textContent = mode.toUpperCase();
      badge.style.color = MODE_COLORS[mode];
    }

    // Body class
    document.body.classList.remove.apply(
      document.body.classList,
      ALL_MODES.map(function (m) { return "cockpit-" + m; })
    );
    document.body.classList.add("cockpit-" + mode);

    // Page container data attribute
    var page = document.querySelector(".cockpit-page");
    if (page) {
      page.setAttribute("data-cockpit-mode", mode);
      page.className = page.className.replace(/cockpit-mode-\w+/g, "").trim()
        + " cockpit-mode-" + mode;
    }

    // Active pill highlight
    document.querySelectorAll(".cockpit-mode-pill").forEach(function (pill) {
      var isActive = (pill.getAttribute("data-mode") === mode);
      pill.classList.toggle("active-pill", isActive);
      if (isActive) {
        pill.style.borderColor = MODE_COLORS[mode];
        pill.style.color = MODE_COLORS[mode];
      } else {
        pill.style.borderColor = "";
        pill.style.color = "";
      }
    });
  }

  // Assign data-mode to each pill from its text content, wire click
  function initModePills() {
    document.querySelectorAll(".cockpit-mode-pill").forEach(function (pill) {
      // pill text is "DARK", "DIM", etc
      var txt = pill.textContent.replace(/\s+/g, " ").trim().toLowerCase();
      // last word in the pill is the mode name
      var parts = txt.split(/\s+/);
      var mode = parts[parts.length - 1];
      if (!MODE_COLORS[mode]) mode = parts[0]; // fallback
      pill.setAttribute("data-mode", mode);
      pill.addEventListener("click", function () { applyMode(mode); });
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // OODA Ring sync
  // ═══════════════════════════════════════════════════════════════
  function syncOodaRing(phase) {
    var p = phase.toLowerCase();
    document.querySelectorAll(".ooda-tier").forEach(function (el) {
      var label = el.querySelector("span, .ooda-dot + *");
      var text = el.textContent.split("\n")[0].trim().toLowerCase();
      el.classList.toggle("active", text === p || text.startsWith(p.substring(0, 4)));
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Alarm Panel
  // ═══════════════════════════════════════════════════════════════
  function fetchAlarms() {
    fetch(ALARMS_API)
      .then(function (r) { return r.json(); })
      .then(function (d) {
        allAlarms = d.alarms || [];
        renderAlarms();
        updateAlarmCountBadge(d.critical || 0, d.warning || 0, d.total || 0);
      })
      .catch(function () {});
  }

  function renderAlarms() {
    var container = document.getElementById("cockpit-alarm-list");
    if (!container) return;

    var filtered = allAlarms.filter(function (a) {
      if (alarmFilter === "ALL") return (a.level || "").toLowerCase() !== "normal";
      return (a.level || "").toLowerCase() === alarmFilter.toLowerCase();
    });

    if (filtered.length === 0) {
      container.innerHTML =
        '<div class="alarm-empty-state">' +
        '<div class="alarm-empty-icon">●</div>' +
        '<div class="alarm-empty-text">Dark Cockpit — All nominal. Nothing to show.</div>' +
        '</div>';
      return;
    }

    // Sort: critical first
    var ORDER = ["critical","warning","caution","advisory","normal"];
    filtered.sort(function (a, b) {
      return ORDER.indexOf(a.level) - ORDER.indexOf(b.level);
    });

    container.innerHTML = filtered.map(function (a) {
      var lvl = (a.level || "normal").toLowerCase();
      var shortLvl = { critical:"CRIT", warning:"WARN", caution:"CAUT",
                       advisory:"INFO", normal:"OK" }[lvl] || lvl.toUpperCase();
      return '<div class="alarm-row">' +
        '<span class="alarm-level-badge alarm-level-' + lvl + '">' + shortLvl + '</span>' +
        '<span class="alarm-source">' + esc(a.source || "SYSTEM") + '</span>' +
        '<span class="alarm-message">' + esc(a.message || "") + '</span>' +
        '<button class="alarm-ack-btn" onclick="c3iCockpitAck(this)">ACK</button>' +
        '</div>';
    }).join("");
  }

  function updateAlarmCountBadge(critical, warning, total) {
    var lbl = document.getElementById("alarm-count-label");
    if (!lbl) return;
    var txt = total + " active alarm" + (total !== 1 ? "s" : "");
    if (critical > 0) txt += " | " + critical + " CRITICAL";
    lbl.textContent = txt;
    lbl.style.color = critical > 0 ? "#ff4757" : warning > 0 ? "#f5a623" : "#3dd68c";
    // If critical alarms, escalate mode
    if (critical > 0 && currentMode === "dark") applyMode("bright");
    if (critical > 2) applyMode("emergency");
  }

  window.c3iCockpitAck = function (btn) {
    var row = btn && btn.closest(".alarm-row");
    if (row) {
      row.classList.add("alarm-acked");
      btn.textContent = "ACK'd";
      btn.disabled = true;
    }
  };

  // Alarm filter chip clicks
  document.addEventListener("click", function (e) {
    var chip = e.target.closest && e.target.closest(".alarm-chip");
    if (!chip) return;
    alarmFilter = chip.textContent.trim();
    document.querySelectorAll(".alarm-chip").forEach(function (c) {
      c.classList.toggle("alarm-chip-active", c === chip);
    });
    renderAlarms();
  });

  // ═══════════════════════════════════════════════════════════════
  // View Toggle (SC-AGUI-UI-001)
  // ═══════════════════════════════════════════════════════════════
  var viewToggle = document.getElementById("cockpit-view-toggle");
  if (viewToggle) {
    viewToggle.addEventListener("click", function (e) {
      var btn = e.target.closest && e.target.closest(".view-btn");
      if (!btn) return;
      currentView = btn.getAttribute("data-view") || "grid";
      viewToggle.querySelectorAll(".view-btn").forEach(function (b) {
        b.classList.toggle("active", b === btn);
      });
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Search (Ctrl+K, SC-AGUI-UI-003)
  // ═══════════════════════════════════════════════════════════════
  var searchInput = document.getElementById("cockpit-search");
  if (searchInput) {
    var searchTimer = null;
    searchInput.addEventListener("input", function () {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(function () {
        var q = searchInput.value.trim().toLowerCase();
        if (!q) { renderAlarms(); return; }
        var backup = allAlarms;
        allAlarms = allAlarms.filter(function (a) {
          return ((a.message || "") + (a.source || "")).toLowerCase().indexOf(q) >= 0;
        });
        renderAlarms();
        allAlarms = backup;
      }, 200);
    });
  }
  document.addEventListener("keydown", function (e) {
    if ((e.ctrlKey || e.metaKey) && e.key === "k") {
      e.preventDefault();
      if (searchInput) searchInput.focus();
    }
    if (e.key === "Escape" && document.activeElement === searchInput) {
      searchInput.value = "";
      renderAlarms();
    }
  });

  // ═══════════════════════════════════════════════════════════════
  // Gemma AI Chat (SC-AGUI-UI-005) — Gemma3 fast → Gemma4 → NIF
  // ═══════════════════════════════════════════════════════════════
  var aiToggle = document.getElementById("cockpit-ai-toggle");
  var chatPanel = document.getElementById("cockpit-chat-panel");
  var aiInput = document.getElementById("cockpit-ai-input");
  var aiSend = document.getElementById("cockpit-ai-send");
  var aiMsgs = document.getElementById("cockpit-ai-messages");

  if (aiToggle && chatPanel) {
    aiToggle.addEventListener("click", function () {
      var shown = chatPanel.style.display !== "none";
      chatPanel.style.display = shown ? "none" : "block";
      aiToggle.textContent = shown ? "Ask AI" : "Close";
    });
  }

  function appendChatMsg(role, text) {
    if (!aiMsgs) return;
    var d = document.createElement("div");
    d.className = "ai-msg ai-msg-" + role;
    d.textContent = text;
    aiMsgs.appendChild(d);
    aiMsgs.scrollTop = aiMsgs.scrollHeight;
    return d;
  }

  function buildSystemPrompt() {
    var critCount = allAlarms.filter(function (a) {
      return (a.level || "").toLowerCase() === "critical";
    }).length;
    return "You are the C3I Dark Cockpit AI advisor. " +
      "Current cockpit mode: " + currentMode.toUpperCase() + ". " +
      "Active alarms: " + allAlarms.filter(function (a) {
        return (a.level || "") !== "normal";
      }).length + " (" + critCount + " critical). " +
      "Focus on actionable triage, mesh health, fractal layer L0-L7 status. Keep answers brief.";
  }

  function sendChat(query) {
    if (!query) return;
    appendChatMsg("user", query);
    chatHistory.push({ role: "user", content: query });
    var thinking = appendChatMsg("thinking", "Thinking…");

    var payload = JSON.stringify({
      model: "gemma3",
      messages: [{ role: "system", content: buildSystemPrompt() }].concat(chatHistory),
      stream: false
    });

    function handleReply(reply) {
      chatHistory.push({ role: "assistant", content: reply });
      if (thinking && thinking.parentNode) thinking.remove();
      appendChatMsg("bot", reply);
    }
    function handleError(fallbackMsg) {
      if (thinking && thinking.parentNode) thinking.remove();
      appendChatMsg("bot", fallbackMsg);
    }

    // Tier 1: Gemma 3
    fetch(GEMMA3_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: payload,
      signal: AbortSignal.timeout(15000)
    })
    .then(function (r) { return r.json(); })
    .then(function (d) {
      handleReply((d.message && d.message.content) || "No response.");
    })
    .catch(function () {
      // Tier 2: Gemma 4
      var p4 = JSON.stringify({ model: "gemma4", messages: chatHistory, stream: false });
      fetch(GEMMA4_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: p4,
        signal: AbortSignal.timeout(15000)
      })
      .then(function (r) { return r.json(); })
      .then(function (d) {
        handleReply((d.message && d.message.content) || "No response from Gemma 4.");
      })
      .catch(function () {
        // Tier 3: NIF search fallback
        fetch(NIF_SEARCH_API + "?q=" + encodeURIComponent(query))
          .then(function (r) { return r.json(); })
          .then(function (d) {
            handleReply(d.response || d.answer || JSON.stringify(d).substring(0, 200));
          })
          .catch(function () {
            handleError("AI advisors offline. Check Gemma 3 (:11434) and Gemma 4 (:11435).");
          });
      });
    });
  }

  if (aiSend) {
    aiSend.addEventListener("click", function () {
      var q = aiInput && aiInput.value.trim();
      if (!q) return;
      if (aiInput) aiInput.value = "";
      sendChat(q);
    });
  }
  if (aiInput) {
    aiInput.addEventListener("keydown", function (e) {
      if (e.key === "Enter") {
        var q = aiInput.value.trim();
        if (!q) return;
        aiInput.value = "";
        sendChat(q);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Fetch cockpit mode on load
  // ═══════════════════════════════════════════════════════════════
  function fetchMode() {
    fetch(MODE_API)
      .then(function (r) { return r.json(); })
      .then(function (d) { if (d.mode) applyMode(d.mode); })
      .catch(function () {});
  }

  // ═══════════════════════════════════════════════════════════════
  // Utility
  // ═══════════════════════════════════════════════════════════════
  function esc(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  // ═══════════════════════════════════════════════════════════════
  // Init
  // ═══════════════════════════════════════════════════════════════
  function init() {
    initModePills();
    fetchMode();
    fetchAlarms();
    connectWS();
    setInterval(fetchAlarms, ALARM_REFRESH_MS);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

})();
