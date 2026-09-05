/**
 * agents-grid.ts — Effect-TS port using shared grid-base
 *
 * Pass-45 per [zk-50657feb899e0a2f] two-step collapse.
 * 19-agent biomorphic hierarchy view + animated OODA ring.
 *
 * SC-AGUI-UI-001, SC-AGENT-001, SC-OODA-001, SC-EFFECT-TS-001..007.
 */

import { Effect, Schedule, Duration, pipe } from "effect";
import { startGrid, injectHeartbeatStyles, type GridState } from "./grid-base.js";

// ─── Types & data ──────────────────────────────────────────────────

interface Agent {
  id: string;
  role: string;
  model: string;
  layer: string;
  status: "active" | "idle" | "busy";
  children: ReadonlyArray<string>;
}

const AGENT_HIERARCHY: ReadonlyArray<Agent> = [
  { id: "EXEC-001",    role: "Orchestrator",       model: "claude-opus-4",   layer: "L5", status: "active", children: ["SUP-CTX","SUP-DOM","SUP-TST","SUP-QUA"] },
  { id: "SUP-CTX",     role: "Context Supervisor", model: "claude-sonnet-4", layer: "L5", status: "active", children: ["W-COMPILE-1","W-COMPILE-2","W-EXPLORE-1","W-DOC-1"] },
  { id: "SUP-DOM",     role: "Domain Supervisor",  model: "claude-sonnet-4", layer: "L3", status: "active", children: ["W-FIX-1","W-FIX-2","W-CREDO-1","W-CREDO-2"] },
  { id: "SUP-TST",     role: "Test Supervisor",    model: "claude-sonnet-4", layer: "L4", status: "active", children: ["W-TEST-1","W-TEST-2","W-TEST-3"] },
  { id: "SUP-QUA",     role: "Quality Supervisor", model: "claude-sonnet-4", layer: "L0", status: "active", children: ["W-SAFETY-1","W-STAMP-1","W-FORMAT-1"] },
  { id: "W-COMPILE-1", role: "Compile Worker",     model: "claude-haiku",    layer: "L4", status: "idle",   children: [] },
  { id: "W-COMPILE-2", role: "Compile Worker",     model: "claude-haiku",    layer: "L4", status: "idle",   children: [] },
  { id: "W-EXPLORE-1", role: "Explore Worker",     model: "claude-haiku",    layer: "L3", status: "idle",   children: [] },
  { id: "W-DOC-1",     role: "Doc Worker",         model: "claude-haiku",    layer: "L3", status: "idle",   children: [] },
  { id: "W-FIX-1",     role: "Fix Worker",         model: "claude-haiku",    layer: "L2", status: "idle",   children: [] },
  { id: "W-FIX-2",     role: "Fix Worker",         model: "claude-haiku",    layer: "L2", status: "idle",   children: [] },
  { id: "W-CREDO-1",   role: "Credo Worker",       model: "claude-haiku",    layer: "L2", status: "idle",   children: [] },
  { id: "W-CREDO-2",   role: "Credo Worker",       model: "claude-haiku",    layer: "L2", status: "idle",   children: [] },
  { id: "W-TEST-1",    role: "Test Worker",        model: "claude-haiku",    layer: "L4", status: "idle",   children: [] },
  { id: "W-TEST-2",    role: "Test Worker",        model: "claude-haiku",    layer: "L4", status: "idle",   children: [] },
  { id: "W-TEST-3",    role: "Test Worker",        model: "claude-haiku",    layer: "L4", status: "idle",   children: [] },
  { id: "W-SAFETY-1",  role: "Safety Worker",      model: "claude-haiku",    layer: "L0", status: "idle",   children: [] },
  { id: "W-STAMP-1",   role: "STAMP Worker",       model: "claude-haiku",    layer: "L0", status: "idle",   children: [] },
  { id: "W-FORMAT-1",  role: "Format Worker",      model: "claude-haiku",    layer: "L2", status: "idle",   children: [] },
];

const LAYER_COLORS: Record<string, string> = {
  L0: "#ff6b6b", L1: "#ffd93d", L2: "#6bcb77", L3: "#4d96ff",
  L4: "#9b59b6", L5: "#00d4aa", L6: "#e74c3c", L7: "#f39c12",
};

const OODA_PHASES = ["Observe", "Orient", "Decide", "Act"] as const;
const OODA_COLORS = ["#4d96ff", "#ffd93d", "#f5a623", "#3dd68c"];

// ─── Styles ────────────────────────────────────────────────────────

function injectStyles(): void {
  const s = document.createElement("style");
  s.textContent = [
    injectHeartbeatStyles("agt"),
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
    "#agt-ooda-phase{font-size:1.2rem;font-weight:700;color:#00d4aa;margin-bottom:4px}",
  ].join("");
  document.head.appendChild(s);
}

// ─── Hierarchy ─────────────────────────────────────────────────────

function injectHierarchy(): void {
  const container = document.createElement("div");
  container.innerHTML = '<div style="margin:16px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">Agent Hierarchy — Biomorphic Mesh</div>';
  const grid = document.createElement("div");
  grid.id = "agt-hierarchy";

  AGENT_HIERARCHY.forEach((a) => {
    const lc = LAYER_COLORS[a.layer] ?? "#7a8fa6";
    const card = document.createElement("div");
    card.className = "agt-card";
    card.dataset["agentId"] = a.id;
    card.innerHTML = [
      `<div class="a-id" style="color:${lc}">${a.id}</div>`,
      `<div class="a-role">${a.role}</div>`,
      `<div class="a-model">${a.model}</div>`,
      `<div><span class="agt-status ${a.status}">${a.status.toUpperCase()}</span>`,
      ` <span style="color:${lc};font-size:0.7rem;margin-left:4px">${a.layer}</span></div>`,
    ].join("");
    grid.appendChild(card);
  });

  container.appendChild(grid);
  const last = document.querySelector(".w-full");
  if (last) last.appendChild(container);
}

// ─── OODA ring ─────────────────────────────────────────────────────

function injectOodaRing(): void {
  const section = document.createElement("div");
  section.className = "ooda-ring-section";
  const nodes = OODA_PHASES.map((_p, i) => {
    const angle = i * 90 - 90;
    const rad = (angle * Math.PI) / 180;
    const x = 50 + 40 * Math.cos(rad);
    const y = 50 + 40 * Math.sin(rad);
    return `<circle id="ooda-node-${i}" cx="${x}" cy="${y}" r="8" fill="${OODA_COLORS[i]}" opacity="0.5"/>`;
  }).join("");

  section.innerHTML = [
    '<svg viewBox="0 0 100 100" id="agt-ooda-svg">',
    '<circle cx="50" cy="50" r="40" fill="none" stroke="#1e2a3a" stroke-width="4"/>',
    nodes,
    '<text x="50" y="46" text-anchor="middle" font-size="9" fill="#7a8fa6">OODA</text>',
    '<text id="agt-ooda-txt" x="50" y="60" text-anchor="middle" font-size="9" fill="#00d4aa">&lt; 100ms</text>',
    "</svg>",
    '<div id="agt-ooda-info">',
    '<div id="agt-ooda-phase">Observe</div>',
    "<div>Cycle budget: &lt;100ms (AOR-CAE-001)</div>",
    '<div style="margin-top:4px">Agent step: &lt;30ms | Knowledge: &lt;1ms</div>',
    '<div style="margin-top:4px">Cortex: &lt;50ms | Strategy: &lt;1s</div>',
    "</div>",
  ].join("");

  const last = document.querySelector(".w-full");
  if (last) {
    const label = document.createElement("div");
    label.style.cssText = "margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px";
    label.textContent = "OODA Cycle Monitor";
    last.appendChild(label);
    last.appendChild(section);
  }

  // Effect.repeat ticker for OODA phase animation
  let phase = 0;
  Effect.runPromise(
    pipe(
      Effect.sync(() => {
        for (let i = 0; i < 4; i++) {
          const node = document.getElementById(`ooda-node-${i}`);
          if (node) node.setAttribute("opacity", i === phase ? "1" : "0.2");
        }
        const phaseEl = document.getElementById("agt-ooda-phase");
        if (phaseEl) phaseEl.textContent = OODA_PHASES[phase] ?? "Observe";
        phase = (phase + 1) % 4;
      }),
      Effect.repeat(Schedule.spaced(Duration.millis(800))),
    ),
  ).catch(() => undefined);
}

// ─── WS handler ────────────────────────────────────────────────────

function onWsMessage(d: unknown): void {
  const msg = d as { type?: string };
  if (!msg || (msg.type !== "connected" && msg.type !== "update")) return;
  document.querySelectorAll<HTMLDivElement>(".agt-card").forEach((card) => {
    const id = card.dataset["agentId"] ?? "";
    if (id.startsWith("EXEC") || id.startsWith("SUP")) {
      const statusEl = card.querySelector<HTMLSpanElement>(".agt-status");
      if (statusEl) {
        statusEl.textContent = "ACTIVE";
        statusEl.className = "agt-status active";
      }
    }
  });
}

// ─── Setup + entry ─────────────────────────────────────────────────

function setup(_state: GridState): void {
  injectStyles();
  injectHierarchy();
  injectOodaRing();
}

startGrid(
  {
    prefix: "agt",
    wsPath: "/ws/dashboard",
    initialStatus: "Connecting to agent mesh...",
    liveStatus: "Agent mesh active — 25 agents monitored",
    stampRef: "SC-AGENT-001 + SC-OODA-001",
  },
  setup,
  onWsMessage,
);
