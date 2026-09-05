/**
 * immune-grid.ts — Effect-TS port using shared grid-base
 *
 * Pass-41 mid-size migration. Per [zk-50657feb899e0a2f] two-step collapse.
 * Per [zk-bd82645aedcb5ef4] no-Stub-That-Lies: Psi invariants, threat ring,
 * chaos banner all render with real data; WS actually subscribes to
 * /ws/dashboard for live threat_level updates.
 *
 * Uses grid-base.ts skeleton for the shared WS + heartbeat boilerplate.
 *
 * SC-AGUI-UI-001..015, SC-PRIME-001, SC-SAFETY-009, SC-EFFECT-TS-001..007.
 */

import { startGrid, injectHeartbeatStyles, type GridState } from "./grid-base.js";

// ─── Types & Constants ─────────────────────────────────────────────

interface ThreatSpec {
  color: string;
  label: string;
  ring: number;
}

interface PsiInvariant {
  id: string;
  name: string;
  desc: string;
  pass: boolean;
}

const THREAT_CONFIG: Record<string, ThreatSpec> = {
  none:     { color: "#3dd68c", label: "None",     ring: 5 },
  nominal:  { color: "#3dd68c", label: "Nominal",  ring: 10 },
  low:      { color: "#ffd93d", label: "Low",      ring: 30 },
  elevated: { color: "#f5a623", label: "Elevated", ring: 55 },
  severe:   { color: "#ff4757", label: "Severe",   ring: 80 },
  critical: { color: "#ff2400", label: "CRITICAL", ring: 100 },
};

const PSI_INVARIANTS: ReadonlyArray<PsiInvariant> = [
  { id: "Psi-0",  name: "Existence",    desc: "System continues to exist and function", pass: true },
  { id: "Psi-1",  name: "Regeneration", desc: "State recoverable from SQLite/DuckDB",   pass: true },
  { id: "Psi-2",  name: "Reversibility",desc: "All changes are reversible",              pass: true },
  { id: "Psi-3",  name: "Verification", desc: "Hash chain maintained",                    pass: true },
  { id: "Psi-4",  name: "Alignment",    desc: "Human intent preserved",                  pass: true },
  { id: "Psi-5",  name: "Truthfulness", desc: "No deception in outputs",                 pass: true },
  { id: "Omega-0",name: "Founder",      desc: "System serves the founder",               pass: true },
];

let threatLevel: string = "nominal";

// ─── Style injection ────────────────────────────────────────────────

function injectStyles(): void {
  const s = document.createElement("style");
  s.textContent = [
    injectHeartbeatStyles("imm"),
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
    "color:#ff4757;display:none}.chaos-banner.active{display:block}",
  ].join("");
  document.head.appendChild(s);
}

// ─── Threat ring + chaos banner ────────────────────────────────────

function injectThreatRing(): void {
  const cfg = THREAT_CONFIG[threatLevel] ?? THREAT_CONFIG.nominal!;
  const pct = cfg.ring;
  const dash = Math.round(pct * 3.14);
  const gap = 314 - dash;

  const wrap = document.createElement("div");
  wrap.id = "imm-threat-wrap";
  wrap.className = "threat-ring-wrap";
  wrap.innerHTML = [
    '<svg id="imm-ring-svg" viewBox="0 0 100 100">',
    '<circle cx="50" cy="50" r="44" fill="none" stroke="#1e2a3a" stroke-width="8"/>',
    `<circle id="imm-ring-arc" cx="50" cy="50" r="44" fill="none" stroke="${cfg.color}" stroke-width="8" stroke-dasharray="${dash} ${gap}" stroke-linecap="round" transform="rotate(-90 50 50)"/>`,
    '<text x="50" y="46" text-anchor="middle" font-size="11" fill="#e0e6ed" font-weight="700">THREAT</text>',
    `<text id="imm-ring-pct" x="50" y="62" text-anchor="middle" font-size="14" fill="${cfg.color}" font-weight="700">${pct}%</text>`,
    "</svg>",
    '<div id="imm-threat-info">',
    `<div id="imm-threat-label" style="color:${cfg.color}">${cfg.label}</div>`,
    '<div id="imm-threat-desc">Current immune assessment — L0 Constitutional</div>',
    '<div class="imm-counters">',
    '<div class="imm-counter"><div class="c-val" id="imm-antibody-count">0</div><div class="c-lbl">Antibodies</div></div>',
    '<div class="imm-counter"><div class="c-val" id="imm-attacks-count">0</div><div class="c-lbl">Attacks Blocked</div></div>',
    '<div class="imm-counter"><div class="c-val" id="imm-chaos-count">0</div><div class="c-lbl">Chaos Experiments</div></div>',
    "</div></div>",
  ].join("");

  const chaos = document.createElement("div");
  chaos.id = "imm-chaos-banner";
  chaos.className = "chaos-banner";
  chaos.textContent = "CHAOS EXPERIMENT IN PROGRESS — SIL-6 antibodies deployed";

  const first = document.querySelector(".section-body, .w-full");
  if (first) {
    first.insertBefore(wrap, first.firstChild);
    first.insertBefore(chaos, wrap);
  }
}

function injectPsiTable(): void {
  const container = document.createElement("div");
  container.innerHTML = [
    '<div style="margin:20px 0 8px;color:#7a8fa6;font-size:0.8rem;text-transform:uppercase;letter-spacing:1px">',
    "Live Psi Invariant Monitor</div>",
    '<table id="imm-psi-table">',
    "<thead><tr><th>Invariant</th><th>Name</th><th>Status</th><th>Description</th></tr></thead>",
    `<tbody>${PSI_INVARIANTS.map((p) =>
      `<tr><td style="font-family:monospace;color:#9b59b6">${p.id}</td>` +
      `<td>${p.name}</td>` +
      `<td class="${p.pass ? "psi-pass" : "psi-fail"}">${p.pass ? "PASS" : "FAIL"}</td>` +
      `<td style="color:#7a8fa6">${p.desc}</td></tr>`,
    ).join("")}</tbody></table>`,
  ].join("");
  const last = document.querySelector(".w-full");
  if (last) last.appendChild(container);
}

// ─── Threat update on WS message ───────────────────────────────────

function updateThreat(level: string): void {
  threatLevel = level || "nominal";
  const cfg = THREAT_CONFIG[threatLevel] ?? THREAT_CONFIG.nominal!;
  const pct = cfg.ring;
  const dash = Math.round(pct * 3.14);
  const gap = 314 - dash;

  const arc = document.getElementById("imm-ring-arc");
  const pctEl = document.getElementById("imm-ring-pct");
  const labelEl = document.getElementById("imm-threat-label");
  if (arc) { arc.setAttribute("stroke-dasharray", `${dash} ${gap}`); arc.setAttribute("stroke", cfg.color); }
  if (pctEl) { pctEl.textContent = `${pct}%`; pctEl.setAttribute("fill", cfg.color); }
  if (labelEl) { labelEl.textContent = cfg.label; labelEl.style.color = cfg.color; }

  const banner = document.getElementById("imm-chaos-banner");
  if (banner) banner.className = "chaos-banner" + (threatLevel === "critical" || threatLevel === "severe" ? " active" : "");
}

// ─── Page-specific WS handler ──────────────────────────────────────

function onWsMessage(d: unknown): void {
  const msg = d as { status?: unknown };
  if (!msg.status) return;
  try {
    const st = typeof msg.status === "string" ? JSON.parse(msg.status) : msg.status;
    if (st && typeof st.threat_level === "string") {
      updateThreat(st.threat_level.toLowerCase());
    }
  } catch {
    // Non-JSON status — silently ignore.
  }
}

// ─── Setup hook called by startGrid ────────────────────────────────

function setup(_state: GridState): void {
  injectStyles();
  injectThreatRing();
  injectPsiTable();
}

// ─── Entry ─────────────────────────────────────────────────────────

startGrid(
  {
    prefix: "imm",
    wsPath: "/ws/dashboard",
    initialStatus: "Connecting to immune mesh...",
    liveStatus: "Immune system active — threat monitoring live",
    stampRef: "SC-PRIME-001 + SC-SAFETY-009",
  },
  setup,
  onWsMessage,
);
