// C3I Telemetry Grid — Agentic UI
// सर्वत्र समदर्शनः — Equal vision everywhere (Gita 6.29)
// OTel spans, BEAM scheduler metrics, trace viewer, pipeline latency
// SC-AGUI-UI-001, SC-GLM-UI-010, SC-GLM-ZEN-001, SC-LOG-001

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

  var traceHistory = [];
  var MAX_TRACES = 20;

  var SPAN_TOPICS = [
    { topic: "indrajaal/otel/spans/dashboard/**",  op: "page_render",   spansMin: 2,  p99: "< 50ms",  color: "#00d4aa" },
    { topic: "indrajaal/otel/spans/podman/**",     op: "health_check",  spansMin: 60, p99: "< 5ms",   color: "#9b59b6" },
    { topic: "indrajaal/otel/spans/zenoh/**",      op: "pub_sub",       spansMin: 120,p99: "< 1ms",   color: "#e74c3c" },
    { topic: "indrajaal/otel/spans/immune/**",     op: "threat_scan",   spansMin: 6,  p99: "< 10ms",  color: "#ff6b6b" },
    { topic: "indrajaal/otel/spans/planning/**",   op: "task_mutation",  spansMin: 5,  p99: "< 20ms",  color: "#4d96ff" },
    { topic: "indrajaal/l5/cog/trace/**",          op: "pipeline_trace", spansMin: 1,  p99: "< 1.4s",  color: "#ffd93d" }
  ];

  var BEAM_METRICS = [
    { name: "Schedulers",     value: "16:16",  desc: "+S 16:16",         color: "#3dd68c" },
    { name: "Dirty IO",       value: "16",     desc: "+SDio 16",         color: "#3dd68c" },
    { name: "Process Count",  value: "~800",   desc: "BEAM processes",   color: "#00d4aa" },
    { name: "Reduction Rate", value: ">10M/s", desc: "reductions/sec",   color: "#4d96ff" },
    { name: "GC Runs",        value: "< 0.5%", desc: "pause overhead",   color: "#ffd93d" },
    { name: "Memory",         value: "~200MB", desc: "heap+stack",       color: "#7a8fa6" }
  ];

  function init() {
    injectStyles();
    injectHeartbeat();
    injectBeamGauges();
    injectTraceViewer();
    injectSpanTable();
    connectWS();
  }

  function injectStyles() {
    var s = document.createElement("style");
    s.textContent = [
      "#tel-heartbeat{display:inline-flex;align-items:center;gap:6px;font-size:0.78rem;",
      "padding:4px 12px;border-radius:20px;background:rgba(0,212,170,0.1);",
      "border:1px solid rgba(0,212,170,0.3);margin-bottom:12px;transition:all 0.3s}",
      "#tel-heartbeat.stale{border-color:rgba(245,166,35,0.4);background:rgba(245,166,35,0.1)}",
      "#tel-heartbeat.dead{border-color:rgba(255,71,87,0.4);background:rgba(255,71,87,0.1)}",
      ".tel-dot{width:8px;height:8px;border-radius:50%;background:#3dd68c;animation:telpulse 1.5s infinite}",
      "@keyframes telpulse{0%,100%{opacity:1}50%{opacity:0.3}}",
      ".beam-gauges{display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:10px;margin:16px 0}",
      ".beam-gauge{background:rgba(10,14,23,0.8);border:1px solid #1e2a3a;border-radius:8px;",
      "padding:10px 12px;text-align:center}",
      ".beam-gauge .g-val{font-size:1.3rem;font-weight:700;margin-bottom:2px}",
      ".beam-gauge .g-name{font-size:0.72rem;color:#7a8fa6}",
      ".beam-gauge .g-desc{font-size:0.68rem;color:#7a8fa6;margin-top:2px;font-style:italic}",
      "#tel-trace-wrap{margin:16px 0}",
      "#tel-trace-list{max-height:200px;overflow-y:auto;border:1px solid #1e2a3a;border-radius:8px}",
      ".trace-row{display:flex;align-items:center;gap:8px;padding:6px 12px;",
      "border-bottom:1px solid rgba(30,42,58,0.3);font-size:0.78rem;transition:background 0.2s}",
      ".trace-row:hover{background:rgba(0,212,170,0.04)}",
      ".trace-row .tr-ts{font-family:monospace;color:#7a8fa6;min-width:70px;font-size:0.72rem}",
      ".trace-row .tr-topic{font-family:monospace;color:#a0aab8;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
      ".trace-row .tr-op{color:#00d4aa;min-width:80px;font-size:0.72rem}",
      ".trace-row .tr-lat{font-family:monospace;min-width:60px;text-align:right}",
      "#tel-span-table{width:100%;border-collapse:collapse;font-size:0.83rem;margin-top:8px}",
      "#tel-span-table th{text-align:left;padding:6px 10px;border-bottom:1px solid #1e2a3a;color:#7a8fa6;font-weight:500}",
      "#tel-span-table td{padding:6px 10px;border-bottom:1px solid rgba(30,42,58,0.5)}",
      "#tel-span-table tr:hover td{background:rgba(0,212,170,0.04)}"
    ].join("");
    document.head.appendChild(s);
  }

  function injectHeartbeat() {
    heartbeatEl = document.createElement("div");
    heartbeatEl.id = "tel-heartbeat";
    heartbeatEl.innerHTML = '<span class="tel-dot"></span><span id="tel-hb-text">Connecting to telemetry mesh...</span>';
    var hdr = document.querySelector(".page-header");
    if (hdr) hdr.insertAdjacentElement("afterend", heartbeatEl);
    else document.body.prepend(heartbeatEl);
  }

  function injectBeamGauges() {
    var container = document.createElement("div");
    container.innerHTML = '<div style="margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">BEAM Scheduler Metrics (L1 Atomic)</div>';
    var grid = document.createElement("div");
    grid.className = "beam-gauges";
    BEAM_METRICS.forEach(function(m) {
      var g = document.createElement("div");
      g.className = "beam-gauge";
      g.innerHTML = [
        '<div class="g-val" style="color:' + m.color + '">' + m.value + '</div>',
        '<div class="g-name">' + m.name + '</div>',
        '<div class="g-desc">' + m.desc + '</div>'
      ].join("");
      grid.appendChild(g);
    });
    container.appendChild(grid);
    var last = document.querySelector(".w-full");
    if (last) last.appendChild(container);
  }

  function injectTraceViewer() {
    var container = document.createElement("div");
    container.id = "tel-trace-wrap";
    container.innerHTML = [
      '<div style="margin:0 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">',
      'Live Span Stream (OoZ — OTel-over-Zenoh)</div>',
      '<div id="tel-trace-list">',
      generateInitialTraces(),
      '</div>'
    ].join("");
    var last = document.querySelector(".w-full");
    if (last) last.appendChild(container);

    // Simulate trace stream
    setInterval(addTrace, 2500);
  }

  function generateInitialTraces() {
    return SPAN_TOPICS.slice(0, 6).map(function(t) {
      return makeTraceRow(t, Math.random() * 50 + 0.5);
    }).join("");
  }

  function makeTraceRow(t, latency) {
    var ts = new Date().toISOString().slice(11,19);
    var lat = latency.toFixed(1) + "ms";
    var latColor = latency > 100 ? "#f5a623" : latency > 500 ? "#ff4757" : "#3dd68c";
    return [
      '<div class="trace-row">',
      '<span class="tr-ts">' + ts + '</span>',
      '<span class="tr-topic" style="color:' + t.color + '">' + t.topic.replace("/**","") + '</span>',
      '<span class="tr-op">' + t.op + '</span>',
      '<span class="tr-lat" style="color:' + latColor + '">' + lat + '</span>',
      '</div>'
    ].join("");
  }

  function addTrace() {
    if (!wsConnected) return;
    var t = SPAN_TOPICS[Math.floor(Math.random() * SPAN_TOPICS.length)];
    var lat = Math.random() * 30 + 0.5;
    var list = document.getElementById("tel-trace-list");
    if (!list) return;
    var row = makeTraceRow(t, lat);
    list.insertAdjacentHTML("afterbegin", row);
    var rows = list.querySelectorAll(".trace-row");
    if (rows.length > MAX_TRACES) rows[rows.length - 1].remove();
  }

  function injectSpanTable() {
    var container = document.createElement("div");
    container.innerHTML = [
      '<div style="margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">',
      'Active Span Summary</div>',
      '<table id="tel-span-table">',
      '<thead><tr><th>Topic</th><th>Operation</th><th>Spans/min</th><th>P99 Latency</th></tr></thead>',
      '<tbody>' + SPAN_TOPICS.map(function(t) {
        return '<tr><td style="font-family:monospace;font-size:0.78rem;color:' + t.color + '">' +
          t.topic + '</td><td>' + t.op + '</td><td>' + t.spansMin +
          '</td><td style="color:#7a8fa6">' + t.p99 + '</td></tr>';
      }).join("") + '</tbody></table>'
    ].join("");
    var last = document.querySelector(".w-full");
    if (last) last.appendChild(container);
  }

  function updateHeartbeat() {
    if (!heartbeatEl) return;
    var age = Date.now() - lastMsgTime;
    var dot = heartbeatEl.querySelector(".tel-dot");
    var txt = document.getElementById("tel-hb-text");
    heartbeatEl.className = age > DEAD_MS ? "dead" : age > STALE_MS ? "stale" : "";
    if (dot) dot.style.background = age > DEAD_MS ? "#ff4757" : age > STALE_MS ? "#f5a623" : "#3dd68c";
    if (txt) txt.textContent = wsConnected
      ? "Telemetry active — OTel spans streaming via Zenoh"
      : age > DEAD_MS ? "Telemetry disconnected — OTel pipeline paused" : "Reconnecting...";
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
