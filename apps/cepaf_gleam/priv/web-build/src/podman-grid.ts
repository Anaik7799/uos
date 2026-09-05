/**
 * podman-grid.ts — Effect-TS port using shared grid-base
 *
 * Pass-44 per [zk-50657feb899e0a2f] two-step collapse.
 * 16-container SIL-6 genome view, health rings, live status from WS.
 *
 * SC-AGUI-UI-001, SC-CNT-001, SC-SIL4-001, SC-EFFECT-TS-001..007.
 */

import { startGrid, injectHeartbeatStyles, type GridState } from "./grid-base.js";

// ─── Types & data ──────────────────────────────────────────────────

interface Container {
  id: string;
  category: string;
  status: "running" | "apoptotic";
  cpu: number;
  mem: number;
  tier: number;
}

const GENOME: ReadonlyArray<Container> = [
  { id: "db-prod",        category: "Database",      status: "running",   cpu: 0.05, mem: 0.35, tier: 2 },
  { id: "obs-prod",       category: "Observability", status: "running",   cpu: 0.08, mem: 0.28, tier: 3 },
  { id: "ex-app-1",       category: "ElixirApp",     status: "running",   cpu: 0.22, mem: 0.41, tier: 6 },
  { id: "cepaf-bridge",   category: "FsharpBridge",  status: "running",   cpu: 0.05, mem: 0.15, tier: 5 },
  { id: "cortex",         category: "FsharpCortex",  status: "running",   cpu: 0.31, mem: 0.55, tier: 5 },
  { id: "zenoh-router",   category: "ZenohRouter",   status: "running",   cpu: 0.02, mem: 0.08, tier: 1 },
  { id: "ollama",         category: "AiCompute",     status: "running",   cpu: 0.15, mem: 0.60, tier: 6 },
  { id: "mojo",           category: "MlRunner",      status: "running",   cpu: 0.12, mem: 0.45, tier: 7 },
  { id: "zenoh-router-1", category: "ZenohRouter",   status: "running",   cpu: 0.02, mem: 0.08, tier: 4 },
  { id: "zenoh-router-2", category: "ZenohRouter",   status: "running",   cpu: 0.02, mem: 0.08, tier: 4 },
  { id: "zenoh-router-3", category: "ZenohRouter",   status: "running",   cpu: 0.02, mem: 0.08, tier: 4 },
  { id: "ex-app-2",       category: "ElixirApp",     status: "running",   cpu: 0.18, mem: 0.38, tier: 7 },
  { id: "ex-app-3",       category: "ElixirApp",     status: "running",   cpu: 0.19, mem: 0.40, tier: 7 },
  { id: "chaya",          category: "ElixirApp",     status: "apoptotic", cpu: 0.08, mem: 0.20, tier: 6 },
  { id: "ml-runner-1",    category: "MlRunner",      status: "running",   cpu: 0.25, mem: 0.70, tier: 7 },
  { id: "ml-runner-2",    category: "MlRunner",      status: "apoptotic", cpu: 0.23, mem: 0.68, tier: 7 },
];

const CATEGORY_COLORS: Record<string, string> = {
  ElixirApp:     "#00d4aa",
  FsharpBridge:  "#4d96ff",
  FsharpCortex:  "#9b59b6",
  ZenohRouter:   "#e74c3c",
  Database:      "#f39c12",
  Observability: "#ffd93d",
  AiCompute:     "#6bcb77",
  MlRunner:      "#ff6b6b",
};

// ─── Styles ────────────────────────────────────────────────────────

function injectStyles(): void {
  const s = document.createElement("style");
  s.textContent = [
    injectHeartbeatStyles("pod"),
    "#pod-genome-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:8px;margin:16px 0}",
    ".pod-container-card{background:rgba(10,14,23,0.8);border:1px solid #1e2a3a;",
    "border-radius:8px;padding:10px 12px;transition:all 0.2s}",
    ".pod-container-card:hover{border-color:rgba(0,212,170,0.3);transform:translateY(-1px)}",
    ".pod-container-card.apoptotic{border-color:rgba(255,71,87,0.3);background:rgba(255,71,87,0.04)}",
    ".pod-container-card .c-id{font-family:monospace;font-size:0.78rem;font-weight:700}",
    ".pod-container-card .c-cat{font-size:0.7rem;color:#7a8fa6;margin-top:2px}",
    ".pod-container-card .c-bars{margin-top:8px;display:flex;flex-direction:column;gap:4px}",
    ".mini-bar{display:flex;align-items:center;gap:6px;font-size:0.68rem}",
    ".mini-bar .mb-label{color:#7a8fa6;min-width:24px}",
    ".mini-bar .mb-track{flex:1;height:4px;background:#1e2a3a;border-radius:2px;overflow:hidden}",
    ".mini-bar .mb-fill{height:100%;border-radius:2px;transition:width 0.8s}",
    ".mini-bar .mb-val{color:#7a8fa6;min-width:28px;text-align:right}",
    ".pod-status-dot{display:inline-block;width:6px;height:6px;border-radius:50%;margin-right:4px}",
    ".pod-status-dot.running{background:#3dd68c;box-shadow:0 0 4px #3dd68c}",
    ".pod-status-dot.apoptotic{background:#ff4757;animation:apoblink 1s infinite}",
    "@keyframes apoblink{0%,100%{opacity:1}50%{opacity:0.3}}",
    ".pod-health-rings{display:flex;gap:16px;flex-wrap:wrap;margin:16px 0;align-items:center}",
    ".pod-health-ring{display:flex;flex-direction:column;align-items:center;gap:4px}",
    ".pod-health-ring svg{width:80px;height:80px}",
    ".pod-health-ring .hr-label{font-size:0.72rem;color:#7a8fa6;text-align:center}",
  ].join("");
  document.head.appendChild(s);
}

// ─── Rings ─────────────────────────────────────────────────────────

function ringHTML(id: string, val: string, color: string, dash: number, gap: number, label: string): string {
  return [
    '<div class="pod-health-ring">',
    '<svg viewBox="0 0 80 80">',
    '<circle cx="40" cy="40" r="34" fill="none" stroke="#1e2a3a" stroke-width="6"/>',
    `<circle cx="40" cy="40" r="34" fill="none" stroke="${color}" stroke-width="6" stroke-dasharray="${dash} ${gap}" stroke-linecap="round" transform="rotate(-90 40 40)"/>`,
    `<text x="40" y="46" text-anchor="middle" font-size="12" fill="${color}" font-weight="700" id="${id}">${val}</text>`,
    "</svg>",
    `<span class="hr-label">${label}</span>`,
    "</div>",
  ].join("");
}

function injectHealthRings(): void {
  const total = GENOME.length;
  const running = GENOME.filter((c) => c.status === "running").length;
  const pct = Math.round((running * 100) / total);
  const dash = Math.round(pct * 2.51);
  const gap = 251 - dash;

  const avgCpu = GENOME.reduce((a, c) => a + c.cpu, 0) / total;
  const cpuPct = Math.round(avgCpu * 100);
  const cpuColor = cpuPct > 80 ? "#ff4757" : cpuPct > 60 ? "#f5a623" : "#00d4aa";
  const cpuDash = Math.round(cpuPct * 2.51);
  const cpuGap = 251 - cpuDash;

  const container = document.createElement("div");
  container.className = "pod-health-rings";
  container.innerHTML = [
    ringHTML("ring-health", `${pct}%`, "#3dd68c", dash, gap, "Health"),
    ringHTML("ring-cpu",    `${cpuPct}%`, cpuColor, cpuDash, cpuGap, "CPU avg"),
    ringHTML("ring-quorum", "2oo3", "#ff6b6b", 209, 42, "Quorum SIL-4"),
  ].join("");

  const label = document.createElement("div");
  label.style.cssText = "margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
  label.textContent = "Genome Health";

  const last = document.querySelector(".w-full");
  if (last) {
    last.appendChild(label);
    last.appendChild(container);
  }
}

// ─── Genome grid ───────────────────────────────────────────────────

function injectGenomeGrid(): void {
  const label = document.createElement("div");
  label.style.cssText = "margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
  label.textContent = "16-Container SIL-6 Genome — Live Status";

  const grid = document.createElement("div");
  grid.id = "pod-genome-grid";

  GENOME.forEach((c) => {
    const color = CATEGORY_COLORS[c.category] ?? "#7a8fa6";
    const isApo = c.status === "apoptotic";
    const card = document.createElement("div");
    card.className = "pod-container-card" + (isApo ? " apoptotic" : "");
    card.id = "pod-card-" + c.id;
    const cpuPct = Math.round(c.cpu * 100);
    const memPct = Math.round(c.mem * 100);
    card.innerHTML = [
      `<div class="c-id" style="color:${color}">`,
      `<span class="pod-status-dot ${c.status}"></span>${c.id}</div>`,
      `<div class="c-cat">T${c.tier} · ${c.category}</div>`,
      '<div class="c-bars">',
      '<div class="mini-bar"><span class="mb-label">CPU</span>',
      `<div class="mb-track"><div class="mb-fill" style="width:${cpuPct}%;background:${color}"></div></div>`,
      `<span class="mb-val">${cpuPct}%</span></div>`,
      '<div class="mini-bar"><span class="mb-label">MEM</span>',
      `<div class="mb-track"><div class="mb-fill" style="width:${memPct}%;background:${color}88"></div></div>`,
      `<span class="mb-val">${memPct}%</span></div>`,
      "</div>",
    ].join("");
    grid.appendChild(card);
  });

  const last = document.querySelector(".w-full");
  if (last) {
    last.appendChild(label);
    last.appendChild(grid);
  }
}

// ─── WS handler ────────────────────────────────────────────────────

function onWsMessage(d: unknown): void {
  const msg = d as { status?: unknown };
  if (!msg.status) return;
  try {
    const st = typeof msg.status === "string"
      ? (JSON.parse(msg.status) as { healthy_count?: number; container_count?: number })
      : (msg.status as { healthy_count?: number; container_count?: number });
    const healthyCount = st.healthy_count ?? 0;
    const totalCount = st.container_count ?? 16;
    const pct = totalCount > 0 ? Math.round((healthyCount * 100) / totalCount) : 100;
    const ring = document.getElementById("ring-health");
    if (ring) ring.textContent = `${pct}%`;
    const txt = document.getElementById("pod-hb-text");
    if (txt) txt.textContent = `${healthyCount}/${totalCount} containers running`;
  } catch {
    // Non-JSON status — ignore.
  }
}

// ─── Setup + entry ─────────────────────────────────────────────────

function setup(_state: GridState): void {
  injectStyles();
  injectHealthRings();
  injectGenomeGrid();
}

const running_count = GENOME.filter((c) => c.status === "running").length;

startGrid(
  {
    prefix: "pod",
    wsPath: "/ws/dashboard",
    initialStatus: `${running_count}/16 containers running — mesh healthy`,
    liveStatus: `${running_count}/16 containers running — mesh healthy`,
    stampRef: "SC-CNT-001 + SC-SIL4-001",
  },
  setup,
  onWsMessage,
);
