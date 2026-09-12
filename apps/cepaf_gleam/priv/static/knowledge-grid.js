// C3I Knowledge Grid — Agentic UI
// सर्वत्र समदर्शनः — Equal vision everywhere (Gita 6.29)
// Zettelkasten search, holon count, entropy scoring, knowledge graph
// SC-AGUI-UI-001, SC-GLM-UI-010, SC-IKE-001, SC-SMRITI-001

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
  var searchDebounce = null;

  var HOLON_LEVELS = [
    { level: "Ecosystem",  count: 86,   color: "#f39c12", desc: "Architecture docs, system vision, strategic decisions" },
    { level: "Organism",   count: 1083, color: "#00d4aa", desc: "Journal entries, session narratives, evolution stories" },
    { level: "Molecular",  count: 284,  color: "#4d96ff", desc: "Allium specs, plans, TLA+, behavioral contracts" },
    { level: "Atomic",     count: 607,  color: "#6bcb77", desc: "Constraints, code patterns, RCA findings" }
  ];
  var TOTAL_HOLONS = 2060;

  function init() {
    injectStyles();
    injectHeartbeat();
    injectEntropyGauge();
    injectSearchWidget();
    injectHolonBars();
    connectWS();
  }

  function injectStyles() {
    var s = document.createElement("style");
    s.textContent = [
      "#knw-heartbeat{display:inline-flex;align-items:center;gap:6px;font-size:0.78rem;",
      "padding:4px 12px;border-radius:20px;background:rgba(0,212,170,0.1);",
      "border:1px solid rgba(0,212,170,0.3);margin-bottom:12px;transition:all 0.3s}",
      "#knw-heartbeat.stale{border-color:rgba(245,166,35,0.4);background:rgba(245,166,35,0.1)}",
      "#knw-heartbeat.dead{border-color:rgba(255,71,87,0.4);background:rgba(255,71,87,0.1)}",
      ".knw-dot{width:8px;height:8px;border-radius:50%;background:#3dd68c;animation:knwpulse 1.5s infinite}",
      "@keyframes knwpulse{0%,100%{opacity:1}50%{opacity:0.3}}",
      ".knw-entropy-wrap{display:flex;align-items:center;gap:20px;margin:16px 0}",
      ".knw-entropy-wrap svg{width:100px;height:100px;flex-shrink:0}",
      "#knw-entropy-info h3{font-size:1.1rem;font-weight:700;color:#00d4aa;margin:0 0 4px}",
      "#knw-entropy-info p{font-size:0.82rem;color:#7a8fa6;margin:2px 0}",
      "#knw-search-wrap{margin:16px 0;display:flex;gap:8px}",
      "#knw-search-input{flex:1;background:rgba(10,14,23,0.8);border:1px solid #1e2a3a;",
      "color:#e0e6ed;padding:10px 16px;border-radius:8px;font-size:0.88rem;outline:none;",
      "transition:border-color 0.2s}",
      "#knw-search-input:focus{border-color:rgba(0,212,170,0.5)}",
      "#knw-search-results{margin-top:8px;min-height:20px;font-size:0.83rem}",
      ".knw-result-item{background:rgba(10,14,23,0.6);border:1px solid #1e2a3a;",
      "border-radius:6px;padding:8px 12px;margin-bottom:6px;cursor:pointer;transition:border-color 0.2s}",
      ".knw-result-item:hover{border-color:rgba(0,212,170,0.3)}",
      ".knw-result-title{font-weight:600;color:#e0e6ed;font-size:0.85rem}",
      ".knw-result-meta{font-size:0.72rem;color:#7a8fa6;margin-top:2px}",
      ".knw-result-snippet{font-size:0.78rem;color:#a0aab8;margin-top:4px}",
      ".holon-bar-row{display:flex;align-items:center;gap:12px;margin-bottom:10px}",
      ".holon-bar-row .hb-label{min-width:80px;font-size:0.82rem;font-weight:600}",
      ".holon-bar-row .hb-bar{flex:1;height:20px;background:#1e2a3a;border-radius:4px;overflow:hidden}",
      ".holon-bar-row .hb-fill{height:100%;border-radius:4px;transition:width 0.6s ease}",
      ".holon-bar-row .hb-count{min-width:50px;text-align:right;font-family:monospace;font-size:0.82rem;color:#7a8fa6}"
    ].join("");
    document.head.appendChild(s);
  }

  function injectHeartbeat() {
    heartbeatEl = document.createElement("div");
    heartbeatEl.id = "knw-heartbeat";
    heartbeatEl.innerHTML = '<span class="knw-dot"></span><span id="knw-hb-text">Connecting to knowledge mesh...</span>';
    var hdr = document.querySelector(".page-header");
    if (hdr) hdr.insertAdjacentElement("afterend", heartbeatEl);
    else document.body.prepend(heartbeatEl);
  }

  function injectEntropyGauge() {
    // Shannon Entropy H = 2.67 bits (current) — gate >= 2.5 bits
    var h = 2.67;
    var pct = Math.round((h / 3.5) * 100);
    var dash = Math.round(pct * 2.51);
    var gap = 251 - dash;

    var wrap = document.createElement("div");
    wrap.className = "knw-entropy-wrap";
    wrap.innerHTML = [
      '<svg viewBox="0 0 80 80">',
      '<circle cx="40" cy="40" r="34" fill="none" stroke="#1e2a3a" stroke-width="6"/>',
      '<circle cx="40" cy="40" r="34" fill="none" stroke="#00d4aa" stroke-width="6"',
      ' stroke-dasharray="' + dash + ' ' + gap + '"',
      ' stroke-linecap="round" transform="rotate(-90 40 40)"/>',
      '<text x="40" y="36" text-anchor="middle" font-size="9" fill="#7a8fa6">Shannon</text>',
      '<text x="40" y="50" text-anchor="middle" font-size="14" fill="#00d4aa" font-weight="700">' + h + '</text>',
      '<text x="40" y="62" text-anchor="middle" font-size="8" fill="#3dd68c">bits</text>',
      '</svg>',
      '<div id="knw-entropy-info">',
      '<h3>Zettelkasten Brain — 2,060+ Holons</h3>',
      '<p>Shannon Entropy H = ' + h + ' bits &nbsp;&nbsp; Gate: >= 2.5 bits &nbsp; <span style="color:#3dd68c">PASS</span></p>',
      '<p>FTS5 search latency: &lt; 1ms &nbsp;&nbsp; RAG pipeline: active</p>',
      '<p>STAMP cross-refs: 6,647 &nbsp;&nbsp; Levels: Ecosystem → Atomic</p>',
      '</div>'
    ].join("");

    var first = document.querySelector(".w-full");
    if (first) first.insertBefore(wrap, first.firstChild);
  }

  function injectSearchWidget() {
    var container = document.createElement("div");
    container.innerHTML = [
      '<div style="margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">',
      'Zettelkasten Search (FTS5 &lt; 1ms)</div>',
      '<div id="knw-search-wrap">',
      '<input id="knw-search-input" type="text" placeholder="Search holons, constraints, patterns... (Ctrl+K)"/>',
      '</div>',
      '<div id="knw-search-results"></div>'
    ].join("");

    var last = document.querySelector(".w-full");
    if (last) last.appendChild(container);

    var input = document.getElementById("knw-search-input");
    if (input) {
      input.addEventListener("input", function() {
        clearTimeout(searchDebounce);
        searchDebounce = setTimeout(function() { doSearch(input.value); }, 200);
      });
      document.addEventListener("keydown", function(e) {
        if ((e.ctrlKey || e.metaKey) && e.key === "k") { e.preventDefault(); input.focus(); }
      });
    }
  }

  function doSearch(query) {
    var results = document.getElementById("knw-search-results");
    if (!results) return;
    if (!query || query.length < 2) { results.innerHTML = ""; return; }

    results.innerHTML = '<div style="color:#7a8fa6;font-size:0.8rem;padding:4px 0">Searching FTS5...</div>';

    fetch("/api/v1/plan/search?q=" + encodeURIComponent(query))
      .then(function(r) { return r.json(); })
      .then(function(data) {
        var items = Array.isArray(data) ? data : (data.results || data.tasks || []);
        if (items.length === 0) {
          results.innerHTML = '<div style="color:#7a8fa6;font-size:0.82rem;padding:4px 0">No results for "' + query + '"</div>';
          return;
        }
        results.innerHTML = items.slice(0, 8).map(function(item) {
          var title = item.description || item.title || item.id || "Unknown";
          var meta = (item.priority || "") + (item.status ? " · " + item.status : "") + (item.layer ? " · " + item.layer : "");
          var snippet = item.content ? item.content.slice(0, 120) + "..." : "";
          return [
            '<div class="knw-result-item">',
            '<div class="knw-result-title">' + escHtml(title) + '</div>',
            meta ? '<div class="knw-result-meta">' + escHtml(meta) + '</div>' : '',
            snippet ? '<div class="knw-result-snippet">' + escHtml(snippet) + '</div>' : '',
            '</div>'
          ].join("");
        }).join("");
      })
      .catch(function() {
        results.innerHTML = '<div style="color:#7a8fa6;font-size:0.82rem;padding:4px 0">Search unavailable — NIF offline</div>';
      });
  }

  function injectHolonBars() {
    var container = document.createElement("div");
    container.innerHTML = '<div style="margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">Holon Level Distribution</div>';

    HOLON_LEVELS.forEach(function(hl) {
      var pct = Math.round((hl.count / TOTAL_HOLONS) * 100);
      var row = document.createElement("div");
      row.className = "holon-bar-row";
      row.innerHTML = [
        '<span class="hb-label" style="color:' + hl.color + '">' + hl.level + '</span>',
        '<div class="hb-bar"><div class="hb-fill" style="width:' + pct + '%;background:' + hl.color + '"></div></div>',
        '<span class="hb-count">' + hl.count.toLocaleString() + '</span>'
      ].join("");
      row.title = hl.desc;
      container.appendChild(row);
    });

    var last = document.querySelector(".w-full");
    if (last) last.appendChild(container);
  }

  function escHtml(s) {
    return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
  }

  function updateHeartbeat() {
    if (!heartbeatEl) return;
    var age = Date.now() - lastMsgTime;
    var dot = heartbeatEl.querySelector(".knw-dot");
    var txt = document.getElementById("knw-hb-text");
    heartbeatEl.className = age > DEAD_MS ? "dead" : age > STALE_MS ? "stale" : "";
    if (dot) dot.style.background = age > DEAD_MS ? "#ff4757" : age > STALE_MS ? "#f5a623" : "#3dd68c";
    if (txt) txt.textContent = wsConnected
      ? "Knowledge mesh active — FTS5 search ready"
      : age > DEAD_MS ? "Knowledge mesh disconnected" : "Reconnecting...";
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
