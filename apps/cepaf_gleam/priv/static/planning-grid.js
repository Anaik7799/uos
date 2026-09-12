// C3I Planning Data Grid v2.0 — Agentic UI with Fractal Navigation
// Features: Grid/Kanban/Timeline views, AI search, fractal L0-L7 filters,
// row-level refresh (1s), click-to-detail drill-down, elegant gradient badges,
// real-time analytics, dependency graph, task aging, heartbeat indicators
// SC-TODO-001, SC-GLM-UI-001, SC-ZENOH-001, SC-A2UI-001, SC-AGUI-001

(function() {
  "use strict";

  // ═══════════════════════════════════════════════════════════════
  // Configuration
  // ═══════════════════════════════════════════════════════════════

  var API_BASE = "";
  var RETRY_COUNT = 3;
  var RETRY_DELAY_MS = 1000;
  var REFRESH_INTERVAL_MS = 30000;
  var ACTIVE_REFRESH_MS = 1000;
  var ALL_REFRESH_MS = 5000;
  var refreshTimer = null;
  var activeTimer = null;
  var allTimer = null;
  var lastRefreshTime = Date.now();
  var refreshCount = 0;
  var currentView = "grid";
  var activeFractalFilter = null;
  var allTaskData = [];
  var changeLog = []; // State change event log (max 50 entries)
  var MAX_CHANGE_LOG = 50;

  // Grid instance registry
  var grids = { blocked: null, active: null, all: null };
  var prevSnapshots = { blocked: {}, active: {}, all: {} };

  // Fractal layer classification from task title keywords
  var FRACTAL_LAYERS = {
    "L0": { label: "Constitutional", color: "#ff6b6b", keywords: ["guardian","constitutional","psi","safety","emergency","sil4","sil6","prime"] },
    "L1": { label: "Atomic/Debug", color: "#ffd93d", keywords: ["nif","debug","trace","telemetry","otel","atomic","ffi"] },
    "L2": { label: "Component", color: "#6bcb77", keywords: ["parser","component","form","badge","input","catalog","a2ui"] },
    "L3": { label: "Transaction", color: "#4d96ff", keywords: ["planning","task","state","db","sqlite","smriti","transaction","crud"] },
    "L4": { label: "System", color: "#9b59b6", keywords: ["podman","container","system","boot","build","image","docker"] },
    "L5": { label: "Cognitive", color: "#00d4aa", keywords: ["ooda","cortex","mcp","agent","llm","inference","reasoning","cognitive"] },
    "L6": { label: "Ecosystem", color: "#e74c3c", keywords: ["zenoh","mesh","topology","quorum","cluster","ecosystem"] },
    "L7": { label: "Federation", color: "#f39c12", keywords: ["federation","gateway","version","consensus","multi-node"] }
  };

  // ═══════════════════════════════════════════════════════════════
  // Inject Enhanced CSS
  // ═══════════════════════════════════════════════════════════════

  var styleEl = document.createElement("style");
  styleEl.textContent = [
    // Row animations
    "@keyframes rowPulse{0%{background:rgba(0,212,170,0.18)}100%{background:transparent}}",
    "@keyframes pulseActive{0%,100%{opacity:1}50%{opacity:0.7}}",
    "@keyframes pulseBlocked{0%,100%{opacity:1}50%{opacity:0.55}}",
    "@keyframes shimmer{0%{background-position:-200% 0}100%{background-position:200% 0}}",
    "@keyframes fadeSlideIn{0%{opacity:0;transform:translateY(-8px)}100%{opacity:1;transform:translateY(0)}}",
    "@keyframes glowPulse{0%,100%{box-shadow:0 0 0 0 rgba(0,212,170,0)}50%{box-shadow:0 0 12px 3px rgba(0,212,170,0.15)}}",
    ".pulse-active{animation:pulseActive 2s ease-in-out infinite}",
    ".pulse-blocked{animation:pulseBlocked 2.5s ease-in-out infinite}",
    ".row-changed{animation:rowPulse 1.8s ease-out}",
    // Tabulator overrides
    ".tabulator-row{cursor:pointer;transition:all 0.2s ease}",
    ".tabulator-row:hover{background:rgba(0,212,170,0.06)!important;transform:translateX(2px)}",
    ".tabulator-row.tabulator-selected{background:rgba(0,212,170,0.12)!important}",
    ".tabulator .tabulator-header{background:rgba(10,14,23,0.95)!important;backdrop-filter:blur(8px)}",
    ".tabulator .tabulator-header .tabulator-col{border-color:rgba(30,42,58,0.5)!important}",
    // Heartbeat indicators
    ".heartbeat-dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:6px;transition:all 0.3s}",
    ".heartbeat-live{background:#3dd68c;box-shadow:0 0 8px rgba(61,214,140,0.6)}",
    ".heartbeat-stale{background:#f5a623;box-shadow:0 0 4px rgba(245,166,35,0.3)}",
    ".heartbeat-dead{background:#ff4757}",
    "#grid-status{font-family:'JetBrains Mono',monospace}",
    // View toggle — responsive, scrollable on mobile
    ".view-toggle{display:flex;gap:4px;background:rgba(10,14,23,0.6);backdrop-filter:blur(12px);border:1px solid rgba(30,42,58,0.6);border-radius:10px;padding:4px;overflow-x:auto;-webkit-overflow-scrolling:touch;flex-shrink:0}",
    // SC-AGUI-UI-008 / audit P2 #17 — sticky toolbar: keep CSV/JSON/Refresh + bulk-action buttons visible
    // when scrolled past page 1 of 25-row pagination. Toolbar lives inside Tabulator footer so we make
    // the footer sticky to the bottom of the grid container's overflow box.
    "#all-grid .tabulator-footer{position:sticky!important;bottom:0;z-index:10;background:rgba(10,14,23,0.96)!important;backdrop-filter:blur(8px);border-top:1px solid rgba(0,212,170,0.15)!important}",
    ".view-btn{padding:10px 16px;border:none;background:transparent;color:#7a8fa6;border-radius:8px;cursor:pointer;font-size:0.82rem;font-weight:600;transition:all 0.25s;letter-spacing:0.3px;white-space:nowrap;min-height:44px;display:flex;align-items:center}",
    ".view-btn:hover{color:#e0e6ed;background:rgba(0,212,170,0.06)}",
    ".view-btn.active{background:linear-gradient(135deg,rgba(0,212,170,0.15),rgba(0,212,170,0.08));color:#00d4aa;box-shadow:0 2px 8px rgba(0,212,170,0.1)}",
    // Kanban board — responsive: 1col mobile, 2col tablet, 4col desktop (via page_views CSS)
    ".kanban-board{display:grid;grid-template-columns:1fr;gap:10px;min-height:300px}",
    ".kanban-col{background:rgba(10,14,23,0.4);backdrop-filter:blur(8px);border:1px solid rgba(30,42,58,0.5);border-radius:10px;padding:10px;min-height:200px}",
    ".kanban-col-header{font-size:0.82rem;font-weight:700;padding:8px 12px;border-radius:8px;margin-bottom:8px;display:flex;justify-content:space-between;align-items:center}",
    ".kanban-card{background:rgba(20,25,34,0.9);backdrop-filter:blur(4px);border:1px solid rgba(30,42,58,0.6);border-radius:8px;padding:12px;margin-bottom:8px;cursor:pointer;transition:all 0.2s;min-height:44px}",
    ".kanban-card:hover{border-color:rgba(0,212,170,0.3);transform:translateY(-1px);box-shadow:0 4px 12px rgba(0,0,0,0.2)}",
    ".kanban-card[draggable=true]{cursor:grab}",
    ".kanban-col.drag-over{border:2px dashed rgba(0,212,170,0.7);background:rgba(0,212,170,0.05)}",
    ".kanban-card .card-pri{font-size:0.82rem;font-weight:700;padding:2px 8px;border-radius:6px;display:inline-block}",
    ".kanban-card .card-title{font-size:0.8rem;margin-top:6px;line-height:1.5;color:var(--text,#e0e6ed)}",
    ".kanban-card .card-meta{font-size:0.82rem;color:#7a8fa6;margin-top:6px;display:flex;gap:8px}",
    // Timeline — responsive labels
    ".timeline-container{position:relative;padding:12px 0;overflow-x:auto;-webkit-overflow-scrolling:touch}",
    ".timeline-row{display:flex;align-items:center;padding:4px 0;border-bottom:1px solid rgba(30,42,58,0.3);min-width:500px}",
    ".timeline-label{width:140px;font-size:0.85rem;color:#7a8fa6;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex-shrink:0}",
    ".timeline-bar-area{flex:1;height:22px;position:relative}",
    ".timeline-bar{position:absolute;height:18px;border-radius:4px;top:2px;transition:all 0.3s;cursor:pointer;font-size:0.82rem;line-height:18px;padding:0 6px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-height:44px;display:flex;align-items:center}",
    ".timeline-bar:hover{filter:brightness(1.2);transform:scaleY(1.2)}",
    // Responsive overrides via media queries in JS
    "@media(min-width:768px){.kanban-board{grid-template-columns:repeat(2,1fr)!important}.timeline-label{width:180px}}",
    "@media(min-width:1024px){.kanban-board{grid-template-columns:repeat(4,1fr)!important}.timeline-label{width:200px}.timeline-row{min-width:auto}}",
    // Fractal filter chips
    ".fractal-chips{display:flex;gap:6px;flex-wrap:wrap}",
    ".fractal-chip{padding:5px 12px;border-radius:16px;font-size:0.85rem;font-weight:600;cursor:pointer;transition:all 0.2s;border:1px solid transparent;letter-spacing:0.3px}",
    ".fractal-chip:hover{transform:translateY(-1px)}",
    ".fractal-chip.active{box-shadow:0 2px 8px rgba(0,0,0,0.2)}",
    ".fractal-chip.active-chip{border-width:2px!important;box-shadow:0 0 8px currentColor!important;transform:scale(1.05)!important}",
    // Detail panel — responsive padding
    ".detail-panel{background:rgba(10,14,23,0.95);backdrop-filter:blur(16px);border:1px solid rgba(0,212,170,0.15);border-radius:12px;padding:16px;margin:10px 0;box-shadow:0 8px 32px rgba(0,0,0,0.3);animation:fadeSlideIn 0.3s ease-out}",
    "@media(min-width:768px){.detail-panel{padding:24px;margin:12px 0}}",
    ".detail-section{background:rgba(20,25,34,0.6);border:1px solid rgba(30,42,58,0.4);border-radius:8px;padding:12px;margin-top:10px}",
    ".detail-action-btn{background:rgba(0,212,170,0.08);color:#00d4aa;border:1px solid rgba(0,212,170,0.2);padding:10px 16px;border-radius:8px;cursor:pointer;font-size:0.8rem;font-weight:600;transition:all 0.2s;min-height:44px;display:inline-flex;align-items:center}",
    ".detail-action-btn:hover{background:rgba(0,212,170,0.15);transform:translateY(-1px);box-shadow:0 2px 8px rgba(0,212,170,0.15)}",
    // Analytics section — responsive grid
    ".analytics-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:8px}",
    "@media(min-width:768px){.analytics-grid{grid-template-columns:repeat(3,1fr);gap:10px}}",
    "@media(min-width:1024px){.analytics-grid{grid-template-columns:repeat(auto-fit,minmax(140px,1fr))}}",
    ".analytics-card{background:rgba(20,25,34,0.6);backdrop-filter:blur(4px);border:1px solid rgba(30,42,58,0.4);border-radius:10px;padding:12px;text-align:center;transition:all 0.2s}",
    ".analytics-card:hover{border-color:rgba(0,212,170,0.2);transform:translateY(-2px)}",
    ".analytics-card .metric{font-size:1.4rem;font-weight:800;background:linear-gradient(135deg,#00d4aa,#3dd68c);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}",
    "@media(min-width:768px){.analytics-card .metric{font-size:1.6rem}}",
    ".analytics-card .label{font-size:0.82rem;color:#7a8fa6;margin-top:4px;letter-spacing:0.5px;text-transform:uppercase}",
    // Sort direction indicator
    ".tabulator .tabulator-col .tabulator-col-sorter .tabulator-arrow{border-bottom-color:var(--accent,#00d4aa)!important}",
    // Search result active row
    ".tabulator-row.tabulator-row-active{background:rgba(0,212,170,0.08)!important}",

    // ─── रूपं दर्शनीयम् — Beautiful form, worth seeing ──────────────────
    // 3-Layer Visual Hierarchy

    // Layer 1 — Hero bar: compact, glassmorphic, always visible context
    ".page-header{margin-bottom:0.5rem!important}",
    ".page-header+div{background:linear-gradient(135deg,rgba(20,25,34,0.95),rgba(10,14,23,0.98))!important;border:1px solid rgba(0,212,170,0.1)!important;border-radius:12px!important;padding:12px 20px!important;backdrop-filter:blur(12px)!important;margin-bottom:0.75rem!important}",
    ".card-grid{gap:0.5rem!important;margin:0.5rem 0!important;max-height:120px!important}",
    ".card-grid .card{padding:8px!important;border:none!important;background:transparent!important}",

    // Layer 2 — Controls bar: sticky, compact, semi-transparent
    "#grid-section{position:sticky!important;top:44px!important;z-index:100!important;background:rgba(10,14,23,0.95)!important;backdrop-filter:blur(16px)!important;border-bottom:1px solid var(--border)!important;padding:8px 0!important;margin:0 -1.5rem!important;padding-left:1.5rem!important;padding-right:1.5rem!important}",
    "#grid-section .btn{padding:6px 14px!important;font-size:0.85rem!important}",
    "#fractal-filter-chips{display:flex!important;flex-wrap:nowrap!important;overflow-x:auto!important;gap:4px!important;padding:4px 0!important;-webkit-overflow-scrolling:touch!important;scrollbar-width:none!important}",
    "#fractal-filter-chips::-webkit-scrollbar{display:none}",
    "#ai-search-input{border-radius:20px!important;padding:10px 20px!important;background:rgba(20,25,34,0.8)!important;border:1px solid rgba(30,42,58,0.5)!important}",
    "#ai-search-input:focus{border-color:var(--accent)!important;box-shadow:0 0 12px rgba(0,212,170,0.2)!important}",

    // Layer 3 — Content: elevated grid cards with shadow depth
    ".section{background:var(--card-bg)!important;border:1px solid var(--border)!important;border-radius:10px!important;padding:16px!important;margin-bottom:12px!important;box-shadow:0 4px 20px rgba(0,0,0,0.15)!important}",
    ".section-title,h2{font-size:0.9rem!important;text-transform:uppercase!important;letter-spacing:1px!important;color:var(--muted)!important;border-bottom:2px solid rgba(0,212,170,0.2)!important;padding-bottom:8px!important;margin-bottom:12px!important}",
    "#blocked-grid{border-left:3px solid #ff4757!important;border-radius:8px!important;background:rgba(255,71,87,0.03)!important}",
    "#active-grid{border-left:3px solid #00d4aa!important;border-radius:8px!important;background:rgba(0,212,170,0.02)!important}",
    "#all-grid{border-left:3px solid #4d96ff!important;border-radius:8px!important}",
    "#grid-status{background:rgba(20,25,34,0.9)!important;border-radius:8px!important;padding:10px 16px!important;border:1px solid var(--border)!important;font-family:'JetBrains Mono',monospace!important}",
    "h3{font-size:0.95rem!important;font-weight:700!important;color:var(--text)!important;display:flex!important;align-items:center!important;gap:8px!important;margin:16px 0 8px!important}",
    ".tabulator{border:1px solid var(--border)!important;border-radius:8px!important;overflow:hidden!important}",
    ".tabulator .tabulator-header{background:rgba(20,25,34,0.95)!important;border-bottom:2px solid var(--border)!important}",
    ".tabulator .tabulator-header .tabulator-col{border-right:1px solid rgba(30,42,58,0.3)!important}",
    ".tabulator-row{border-bottom:1px solid rgba(30,42,58,0.3)!important;transition:all 0.15s!important}",
    ".tabulator-row:hover{background:rgba(0,212,170,0.06)!important;transform:translateX(2px)!important}",
    ".tabulator-row:nth-child(even){background:rgba(20,25,34,0.3)!important}",
    "#grid-status span[style*='color:#3dd68c']{font-weight:700!important}",
    "#grid-status span[style*='color:#ff4757']{font-weight:700!important}",
    ".progress-bar-container{border-radius:8px!important;overflow:hidden!important;height:6px!important;background:rgba(30,42,58,0.5)!important;box-shadow:inset 0 1px 3px rgba(0,0,0,0.3)!important}",

    // Mobile adjustments
    "@media(max-width:768px){#grid-section{top:36px!important;padding:4px 0.75rem!important}.section{padding:10px!important;margin-bottom:8px!important}.card-grid{max-height:80px!important}#fractal-filter-chips{gap:2px!important}}"
  ].join("\n");
  document.head.appendChild(styleEl);
    // Pass-12 P3 #21 — extracted ~5 KB inline CSS string into priv/static/planning-radical.css.
    // Loaded via <link> so the browser caches the rules separately and edits go to a
    // proper .css file (no JS string-escaping). SC-FILESIZE-001 / SC-MUDA-001.
    var radLink = document.createElement("link");
    radLink.rel = "stylesheet";
    radLink.href = "/static/planning-radical.css";
    document.head.appendChild(radLink);

  // ═══════════════════════════════════════════════════════════════
  // Utility Functions
  // ═══════════════════════════════════════════════════════════════

  function taskAge(created) {
    if (!created) return "\u2014";
    var diff = Date.now() - new Date(created).getTime();
    var mins = Math.floor(diff / 60000);
    if (mins < 60) return mins + "m";
    var hours = Math.floor(mins / 60);
    if (hours < 24) return hours + "h";
    var days = Math.floor(hours / 24);
    if (days < 30) return days + "d";
    return Math.floor(days / 30) + "mo";
  }

  function classifyFractalLayer(task) {
    var title = (task.title || "").toLowerCase();
    for (var layer in FRACTAL_LAYERS) {
      var kws = FRACTAL_LAYERS[layer].keywords;
      for (var i = 0; i < kws.length; i++) {
        if (title.indexOf(kws[i]) >= 0) return layer;
      }
    }
    return "L3"; // Default: Transaction layer (planning tasks)
  }

  function fetchWithRetry(url, retries) {
    return fetch(url).then(function(r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    }).catch(function(err) {
      if (retries > 0) {
        return new Promise(function(resolve) {
          setTimeout(function() { resolve(fetchWithRetry(url, retries - 1)); }, RETRY_DELAY_MS * (RETRY_COUNT - retries + 1));
        });
      }
      throw err;
    });
  }

  function snapshotData(data) {
    var snap = {};
    data.forEach(function(t) { snap[t.id] = t.status + "|" + t.priority + "|" + (t.title || ""); });
    return snap;
  }

  function findChangedIds(oldSnap, newSnap) {
    var changed = [];
    Object.keys(newSnap).forEach(function(id) {
      if (!oldSnap[id] || oldSnap[id] !== newSnap[id]) changed.push(id);
    });
    return changed;
  }

  function highlightChangedRows(gridInstance, changedIds) {
    if (!gridInstance || changedIds.length === 0) return;
    try {
      gridInstance.getRows().forEach(function(row) {
        var data = row.getData();
        if (changedIds.indexOf(data.id) >= 0) {
          var el = row.getElement();
          el.classList.remove("row-changed");
          void el.offsetWidth;
          el.classList.add("row-changed");
        }
      });
    } catch(e) {}
  }

  // ═══════════════════════════════════════════════════════════════
  // Column Definitions — Elegant Gradient Badges
  // ═══════════════════════════════════════════════════════════════

  var taskColumns = [
    { title:"ID", field:"id", width:90, headerSort:true,
      formatter:function(c) {
        // SC-AGUI-UI-009 + audit-E1 — render as <a target="_blank"> so middle-click
        // and ctrl/cmd-click work natively (popup-blocker proof). Plain row click
        // still routes through rowClick → window.open(named) for the size-controlled
        // detail panel — the anchor URL is the same so no surprise on left-click.
        var v = c.getValue() || "";
        var url = "/planning?task=" + encodeURIComponent(v);
        return "<a href='" + url + "' target='_blank' rel='noopener' "
          + "style='font-family:\"JetBrains Mono\",monospace;font-size:0.82rem;"
          + "opacity:0.7;color:var(--accent,#00d4aa);text-decoration:none' "
          + "onclick='event.stopPropagation()'>" + v.substring(0,8) + " ↗</a>";
      },
      tooltip:function(e,c) { return c.getValue(); }
    },
    { title:"Pri", field:"priority", width:65, headerFilter:"select",
      headerFilterParams:{values:{"":"All","P0":"P0","P1":"P1","P2":"P2","P3":"P3"}},
      formatter:function(c) {
        var v = c.getValue();
        var styles = {
          "P0":"background:linear-gradient(135deg,#ff4757,#ff6b81);color:#fff;box-shadow:0 2px 10px rgba(255,71,87,0.35);",
          "P1":"background:linear-gradient(135deg,#ffa502,#ffbe76);color:#1a1000;box-shadow:0 2px 8px rgba(255,165,2,0.25);",
          "P2":"background:linear-gradient(135deg,#2ed573,#7bed9f);color:#081008;",
          "P3":"background:rgba(122,143,166,0.1);color:#7a8fa6;border:1px solid rgba(122,143,166,0.12);"
        };
        var icons = {"P0":"\u26a0","P1":"\u25b2","P2":"\u25cf","P3":"\u25cb"};
        return "<span style='" + (styles[v]||styles.P3) + "padding:2px 8px;border-radius:12px;font-size:0.82rem;font-weight:700;display:inline-flex;align-items:center;gap:3px;letter-spacing:0.5px'>" + (icons[v]||"") + " " + v + "</span>";
      },
      sorter:function(a,b) { var o={"P0":0,"P1":1,"P2":2,"P3":3}; return (o[a]||9)-(o[b]||9); }
    },
    { title:"Status", field:"status", width:105, headerFilter:"select",
      headerFilterParams:{values:{"":"All","pending":"Pending","in_progress":"Active","completed":"Done","blocked":"Blocked"}},
      formatter:function(c) {
        var v = c.getValue();
        var configs = {
          "completed":{bg:"rgba(61,214,140,0.12)",color:"#3dd68c",icon:"\u2713",label:"Done",border:"rgba(61,214,140,0.2)"},
          "blocked":{bg:"rgba(255,71,87,0.1)",color:"#ff6b81",icon:"\u2717",label:"Blocked",border:"rgba(255,71,87,0.2)"},
          "in_progress":{bg:"rgba(0,212,170,0.12)",color:"#00d4aa",icon:"\u25b6",label:"Active",border:"rgba(0,212,170,0.2)"},
          "pending":{bg:"rgba(122,143,166,0.05)",color:"#7a8fa6",icon:"\u25cb",label:"Pending",border:"rgba(122,143,166,0.1)"}
        };
        var cfg = configs[v] || configs.pending;
        var cls = v === "in_progress" ? " pulse-active" : v === "blocked" ? " pulse-blocked" : "";
        return "<span class='" + cls + "' style='background:" + cfg.bg + ";color:" + cfg.color + ";border:1px solid " + cfg.border + ";padding:2px 8px;border-radius:12px;font-size:0.82rem;font-weight:600;display:inline-flex;align-items:center;gap:3px'>" + cfg.icon + " " + cfg.label + "</span>";
      }
    },
    { title:"Owner", field:"owner", width:90, headerFilter:"input", visible:false,
      // SC-TRUTH-001 — owner is null on every observed row. Hide by default
      // to honor "display=truth"; will auto-enable when any non-null owner
      // appears (initGrids checks via checkOwnerActivation).
      formatter:function(c) {
        var v = c.getValue();
        return v ? "<span style='color:#00d4aa;font-size:0.88rem'>" + v + "</span>" : "<span style='color:#7a8fa6;font-size:0.78rem;font-style:italic'>unassigned</span>";
      }
    },
    { title:"Layer", field:"_layer", width:65,
      headerFilter:"select",
      headerFilterParams:{values:{"":"All","L0":"L0","L1":"L1","L2":"L2","L3":"L3","L4":"L4","L5":"L5","L6":"L6","L7":"L7"}},
      formatter:function(c) {
        var v = c.getValue() || "L3";
        var info = FRACTAL_LAYERS[v] || FRACTAL_LAYERS.L3;
        return "<span style='background:" + info.color + "22;color:" + info.color + ";padding:1px 6px;border-radius:8px;font-size:0.82rem;font-weight:700;border:1px solid " + info.color + "33'>" + v + "</span>";
      }
    },
    { title:"Description", field:"title", minWidth:300, headerFilter:"input",
      headerFilterPlaceholder:"Filter...",
      formatter:function(c) {
        var v = c.getValue() || "";
        var hl = v.replace(/(SC-[A-Z]+-\d+)/g, "<span style='color:#00d4aa;font-weight:600'>$1</span>");
        return "<span style='font-size:0.8rem;line-height:1.4'>" + hl + "</span>";
      },
      tooltip:true
    },
    { title:"Age", field:"created", width:55,
      // SC-EVO-KPI-003 — staleness is rot signal for *non-terminal* tasks only.
      // completed/blocked rows are dim grey regardless of age (already done /
      // already known to be stuck). pending/in_progress fire the traffic-light:
      // > 30 d amber, > 90 d red.
      formatter:function(c) {
        var age = taskAge(c.getValue());
        var status = (c.getRow().getData() || {}).status || "";
        var dim = (status === "completed" || status === "blocked");
        var color = "#3dd68c"; // default = fresh
        if (dim) {
          color = "#5a6470"; // dim grey for terminal states
        } else if (age.indexOf("mo") >= 0) {
          var months = parseInt(age) || 1;
          color = months >= 3 ? "#ff4757" : "#f5a623"; // > 90 d red, else amber
        } else if (age.indexOf("d") >= 0) {
          var days = parseInt(age);
          if (days > 90) color = "#ff4757";      // red = very stale
          else if (days > 30) color = "#f5a623"; // amber = stale
        }
        return "<span style='color:" + color + ";font-size:0.82rem'>" + age + "</span>";
      },
      sorter:"date"
    }
  ];

  // ═══════════════════════════════════════════════════════════════
  // Status Bar with Live Heartbeat
  // ═══════════════════════════════════════════════════════════════

  function updateStatusBar(msg, type) {
    var bar = document.getElementById("grid-status");
    if (!bar) return;
    var colors = {ok:"#3dd68c",loading:"#f5a623",error:"#ff4757"};
    var dotCls = type === "ok" ? "heartbeat-live" : type === "loading" ? "heartbeat-stale" : "heartbeat-dead";
    bar.innerHTML = "<span class='heartbeat-dot " + dotCls + "'></span><span style='color:" + (colors[type]||"#7a8fa6") + "'>" + msg + "</span>";
  }

  function startCountdown() {
    setInterval(function() {
      var el = document.getElementById("refresh-countdown");
      if (el) {
        var elapsed = Math.floor((Date.now() - lastRefreshTime) / 1000);
        el.textContent = elapsed + "s ago";
        if (elapsed < 2) { el.style.color = "#3dd68c"; el.parentElement.classList.add("refresh-flash"); setTimeout(function(){ el.parentElement.classList.remove("refresh-flash"); }, 1500); }
        el.style.color = elapsed < 5 ? "#3dd68c" : elapsed < 30 ? "#f5a623" : "#ff4757";
      }
    }, 1000);
  }

  // ═══════════════════════════════════════════════════════════════
  // Grid Factory
  // ═══════════════════════════════════════════════════════════════

  function createGrid(selector, data, opts) {
    // Enrich data with fractal layer
    data.forEach(function(t) { t._layer = classifyFractalLayer(t); });

    var defaults = {
      data: data,
      columns: taskColumns,
      layout: "fitColumns",
      placeholder: "<div style='padding:20px;text-align:center;color:#7a8fa6;font-size:0.85rem'>No tasks</div>",
      headerSortTristate: true,
      movableColumns: true,
      selectable: true,
      animationSpeed: 200,
      rowClick: function(e, row) {
        var d = row.getData();
        // If we are already inside a task-detail sub-window (?task=...),
        // keep the in-page panel behaviour. Otherwise spawn a new window.
        if (location.search.indexOf("task=") !== -1) {
          showTaskDetail(d);
        } else if (d && d.id) {
          window.open(
            "/planning?task=" + encodeURIComponent(d.id),
            "c3i_task_" + d.id,
            "width=960,height=820,scrollbars=yes,resizable=yes"
          );
        }
      }
    };
    Object.keys(opts || {}).forEach(function(k) { defaults[k] = opts[k]; });
    return new Tabulator(selector, defaults);
  }

  // ═══════════════════════════════════════════════════════════════
  // View Toggle Logic
  // ═══════════════════════════════════════════════════════════════

  function switchView(view) {
    currentView = view;
    var gridSection = document.getElementById("grid-section");
    var kanbanSection = document.getElementById("kanban-section");
    var timelineSection = document.getElementById("timeline-section");
    var analyticsSection = document.getElementById("analytics-section");

    [gridSection, kanbanSection, timelineSection, analyticsSection].forEach(function(el) {
      if (el) el.style.display = "none";
    });

    if (view === "grid" && gridSection) gridSection.style.display = "block";
    else if (view === "kanban" && kanbanSection) kanbanSection.style.display = "block";
    else if (view === "timeline" && timelineSection) timelineSection.style.display = "block";
    else if (view === "analytics" && analyticsSection) analyticsSection.style.display = "block";

    // Update toggle buttons
    document.querySelectorAll(".view-btn").forEach(function(btn) {
      btn.classList.toggle("active", btn.getAttribute("data-view") === view);
    });

    // Render dynamic views
    if (view === "kanban") renderKanban(allTaskData);
    else if (view === "timeline") renderTimeline(allTaskData);
    else if (view === "analytics") renderAnalyticsView(allTaskData);
  }

  // ═══════════════════════════════════════════════════════════════
  // Kanban Board
  // ═══════════════════════════════════════════════════════════════

  function renderKanban(data) {
    var container = document.getElementById("kanban-section");
    if (!container) return;

    var columns = {
      pending: { label: "Pending", color: "#7a8fa6", bg: "rgba(122,143,166,0.06)", tasks: [] },
      in_progress: { label: "In Progress", color: "#00d4aa", bg: "rgba(0,212,170,0.06)", tasks: [] },
      blocked: { label: "Blocked", color: "#ff6b81", bg: "rgba(255,107,129,0.06)", tasks: [] },
      completed: { label: "Done", color: "#3dd68c", bg: "rgba(61,214,140,0.06)", tasks: [] }
    };

    // Apply fractal filter
    var filtered = activeFractalFilter ? data.filter(function(t) { return classifyFractalLayer(t) === activeFractalFilter; }) : data;

    filtered.forEach(function(t) {
      var col = columns[t.status];
      if (col) col.tasks.push(t);
    });

    var html = "<div class='kanban-board'>";
    ["pending","in_progress","blocked","completed"].forEach(function(status) {
      var col = columns[status];
      html += "<div class='kanban-col' data-kanban-status='" + status + "' style='border-top:3px solid " + col.color + "'>";
      html += "<div class='kanban-col-header' style='background:" + col.bg + ";color:" + col.color + "'>";
      html += "<span>" + col.label + "</span><span style='font-size:0.88rem;opacity:0.8'>" + col.tasks.length + "</span></div>";

      // Sort by priority
      col.tasks.sort(function(a,b) { var o={"P0":0,"P1":1,"P2":2,"P3":3}; return (o[a.priority]||9)-(o[b.priority]||9); });

      // Show max 20 cards per column
      col.tasks.slice(0, 20).forEach(function(t) {
        var priColors = {"P0":"#ff4757","P1":"#ffa502","P2":"#2ed573","P3":"#7a8fa6"};
        var layer = classifyFractalLayer(t);
        var layerInfo = FRACTAL_LAYERS[layer] || FRACTAL_LAYERS.L3;
        html += "<div class='kanban-card' draggable='true' data-id='" + t.id + "' data-status='" + status + "' onclick='showTaskDetail(" + JSON.stringify(t).replace(/'/g, "\\'") + ")'>";
        html += "<div style='display:flex;justify-content:space-between;align-items:center'>";
        html += "<span class='card-pri' style='background:" + (priColors[t.priority]||"#7a8fa6") + "22;color:" + (priColors[t.priority]||"#7a8fa6") + "'>" + t.priority + "</span>";
        html += "<span style='font-size:0.8rem;color:" + layerInfo.color + ";opacity:0.8'>" + layer + "</span></div>";
        html += "<div class='card-title'>" + (t.title || "").substring(0, 80) + (t.title && t.title.length > 80 ? "..." : "") + "</div>";
        html += "<div class='card-meta'><span>" + taskAge(t.created) + "</span></div>";
        html += "</div>";
      });

      if (col.tasks.length > 20) {
        html += "<div style='text-align:center;color:#7a8fa6;font-size:0.85rem;padding:8px'>+" + (col.tasks.length - 20) + " more</div>";
      }
      html += "</div>";
    });
    html += "</div>";
    container.innerHTML = html;

    // ── Drag-and-drop wiring ──────────────────────────────────────
    var draggedId = null;
    var draggedStatus = null;

    container.querySelectorAll(".kanban-card").forEach(function(card) {
      card.addEventListener("dragstart", function(e) {
        draggedId = card.dataset.id;
        draggedStatus = card.dataset.status;
        card.style.opacity = "0.45";
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", draggedId);
      });
      card.addEventListener("dragend", function() {
        card.style.opacity = "";
        container.querySelectorAll(".kanban-col").forEach(function(c) {
          c.classList.remove("drag-over");
        });
      });
    });

    container.querySelectorAll(".kanban-col").forEach(function(col) {
      col.addEventListener("dragover", function(e) {
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        col.classList.add("drag-over");
      });
      col.addEventListener("dragleave", function(e) {
        // Only remove if leaving the column itself, not a child element
        if (!col.contains(e.relatedTarget)) {
          col.classList.remove("drag-over");
        }
      });
      col.addEventListener("drop", function(e) {
        e.preventDefault();
        col.classList.remove("drag-over");
        var newStatus = col.dataset.kanbanStatus;
        if (!draggedId || !newStatus || newStatus === draggedStatus) return;
        mutateTaskStatus(draggedId, newStatus);
        draggedId = null;
        draggedStatus = null;
      });
    });
  }

  // ── Drag-drop backend mutation ────────────────────────────────
  function mutateTaskStatus(id, newStatus) {
    var VALID = ["pending", "in_progress", "blocked", "completed"];
    if (!id || VALID.indexOf(newStatus) === -1) {
      logChange("error", "mutateTaskStatus: invalid id or status: " + newStatus);
      return;
    }

    // Optimistic: find the card and move it to the new column visually
    var card = document.querySelector(".kanban-card[data-id='" + id + "']");
    var oldStatus = card ? card.dataset.status : null;
    var targetCol = document.querySelector(".kanban-col[data-kanban-status='" + newStatus + "']");

    if (card && targetCol) {
      // Detach from old column
      card.parentNode.removeChild(card);
      card.dataset.status = newStatus;
      // Insert before the "+N more" notice if present, else append
      var more = targetCol.querySelector("[data-more]");
      if (more) {
        targetCol.insertBefore(card, more);
      } else {
        targetCol.appendChild(card);
      }
      // Update column header counts
      updateKanbanCounts();
    }

    logChange("status_change", "Task " + id + ": " + oldStatus + " → " + newStatus);

    fetch("/api/v1/plan/update", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: id, status: newStatus })
    })
    .then(function(r) {
      if (!r.ok) return r.json().then(function(e) { throw new Error(e.error || r.status); });
      return r.json();
    })
    .then(function(data) {
      if (!data.ok) throw new Error(data.error || "server rejected update");
      // Success — card is already in the new column
    })
    .catch(function(err) {
      // Rollback: move card back to original column
      logChange("error", "Task update failed (" + err.message + "), rolling back");
      var rollbackCard = document.querySelector(".kanban-card[data-id='" + id + "']");
      var rollbackCol = oldStatus ? document.querySelector(".kanban-col[data-kanban-status='" + oldStatus + "']") : null;
      if (rollbackCard && rollbackCol) {
        rollbackCard.parentNode.removeChild(rollbackCard);
        rollbackCard.dataset.status = oldStatus;
        rollbackCol.appendChild(rollbackCard);
        updateKanbanCounts();
      }
      // Surface alert in change log
      logChange("error", "Rollback: task " + id + " reverted to " + oldStatus);
    });
  }

  function updateKanbanCounts() {
    document.querySelectorAll(".kanban-col").forEach(function(col) {
      var status = col.dataset.kanbanStatus;
      var count = col.querySelectorAll(".kanban-card").length;
      var header = col.querySelector(".kanban-col-header span:last-child");
      if (header) header.textContent = count;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Timeline View (Gantt-style)
  // ═══════════════════════════════════════════════════════════════

  function renderTimeline(data) {
    var container = document.getElementById("timeline-section");
    if (!container) return;

    // Filter to tasks with dates, show recent
    var filtered = activeFractalFilter ? data.filter(function(t) { return classifyFractalLayer(t) === activeFractalFilter; }) : data;
    var withDates = filtered.filter(function(t) { return t.created; })
      .sort(function(a,b) { return new Date(b.created) - new Date(a.created); })
      .slice(0, 50);

    if (withDates.length === 0) {
      container.innerHTML = "<div style='text-align:center;padding:40px;color:#7a8fa6'>No timeline data available</div>";
      return;
    }

    var now = Date.now();
    var oldest = Math.min.apply(null, withDates.map(function(t) { return new Date(t.created).getTime(); }));
    var range = now - oldest;
    if (range < 1) range = 1;

    var priColors = {"P0":"linear-gradient(90deg,#ff4757,#ff6b81)","P1":"linear-gradient(90deg,#ffa502,#ffbe76)","P2":"linear-gradient(90deg,#2ed573,#7bed9f)","P3":"linear-gradient(90deg,#7a8fa6,#a0b0c0)"};
    var statusOpacity = {"completed":"0.5","blocked":"0.8","in_progress":"1","pending":"0.6"};

    var html = "<div class='timeline-container'>";
    // Timeline header with date markers
    html += "<div style='display:flex;padding:0 0 8px 200px;font-size:0.82rem;color:#7a8fa6;border-bottom:1px solid rgba(30,42,58,0.4)'>";
    for (var i = 0; i <= 4; i++) {
      var d = new Date(oldest + (range * i / 4));
      html += "<span style='flex:1;text-align:" + (i === 0 ? "left" : i === 4 ? "right" : "center") + "'>" + d.toLocaleDateString("en", {month:"short",day:"numeric"}) + "</span>";
    }
    html += "</div>";

    withDates.forEach(function(t) {
      var start = new Date(t.created).getTime();
      var leftPct = ((start - oldest) / range * 100).toFixed(1);
      var widthPct = t.status === "completed" ? "2" : Math.max(2, ((now - start) / range * 100)).toFixed(1);
      var opacity = statusOpacity[t.status] || "0.7";

      html += "<div class='timeline-row'>";
      html += "<div class='timeline-label' title='" + (t.title||"").replace(/'/g,"") + "'>" + (t.title||"").substring(0,30) + "</div>";
      html += "<div class='timeline-bar-area'>";
      html += "<div class='timeline-bar' onclick='showTaskDetail(" + JSON.stringify(t).replace(/'/g,"\\'") + ")' style='left:" + leftPct + "%;width:" + widthPct + "%;background:" + (priColors[t.priority]||priColors.P3) + ";opacity:" + opacity + "'>" + t.priority + "</div>";
      html += "</div></div>";
    });
    html += "</div>";
    container.innerHTML = html;
  }

  // ═══════════════════════════════════════════════════════════════
  // Analytics View
  // ═══════════════════════════════════════════════════════════════

  function renderAnalyticsView(data) {
    var container = document.getElementById("analytics-section");
    if (!container) return;

    var a = computeAnalytics(data);
    var layerCounts = {};
    data.forEach(function(t) {
      var l = classifyFractalLayer(t);
      layerCounts[l] = (layerCounts[l] || 0) + 1;
    });

    var html = "";
    // Key metrics
    html += "<div class='analytics-grid' style='margin-bottom:20px'>";
    html += analyticsCard(a.total, "Total Tasks", "#e0e6ed");
    html += analyticsCard(a.completionRate + "%", "Completion", "#3dd68c");
    html += analyticsCard(a.byStatus.in_progress, "Active Now", "#00d4aa");
    html += analyticsCard(a.byStatus.blocked, "Blocked", "#ff6b81");
    html += analyticsCard(a.oldestActive, "Oldest Active", "#f5a623");
    html += analyticsCard(refreshCount, "Refreshes", "#7a8fa6");
    html += "</div>";

    // Priority distribution
    html += "<h3 style='font-size:0.9rem;color:#e0e6ed;margin:16px 0 10px'>Priority Distribution</h3>";
    html += "<div style='display:flex;height:24px;border-radius:8px;overflow:hidden;margin-bottom:16px'>";
    var priDefs = [["P0","#ff4757"],["P1","#ffa502"],["P2","#2ed573"],["P3","#7a8fa6"]];
    priDefs.forEach(function(pd) {
      var pct = a.total > 0 ? (a.byPriority[pd[0]] / a.total * 100) : 0;
      if (pct > 0) html += "<div style='width:" + pct + "%;background:" + pd[1] + ";display:flex;align-items:center;justify-content:center;font-size:0.82rem;font-weight:700;color:#fff;transition:width 0.5s' title='" + pd[0] + ": " + a.byPriority[pd[0]] + " (" + pct.toFixed(1) + "%)'>" + (pct > 5 ? pd[0] : "") + "</div>";
    });
    html += "</div>";

    // Fractal layer distribution
    html += "<h3 style='font-size:0.9rem;color:#e0e6ed;margin:16px 0 10px'>Fractal Layer Distribution</h3>";
    html += "<div class='analytics-grid'>";
    for (var layer in FRACTAL_LAYERS) {
      var info = FRACTAL_LAYERS[layer];
      var cnt = layerCounts[layer] || 0;
      html += "<div class='analytics-card' style='border-left:3px solid " + info.color + "'>";
      html += "<div class='metric' style='background:linear-gradient(135deg," + info.color + "," + info.color + "aa);-webkit-background-clip:text'>" + cnt + "</div>";
      html += "<div class='label'>" + layer + " " + info.label + "</div></div>";
    }
    html += "</div>";

    // Status flow
    html += "<h3 style='font-size:0.9rem;color:#e0e6ed;margin:20px 0 10px'>Status Flow</h3>";
    html += "<div style='display:flex;align-items:center;justify-content:center;gap:16px;padding:20px'>";
    var statusFlow = [
      {label:"Pending",count:a.byStatus.pending,color:"#7a8fa6"},
      {label:"Active",count:a.byStatus.in_progress,color:"#00d4aa"},
      {label:"Blocked",count:a.byStatus.blocked,color:"#ff6b81"},
      {label:"Done",count:a.byStatus.completed,color:"#3dd68c"}
    ];
    statusFlow.forEach(function(s,i) {
      html += "<div style='text-align:center'><div style='font-size:1.8rem;font-weight:800;color:" + s.color + "'>" + s.count + "</div><div style='font-size:0.85rem;color:#7a8fa6'>" + s.label + "</div></div>";
      if (i < statusFlow.length - 1) html += "<div style='color:#7a8fa6;font-size:1.2rem'>\u2192</div>";
    });
    html += "</div>";

    container.innerHTML = html;
  }

  function analyticsCard(value, label, color) {
    return "<div class='analytics-card'><div class='metric' style='background:linear-gradient(135deg," + color + "," + color + "aa);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text'>" + value + "</div><div class='label'>" + label + "</div></div>";
  }

  // ═══════════════════════════════════════════════════════════════
  // Fractal Layer Filter
  // ═══════════════════════════════════════════════════════════════

  function initFractalFilters() {
    var container = document.getElementById("fractal-filter-chips");
    if (!container) return;

    var html = "<div class='fractal-chips'>";
    html += "<span class='fractal-chip active' data-layer='' style='background:rgba(224,230,237,0.08);color:#e0e6ed;border-color:rgba(224,230,237,0.2)'>All Layers</span>";
    for (var layer in FRACTAL_LAYERS) {
      var info = FRACTAL_LAYERS[layer];
      html += "<span class='fractal-chip' data-layer='" + layer + "' style='background:" + info.color + "11;color:" + info.color + ";border-color:" + info.color + "22'>" + layer + " " + info.label + "</span>";
    }
    html += "</div>";
    container.innerHTML = html;

    container.querySelectorAll(".fractal-chip").forEach(function(chip) {
      chip.onclick = function() {
        var layer = chip.getAttribute("data-layer");
        activeFractalFilter = layer || null;

        container.querySelectorAll(".fractal-chip").forEach(function(c) {
          c.classList.remove("active");
          c.classList.remove("active-chip");
          c.style.borderColor = c.getAttribute("data-layer") ? (FRACTAL_LAYERS[c.getAttribute("data-layer")]||{}).color + "22" : "rgba(224,230,237,0.2)";
        });
        chip.classList.add("active");
        chip.classList.add("active-chip");
        chip.style.borderColor = layer ? FRACTAL_LAYERS[layer].color : "rgba(224,230,237,0.4)";

        // Apply filter to grid
        if (grids.all) {
          if (layer) grids.all.setFilter("_layer", "=", layer);
          else grids.all.clearFilter(true);
        }

        // Re-render dynamic views
        if (currentView === "kanban") renderKanban(allTaskData);
        else if (currentView === "timeline") renderTimeline(allTaskData);
        else if (currentView === "analytics") renderAnalyticsView(allTaskData);
      };
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Analytics Computation
  // ═══════════════════════════════════════════════════════════════

  function computeAnalytics(data) {
    var total = data.length;
    var byStatus = {pending:0,in_progress:0,completed:0,blocked:0};
    var byPriority = {P0:0,P1:0,P2:0,P3:0};
    var oldestActive = null;

    data.forEach(function(t) {
      if (byStatus[t.status] !== undefined) byStatus[t.status]++;
      if (byPriority[t.priority] !== undefined) byPriority[t.priority]++;
      if (t.status === "in_progress" && t.created) {
        var age = Date.now() - new Date(t.created).getTime();
        if (!oldestActive || age > oldestActive) oldestActive = age;
      }
    });

    return {
      total: total,
      completionRate: total > 0 ? ((byStatus.completed / total) * 100).toFixed(1) : "0",
      blockedRate: total > 0 ? ((byStatus.blocked / total) * 100).toFixed(1) : "0",
      activeRate: total > 0 ? ((byStatus.in_progress / total) * 100).toFixed(1) : "0",
      velocity: byStatus.completed,
      oldestActive: oldestActive ? Math.floor(oldestActive / 86400000) + "d" : "\u2014",
      byStatus: byStatus,
      byPriority: byPriority
    };
  }

  function renderAnalyticsBadges(a) {
    var container = document.getElementById("grid-analytics");
    if (!container) return;
    container.innerHTML =
      "<div style='display:flex;flex-wrap:wrap;gap:12px;align-items:center'>" +
      badge("#e0e6ed", a.total, "Total") +
      badge("#3dd68c", a.byStatus.completed, "Done " + a.completionRate + "%") +
      badge("#00d4aa", a.byStatus.in_progress, "Active") +
      badge("#ff6b81", a.byStatus.blocked, "Blocked") +
      badge("#7a8fa6", a.byStatus.pending, "Pending") +
      "<span style='border-left:1px solid rgba(122,143,166,0.15);height:18px;margin:0 4px'></span>" +
      priBadge("#ff4757","P0",a.byPriority.P0) + priBadge("#ffa502","P1",a.byPriority.P1) +
      priBadge("#2ed573","P2",a.byPriority.P2) + priBadge("#7a8fa6","P3",a.byPriority.P3) +
      "<span style='border-left:1px solid rgba(122,143,166,0.15);height:18px;margin:0 4px'></span>" +
      "<span style='color:#7a8fa6;font-size:0.82rem'>Oldest active: " + a.oldestActive + "</span></div>";
  }

  function badge(color, count, label) {
    return "<span style='font-size:0.9rem'><b style='color:" + color + "'>" + count + "</b> <span style='color:#7a8fa6'>" + label + "</span></span>";
  }
  function priBadge(color, label, count) {
    return "<span style='color:" + color + ";font-size:0.85rem;font-weight:700'>" + label + "</span><span style='color:#7a8fa6;font-size:0.85rem;margin-right:4px'>:" + count + "</span>";
  }

  function renderMiniChart(a) {
    var container = document.getElementById("grid-minichart");
    if (!container) return;
    var total = a.total || 1;
    var pcts = {
      completed: (a.byStatus.completed / total * 100).toFixed(1),
      active: (a.byStatus.in_progress / total * 100).toFixed(1),
      blocked: (a.byStatus.blocked / total * 100).toFixed(1),
      pending: (a.byStatus.pending / total * 100).toFixed(1)
    };
    container.innerHTML =
      "<div style='display:flex;height:8px;border-radius:4px;overflow:hidden;background:rgba(122,143,166,0.06);margin:8px 0'>" +
      "<div style='width:" + pcts.completed + "%;background:linear-gradient(90deg,#2ed573,#3dd68c);transition:width 0.8s' title='Done: " + pcts.completed + "%'></div>" +
      "<div style='width:" + pcts.active + "%;background:linear-gradient(90deg,#00b894,#00d4aa);transition:width 0.8s' title='Active: " + pcts.active + "%'></div>" +
      "<div style='width:" + pcts.blocked + "%;background:linear-gradient(90deg,#ff4757,#ff6b81);transition:width 0.8s' title='Blocked: " + pcts.blocked + "%'></div>" +
      "<div style='width:" + pcts.pending + "%;background:rgba(122,143,166,0.1);transition:width 0.8s' title='Pending: " + pcts.pending + "%'></div>" +
      "</div>";
  }

  // ═══════════════════════════════════════════════════════════════
  // State Change Event Log — Captures and displays all mutations
  // ═══════════════════════════════════════════════════════════════

  function logChange(type, details) {
    var entry = {
      time: new Date().toLocaleTimeString(),
      ts: Date.now(),
      type: type,
      details: details
    };
    changeLog.unshift(entry);
    if (changeLog.length > MAX_CHANGE_LOG) changeLog.pop();
    renderChangeLog();
  }

  function renderChangeLog() {
    var container = document.getElementById("change-log");
    if (!container) return;

    var typeColors = {
      "status_change": "#ffa502",
      "new_task": "#3dd68c",
      "task_removed": "#ff6b81",
      "refresh": "#7a8fa6",
      "priority_change": "#9b59b6",
      "data_diff": "#00d4aa"
    };

    var html = changeLog.slice(0, 15).map(function(e) {
      var color = typeColors[e.type] || "#7a8fa6";
      return "<div style='display:flex;align-items:center;gap:8px;padding:4px 0;border-bottom:1px solid rgba(30,42,58,0.2);font-size:0.85rem;animation:fadeSlideIn 0.3s ease-out'>" +
        "<span style='color:#7a8fa6;min-width:60px;font-family:monospace'>" + e.time + "</span>" +
        "<span style='background:" + color + "22;color:" + color + ";padding:1px 6px;border-radius:6px;font-weight:600;min-width:55px;text-align:center;font-size:0.82rem'>" + e.type.replace(/_/g, " ") + "</span>" +
        "<span style='color:var(--text,#e0e6ed);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap'>" + e.details + "</span></div>";
    }).join("");

    if (changeLog.length === 0) {
      html = "<div style='color:#7a8fa6;font-size:0.9rem;padding:8px;text-align:center'>Monitoring for state changes...</div>";
    }

    container.innerHTML = html;
  }

  function detectAndLogChanges(oldSnap, newSnap, gridName) {
    var changes = 0;
    // Detect status changes
    Object.keys(newSnap).forEach(function(id) {
      if (oldSnap[id] && oldSnap[id] !== newSnap[id]) {
        var oldParts = oldSnap[id].split("|");
        var newParts = newSnap[id].split("|");
        if (oldParts[0] !== newParts[0]) {
          logChange("status_change", id.substring(0,8) + ": " + oldParts[0] + " \u2192 " + newParts[0]);
          changes++;
        }
        if (oldParts[1] !== newParts[1]) {
          logChange("priority_change", id.substring(0,8) + ": " + oldParts[1] + " \u2192 " + newParts[1]);
          changes++;
        }
      }
    });
    // Detect new tasks
    Object.keys(newSnap).forEach(function(id) {
      if (!oldSnap[id]) {
        logChange("new_task", "New task: " + id.substring(0,8));
        changes++;
      }
    });
    // Detect removed tasks
    Object.keys(oldSnap).forEach(function(id) {
      if (!newSnap[id]) {
        logChange("task_removed", "Removed: " + id.substring(0,8));
        changes++;
      }
    });
    return changes;
  }

  // ═══════════════════════════════════════════════════════════════
  // Detail Panel — Enhanced Multi-Level Drill-Down
  // ═══════════════════════════════════════════════════════════════

  function showTaskDetail(taskData) {
    var panel = document.getElementById("task-detail-panel");
    if (!panel) return;

    var pColor = {"P0":"#ff4757","P1":"#ffa502","P2":"#2ed573","P3":"#7a8fa6"}[taskData.priority] || "#7a8fa6";
    var sColor = {"completed":"#3dd68c","blocked":"#ff6b81","in_progress":"#00d4aa","pending":"#7a8fa6"}[taskData.status] || "#7a8fa6";
    var age = taskAge(taskData.created);
    var layer = classifyFractalLayer(taskData);
    var layerInfo = FRACTAL_LAYERS[layer] || FRACTAL_LAYERS.L3;

    panel.innerHTML =
      "<div class='detail-panel'>" +
      // Header
      "<div style='display:flex;justify-content:space-between;align-items:center;margin-bottom:16px'>" +
      "<div style='display:flex;align-items:center;gap:10px;flex-wrap:wrap'>" +
      "<span style='background:linear-gradient(135deg," + pColor + "," + pColor + "cc);color:#fff;padding:4px 12px;border-radius:10px;font-weight:700;font-size:0.8rem'>" + taskData.priority + "</span>" +
      "<span style='color:" + sColor + ";font-weight:600;font-size:0.85rem;background:" + sColor + "15;padding:3px 10px;border-radius:8px'>" + (taskData.status||"unknown").replace(/_/g," ") + "</span>" +
      "<span style='color:" + layerInfo.color + ";font-size:0.88rem;background:" + layerInfo.color + "15;padding:2px 8px;border-radius:8px'>" + layer + " " + layerInfo.label + "</span>" +
      "<span style='color:#7a8fa6;font-size:0.88rem'>" + age + " old</span>" +
      "</div>" +
      "<button id='close-detail' style='background:rgba(122,143,166,0.1);border:1px solid rgba(122,143,166,0.2);color:#7a8fa6;padding:6px 12px;border-radius:8px;cursor:pointer;font-size:0.9rem;transition:all 0.2s' onmouseover='this.style.background=\"rgba(255,107,129,0.1)\";this.style.color=\"#ff6b81\"' onmouseout='this.style.background=\"rgba(122,143,166,0.1)\";this.style.color=\"#7a8fa6\"'>\u2715 Close</button>" +
      "</div>" +
      // Title
      "<div style='font-size:0.95rem;line-height:1.6;margin-bottom:16px;color:var(--text,#e0e6ed)'>" + ((taskData.title||"Untitled").replace(/(SC-[A-Z]+-\d+)/g, "<span style='color:#00d4aa;font-weight:600'>$1</span>")) + "</div>" +
      // Metadata grid
      "<div style='display:grid;grid-template-columns:100px 1fr 100px 1fr;gap:6px 12px;font-size:0.8rem;color:#7a8fa6;margin-bottom:16px;background:rgba(20,25,34,0.5);padding:12px;border-radius:8px'>" +
      "<span>ID</span><span style='font-family:monospace;color:var(--text,#e0e6ed);font-size:0.85rem'>" + taskData.id + "</span>" +
      "<span>Owner</span><span style='color:var(--text,#e0e6ed)'>" + (taskData.owner || "Unassigned") + "</span>" +
      "<span>Created</span><span style='color:var(--text,#e0e6ed)'>" + (taskData.created ? taskData.created.substring(0, 19) : "\u2014") + "</span>" +
      "<span>Parent</span><span style='font-family:monospace;color:var(--text,#e0e6ed);font-size:0.85rem'>" + (taskData.parent_id || "None (root)") + "</span>" +
      "</div>" +
      // Action buttons
      "<div style='display:flex;gap:8px;flex-wrap:wrap'>" +
      "<button class='detail-action-btn' data-action='knowledge'>\uD83D\uDD0D Knowledge Lookup</button>" +
      "<button class='detail-action-btn' data-action='related'>\uD83D\uDD17 Related Tasks</button>" +
      "<button class='detail-action-btn' data-action='stamp' style='color:#f5a623;background:rgba(245,166,35,0.08);border-color:rgba(245,166,35,0.2)'>\uD83D\uDEE1 STAMP Refs</button>" +
      "<button class='detail-action-btn' data-action='subtasks' style='color:#9b59b6;background:rgba(155,89,182,0.08);border-color:rgba(155,89,182,0.2)'>\uD83C\uDF33 Sub-Tasks</button>" +
      "<button class='detail-action-btn' data-action='ai' style='color:#ffd93d;background:rgba(255,217,61,0.08);border-color:rgba(255,217,61,0.2)'>\u2728 AI Analysis</button>" +
      "</div>" +
      // Quick status action buttons
      "<div style='margin-top:12px;display:flex;gap:8px;flex-wrap:wrap'>" +
      "<button class='detail-action-btn' data-action='complete' style='color:#3dd68c;background:rgba(61,214,140,0.08);border:1px solid rgba(61,214,140,0.2);padding:8px 16px;border-radius:6px;cursor:pointer;min-height:44px;font-weight:600'>\u2713 Mark Complete</button>" +
      "<button class='detail-action-btn' data-action='block' style='color:#ff4757;background:rgba(255,71,87,0.08);border:1px solid rgba(255,71,87,0.2);padding:8px 16px;border-radius:6px;cursor:pointer;min-height:44px;font-weight:600'>\u2717 Mark Blocked</button>" +
      "<button class='detail-action-btn' data-action='activate' style='color:#00d4aa;background:rgba(0,212,170,0.08);border:1px solid rgba(0,212,170,0.2);padding:8px 16px;border-radius:6px;cursor:pointer;min-height:44px;font-weight:600'>\u25b6 Activate</button>" +
      "</div>" +
      "<div id='detail-results'></div>" +
      "</div>";

    // Bind handlers
    setTimeout(function() {
      var closeBtn = document.getElementById("close-detail");
      if (closeBtn) closeBtn.onclick = function() { panel.innerHTML = ""; };

      panel.querySelectorAll(".detail-action-btn").forEach(function(btn) {
        btn.onclick = function() {
          var action = btn.getAttribute("data-action");
          var div = document.getElementById("detail-results");
          if (!div) return;

          if (action === "knowledge") searchKnowledgeInPanel(taskData.title.substring(0, 60), div);
          else if (action === "related") searchRelatedInPanel(taskData, div);
          else if (action === "stamp") showStampRefs(taskData.title, div);
          else if (action === "subtasks") showSubTasks(taskData, div);
          else if (action === "ai") runAIAnalysis(taskData, div);
          else if (action === "complete") quickStatusUpdate(taskData, "completed", btn, div);
          else if (action === "block") quickStatusUpdate(taskData, "blocked", btn, div);
          else if (action === "activate") quickStatusUpdate(taskData, "in_progress", btn, div);
        };
      });
    }, 50);

    panel.scrollIntoView({behavior:"smooth", block:"nearest"});
  }
  window.showTaskDetail = showTaskDetail;

  function searchKnowledgeInPanel(query, div) {
    div.innerHTML = "<div class='detail-section'><span style='color:#f5a623;font-size:0.8rem'>Searching Zettelkasten: \"" + query + "\"...</span></div>";
    // SC-AGUI-UI-003 / SC-TRUTH-001 - try real ZK first; fall back to plan-title search.
    var renderResult = function(source, text) {
      div.innerHTML = "<div class='detail-section'><div style='color:#00d4aa;font-weight:600;font-size:0.82rem;margin-bottom:8px'>\uD83D\uDCDA " + source + "</div><pre style='color:var(--text,#e0e6ed);font-size:0.88rem;white-space:pre-wrap;max-height:250px;overflow-y:auto;margin:0;line-height:1.5'>" + text.substring(0,2000) + "</pre></div>";
    };
    fetch("/api/v1/zk/search?q=" + encodeURIComponent(query))
      .then(function(r) { if (r.status === 404) { throw new Error('zk-not-wired'); } return r.text(); })
      .then(function(text) {
        // SC-TRUTH-001 — only render as ZK when payload has real hits.
        // The Gleam knowledge_search NIF queries `knowledge` (empty in this
        // Smriti.db); real ZK lives in `holons` via sa-plan knowledge-search.
        // Empty envelope falls through to plan-title fallback.
        if (/"total":\s*0/.test(text) || /"results":\s*\[\s*\]/.test(text)) {
          throw new Error('zk-empty');
        }
        renderResult('Zettelkasten Knowledge (ZK)', text);
      })
      .catch(function() {
        fetch("/api/v1/plan/search?q=" + encodeURIComponent(query))
          .then(function(r) { return r.text(); })
          .then(function(text) { renderResult('Title search (ZK unavailable, fallback)', text); })
          .catch(function() { div.innerHTML = "<div class='detail-section'><span style='color:#ff6b81'>Knowledge search unavailable</span></div>"; });
      });
  }

  function searchRelatedInPanel(task, div) {
    if (!allTaskData.length) return;
    var words = (task.title||"").toLowerCase().split(/\s+/).filter(function(w) { return w.length > 3; });
    var related = allTaskData.filter(function(t) {
      if (t.id === task.id) return false;
      var title = (t.title||"").toLowerCase();
      var matches = words.filter(function(w) { return title.indexOf(w) >= 0; });
      return matches.length >= 2;
    }).slice(0, 10);

    var html = "<div class='detail-section'><div style='color:#00d4aa;font-weight:600;font-size:0.82rem;margin-bottom:10px'>\uD83D\uDD17 " + related.length + " Related Tasks</div>";
    if (related.length === 0) html += "<span style='color:#7a8fa6;font-size:0.9rem'>No strongly related tasks found</span>";
    else {
      related.forEach(function(r) {
        var pc = {"P0":"#ff4757","P1":"#ffa502","P2":"#2ed573","P3":"#7a8fa6"}[r.priority] || "#7a8fa6";
        var sc = {"completed":"#3dd68c","blocked":"#ff6b81","in_progress":"#00d4aa","pending":"#7a8fa6"}[r.status] || "#7a8fa6";
        html += "<div style='padding:6px 0;border-bottom:1px solid rgba(30,42,58,0.3);font-size:0.9rem;display:flex;align-items:center;gap:8px;cursor:pointer' onclick='showTaskDetail(" + JSON.stringify(r).replace(/'/g,"\\'") + ")'>";
        html += "<span style='color:" + pc + ";font-weight:700;min-width:24px'>" + r.priority + "</span>";
        html += "<span style='color:" + sc + ";min-width:55px;font-size:0.82rem'>" + (r.status||"").replace(/_/g," ") + "</span>";
        html += "<span style='flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--text,#e0e6ed)'>" + (r.title||"") + "</span></div>";
      });
    }
    html += "</div>";
    div.innerHTML = html;
  }

  function showStampRefs(title, div) {
    var refs = (title||"").match(/SC-[A-Z]+-\d+/g) || [];
    if (refs.length === 0) {
      div.innerHTML = "<div class='detail-section'><span style='color:#7a8fa6;font-size:0.9rem'>No STAMP references found in task title</span></div>";
      return;
    }
    var html = "<div class='detail-section'><div style='color:#f5a623;font-weight:600;font-size:0.82rem;margin-bottom:10px'>\uD83D\uDEE1 " + refs.length + " STAMP References</div><div style='display:flex;flex-wrap:wrap;gap:6px'>";
    refs.forEach(function(ref) {
      html += "<span style='background:rgba(245,166,35,0.1);color:#f5a623;padding:4px 12px;border-radius:8px;font-size:0.88rem;font-weight:600;border:1px solid rgba(245,166,35,0.15)'>" + ref + "</span>";
    });
    html += "</div></div>";
    div.innerHTML = html;
  }

  function showSubTasks(task, div) {
    if (!allTaskData.length) return;
    var subs = allTaskData.filter(function(t) { return t.parent_id === task.id; });
    var html = "<div class='detail-section'><div style='color:#9b59b6;font-weight:600;font-size:0.82rem;margin-bottom:10px'>\uD83C\uDF33 " + subs.length + " Sub-Tasks</div>";
    if (subs.length === 0) html += "<span style='color:#7a8fa6;font-size:0.9rem'>No sub-tasks found (this may be a leaf task)</span>";
    else {
      subs.forEach(function(s) {
        var sc = {"completed":"#3dd68c","blocked":"#ff6b81","in_progress":"#00d4aa","pending":"#7a8fa6"}[s.status]||"#7a8fa6";
        html += "<div style='padding:6px 0;border-bottom:1px solid rgba(30,42,58,0.3);font-size:0.9rem;display:flex;align-items:center;gap:8px;cursor:pointer' onclick='showTaskDetail(" + JSON.stringify(s).replace(/'/g,"\\'") + ")'>";
        html += "<span style='color:" + sc + ";font-weight:600;min-width:18px'>" + (s.status === "completed" ? "\u2713" : s.status === "blocked" ? "\u2717" : "\u25cb") + "</span>";
        html += "<span style='flex:1;color:var(--text,#e0e6ed)'>" + (s.title||"").substring(0,80) + "</span></div>";
      });
    }
    html += "</div>";
    div.innerHTML = html;
  }

  function runAIAnalysis(task, div) {
    div.innerHTML = "<div class='detail-section'><div style='display:flex;align-items:center;gap:8px'><span style='color:#ffd93d;font-size:0.82rem'>Analyzing with AI agent...</span><span style='animation:shimmer 1.5s infinite;background:linear-gradient(90deg,#ffd93d33,#ffd93d88,#ffd93d33);background-size:200%;border-radius:4px;display:inline-block;width:60px;height:12px'></span></div></div>";

    // Call the AI search endpoint for context
    fetch("/api/v1/plan/search?q=" + encodeURIComponent(task.title.substring(0, 50)))
      .then(function(r) { return r.text(); })
      .then(function(text) {
        var layer = classifyFractalLayer(task);
        var layerInfo = FRACTAL_LAYERS[layer] || FRACTAL_LAYERS.L3;
        var refs = (task.title||"").match(/SC-[A-Z]+-\d+/g) || [];
        var age = taskAge(task.created);

        var html = "<div class='detail-section'>";
        html += "<div style='color:#ffd93d;font-weight:600;font-size:0.82rem;margin-bottom:12px'>\u2728 AI Analysis — " + task.priority + " " + layer + " Task</div>";

        // Risk assessment
        var risk = task.priority === "P0" ? "Critical" : task.priority === "P1" ? "High" : "Normal";
        var riskColor = task.priority === "P0" ? "#ff4757" : task.priority === "P1" ? "#ffa502" : "#3dd68c";
        html += "<div style='margin-bottom:12px'><span style='color:#7a8fa6;font-size:0.88rem'>Risk Level:</span> <span style='color:" + riskColor + ";font-weight:600;font-size:0.82rem'>" + risk + "</span></div>";

        // Layer context
        html += "<div style='margin-bottom:12px'><span style='color:#7a8fa6;font-size:0.88rem'>Fractal Layer:</span> <span style='color:" + layerInfo.color + ";font-weight:600'>" + layer + " " + layerInfo.label + "</span></div>";

        // STAMP cross-refs
        if (refs.length > 0) {
          html += "<div style='margin-bottom:12px'><span style='color:#7a8fa6;font-size:0.88rem'>Constraint Refs:</span> " + refs.map(function(r) { return "<span style='color:#f5a623;font-size:0.88rem;margin-left:4px'>" + r + "</span>"; }).join("") + "</div>";
        }

        // Age assessment
        html += "<div style='margin-bottom:12px'><span style='color:#7a8fa6;font-size:0.88rem'>Age:</span> <span style='color:" + (age.indexOf("mo") >= 0 ? "#ff6b81" : "#e0e6ed") + "'>" + age + "</span>";
        if (age.indexOf("mo") >= 0) html += " <span style='color:#ff6b81;font-size:0.85rem'>(stale \u2014 consider review)</span>";
        html += "</div>";

        // Knowledge context
        if (text && text.length > 10) {
          html += "<div style='margin-top:12px;padding-top:10px;border-top:1px solid rgba(30,42,58,0.4)'>";
          html += "<div style='color:#7a8fa6;font-size:0.85rem;margin-bottom:6px'>Related Knowledge (Zettelkasten):</div>";
          html += "<pre style='color:var(--text,#e0e6ed);font-size:0.85rem;white-space:pre-wrap;max-height:150px;overflow-y:auto;margin:0;opacity:0.85'>" + text.substring(0,800) + "</pre></div>";
        }

        html += "</div>";
        div.innerHTML = html;
      })
      .catch(function() {
        div.innerHTML = "<div class='detail-section'><span style='color:#ff6b81'>AI analysis unavailable \u2014 inference endpoint not reachable</span></div>";
      });
  }

  function quickStatusUpdate(task, newStatus, btn, div) {
    var statusLabels = { completed: "completed", blocked: "blocked", in_progress: "active" };
    var statusColors = { completed: "#3dd68c", blocked: "#ff4757", in_progress: "#00d4aa" };
    var origText = btn.textContent;
    btn.disabled = true;
    btn.textContent = "Updating...";
    fetch(API_BASE + "/api/v1/plan/update", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: task.id, status: newStatus })
    }).then(function(r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    }).then(function() {
      btn.textContent = "\u2713 Done";
      btn.style.color = "#3dd68c";
      div.innerHTML = "<div class='detail-section' style='color:" + (statusColors[newStatus] || "#00d4aa") + ";font-weight:600'>" +
        "Task marked as <b>" + (statusLabels[newStatus] || newStatus) + "</b>. Grid will refresh shortly.</div>";
      logChange("status_change", (task.id||"").substring(0,8) + ": \u2192 " + newStatus);
      setTimeout(function() { loadAndRefreshAll(); }, 400);
    }).catch(function(err) {
      btn.disabled = false;
      btn.textContent = origText;
      div.innerHTML = "<div class='detail-section' style='color:#ff4757'>Update failed: " + err.message +
        ". Use CLI: <code style='color:#f5a623'>sa-plan update " + (task.id||"") + " " + newStatus + "</code></div>";
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // AI Search (Enhanced)
  // ═══════════════════════════════════════════════════════════════

  function initAISearch() {
    var searchBox = document.getElementById("ai-search-input");
    var resultsDiv = document.getElementById("ai-search-results");
    if (!searchBox || !resultsDiv) return;

    var debounceTimer = null;
    searchBox.addEventListener("input", function() {
      var query = searchBox.value.trim();
      if (query.length < 2) {
        resultsDiv.innerHTML = "";
        if (grids.all) grids.all.clearFilter();
        return;
      }
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(function() {
        if (grids.all) grids.all.setFilter("title", "like", query);
        resultsDiv.innerHTML = "<span style='color:#f5a623;font-size:0.9rem'>\uD83D\uDD0D Searching...</span>";
        fetch("/api/v1/plan/search?q=" + encodeURIComponent(query))
          .then(function(r) { return r.text(); })
          .then(function(text) {
            try {
              var data = JSON.parse(text);
              var filtered = grids.all ? grids.all.getDataCount("active") : "?";
              resultsDiv.innerHTML = "<span style='color:#00d4aa;font-size:0.9rem'>" + filtered + " tasks match \u00b7 " + (Array.isArray(data) ? data.length : 0) + " knowledge results</span>";
            } catch(e) {
              resultsDiv.innerHTML = "<span style='color:#00d4aa;font-size:0.9rem'>\uD83D\uDCD6 " + text.substring(0, 200) + "</span>";
            }
          })
          .catch(function() {
            var filtered = grids.all ? grids.all.getDataCount("active") : "?";
            resultsDiv.innerHTML = "<span style='color:#7a8fa6;font-size:0.9rem'>" + filtered + " tasks match filter</span>";
          });
      }, 200);
    });

    searchBox.addEventListener("keydown", function(e) {
      if (e.key === "Escape") { searchBox.value = ""; resultsDiv.innerHTML = ""; if (grids.all) grids.all.clearFilter(); searchBox.blur(); }
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Refresh Functions
  // ═══════════════════════════════════════════════════════════════

  function loadAndRefreshAll() {
    updateStatusBar("Refreshing...", "loading");
    Promise.all([
      fetchWithRetry(API_BASE + "/api/v1/plan/list/blocked", 1),
      fetchWithRetry(API_BASE + "/api/v1/plan/list/in_progress", 1),
      fetchWithRetry(API_BASE + "/api/v1/plan/list/all", RETRY_COUNT)
    ]).then(function(results) {
      var blockedData = results[0] || [];
      var activeData = results[1] || [];
      var allData = results[2] || [];

      // Enrich with fractal layer
      allData.forEach(function(t) { t._layer = classifyFractalLayer(t); });
      blockedData.forEach(function(t) { t._layer = classifyFractalLayer(t); });
      activeData.forEach(function(t) { t._layer = classifyFractalLayer(t); });

      allTaskData = allData;
      refreshCount++;
      lastRefreshTime = Date.now();

      // Sub-window mode: ?task=<id> auto-opens that task's detail panel.
      (function() {
        var m = location.search.match(/[?&]task=([^&]+)/);
        if (!m || window.__c3iTaskAutoOpened) return;
        var wantId = decodeURIComponent(m[1]);
        var hit = allData.filter(function(t) { return t.id === wantId; })[0];
        if (hit) {
          window.__c3iTaskAutoOpened = true;
          try { document.title = "Task " + hit.id.substring(0,8) + " — " + (hit.title||"").substring(0,60); } catch (e) {}
          showTaskDetail(hit);
        }
      })();

      var newBlockedSnap = snapshotData(blockedData);
      var newActiveSnap = snapshotData(activeData);
      var newAllSnap = snapshotData(allData);

      var changedBlocked = findChangedIds(prevSnapshots.blocked, newBlockedSnap);
      var changedActive = findChangedIds(prevSnapshots.active, newActiveSnap);
      var changedAll = findChangedIds(prevSnapshots.all, newAllSnap);

      // Detect and log state changes
      var loggedChanges = 0;
      loggedChanges += detectAndLogChanges(prevSnapshots.blocked, newBlockedSnap, "blocked");
      loggedChanges += detectAndLogChanges(prevSnapshots.active, newActiveSnap, "active");
      loggedChanges += detectAndLogChanges(prevSnapshots.all, newAllSnap, "all");

      if (grids.blocked) { grids.blocked.replaceData(blockedData); highlightChangedRows(grids.blocked, changedBlocked); }
      if (grids.active) { grids.active.replaceData(activeData); highlightChangedRows(grids.active, changedActive); }
      if (grids.all) { grids.all.replaceData(allData); highlightChangedRows(grids.all, changedAll); }

      prevSnapshots.blocked = newBlockedSnap;
      prevSnapshots.active = newActiveSnap;
      prevSnapshots.all = newAllSnap;

      var totalChanges = changedBlocked.length + changedActive.length + changedAll.length;
      if (totalChanges > 0) logChange("data_diff", totalChanges + " rows changed across grids");
      var stats = blockedData.length + " blocked | " + activeData.length + " active | " + allData.length + " total";
      var changeNote = totalChanges > 0 ? " \u00b7 " + totalChanges + " changed" : "";
      updateStatusBar(stats + changeNote + "  \u00b7  " + new Date().toLocaleTimeString() + "  \u00b7  <span id='refresh-countdown'>0s ago</span>", "ok");

      // SC-AGUI-UI-014 / audit-P3 — keep document.title in sync with live
      // counts so OS tab strip surfaces system state without focusing page.
      if (!window.__c3iTaskAutoOpened) {
        try {
          document.title = "C3I \u2014 Planning \u00b7 " + blockedData.length
            + " blocked \u00b7 " + activeData.length + " active \u00b7 "
            + allData.length + " total";
        } catch (e) {}
      }

      var analytics = computeAnalytics(allData);
      renderAnalyticsBadges(analytics);
      renderMiniChart(analytics);

      // Re-render dynamic views if active
      if (currentView === "kanban") renderKanban(allData);
      else if (currentView === "analytics") renderAnalyticsView(allData);
    }).catch(function(err) {
      updateStatusBar("Refresh failed: " + err.message, "error");
    });
  }

  function refreshActiveTasks() {
    fetchWithRetry(API_BASE + "/api/v1/plan/list/in_progress", 1).then(function(data) {
      if (!grids.active) return;
      data.forEach(function(t) { t._layer = classifyFractalLayer(t); });
      var newSnap = snapshotData(data);
      var changed = findChangedIds(prevSnapshots.active, newSnap);
      prevSnapshots.active = newSnap;
      grids.active.replaceData(data);
      if (changed.length > 0) {
        highlightChangedRows(grids.active, changed);
        lastRefreshTime = Date.now();
      }
    }).catch(function() {});
  }

  function startRefreshTimers() {
    if (refreshTimer) clearInterval(refreshTimer);
    if (activeTimer) clearInterval(activeTimer);
    if (allTimer) clearInterval(allTimer);
    refreshTimer = setInterval(loadAndRefreshAll, REFRESH_INTERVAL_MS);
    activeTimer = setInterval(refreshActiveTasks, ACTIVE_REFRESH_MS);
    allTimer = setInterval(function() {
      // Refresh all data every 5s for near-real-time experience
      if (currentView !== "grid") loadAndRefreshAll();
    }, ALL_REFRESH_MS);
  }

  // ═══════════════════════════════════════════════════════════════
  // View Toggle Initialization
  // ═══════════════════════════════════════════════════════════════

  function initViewToggle() {
    document.querySelectorAll(".view-btn").forEach(function(btn) {
      btn.onclick = function() { switchView(btn.getAttribute("data-view")); };
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Keyboard Shortcuts
  // ═══════════════════════════════════════════════════════════════

  document.addEventListener("keydown", function(e) {
    if (e.key === "Escape") {
      var panel = document.getElementById("task-detail-panel");
      if (panel && panel.innerHTML !== "") { panel.innerHTML = ""; e.preventDefault(); }
    }
    if ((e.ctrlKey || e.metaKey) && e.key === "k") {
      var search = document.getElementById("ai-search-input");
      if (search) { search.focus(); e.preventDefault(); }
    }
    if (document.activeElement.tagName !== "INPUT") {
      if (e.key === "r" && !e.ctrlKey && !e.metaKey) loadAndRefreshAll();
      if (e.key === "1") switchView("grid");
      if (e.key === "2") switchView("kanban");
      if (e.key === "3") switchView("timeline");
      if (e.key === "4") switchView("analytics");
    }
  });

  // ═══════════════════════════════════════════════════════════════
  // Grid Initialization
  // ═══════════════════════════════════════════════════════════════

  function initGrids() {
    if (typeof Tabulator === "undefined") { setTimeout(initGrids, 200); return; }
    updateStatusBar("Connecting to Smriti...", "loading");

    Promise.all([
      fetchWithRetry(API_BASE + "/api/v1/plan/list/blocked", RETRY_COUNT),
      fetchWithRetry(API_BASE + "/api/v1/plan/list/in_progress", RETRY_COUNT),
      fetchWithRetry(API_BASE + "/api/v1/plan/list/all", RETRY_COUNT)
    ]).then(function(results) {
      var blockedData = results[0] || [];
      var activeData = results[1] || [];
      var allData = results[2] || [];

      // Enrich with fractal layer
      allData.forEach(function(t) { t._layer = classifyFractalLayer(t); });
      blockedData.forEach(function(t) { t._layer = classifyFractalLayer(t); });
      activeData.forEach(function(t) { t._layer = classifyFractalLayer(t); });

      allTaskData = allData;
      refreshCount++;
      lastRefreshTime = Date.now();

      // Sub-window mode: ?task=<id> auto-opens that task's detail panel.
      (function() {
        var m = location.search.match(/[?&]task=([^&]+)/);
        if (!m || window.__c3iTaskAutoOpened) return;
        var wantId = decodeURIComponent(m[1]);
        var hit = allData.filter(function(t) { return t.id === wantId; })[0];
        if (hit) {
          window.__c3iTaskAutoOpened = true;
          try { document.title = "Task " + hit.id.substring(0,8) + " — " + (hit.title||"").substring(0,60); } catch (e) {}
          showTaskDetail(hit);
        }
      })();

      prevSnapshots.blocked = snapshotData(blockedData);
      prevSnapshots.active = snapshotData(activeData);
      prevSnapshots.all = snapshotData(allData);

      var stats = blockedData.length + " blocked | " + activeData.length + " active | " + allData.length + " total";
      updateStatusBar(stats + "  \u00b7  " + new Date().toLocaleTimeString() + "  \u00b7  <span id='refresh-countdown' style='font-size:0.85rem'>0s ago</span>", "ok");
      startCountdown();

      // Blocked grid
      var blockedEl = document.getElementById("blocked-grid");
      if (blockedEl) {
        if (blockedData.length > 0) {
          grids.blocked = createGrid("#blocked-grid", blockedData, { height: Math.min(blockedData.length * 36 + 55, 280) });
        } else {
          blockedEl.innerHTML = "<div style='text-align:center;padding:16px;color:#3dd68c;border:1px dashed rgba(61,214,140,0.2);border-radius:10px;font-size:0.85rem'>\u2713 No blocked tasks \u2014 all clear</div>";
        }
      }

      // Active grid
      var activeEl = document.getElementById("active-grid");
      if (activeEl) {
        if (activeData.length > 0) {
          grids.active = createGrid("#active-grid", activeData, { height: Math.min(activeData.length * 36 + 55, 320) });
        } else {
          activeEl.innerHTML = "<div style='text-align:center;padding:16px;color:#7a8fa6;border:1px dashed rgba(122,143,166,0.15);border-radius:10px;font-size:0.85rem'>No active tasks</div>";
        }
      }

      // All tasks grid
      var allEl = document.getElementById("all-grid");
      if (allEl) {
        grids.all = createGrid("#all-grid", allData, {
          height: 460,
          pagination: "local",
          paginationSize: 25,
          paginationSizeSelector: [10, 25, 50, 100, true],
          paginationCounter: "rows",
          initialSort: [{column:"priority", dir:"asc"}],
          footerElement:
            "<div style='padding:6px 10px;display:flex;align-items:center;gap:8px;flex-wrap:wrap'>" +
            // SC-AGUI-UI-005 / audit-P2 - bulk actions wired to selectable rows.
            "<button id='bulk-activate' class='bulk-btn' style='background:rgba(0,212,170,0.08);color:#00d4aa;border:1px solid rgba(0,212,170,0.3);padding:5px 14px;border-radius:8px;cursor:pointer;font-size:0.88rem;font-weight:600;min-height:32px' title='Mark selected rows as in_progress'>\u25b6 Activate selected</button>" +
            "<button id='bulk-block' class='bulk-btn' style='background:rgba(255,71,87,0.08);color:#ff6b81;border:1px solid rgba(255,71,87,0.3);padding:5px 14px;border-radius:8px;cursor:pointer;font-size:0.88rem;font-weight:600;min-height:32px' title='Mark selected rows as blocked'>\u2717 Block selected</button>" +
            "<button id='bulk-complete' class='bulk-btn' style='background:rgba(61,214,140,0.08);color:#3dd68c;border:1px solid rgba(61,214,140,0.3);padding:5px 14px;border-radius:8px;cursor:pointer;font-size:0.88rem;font-weight:600;min-height:32px' title='Mark selected rows as completed'>\u2713 Complete selected</button>" +
            "<span style='color:#7a8fa6;font-size:0.78rem' id='bulk-selection-count'>0 selected</span>" +
            "<span style='flex:1'></span>" +
            "<button id='export-csv' style='background:linear-gradient(135deg,#00d4aa,#00b894);color:#0a0e17;border:none;padding:5px 14px;border-radius:8px;cursor:pointer;font-size:0.88rem;font-weight:600;transition:all 0.2s'>CSV</button>" +
            "<button id='export-json' style='background:transparent;color:#00d4aa;border:1px solid rgba(0,212,170,0.3);padding:5px 14px;border-radius:8px;cursor:pointer;font-size:0.88rem;transition:all 0.2s'>JSON</button>" +
            "<button id='refresh-btn' style='background:transparent;color:#f5a623;border:1px solid rgba(245,166,35,0.3);padding:5px 14px;border-radius:8px;cursor:pointer;font-size:0.88rem;transition:all 0.2s'>\u21bb Refresh</button>" +
            "<span style='color:#7a8fa6;font-size:0.78rem;border-left:1px solid var(--border,#1e2a3a);padding-left:8px'>Keys: 1-4 views \u00b7 Ctrl+K search \u00b7 R refresh</span>" +
            "</div>",
          dataLoaded: function() {
            setTimeout(function() {
              var csvBtn = document.getElementById("export-csv");
              var jsonBtn = document.getElementById("export-json");
              var refreshBtn = document.getElementById("refresh-btn");
              if (csvBtn) csvBtn.onclick = function() { grids.all.download("csv", "c3i-tasks.csv"); };
              if (jsonBtn) jsonBtn.onclick = function() { grids.all.download("json", "c3i-tasks.json"); };
              if (refreshBtn) refreshBtn.onclick = function() { loadAndRefreshAll(); };
              // SC-AGUI-UI-005 / audit-P2 - bulk action handlers POST to /api/v1/planning/update
              var bulkRun = function(targetStatus, label) {
                if (!grids.all) return;
                var rows = grids.all.getSelectedData();
                if (!rows.length) { alert("No rows selected. Click row cells in the leftmost column to select."); return; }
                if (!confirm(label + " " + rows.length + " task(s)? Reversible via the same buttons.")) return;
                var done = 0, failed = 0;
                rows.forEach(function(r) {
                  fetch("/api/v1/planning/update", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id: r.id, status: targetStatus }) })
                    .then(function(res) { if (res.ok) done++; else failed++; })
                    .catch(function() { failed++; })
                    .then(function() {
                      if (done + failed === rows.length) {
                        logChange("bulk_" + targetStatus, done + " ok, " + failed + " failed");
                        grids.all.deselectRow();
                        loadAndRefreshAll();
                      }
                    });
                });
              };
              var btnA = document.getElementById("bulk-activate");
              var btnB = document.getElementById("bulk-block");
              var btnC = document.getElementById("bulk-complete");
              if (btnA) btnA.onclick = function() { bulkRun("in_progress", "Activate"); };
              if (btnB) btnB.onclick = function() { bulkRun("blocked", "Block"); };
              if (btnC) btnC.onclick = function() { bulkRun("completed", "Complete"); };
            }, 100);
          },
          rowSelectionChanged: function(data) {
            var el = document.getElementById("bulk-selection-count");
            if (el) el.textContent = (data.length || 0) + " selected";
          }
        });
        window._c3iAllGrid = grids.all;
      }

      var analytics = computeAnalytics(allData);
      renderAnalyticsBadges(analytics);
      renderMiniChart(analytics);

    }).catch(function(err) {
      console.error("Grid init failed:", err);
      updateStatusBar("Connection failed: " + err.message + " \u2014 retrying in 5s...", "error");
      setTimeout(initGrids, 5000);
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // WebSocket — Real-time bidirectional task push (SC-GLM-UI-010)
  // ═══════════════════════════════════════════════════════════════

  var ws = null;
  var wsConnected = false;
  var wsReconnectTimer = null;
  var wsReconnectDelay = 1000;

  function initWebSocket() {
    try {
      var protocol = location.protocol === "https:" ? "wss:" : "ws:";
      var wsUrl = protocol + "//" + location.host + "/ws/planning";
      ws = new WebSocket(wsUrl);

      ws.onopen = function() {
        wsConnected = true;
        wsReconnectDelay = 1000; // Reset backoff
        logChange("refresh", "WebSocket connected \u2014 real-time bidirectional");
        updateStatusBar("WebSocket live \u00b7 1s push", "ok");
        // Start 1s ping loop — server responds with fresh data on each ping
        if (window._wsPingTimer) clearInterval(window._wsPingTimer);
        window._wsPingTimer = setInterval(function() {
          if (ws && ws.readyState === WebSocket.OPEN) ws.send("ping");
        }, 1000);
      };

      ws.onmessage = function(event) {
        try {
          var msg = JSON.parse(event.data);
          lastRefreshTime = Date.now();

          if (msg.type === "connected") {
            // Initial status on connect
            try {
              var status = JSON.parse(msg.status);
              updateHeaderFromWS(status.total, status.completed, status.pending, status.active, status.blocked);
            } catch(e) {}

          } else if (msg.type === "update") {
            // Data changed — update grids and header
            try {
              var status = JSON.parse(msg.status);
              updateHeaderFromWS(status.total, status.completed, status.pending, status.active, status.blocked);
            } catch(e) {}

            // Update active tasks grid
            try {
              var activeData = JSON.parse(msg.active);
              if (grids.active && Array.isArray(activeData)) {
                activeData.forEach(function(t) { t._layer = classifyFractalLayer(t); });
                var newSnap = snapshotData(activeData);
                var changed = findChangedIds(prevSnapshots.active, newSnap);
                if (changed.length > 0) {
                  detectAndLogChanges(prevSnapshots.active, newSnap, "active");
                  grids.active.replaceData(activeData);
                  highlightChangedRows(grids.active, changed);
                }
                prevSnapshots.active = newSnap;
              }
            } catch(e) {}

            // Update blocked tasks grid
            try {
              var blockedData = JSON.parse(msg.blocked);
              if (grids.blocked && Array.isArray(blockedData)) {
                blockedData.forEach(function(t) { t._layer = classifyFractalLayer(t); });
                var newSnap = snapshotData(blockedData);
                var changed = findChangedIds(prevSnapshots.blocked, newSnap);
                if (changed.length > 0) {
                  detectAndLogChanges(prevSnapshots.blocked, newSnap, "blocked");
                  grids.blocked.replaceData(blockedData);
                  highlightChangedRows(grids.blocked, changed);
                }
                prevSnapshots.blocked = newSnap;
              }
            } catch(e) {}

            logChange("data_diff", "WS push #" + msg.seq + " \u2014 data changed");

          } else if (msg.type === "heartbeat") {
            // No data change, just keep-alive
            var el = document.getElementById("refresh-countdown");
            if (el) { el.textContent = "0s ago"; el.style.color = "#3dd68c"; }

          } else if (msg.type === "search") {
            // Search results from server (bidirectional)
            logChange("refresh", "WS search: " + msg.query);
          }
        } catch(ex) {}
      };

      ws.onclose = function() {
        wsConnected = false;
        updateStatusBar("WebSocket closed \u2014 reconnecting in " + (wsReconnectDelay / 1000) + "s...", "error");
        // Exponential backoff reconnect (1s, 2s, 4s, max 30s)
        wsReconnectTimer = setTimeout(function() {
          wsReconnectDelay = Math.min(wsReconnectDelay * 2, 30000);
          initWebSocket();
        }, wsReconnectDelay);
      };

      ws.onerror = function() {
        wsConnected = false;
      };
    } catch(ex) {
      // WebSocket not available
    }
  }

  // Send a message to the server via WebSocket (bidirectional)
  function wsSend(text) {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(text);
      return true;
    }
    return false;
  }

  function updateHeaderFromWS(total, completed, pending, active, blocked) {
    var pct = total > 0 ? ((completed / total) * 100).toFixed(1) : "0";
    var health = 92; var wsEl = document.getElementById("weather-score"); if (wsEl) { var m = wsEl.textContent.match(/\d+/); if (m) health = parseInt(m[0]); } else { health = blocked > 5 ? 78 : 92; }
    var mood = health >= 80 ? "Clear" : health >= 60 ? "Partly cloudy" : "Stormy";
    var emoji = health >= 80 ? "\u2600\uFE0F" : health >= 60 ? "\u26C5" : "\uD83C\uDF27\uFE0F";

    var weatherEmoji = document.getElementById("weather-emoji");
    var weatherLabel = document.getElementById("weather-label");
    var weatherScore = document.getElementById("weather-score");
    if (weatherEmoji) weatherEmoji.textContent = emoji;
    if (weatherLabel) weatherLabel.textContent = "System Mood: " + mood + " \u2014 P0 100% done, " + pending + " pending, " + completed + "/" + total + " complete";
    if (weatherScore) weatherScore.textContent = health + "/100";

    var cards = document.getElementById("live-status-cards");
    if (cards) {
      var vals = cards.querySelectorAll(".card-value");
      if (vals.length >= 5) {
        updateCardValue(vals[0], total.toLocaleString());
        updateCardValue(vals[1], completed.toLocaleString());
        updateCardValue(vals[2], pending.toLocaleString());
        updateCardValue(vals[3], active.toLocaleString());
        updateCardValue(vals[4], blocked.toLocaleString());
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Gemma 4 AI Chat Widget
  // ═══════════════════════════════════════════════════════════════

  var aiChatHistory = [];

  function initAIChat() {
    var container = document.getElementById("ai-chat-widget");
    if (!container) return;

    container.innerHTML =
      "<div style='display:flex;flex-direction:column;height:100%'>" +
      "<div id='ai-chat-messages' style='flex:1;overflow-y:auto;padding:10px;font-size:0.82rem;line-height:1.5'>" +
      "<div style='color:#7a8fa6;text-align:center;padding:20px;font-size:0.9rem'>Ask Gemma about your tasks (Gemma 3 fast / Gemma 4 deep).<br>Try: \"What are the blocked tasks?\" or \"Summarize active work\" or \"Risk assessment\"</div>" +
      "</div>" +
      "<div style='display:flex;gap:6px;padding:8px;border-top:1px solid rgba(30,42,58,0.4)'>" +
      "<input id='ai-chat-input' type='text' placeholder='Ask Gemma... (e.g. What tasks are blocked?)' style='flex:1;background:rgba(10,14,23,0.6);border:1px solid rgba(30,42,58,0.5);color:var(--text,#e0e6ed);padding:10px 14px;border-radius:8px;font-size:0.85rem;outline:none;min-height:44px'>" +
      "<button id='ai-chat-send' style='background:linear-gradient(135deg,#00d4aa,#00b894);color:#0a0e17;border:none;padding:10px 18px;border-radius:8px;cursor:pointer;font-weight:700;font-size:0.82rem;min-height:44px;white-space:nowrap'>Send</button>" +
      "</div></div>";

    var input = document.getElementById("ai-chat-input");
    var sendBtn = document.getElementById("ai-chat-send");
    if (input && sendBtn) {
      sendBtn.onclick = function() { sendAIMessage(input.value.trim()); input.value = ""; };
      input.addEventListener("keydown", function(e) {
        if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendBtn.click(); }
      });
    }
  }

  function sendAIMessage(query) {
    if (!query) return;
    var messagesDiv = document.getElementById("ai-chat-messages");
    if (!messagesDiv) return;

    // Add user message
    appendChatMessage(messagesDiv, "user", query);
    aiChatHistory.push({role: "user", content: query});

    // Show typing indicator
    var typingId = "typing-" + Date.now();
    messagesDiv.innerHTML += "<div id='" + typingId + "' style='display:flex;align-items:center;gap:8px;padding:8px 0'><span style='color:#00d4aa;font-weight:600;font-size:0.85rem'>" + activeModel.label + "</span><span style='color:#7a8fa6;font-size:0.9rem;animation:shimmer 1.5s infinite;background:linear-gradient(90deg,#7a8fa633,#7a8fa688,#7a8fa633);background-size:200%;border-radius:4px;display:inline-block;width:80px;height:14px'></span></div>";
    messagesDiv.scrollTop = messagesDiv.scrollHeight;

    // Call Gemma via Ollama (Gemma 3 fast, Gemma 4 fallback)
    callGemma(query).then(function(response) {
      var typing = document.getElementById(typingId);
      if (typing) typing.remove();
      appendChatMessage(messagesDiv, "assistant", response);
      aiChatHistory.push({role: "assistant", content: response});
    }).catch(function(err) {
      var typing = document.getElementById(typingId);
      if (typing) typing.remove();
      // Fallback: use local search results
      fetch(API_BASE + "/api/v1/ai/chat?q=" + encodeURIComponent(query))
        .then(function(r) { return r.json(); })
        .then(function(data) {
          var fallbackMsg = "Gemma 4 offline. Here's what I found:\n\n" +
            "Task context: " + (data.context || "unavailable") + "\n" +
            "Search results available in data.search_results_raw";
          appendChatMessage(messagesDiv, "assistant", fallbackMsg);
        })
        .catch(function() {
          appendChatMessage(messagesDiv, "assistant", "AI agent unavailable. Check Ollama: port 11434 (gemma3) or 11435 (gemma4).");
        });
    });
  }

  // Ollama config: Gemma 3 (fast, 3.3GB) on 11434, Gemma 4 (large, 9.6GB) on 11435
  var OLLAMA_MODELS = [
    { name: "gemma3", port: 11434, label: "Gemma 3" },
    { name: "gemma4", port: 11435, label: "Gemma 4" }
  ];
  var activeModel = OLLAMA_MODELS[0]; // Default: Gemma 3 (fast)

  function callGemma(query) {
    var statusData = null;
    return fetch(API_BASE + "/api/v1/plan/status")
      .then(function(r) { return r.json(); })
      .then(function(status) {
        statusData = status;
        var systemMsg = "You are the C3I Planning AI assistant for the Indrajaal distributed mesh system. " +
          "Current system status: " + status.total + " total tasks (" +
          status.active + " active, " + status.blocked + " blocked, " +
          status.completed + " completed, " + status.pending + " pending). " +
          "Completion rate: " + (status.total > 0 ? ((status.completed / status.total) * 100).toFixed(1) : 0) + "%. " +
          "You help operators analyze tasks, suggest priorities, assess risks, and answer questions. " +
          "Be concise and actionable (2-4 sentences). Reference specific numbers.";

        var body = JSON.stringify({
          model: activeModel.name,
          messages: [
            { role: "system", content: systemMsg },
            { role: "user", content: query }
          ],
          stream: false,
          options: { temperature: 0.3, num_predict: 300 }
        });

        // Use AbortController for timeout
        var controller = new AbortController();
        var timeoutId = setTimeout(function() { controller.abort(); }, 15000);

        return fetch("http://localhost:" + activeModel.port + "/api/chat", {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: body,
          signal: controller.signal
        }).then(function(r) {
          clearTimeout(timeoutId);
          if (!r.ok) throw new Error("HTTP " + r.status);
          return r.json();
        });
      })
      .then(function(data) {
        var content = (data.message && data.message.content) || "";
        if (!content && data.response) content = data.response;
        if (!content) throw new Error("Empty response");
        return content;
      })
      .catch(function(err) {
        // Try fallback model
        if (activeModel === OLLAMA_MODELS[0] && OLLAMA_MODELS.length > 1) {
          activeModel = OLLAMA_MODELS[1];
          return callGemma(query).finally(function() { activeModel = OLLAMA_MODELS[0]; });
        }
        throw err;
      });
  }

  function appendChatMessage(container, role, content) {
    var isUser = role === "user";
    var color = isUser ? "#e0e6ed" : "#00d4aa";
    var label = isUser ? "You" : activeModel.label;
    var bg = isUser ? "rgba(224,230,237,0.05)" : "rgba(0,212,170,0.05)";
    var border = isUser ? "rgba(224,230,237,0.1)" : "rgba(0,212,170,0.1)";

    container.innerHTML +=
      "<div style='padding:10px;margin:6px 0;background:" + bg + ";border:1px solid " + border + ";border-radius:8px'>" +
      "<div style='font-size:0.82rem;font-weight:600;color:" + color + ";margin-bottom:4px'>" + label + "</div>" +
      "<div style='color:var(--text,#e0e6ed);font-size:0.82rem;white-space:pre-wrap;line-height:1.5'>" + content.replace(/</g, "&lt;") + "</div>" +
      "</div>";
    container.scrollTop = container.scrollHeight;
  }

  // ═══════════════════════════════════════════════════════════════
  // Live Header Update — Refreshes status cards, weather bar, rings
  // ═══════════════════════════════════════════════════════════════

  function refreshHeaderStatus() {
    fetch(API_BASE + "/api/v1/plan/status").then(function(r) { return r.json(); }).then(function(data) {
      var total = data.total || 0;
      var completed = data.completed || 0;
      var pending = data.pending || 0;
      var active = data.active || 0;
      var blocked = data.blocked || 0;
      var pct = total > 0 ? ((completed / total) * 100).toFixed(1) : "0";
      var health = 92; var wsEl = document.getElementById("weather-score"); if (wsEl) { var m = wsEl.textContent.match(/\d+/); if (m) health = parseInt(m[0]); } else { health = blocked > 5 ? 78 : 92; }
      var mood = health >= 80 ? "Clear" : health >= 60 ? "Partly cloudy" : "Stormy";
      var emoji = health >= 80 ? "\u2600\uFE0F" : health >= 60 ? "\u26C5" : "\uD83C\uDF27\uFE0F";

      // Update weather bar
      var weatherEmoji = document.getElementById("weather-emoji");
      var weatherLabel = document.getElementById("weather-label");
      var weatherScore = document.getElementById("weather-score");
      if (weatherEmoji) weatherEmoji.textContent = emoji;
      if (weatherLabel) weatherLabel.textContent = "System Mood: " + mood + " \u2014 P0 100% done, " + pending + " pending, " + completed + "/" + total + " complete";
      if (weatherScore) weatherScore.textContent = health + "/100";

      // Update status cards
      var cards = document.getElementById("live-status-cards");
      if (cards) {
        var cardEls = cards.querySelectorAll(".card-value");
        if (cardEls.length >= 5) {
          updateCardValue(cardEls[0], total.toLocaleString());
          updateCardValue(cardEls[1], completed.toLocaleString());
          updateCardValue(cardEls[2], pending.toLocaleString());
          updateCardValue(cardEls[3], active.toLocaleString());
          updateCardValue(cardEls[4], blocked.toLocaleString());
        }
        // Update status colors on blocked card
        var statusEls = cards.querySelectorAll(".badge");
        statusEls.forEach(function(el) {
          if (el.textContent.indexOf("Critical") >= 0 || el.textContent.indexOf("Blocked") >= 0) {
            el.className = blocked > 0 ? "badge badge-critical" : "badge badge-healthy";
            el.textContent = blocked > 0 ? "Critical" : "Healthy";
          }
        });
      }

      // Update progress ring values
      var ringValues = document.querySelectorAll(".ring-item .ring-value");
      if (ringValues.length >= 4) {
        updateCardValue(ringValues[0], pct + "%");
        updateCardValue(ringValues[3], total.toLocaleString());
      }

      // Update SVG dasharray for completion ring
      var rings = document.querySelectorAll(".ring-item svg circle:nth-child(2)");
      if (rings.length >= 1) {
        var dash = total > 0 ? Math.round(completed * 314 / total) : 0;
        rings[0].setAttribute("stroke-dasharray", dash + " " + (314 - dash));
      }
    }).catch(function() {});
  }

  function updateCardValue(el, newValue) {
    if (!el) return;
    if (el.textContent !== newValue) {
      el.textContent = newValue;
      el.style.transition = "color 0.3s";
      el.style.color = "#00d4aa";
      setTimeout(function() { el.style.color = ""; }, 1500);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Initialize Everything
  // ═══════════════════════════════════════════════════════════════

  initGrids();
  setTimeout(function() {
    initAISearch();
    initViewToggle();
    initFractalFilters();
    initAIChat();
    // WebSocket for real-time push (SSE fallback removed — WS is bidirectional)
    initWebSocket();
    startRefreshTimers();
    // Polling fallback when WebSocket disconnected
    setInterval(function() {
      if (!wsConnected) refreshHeaderStatus();
    }, 5000);
    refreshHeaderStatus(); // Initial sync
    initStalenessMonitor();
  }, 800);

  // ═══════════════════════════════════════════════════════════════
  // Staleness Monitor (स्थिरता निगरानी)
  // Components self-report if data is stale. Visual banner + console log.
  // SC-EVO-KPI-003: Data freshness is a KPI.
  // ═══════════════════════════════════════════════════════════════

  var STALE_THRESHOLD_MS = 60000;  // 60s = stale
  var DEAD_THRESHOLD_MS = 300000;  // 5min = dead data
  var stalenessState = "fresh";    // fresh | stale | dead

  function initStalenessMonitor() {
    // Create staleness banner (hidden by default)
    var banner = document.createElement("div");
    banner.id = "staleness-banner";
    banner.style.cssText = "display:none;position:fixed;top:0;left:0;right:0;z-index:9999;padding:8px 16px;font-size:0.82rem;font-weight:700;text-align:center;font-family:'JetBrains Mono',monospace;transition:all 0.3s";
    document.body.prepend(banner);

    // Check every 2 seconds
    setInterval(checkStaleness, 2000);
  }

  function checkStaleness() {
    var elapsed = Date.now() - lastRefreshTime;
    var banner = document.getElementById("staleness-banner");
    if (!banner) return;

    var newState;
    if (elapsed < STALE_THRESHOLD_MS) {
      newState = "fresh";
      banner.style.display = "none";
    } else if (elapsed < DEAD_THRESHOLD_MS) {
      newState = "stale";
      var secs = Math.floor(elapsed / 1000);
      banner.style.display = "block";
      banner.style.background = "rgba(245,166,35,0.95)";
      banner.style.color = "#1a1000";
      banner.textContent = "\u26A0 DATA STALE: Last refresh " + secs + "s ago. Grid data may not reflect current state. [Auto-retry in " + Math.max(0, 30 - (secs % 30)) + "s]";
    } else {
      newState = "dead";
      var mins = Math.floor(elapsed / 60000);
      banner.style.display = "block";
      banner.style.background = "rgba(255,71,87,0.95)";
      banner.style.color = "#fff";
      banner.textContent = "\u274C DATA DEAD: No update for " + mins + "min. Check server connection. WebSocket: " + (wsConnected ? "connected" : "DISCONNECTED");
    }

    // Log state transitions
    if (newState !== stalenessState) {
      stalenessState = newState;
      console.warn("[C3I Staleness] State transition: " + newState + " (elapsed: " + Math.floor(elapsed/1000) + "s)");
      logChange("staleness", "Data freshness: " + newState + " (" + Math.floor(elapsed/1000) + "s since last update)");

      // Set data-freshness attribute on all grid containers for automated testing
      var grids = document.querySelectorAll("[id$='-grid']");
      for (var i = 0; i < grids.length; i++) {
        grids[i].setAttribute("data-freshness", newState);
        grids[i].setAttribute("data-last-refresh", lastRefreshTime);
        grids[i].setAttribute("data-elapsed-ms", elapsed);
      }
    }

    // Force refresh if stale and WS connected
    if (newState === "stale" && wsConnected && elapsed % 30000 < 2000) {
      console.info("[C3I Staleness] Auto-triggering refresh via WS ping");
      if (ws && ws.readyState === WebSocket.OPEN) ws.send("ping");
    }

    // Force full HTTP refresh if dead
    if (newState === "dead" && elapsed % 60000 < 2000) {
      console.info("[C3I Staleness] Auto-triggering full HTTP refresh");
      loadAndRefreshAll();
    }
  }

  // Expose staleness state for automated testing
  window.__c3i_staleness = function() {
    return {
      state: stalenessState,
      lastRefreshTime: lastRefreshTime,
      elapsedMs: Date.now() - lastRefreshTime,
      wsConnected: wsConnected,
      refreshCount: refreshCount,
      taskCount: allTaskData.length,
      gridCount: Object.keys(grids).filter(function(k) { return grids[k] !== null; }).length
    };
  };

  // ── Vega-Lite chart bootstrap (SC-AGUI-UI-001, SC-A2UI-001) ──
  // Reads the Vega-Lite v5 spec baked into data-spec by the SSR and renders it
  // via vegaEmbed if the library is present on the page.  Fails silently when
  // the CDN bundle is absent so the rest of the page is never broken.
  (function initVegaChart() {
    var container = document.getElementById("vega-chart");
    if (!container) return;
    var specStr = container.getAttribute("data-spec");
    if (!specStr) return;
    // vegaEmbed is loaded externally via CDN (e.g. vega-embed@6). When absent,
    // we leave the container empty — the JS staleness banner and grids still work.
    if (typeof vegaEmbed !== "function") {
      container.style.display = "none";
      return;
    }
    try {
      var spec = JSON.parse(specStr);
      vegaEmbed(container, spec, {
        renderer: "svg",
        actions: false,
        theme: "dark",
        config: {
          background: "transparent",
          axis: { labelColor: "#e0e6ed", titleColor: "#e0e6ed", gridColor: "#1e2a3a" },
          title: { color: "#e0e6ed" },
          legend: { labelColor: "#e0e6ed", titleColor: "#e0e6ed" }
        }
      }).catch(function(err) {
        console.warn("[C3I Vega] render error:", err);
        container.style.display = "none";
      });
    } catch (e) {
      console.warn("[C3I Vega] spec parse error:", e);
      container.style.display = "none";
    }
  })();

})();
