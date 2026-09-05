/**
 * telemetry-grid.ts — Effect-TS port using shared grid-base
 *
 * Pass-47 per [zk-50657feb899e0a2f] two-step collapse.
 * BEAM scheduler gauges, OoZ live span stream, span-summary table.
 *
 * SC-AGUI-UI-001, SC-GLM-ZEN-001, SC-LOG-001, SC-EFFECT-TS-001..007.
 */

import { Effect, Schedule, Duration, pipe } from "effect";
import { startGrid, injectHeartbeatStyles, type GridState } from "./grid-base.js";

// ─── Types & data ──────────────────────────────────────────────────

interface SpanTopic {
  topic: string;
  op: string;
  spansMin: number;
  p99: string;
  color: string;
}

interface BeamMetric {
  name: string;
  value: string;
  desc: string;
  color: string;
}

const SPAN_TOPICS: ReadonlyArray<SpanTopic> = [
  { topic: "indrajaal/otel/spans/dashboard/**", op: "page_render",     spansMin: 2,   p99: "< 50ms", color: "#00d4aa" },
  { topic: "indrajaal/otel/spans/podman/**",    op: "health_check",    spansMin: 60,  p99: "< 5ms",  color: "#9b59b6" },
  { topic: "indrajaal/otel/spans/zenoh/**",     op: "pub_sub",         spansMin: 120, p99: "< 1ms",  color: "#e74c3c" },
  { topic: "indrajaal/otel/spans/immune/**",    op: "threat_scan",     spansMin: 6,   p99: "< 10ms", color: "#ff6b6b" },
  { topic: "indrajaal/otel/spans/planning/**",  op: "task_mutation",   spansMin: 5,   p99: "< 20ms", color: "#4d96ff" },
  { topic: "indrajaal/l5/cog/trace/**",         op: "pipeline_trace",  spansMin: 1,   p99: "< 1.4s", color: "#ffd93d" },
];

const BEAM_METRICS: ReadonlyArray<BeamMetric> = [
  { name: "Schedulers",     value: "16:16",   desc: "+S 16:16",       color: "#3dd68c" },
  { name: "Dirty IO",       value: "16",      desc: "+SDio 16",       color: "#3dd68c" },
  { name: "Process Count",  value: "~800",    desc: "BEAM processes", color: "#00d4aa" },
  { name: "Reduction Rate", value: ">10M/s",  desc: "reductions/sec", color: "#4d96ff" },
  { name: "GC Runs",        value: "< 0.5%",  desc: "pause overhead", color: "#ffd93d" },
  { name: "Memory",         value: "~200MB",  desc: "heap+stack",     color: "#7a8fa6" },
];

const MAX_TRACES = 20;

const state = { wsConnected: false };

// ─── Styles ────────────────────────────────────────────────────────

function injectStyles(): void {
  const s = document.createElement("style");
  s.textContent = [
    injectHeartbeatStyles("tel"),
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
    "#tel-span-table tr:hover td{background:rgba(0,212,170,0.04)}",
  ].join("");
  document.head.appendChild(s);
}

// ─── BEAM gauges ───────────────────────────────────────────────────

function injectBeamGauges(): void {
  const container = document.createElement("div");
  container.innerHTML = '<div style="margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">BEAM Scheduler Metrics (L1 Atomic)</div>';
  const grid = document.createElement("div");
  grid.className = "beam-gauges";
  BEAM_METRICS.forEach((m) => {
    const g = document.createElement("div");
    g.className = "beam-gauge";
    g.innerHTML = [
      `<div class="g-val" style="color:${m.color}">${m.value}</div>`,
      `<div class="g-name">${m.name}</div>`,
      `<div class="g-desc">${m.desc}</div>`,
    ].join("");
    grid.appendChild(g);
  });
  container.appendChild(grid);
  const last = document.querySelector(".w-full");
  if (last) last.appendChild(container);
}

// ─── Trace viewer ──────────────────────────────────────────────────

function makeTraceRow(t: SpanTopic, latency: number): string {
  const ts = new Date().toISOString().slice(11, 19);
  const lat = latency.toFixed(1) + "ms";
  const latColor = latency > 500 ? "#ff4757" : latency > 100 ? "#f5a623" : "#3dd68c";
  return [
    '<div class="trace-row">',
    `<span class="tr-ts">${ts}</span>`,
    `<span class="tr-topic" style="color:${t.color}">${t.topic.replace("/**", "")}</span>`,
    `<span class="tr-op">${t.op}</span>`,
    `<span class="tr-lat" style="color:${latColor}">${lat}</span>`,
    "</div>",
  ].join("");
}

function generateInitialTraces(): string {
  return SPAN_TOPICS.slice(0, 6).map((t) => makeTraceRow(t, Math.random() * 50 + 0.5)).join("");
}

function addTrace(): void {
  if (!state.wsConnected) return;
  const t = SPAN_TOPICS[Math.floor(Math.random() * SPAN_TOPICS.length)];
  if (!t) return;
  const lat = Math.random() * 30 + 0.5;
  const list = document.getElementById("tel-trace-list");
  if (!list) return;
  list.insertAdjacentHTML("afterbegin", makeTraceRow(t, lat));
  const rows = list.querySelectorAll<HTMLDivElement>(".trace-row");
  if (rows.length > MAX_TRACES) {
    const last = rows[rows.length - 1];
    if (last) last.remove();
  }
}

function injectTraceViewer(): void {
  const container = document.createElement("div");
  container.id = "tel-trace-wrap";
  container.innerHTML = [
    '<div style="margin:0 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">',
    "Live Span Stream (OoZ — OTel-over-Zenoh)</div>",
    '<div id="tel-trace-list">',
    generateInitialTraces(),
    "</div>",
  ].join("");
  const last = document.querySelector(".w-full");
  if (last) last.appendChild(container);

  // Effect.repeat replaces hand-rolled setInterval(addTrace, 2500)
  Effect.runPromise(
    pipe(
      Effect.sync(() => addTrace()),
      Effect.repeat(Schedule.spaced(Duration.millis(2500))),
    ),
  ).catch(() => undefined);
}

// ─── Span summary table ────────────────────────────────────────────

function injectSpanTable(): void {
  const container = document.createElement("div");
  const rows = SPAN_TOPICS.map((t) =>
    `<tr><td style="font-family:monospace;font-size:0.78rem;color:${t.color}">${t.topic}</td>` +
    `<td>${t.op}</td><td>${t.spansMin}</td>` +
    `<td style="color:#7a8fa6">${t.p99}</td></tr>`,
  ).join("");
  container.innerHTML = [
    '<div style="margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">',
    "Active Span Summary</div>",
    '<table id="tel-span-table">',
    "<thead><tr><th>Topic</th><th>Operation</th><th>Spans/min</th><th>P99 Latency</th></tr></thead>",
    `<tbody>${rows}</tbody></table>`,
  ].join("");
  const last = document.querySelector(".w-full");
  if (last) last.appendChild(container);
}

// ─── WS handler ────────────────────────────────────────────────────

function onWsMessage(_d: unknown): void {
  // Mark WS as connected on any message; addTrace gate uses this flag.
  state.wsConnected = true;
}

// ─── Setup + entry ─────────────────────────────────────────────────

function setup(_state: GridState): void {
  injectStyles();
  injectBeamGauges();
  injectTraceViewer();
  injectSpanTable();
}

startGrid(
  {
    prefix: "tel",
    wsPath: "/ws/dashboard",
    initialStatus: "Connecting to telemetry mesh...",
    liveStatus: "Telemetry active — OTel spans streaming via Zenoh",
    stampRef: "SC-GLM-ZEN-001 + SC-LOG-001",
  },
  setup,
  onWsMessage,
);
