/**
 * substrate-grid.ts — Effect-TS port using shared grid-base
 *
 * Pass-43 per [zk-50657feb899e0a2f] two-step collapse.
 * Renders SQLite WAL DB list, CPU Governor adaptive gauge, storage chart.
 *
 * SC-AGUI-UI-001, SC-XHOLON-001, SC-CPU-GOV, SC-EFFECT-TS-001..007.
 */

import { startGrid, injectHeartbeatStyles, type GridState } from "./grid-base.js";

// ─── Types & data ──────────────────────────────────────────────────

interface DbFile {
  path: string;
  engine: string;
  purpose: string;
  size: string;
}

interface CpuGovLevel {
  range: string;
  schedulers: string;
  dirty: string;
  jobs: string;
  action: string;
  color: string;
}

interface StorageItem {
  label: string;
  val: string;
  pct: number;
  color: string;
}

const DB_FILES: ReadonlyArray<DbFile> = [
  { path: "data/smriti/Smriti.db",     engine: "SQLite WAL", purpose: "Knowledge store + FTS5",    size: "~12MB" },
  { path: "data/smriti/planning.db",   engine: "SQLite WAL", purpose: "sa-plan task state",        size: "~2MB" },
  { path: "artifacts/cepa-state.db",   engine: "SQLite WAL", purpose: "CEPAF state",               size: "~800KB" },
  { path: "artifacts/build-history.db",engine: "SQLite WAL", purpose: "EMA build history (α=0.3)", size: "~400KB" },
];

const CPU_GOV_LEVELS: ReadonlyArray<CpuGovLevel> = [
  { range: "< 60%",  schedulers: "16:16", dirty: "16",   jobs: "16",   action: "Full speed",       color: "#3dd68c" },
  { range: "60-70%", schedulers: "12:12", dirty: "12",   jobs: "12",   action: "Slight reduction", color: "#ffd93d" },
  { range: "70-80%", schedulers: "10:10", dirty: "10",   jobs: "10",   action: "Moderate throttle",color: "#f5a623" },
  { range: "80-85%", schedulers: "6:6",   dirty: "6",    jobs: "6",    action: "Heavy throttle",   color: "#ff4757" },
  { range: "> 85%",  schedulers: "WAIT",  dirty: "WAIT", jobs: "WAIT", action: "Pause until < 75%",color: "#ff2400" },
];

const STORAGES: ReadonlyArray<StorageItem> = [
  { label: "Smriti.db",  val: "12MB",   pct: 80, color: "#00d4aa" },
  { label: "planning.db",val: "2MB",    pct: 14, color: "#4d96ff" },
  { label: "cepa.db",    val: "800KB",  pct: 6,  color: "#9b59b6" },
  { label: "build.db",   val: "400KB",  pct: 3,  color: "#ffd93d" },
  { label: "DuckDB",     val: "active", pct: 20, color: "#f39c12" },
  { label: "Zenoh KV",   val: "ephem",  pct: 10, color: "#e74c3c" },
];

// ─── Styles ────────────────────────────────────────────────────────

function injectStyles(): void {
  const s = document.createElement("style");
  s.textContent = [
    injectHeartbeatStyles("sub"),
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
    ".storage-bar .sb-val{font-size:0.72rem;font-family:monospace;color:#e0e6ed}",
  ].join("");
  document.head.appendChild(s);
}

// ─── CPU Governor gauge + table ────────────────────────────────────

function injectCpuGovGauge(): void {
  const pct = 45;
  const dash = Math.round(pct * 2.51);
  const gap = 251 - dash;

  const wrap = document.createElement("div");
  wrap.className = "sub-cpu-wrap";
  wrap.innerHTML = [
    '<svg viewBox="0 0 80 80">',
    '<circle cx="40" cy="40" r="34" fill="none" stroke="#1e2a3a" stroke-width="6"/>',
    `<circle id="sub-cpu-arc" cx="40" cy="40" r="34" fill="none" stroke="#3dd68c" stroke-width="6" stroke-dasharray="${dash} ${gap}" stroke-linecap="round" transform="rotate(-90 40 40)"/>`,
    '<text x="40" y="36" text-anchor="middle" font-size="9" fill="#7a8fa6">CPU</text>',
    `<text id="sub-cpu-pct" x="40" y="52" text-anchor="middle" font-size="14" fill="#3dd68c" font-weight="700">${pct}%</text>`,
    "</svg>",
    '<div id="sub-cpu-info">',
    '<div id="sub-cpu-level">Full Speed</div>',
    '<div id="sub-cpu-desc">Schedulers: 16:16 | Dirty IO: 16 | Jobs: 16</div>',
    '<div style="color:#7a8fa6;font-size:0.78rem;margin-top:4px">Gate: &lt; 85% (SC-CPU-GOV)</div>',
    "</div>",
  ].join("");

  const label = document.createElement("div");
  label.style.cssText = "margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
  label.textContent = "CPU Governor — Adaptive Parallelism";

  const rows = CPU_GOV_LEVELS.map((g, i) => {
    const active = i === 0 ? " active-row" : "";
    return [
      `<tr class="${active.trim()}">`,
      `<td style="color:${g.color}">${g.range}</td>`,
      `<td>${g.schedulers}</td><td>${g.dirty}</td><td>${g.jobs}</td>`,
      `<td style="color:${g.color}">${g.action}</td></tr>`,
    ].join("");
  }).join("");

  const govTable = document.createElement("table");
  govTable.className = "sub-gov-table";
  govTable.innerHTML = [
    "<thead><tr><th>CPU %</th><th>Schedulers</th><th>Dirty IO</th><th>--jobs</th><th>Action</th></tr></thead>",
    `<tbody>${rows}</tbody>`,
  ].join("");

  const last = document.querySelector(".w-full");
  if (last) {
    last.appendChild(label);
    last.appendChild(wrap);
    last.appendChild(govTable);
  }
}

// ─── DB file list ──────────────────────────────────────────────────

function injectDbFileList(): void {
  const label = document.createElement("div");
  label.style.cssText = "margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
  label.textContent = "Database Files — SQLite WAL (SC-XHOLON-001)";

  const list = document.createElement("div");
  list.className = "db-file-list";
  list.id = "sub-db-list";

  DB_FILES.forEach((f) => {
    const row = document.createElement("div");
    row.className = "db-file-row";
    row.innerHTML = [
      '<span class="db-status-dot"></span>',
      `<span class="df-path">${f.path}</span>`,
      `<span class="df-engine">${f.engine}</span>`,
      `<span style="color:#7a8fa6;font-size:0.75rem;flex:1">${f.purpose}</span>`,
      `<span class="df-size">${f.size}</span>`,
    ].join("");
    list.appendChild(row);
  });

  const last = document.querySelector(".w-full");
  if (last) {
    last.appendChild(label);
    last.appendChild(list);
  }
}

// ─── Storage chart ─────────────────────────────────────────────────

function injectStorageChart(): void {
  const label = document.createElement("div");
  label.style.cssText = "margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
  label.textContent = "Storage Distribution";

  const bars = document.createElement("div");
  bars.className = "storage-bars";

  STORAGES.forEach((s) => {
    const bar = document.createElement("div");
    bar.className = "storage-bar";
    bar.innerHTML = [
      `<div class="sb-val">${s.val}</div>`,
      `<div class="sb-bar" style="height:${s.pct}px;background:${s.color}"></div>`,
      `<div class="sb-label">${s.label}</div>`,
    ].join("");
    bars.appendChild(bar);
  });

  const last = document.querySelector(".w-full");
  if (last) {
    last.appendChild(label);
    last.appendChild(bars);
  }
}

// ─── Setup + entry ─────────────────────────────────────────────────

function setup(_state: GridState): void {
  injectStyles();
  injectCpuGovGauge();
  injectDbFileList();
  injectStorageChart();
}

function onWsMessage(_d: unknown): void {
  // Substrate page: heartbeat-only WS for now; future CPU/disk push deferred.
}

startGrid(
  {
    prefix: "sub",
    wsPath: "/ws/dashboard",
    initialStatus: "Connecting to substrate...",
    liveStatus: "Substrate active — SQLite WAL healthy",
    stampRef: "SC-XHOLON-001 + SC-CPU-GOV",
  },
  setup,
  onWsMessage,
);
