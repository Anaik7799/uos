/**
 * dashboard-grid.ts — Effect-TS port of C3I System Dashboard v2.0
 *
 * Pass-49 per [zk-50657feb899e0a2f] two-step collapse — largest port (1336→~1100 LOC).
 * Per [zk-bd82645aedcb5ef4] no-Stub-That-Lies: 4-view toggle, fractal filter chips,
 * supervisor tree, 6-tier inference cascade view, Gemma chat with dual-model fallback,
 * Ctrl+K search with WS + REST + local fallback — all real wiring.
 *
 * SC-AGUI-UI-001..015, SC-GLM-UI-001, SC-ZMOF-001, SC-MUDA-001,
 * SC-EFFECT-TS-001..007.
 */

import { Effect, Schedule, Duration, pipe } from "effect";

// ─── Config ────────────────────────────────────────────────────────

const WS_URL = "/ws/dashboard";
const GEMMA3_PORT = 11434;
const GEMMA4_PORT = 11435;
const MAX_CHANGE_LOG = 50;
const RECONNECT_BASE = 1000;
const RECONNECT_MAX = 30000;

// ─── Types ─────────────────────────────────────────────────────────

type ViewName = "grid" | "supervisors" | "fractal" | "analytics";
type HbState = "live" | "stale" | "dead";

interface FractalLayer {
  label: string;
  color: string;
  bg: string;
  keywords: ReadonlyArray<string>;
}

interface StatusFeed {
  total?: number;
  active?: number;
  in_progress?: number;
  blocked?: number;
  pending?: number;
  completed?: number;
}

interface WsMessage {
  type?: "connected" | "update" | "heartbeat" | "search";
  status?: string;
  results?: SearchItem[];
}

interface SearchItem {
  id?: string;
  title?: string;
  description?: string;
  priority?: string;
  status?: string;
}

interface ChangeEntry {
  time: string;
  type: string;
  detail: string;
  color: string;
}

interface SupervisorNode {
  id: string;
  name: string;
  role: string;
  model: string;
  layer: string;
  color?: string;
  status: string;
  children?: SupervisorNode[];
}

// ─── Static data ───────────────────────────────────────────────────

const FRACTAL_LAYERS: Record<string, FractalLayer> = {
  L0: { label: "Constitutional", color: "#ff6b6b", bg: "rgba(255,107,107,0.08)", keywords: ["guardian","constitutional","psi","safety","emergency","sil4","sil6","prime","invariant","omega"] },
  L1: { label: "Atomic/Debug",   color: "#ffd93d", bg: "rgba(255,217,61,0.08)",  keywords: ["nif","debug","trace","telemetry","otel","atomic","ffi","elf","native"] },
  L2: { label: "Component",      color: "#6bcb77", bg: "rgba(107,203,119,0.08)", keywords: ["parser","component","form","badge","input","catalog","a2ui","widget","lustre"] },
  L3: { label: "Transaction",    color: "#4d96ff", bg: "rgba(77,150,255,0.08)",  keywords: ["planning","task","state","db","sqlite","smriti","transaction","crud","ash"] },
  L4: { label: "System",         color: "#9b59b6", bg: "rgba(155,89,182,0.08)",  keywords: ["podman","container","system","boot","build","image","docker","supervisor","beam"] },
  L5: { label: "Cognitive",      color: "#00d4aa", bg: "rgba(0,212,170,0.08)",   keywords: ["ooda","cortex","mcp","agent","llm","inference","reasoning","cognitive","gemma"] },
  L6: { label: "Ecosystem",      color: "#e74c3c", bg: "rgba(231,76,60,0.08)",   keywords: ["zenoh","mesh","topology","quorum","cluster","ecosystem","router","pubsub"] },
  L7: { label: "Federation",     color: "#f39c12", bg: "rgba(243,156,18,0.08)",  keywords: ["federation","gateway","version","consensus","multi-node","tla","formal"] },
};

const SUPERVISOR_TREE: SupervisorNode = {
  id: "exec-001", name: "EXEC-001", role: "Orchestrator", model: "opus",
  layer: "L5", color: "#00d4aa", status: "active",
  children: [
    { id: "sup-ctx", name: "SUP-CTX", role: "Context Supervisor", model: "sonnet", layer: "L5", color: "#4d96ff", status: "active",
      children: [
        { id: "w-compile-1", name: "W-COMPILE-1", role: "Compile Worker", model: "haiku", layer: "L4", status: "idle" },
        { id: "w-compile-2", name: "W-COMPILE-2", role: "Compile Worker", model: "haiku", layer: "L4", status: "idle" },
        { id: "w-explore-1", name: "W-EXPLORE-1", role: "Explore Worker", model: "haiku", layer: "L3", status: "idle" },
        { id: "w-explore-2", name: "W-EXPLORE-2", role: "Explore Worker", model: "haiku", layer: "L3", status: "idle" },
        { id: "w-doc-1",     name: "W-DOC-1",     role: "Doc Worker",     model: "haiku", layer: "L3", status: "idle" },
      ] },
    { id: "sup-dom", name: "SUP-DOM", role: "Domain Supervisor", model: "sonnet", layer: "L3", color: "#9b59b6", status: "active",
      children: [
        { id: "w-fix-1",   name: "W-FIX-1",   role: "Fix Worker",   model: "haiku", layer: "L2", status: "idle" },
        { id: "w-fix-2",   name: "W-FIX-2",   role: "Fix Worker",   model: "haiku", layer: "L2", status: "idle" },
        { id: "w-fix-3",   name: "W-FIX-3",   role: "Fix Worker",   model: "haiku", layer: "L2", status: "idle" },
        { id: "w-credo-1", name: "W-CREDO-1", role: "Credo Worker", model: "haiku", layer: "L2", status: "idle" },
        { id: "w-credo-2", name: "W-CREDO-2", role: "Credo Worker", model: "haiku", layer: "L2", status: "idle" },
      ] },
    { id: "sup-tst", name: "SUP-TST", role: "Test Supervisor", model: "sonnet", layer: "L4", color: "#ffd93d", status: "active",
      children: [
        { id: "w-test-1", name: "W-TEST-1", role: "Test Worker", model: "haiku", layer: "L4", status: "idle" },
        { id: "w-test-2", name: "W-TEST-2", role: "Test Worker", model: "haiku", layer: "L4", status: "idle" },
        { id: "w-test-3", name: "W-TEST-3", role: "Test Worker", model: "haiku", layer: "L4", status: "idle" },
        { id: "w-test-4", name: "W-TEST-4", role: "Test Worker", model: "haiku", layer: "L4", status: "idle" },
        { id: "w-test-5", name: "W-TEST-5", role: "Test Worker", model: "haiku", layer: "L4", status: "idle" },
      ] },
    { id: "sup-qua", name: "SUP-QUA", role: "Quality Supervisor", model: "sonnet", layer: "L0", color: "#ff6b6b", status: "active",
      children: [
        { id: "w-safety-1", name: "W-SAFETY-1", role: "Safety Worker", model: "haiku", layer: "L0", status: "idle" },
        { id: "w-safety-2", name: "W-SAFETY-2", role: "Safety Worker", model: "haiku", layer: "L0", status: "idle" },
        { id: "w-stamp-1",  name: "W-STAMP-1",  role: "STAMP Worker",  model: "haiku", layer: "L0", status: "idle" },
        { id: "w-stamp-2",  name: "W-STAMP-2",  role: "STAMP Worker",  model: "haiku", layer: "L0", status: "idle" },
        { id: "w-format-1", name: "W-FORMAT-1", role: "Format Worker", model: "haiku", layer: "L2", status: "idle" },
      ] },
  ],
};

const RUST_THREADS = [
  { name: "cortex",          role: "Intent processing, classify, RAG, dispatch",    layer: "L5" },
  { name: "gateway",         role: "Parallel broadcast Telegram/GChat",             layer: "L7" },
  { name: "mcp_inference",   role: "Hedged 6-tier inference, circuit breakers",     layer: "L5" },
  { name: "trace",           role: "PipelineTracer zero-write hot path",            layer: "L1" },
  { name: "gemini_live",     role: "WebSocket voice, OGG->PCM, 3-tier fallback",    layer: "L5" },
  { name: "zenoh_telemetry", role: "Boot state vector, checkpoints",                layer: "L6" },
  { name: "ha_election",     role: "Leader election Primary/Backup/Standby",        layer: "L6" },
  { name: "ingress_polling", role: "Dark cockpit secure outbound polling",          layer: "L7" },
  { name: "heartbeat",       role: "10-min cron for proactive OODA",                layer: "L5" },
  { name: "ruliology",       role: "Wolfram-style cellular automata, causal graph", layer: "L5" },
] as const;

// ─── State ─────────────────────────────────────────────────────────

const state: {
  ws: WebSocket | null;
  wsConnected: boolean;
  reconnectDelay: number;
  lastMessageTime: number;
  lastStatusJson: string;
  currentView: ViewName;
  activeFractalFilter: string | null;
  changeLog: ChangeEntry[];
  pingTimer: ReturnType<typeof setInterval> | null;
  searchDebounce: ReturnType<typeof setTimeout> | null;
  systemData: { status: StatusFeed };
} = {
  ws: null,
  wsConnected: false,
  reconnectDelay: RECONNECT_BASE,
  lastMessageTime: Date.now(),
  lastStatusJson: "",
  currentView: "grid",
  activeFractalFilter: null,
  changeLog: [],
  pingTimer: null,
  searchDebounce: null,
  systemData: { status: {} },
};

// ─── Utilities ─────────────────────────────────────────────────────

function esc(s: string | number | undefined | null): string {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function moodEmoji(score: number): { emoji: string; label: string; color: string } {
  if (score >= 0.9) return { emoji: "⬛", label: "Dark Cockpit", color: "#7a8fa6" };
  if (score >= 0.7) return { emoji: "🔵", label: "Nominal",      color: "#4d96ff" };
  if (score >= 0.5) return { emoji: "🟡", label: "Dim",          color: "#ffd93d" };
  if (score >= 0.3) return { emoji: "🟠", label: "Bright",       color: "#f5a623" };
  return                  { emoji: "🔴", label: "Emergency",    color: "#ff4757" };
}

function layerColor(layer: string): string {
  return (FRACTAL_LAYERS[layer] ?? FRACTAL_LAYERS.L3!).color;
}

function progressRingSvg(pct: number, r: number, color: string): string {
  const circ = 2 * Math.PI * r;
  const dash = (pct / 100 * circ).toFixed(1);
  const size = r * 2 + 8;
  const cx = size / 2;
  const cy = size / 2;
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">` +
    `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="rgba(30,42,58,0.6)" stroke-width="4"/>` +
    `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${color}" stroke-width="4" stroke-linecap="round" ` +
    `stroke-dasharray="${dash} ${circ.toFixed(1)}" transform="rotate(-90 ${cx} ${cy})" style="transition:stroke-dasharray 0.6s ease"/>` +
    `<text x="${cx}" y="${cy + 4}" text-anchor="middle" fill="${color}" font-size="${r * 0.48}" font-weight="800">${pct}%</text>` +
    `</svg>`;
}

// ─── Change log ────────────────────────────────────────────────────

function logChange(type: string, detail: string, color?: string): void {
  const COLORS: Record<string, string> = {
    status_change: "#00d4aa", new: "#3dd68c", removed: "#ff4757",
    ws_event: "#4d96ff", ooda: "#9b59b6", error: "#ff4757",
  };
  const entry: ChangeEntry = {
    time: new Date().toLocaleTimeString(),
    type, detail,
    color: color ?? COLORS[type] ?? "#7a8fa6",
  };
  state.changeLog.unshift(entry);
  if (state.changeLog.length > MAX_CHANGE_LOG) state.changeLog.pop();
  renderChangeLog();
}

function renderChangeLog(): void {
  const el = document.getElementById("dash-change-log");
  if (!el) return;
  if (state.changeLog.length === 0) {
    el.innerHTML = "<div style='color:#7a8fa6;text-align:center;padding:16px;font-size:0.78rem'>No changes yet</div>";
    return;
  }
  let html = "<div class='db-change-log'>";
  state.changeLog.slice(0, 20).forEach((e) => {
    html += "<div class='db-change-entry'>";
    html += `<span class='db-change-time'>${esc(e.time)}</span>`;
    html += `<span class='db-change-badge' style='background:${e.color}22;color:${e.color}'>${esc(e.type)}</span>`;
    html += `<span class='db-change-detail'>${esc(e.detail)}</span>`;
    html += "</div>";
  });
  html += "</div>";
  el.innerHTML = html;
}

// ─── WebSocket ─────────────────────────────────────────────────────

function updateHeartbeat(s: HbState): void {
  const el = document.getElementById("dash-ws-status");
  if (!el) return;
  const dot = `<span class='hb-dot hb-${s}'></span>`;
  const labels: Record<HbState, string> = {
    live:  "<span style='color:#3dd68c'>Live</span>",
    stale: "<span style='color:#f5a623'>Stale</span>",
    dead:  "<span style='color:#ff4757'>Disconnected</span>",
  };
  el.innerHTML = dot + labels[s];
}

function handleStatusUpdate(msg: WsMessage): void {
  const statusStr = msg.status ?? "{}";
  if (statusStr !== state.lastStatusJson) {
    state.lastStatusJson = statusStr;
    try {
      const s = JSON.parse(statusStr) as StatusFeed;
      state.systemData.status = s;
      logChange("status_change", `Status updated: ${s.total ?? 0} tasks, ${s.active ?? 0} active`);
      renderWeatherBar(s);
      renderTaskSummary(s);
      if (state.currentView === "grid") renderGridView(s);
      else if (state.currentView === "analytics") renderAnalyticsView(s);
    } catch {
      // Non-JSON — ignore.
    }
  }
  updateHeartbeat("live");
}

function initWebSocket(): void {
  if (state.ws && (state.ws.readyState === 0 || state.ws.readyState === 1)) return;
  try {
    const protocol = location.protocol === "https:" ? "wss:" : "ws:";
    state.ws = new WebSocket(`${protocol}//${location.host}${WS_URL}`);
  } catch {
    updateHeartbeat("dead");
    setTimeout(() => {
      state.reconnectDelay = Math.min(state.reconnectDelay * 2, RECONNECT_MAX);
      initWebSocket();
    }, state.reconnectDelay);
    return;
  }
  const ws = state.ws;
  if (!ws) return;

  ws.onopen = () => {
    state.wsConnected = true;
    state.reconnectDelay = RECONNECT_BASE;
    updateHeartbeat("live");
    logChange("ws_event", `WebSocket connected to ${WS_URL}`);
    if (state.pingTimer) clearInterval(state.pingTimer);
    state.pingTimer = setInterval(() => {
      if (state.ws && state.ws.readyState === 1) state.ws.send("ping");
    }, 1000);
  };

  ws.onmessage = (ev) => {
    state.lastMessageTime = Date.now();
    try {
      const msg = JSON.parse(ev.data) as WsMessage;
      if (msg.type === "connected" || msg.type === "update") handleStatusUpdate(msg);
      else if (msg.type === "heartbeat") updateHeartbeat("live");
      else if (msg.type === "search") renderSearchResults(msg.results ?? []);
    } catch {
      // Non-JSON — ignore.
    }
  };

  ws.onclose = () => {
    state.wsConnected = false;
    if (state.pingTimer) { clearInterval(state.pingTimer); state.pingTimer = null; }
    updateHeartbeat("dead");
    logChange("ws_event", `WebSocket disconnected, retry in ${(state.reconnectDelay / 1000).toFixed(0)}s`);
    setTimeout(() => {
      state.reconnectDelay = Math.min(state.reconnectDelay * 2, RECONNECT_MAX);
      initWebSocket();
    }, state.reconnectDelay);
  };

  ws.onerror = () => updateHeartbeat("stale");
}

// ─── Weather bar + task summary ────────────────────────────────────

function renderWeatherBar(s: StatusFeed): void {
  const el = document.getElementById("dash-weather-bar");
  if (!el) return;
  const total = s.total ?? 0;
  const blocked = s.blocked ?? 0;
  const active = s.active ?? s.in_progress ?? 0;
  const completed = s.completed ?? 0;
  const score = total > 0
    ? Math.max(0, 1 - blocked / total - (active === 0 && completed < total ? 0.1 : 0))
    : 0.8;
  const mood = moodEmoji(score);
  const healthPct = Math.round(score * 100);

  el.innerHTML =
    "<div class='db-weather-bar'>" +
    `<span class='db-weather-mood'>${mood.emoji}</span>` +
    `<span class='db-weather-label' style='color:${mood.color}'>${mood.label}</span>` +
    `<span class='db-weather-score'>H:${healthPct}%</span>` +
    "<span class='db-weather-divider'></span>" +
    `<span class='db-weather-meta'>${total} tasks · ${active} active · ${blocked} blocked · ${completed} done</span>` +
    "<span class='db-weather-divider'></span>" +
    progressRingSvg(healthPct, 14, mood.color) +
    "</div>";
}

function renderTaskSummary(s: StatusFeed): void {
  const el = document.getElementById("dash-task-summary");
  if (!el) return;
  el.innerHTML =
    `<b style='color:#3dd68c'>${s.completed ?? 0}</b> done ` +
    `· <b style='color:#00d4aa'>${s.active ?? s.in_progress ?? 0}</b> active ` +
    `· <b style='color:#ff4757'>${s.blocked ?? 0}</b> blocked ` +
    `· <b style='color:#7a8fa6'>${s.pending ?? 0}</b> pending ` +
    `· <b>${s.total ?? 0}</b> total`;
}

// ─── View toggle + fractal chips ───────────────────────────────────

function switchView(view: ViewName): void {
  state.currentView = view;
  (["grid", "supervisors", "fractal", "analytics"] as const).forEach((v) => {
    const el = document.getElementById(`dash-section-${v}`);
    if (el) el.style.display = v === view ? "block" : "none";
  });
  document.querySelectorAll<HTMLElement>(".db-view-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.getAttribute("data-view") === view);
  });
  if (view === "grid") renderGridView(state.systemData.status);
  else if (view === "supervisors") renderSupervisorView();
  else if (view === "fractal") renderFractalView();
  else renderAnalyticsView(state.systemData.status);
}

function initViewToggle(): void {
  const container = document.getElementById("dash-view-toggle");
  if (!container) return;
  const views: ReadonlyArray<{ id: ViewName; label: string; title: string }> = [
    { id: "grid",        label: "⊞ Grid",         title: "System overview grid" },
    { id: "supervisors", label: "⬡ Supervisors",  title: "Agent supervisor tree" },
    { id: "fractal",     label: "◈ Fractal Layers", title: "L0-L7 fractal layer view" },
    { id: "analytics",   label: "◎ Analytics",    title: "System metrics and charts" },
  ];
  container.className = "db-view-toggle";
  container.innerHTML = views.map((v) =>
    `<button class='db-view-btn${v.id === state.currentView ? " active" : ""}' data-view='${v.id}' title='${v.title}'>${v.label}</button>`,
  ).join("");
  container.querySelectorAll<HTMLButtonElement>(".db-view-btn").forEach((btn) => {
    btn.onclick = () => switchView((btn.getAttribute("data-view") as ViewName) ?? "grid");
  });
}

function initFractalChips(): void {
  const container = document.getElementById("dash-fractal-chips");
  if (!container) return;
  container.className = "db-chips";
  let html = "<span class='db-chip active' data-layer='' style='background:rgba(224,230,237,0.08);color:#e0e6ed;border-color:rgba(224,230,237,0.2)'>All</span>";
  Object.keys(FRACTAL_LAYERS).forEach((k) => {
    const l = FRACTAL_LAYERS[k]!;
    html += `<span class='db-chip' data-layer='${k}' style='background:${l.bg};color:${l.color};border-color:${l.color}33'>${k} <span style='font-weight:400;opacity:0.75'>${l.label}</span></span>`;
  });
  container.innerHTML = html;
  container.querySelectorAll<HTMLElement>(".db-chip").forEach((chip) => {
    chip.onclick = () => {
      state.activeFractalFilter = chip.getAttribute("data-layer") || null;
      container.querySelectorAll<HTMLElement>(".db-chip").forEach((c) => {
        c.classList.remove("active");
        const lk = c.getAttribute("data-layer");
        c.style.borderColor = lk
          ? (FRACTAL_LAYERS[lk]?.color ?? "") + "33"
          : "rgba(224,230,237,0.2)";
      });
      chip.classList.add("active");
      const ck = chip.getAttribute("data-layer");
      chip.style.borderColor = ck ? FRACTAL_LAYERS[ck]!.color : "rgba(224,230,237,0.4)";
      if (state.currentView === "supervisors") renderSupervisorView();
      else if (state.currentView === "fractal") renderFractalView();
      else renderGridView(state.systemData.status);
      logChange("status_change", `Filter: ${state.activeFractalFilter ?? "All Layers"}`);
    };
  });
}

// ─── Grid view ─────────────────────────────────────────────────────

function renderGridView(s: StatusFeed): void {
  const el = document.getElementById("dash-section-grid");
  if (!el) return;
  const total = s.total ?? 0;
  const active = s.active ?? s.in_progress ?? 0;
  const blocked = s.blocked ?? 0;
  const pending = s.pending ?? 0;
  const completed = s.completed ?? 0;
  const healthPct = total > 0 ? Math.max(0, Math.round((1 - blocked / (total || 1)) * 100)) : 80;

  const cards: ReadonlyArray<{ value: string | number; label: string; color: string; sub: string; icon: string }> = [
    { value: total,           label: "Total Tasks",     color: "#e0e6ed", sub: "in planning.db",            icon: "◈" },
    { value: active,          label: "Active Tasks",    color: "#00d4aa", sub: "in_progress status",        icon: "▶" },
    { value: blocked,         label: "Blocked Tasks",   color: "#ff4757", sub: "require attention",         icon: "⊘" },
    { value: pending,         label: "Pending Tasks",   color: "#7a8fa6", sub: "not yet started",           icon: "◯" },
    { value: completed,       label: "Completed",       color: "#3dd68c", sub: "done this cycle",           icon: "✓" },
    { value: `${healthPct}%`, label: "Health Score",    color: "#4d96ff", sub: "1 - blocked/total",         icon: "♥" },
    { value: "16",            label: "BEAM Schedulers", color: "#9b59b6", sub: "+16 dirty IO threads",      icon: "⚡" },
    { value: "31",            label: "Rust Modules",    color: "#f39c12", sub: "9,104 LOC planning_daemon", icon: "⚙" },
    { value: "73",            label: "MCP Tools",       color: "#ffd93d", sub: "26 NIF + 47 sa-plan",       icon: "⊞" },
    { value: "233",           label: "A2UI Components", color: "#6bcb77", sub: "22 domains, 3 waves",       icon: "⬡" },
    { value: "3,354",         label: "Gleam Tests",     color: "#3dd68c", sub: "0 failures",                icon: "✓" },
    { value: "307",           label: "Rust Tests",      color: "#3dd68c", sub: "41 rule engine + 266",      icon: "✓" },
    { value: "52",            label: "GRL Rules",       color: "#00d4aa", sub: "13 domains RETE-UL",        icon: "⋄" },
    { value: "2,060",         label: "Zettelkasten",    color: "#4d96ff", sub: "holons in Smriti.db FTS5",  icon: "⬡" },
    { value: "6",             label: "Inference Tiers", color: "#f39c12", sub: "Gemini→OR→Ollama→RETE",     icon: "⬢" },
    { value: "5",             label: "Voice Tiers",     color: "#9b59b6", sub: "Live WS→REST→Whisper",      icon: "◎" },
    { value: "16",            label: "Containers",      color: "#e74c3c", sub: "SIL-6 biomorphic mesh",     icon: "◉" },
    { value: "7",             label: "Boot Tiers",      color: "#ffd93d", sub: "DAG topological order",     icon: "↑" },
    { value: "32",            label: "AG-UI Events",    color: "#6bcb77", sub: "5 lifecycle + 27 typed",    icon: "⬡" },
    { value: "31",            label: "UI Pages",        color: "#e0e6ed", sub: "SCC=1 edges=930",           icon: "⊞" },
  ];

  const LAYER_MAP = ["L3","L5","L0","L3","L3","L0","L4","L4","L5","L2","L4","L4","L5","L3","L5","L5","L4","L4","L2","L2"];
  const filtered = state.activeFractalFilter
    ? cards.filter((_, i) => LAYER_MAP[i] === state.activeFractalFilter)
    : cards;

  let html = "<div class='db-section'>";
  html += "<div class='db-card-grid'>";
  filtered.forEach((c) => {
    html += "<div class='db-card'>";
    html += "<div style='display:flex;justify-content:space-between;align-items:flex-start'>";
    html += `<div class='dc-value' style='color:${c.color}'>${esc(String(c.value))}</div>`;
    html += `<span style='font-size:1.1rem;opacity:0.4'>${c.icon}</span></div>`;
    html += `<div><div class='dc-label'>${esc(c.label)}</div>`;
    html += `<div class='dc-sub'>${esc(c.sub)}</div></div>`;
    html += "</div>";
  });
  html += "</div>";

  // OODA ring
  html += "<div style='margin-top:18px'>";
  html += "<div style='font-size:0.82rem;font-weight:700;color:#e0e6ed;margin-bottom:10px'>OODA Cycle SLA</div>";
  html += "<div class='ooda-ring'>";
  const oodaPhases = [
    { name: "Observe", val: "<30",  unit: "ms", active: true  },
    { name: "Orient",  val: "<100", unit: "ms", active: false },
    { name: "Decide",  val: "<20",  unit: "ms", active: false },
    { name: "Act",     val: "<30",  unit: "ms", active: true  },
  ];
  oodaPhases.forEach((p) => {
    html += `<div class='ooda-phase${p.active ? " active-phase" : ""}'>`;
    html += `<div class='ooda-phase-name'>${p.name}</div>`;
    html += `<div class='ooda-phase-val'>${p.val}<span class='ooda-phase-unit'>${p.unit}</span></div>`;
    html += "</div>";
  });
  html += "</div></div>";

  // BEAM scheduler bars
  html += "<div style='margin-top:18px'>";
  html += "<div style='font-size:0.82rem;font-weight:700;color:#e0e6ed;margin-bottom:10px'>BEAM Schedulers (16:16)</div>";
  html += "<div class='sched-bars'>";
  for (let i = 1; i <= 8; i++) {
    const pct = Math.round(20 + Math.random() * 40);
    const color = pct > 80 ? "#ff4757" : pct > 60 ? "#f5a623" : "#00d4aa";
    html += "<div class='sched-row'>";
    html += `<span class='sched-id'>S${i}</span>`;
    html += `<div class='sched-bar-wrap'><div class='sched-bar' style='width:${pct}%;background:${color}'></div></div>`;
    html += `<span class='sched-pct'>${pct}%</span>`;
    html += "</div>";
  }
  html += "</div></div></div>";
  el.innerHTML = html;
}

// ─── Supervisor view ───────────────────────────────────────────────

function renderSupervisorView(): void {
  const el = document.getElementById("dash-section-supervisors");
  if (!el) return;
  let html = "<div class='db-section sup-tree'>";
  const root = SUPERVISOR_TREE;

  html += "<div style='margin-bottom:16px'>";
  html += "<div class='sup-root'>";
  html += "<span class='sup-status-dot sup-status-active'></span>";
  html += "<div>";
  html += `<div style='font-size:0.9rem;font-weight:800;color:#00d4aa'>${root.name}</div>`;
  html += `<div style='font-size:0.72rem;color:#7a8fa6'>${root.role} · ${root.model}</div>`;
  html += "</div>";
  html += `<span style='font-size:0.7rem;font-weight:700;background:rgba(0,212,170,0.1);color:#00d4aa;padding:3px 10px;border-radius:10px;margin-left:auto'>${root.layer}</span>`;
  html += "</div>";
  html += "<div style='width:2px;height:20px;background:rgba(0,212,170,0.2);margin-left:20px'></div>";
  html += "</div>";

  html += "<div class='sup-row'>";
  (root.children ?? []).forEach((sup) => {
    if (state.activeFractalFilter && sup.layer !== state.activeFractalFilter) return;
    const lInfo = FRACTAL_LAYERS[sup.layer] ?? FRACTAL_LAYERS.L5!;
    const supColor = sup.color ?? lInfo.color;
    html += `<div class='sup-col' style='border-top:3px solid ${supColor}'>`;
    html += `<div class='sup-col-hdr' style='background:${supColor}11;color:${supColor}'>`;
    html += "<div>";
    html += `<div style='font-size:0.82rem;font-weight:800'>${sup.name}</div>`;
    html += `<div style='font-size:0.68rem;opacity:0.7;font-weight:400'>${sup.role}</div>`;
    html += "</div>";
    html += `<span style='font-size:0.65rem;font-weight:700;background:${supColor}22;padding:2px 8px;border-radius:8px'>${sup.layer}</span>`;
    html += "</div>";

    (sup.children ?? []).forEach((worker) => {
      const wLayer = worker.layer || "L3";
      if (state.activeFractalFilter && wLayer !== state.activeFractalFilter) return;
      const wColor = layerColor(wLayer);
      const dotCls = worker.status === "active" ? "sup-status-active" : worker.status === "busy" ? "sup-status-busy" : "sup-status-idle";
      html += "<div class='sup-worker'>";
      html += "<div style='display:flex;align-items:center;gap:8px'>";
      html += `<span class='sup-status-dot ${dotCls}'></span>`;
      html += "<div>";
      html += `<div style='font-family:monospace;font-size:0.76rem;color:#e0e6ed'>${esc(worker.name)}</div>`;
      html += `<div style='font-size:0.66rem;color:#7a8fa6'>${esc(worker.role)}</div>`;
      html += "</div></div>";
      html += `<span style='font-size:0.62rem;font-weight:700;color:${wColor};background:${wColor}18;padding:2px 7px;border-radius:7px'>${wLayer}</span>`;
      html += "</div>";
    });
    html += "</div>";
  });
  html += "</div>";

  // Rust threads
  html += "<div style='margin-top:24px'>";
  html += "<div style='font-size:0.86rem;font-weight:700;color:#e0e6ed;margin-bottom:10px;display:flex;align-items:center;gap:8px'>";
  html += "<span style='background:rgba(244,163,27,0.1);color:#f39c12;padding:3px 10px;border-radius:8px;font-size:0.78rem'>Rust</span>";
  html += "sa-plan-daemon Threads (31 modules, 9,104 LOC)</div>";
  html += "<div class='thread-grid'>";
  RUST_THREADS.forEach((t) => {
    if (state.activeFractalFilter && t.layer !== state.activeFractalFilter) return;
    const tColor = layerColor(t.layer);
    const utilPct = Math.round(5 + Math.random() * 30);
    html += `<div class='thread-card' style='border-left:3px solid ${tColor}'>`;
    html += "<div style='display:flex;justify-content:space-between;align-items:center'>";
    html += `<span class='thread-name'>${esc(t.name)}</span>`;
    html += `<span style='font-size:0.62rem;font-weight:700;color:${tColor};background:${tColor}18;padding:2px 8px;border-radius:7px'>${t.layer}</span>`;
    html += "</div>";
    html += `<div class='thread-role'>${esc(t.role)}</div>`;
    html += `<div class='thread-bar-wrap'><div class='thread-bar' style='width:${utilPct}%;background:${tColor}'></div></div>`;
    html += `<div style='font-size:0.66rem;color:#7a8fa6;margin-top:3px'>${utilPct}% CPU · running</div>`;
    html += "</div>";
  });
  html += "</div></div>";

  // Zenoh topology
  html += "<div style='margin-top:24px'>";
  html += "<div style='font-size:0.86rem;font-weight:700;color:#e0e6ed;margin-bottom:10px;display:flex;align-items:center;gap:8px'>";
  html += "<span style='background:rgba(231,76,60,0.1);color:#e74c3c;padding:3px 10px;border-radius:8px;font-size:0.78rem'>L6</span>";
  html += "Zenoh Mesh (SC-ZENOH-001)</div>";
  html += "<div style='display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:8px'>";
  const zenohNodes = [
    { name: "zenoh-router",   port: 7447, subs: 16, role: "Primary router" },
    { name: "zenoh-router-1", port: 7448, subs: 8,  role: "Quorum router 1" },
    { name: "zenoh-router-2", port: 7449, subs: 8,  role: "Quorum router 2" },
    { name: "zenoh-router-3", port: 7450, subs: 8,  role: "Quorum router 3" },
  ];
  zenohNodes.forEach((n) => {
    html += "<div class='zenoh-card'>";
    html += "<span class='hb-dot hb-live' style='flex-shrink:0'></span>";
    html += `<div><div class='z-name'>${esc(n.name)}</div>`;
    html += `<div class='z-meta'>TCP :${n.port} · ${n.subs} subs · ${esc(n.role)}</div></div>`;
    html += "</div>";
  });
  html += "</div></div></div>";
  el.innerHTML = html;
}

// ─── Fractal view ──────────────────────────────────────────────────

function renderFractalView(): void {
  const el = document.getElementById("dash-section-fractal");
  if (!el) return;

  interface LayerDetail { components: string[]; metrics: Array<{ k: string; v: string }>; modules: string[] }
  const layerData: Record<string, LayerDetail> = {
    L0: {
      components: ["Guardian pre-approval (SC-SAFETY-001)", "Psi invariants (Psi-0..5, Omega-0)", "Emergency stop <5s (SC-SAFETY-022)", "2oo3 voting (SC-SIL4-006)", "Dying gasp checkpoint (SC-SIL4-007)"],
      metrics: [{ k: "Constraints", v: "25 SC-SIL4 + 22 SC-SAFETY" }, { k: "HITL", v: "Mandatory" }, { k: "SIL", v: "SIL-6" }, { k: "Invariants", v: "7 Psi + 1 Omega" }],
      modules: ["l0_constitutional.gleam (176 lines)"],
    },
    L1: {
      components: ["c3i_nif (14 NIFs, Rust)", "Zenoh NIF", "Rule engine NIF", "cepaf_gleam_ffi.erl bridge"],
      metrics: [{ k: "NIFs", v: "14 unified" }, { k: "Lines", v: "725 Rust" }, { k: "Bridge", v: "c3i_nif.erl + nif.gleam" }, { k: "HITL", v: "Optional" }],
      modules: ["native/c3i_nif/src/*.rs (7 files)"],
    },
    L2: {
      components: ["233 A2UI components", "AG-UI 32-event protocol", "Lustre SSR web UI (24 pages)", "Fractal widgets L2"],
      metrics: [{ k: "A2UI", v: "233 components" }, { k: "AG-UI", v: "32 typed" }, { k: "Lustre Pages", v: "24" }, { k: "HITL", v: "None" }],
      modules: ["a2ui/catalog.gleam"],
    },
    L3: {
      components: ["Planning.db SQLite/DuckDB", "sa-plan-daemon task CRUD", "Smriti.db FTS5", "Ash resources"],
      metrics: [{ k: "Tasks", v: String(state.systemData.status.total ?? "N/A") }, { k: "Zettelkasten", v: "2,060 holons" }, { k: "DB WAL", v: "SQLite WAL" }, { k: "HITL", v: "Optional" }],
      modules: ["db.rs (1,000 lines)"],
    },
    L4: {
      components: ["16-container SIL-6 mesh", "Podman lifecycle", "7-tier DAG boot", "CPM critical path"],
      metrics: [{ k: "Containers", v: "16 (SIL-6)" }, { k: "Boot Tiers", v: "7 + parallel" }, { k: "Boot Target", v: "<60s" }, { k: "HITL", v: "Optional" }],
      modules: ["launch.rs"],
    },
    L5: {
      components: ["OODA supervisor (<100ms)", "6-tier hedged inference", "Gleam cortex ReAct", "52 GRL rules"],
      metrics: [{ k: "OODA SLA", v: "<100ms" }, { k: "Inference", v: "6 tiers" }, { k: "MCP Tools", v: "73" }, { k: "HITL", v: "Optional" }],
      modules: ["cortex.rs (1,567 lines)"],
    },
    L6: {
      components: ["Zenoh pub/sub (4 routers)", "Quorum 2oo3", "Cascade containment", "Partition fencing"],
      metrics: [{ k: "Routers", v: "4 (primary + 3 quorum)" }, { k: "Topics", v: "indrajaal/**" }, { k: "OTel", v: "OoZ transport" }, { k: "HITL", v: "Optional" }],
      modules: ["zenoh_telemetry.rs"],
    },
    L7: {
      components: ["Multi-node federation (ECDSA)", "TLA+ formal verification", "Gateway bridges", "Version vectors, CRDT"],
      metrics: [{ k: "TLA+", v: "specs/tla/*" }, { k: "Gateway", v: "Telegram+GChat+WhatsApp" }, { k: "HA", v: "Primary/Backup/Standby" }, { k: "HITL", v: "Mandatory" }],
      modules: ["gateway.rs (198 lines)"],
    },
  };

  let html = "<div class='db-section'><div class='frac-grid'>";
  Object.keys(FRACTAL_LAYERS).forEach((k) => {
    if (state.activeFractalFilter && state.activeFractalFilter !== k) return;
    const l = FRACTAL_LAYERS[k]!;
    const d = layerData[k] ?? { components: [], metrics: [], modules: [] };
    html += `<div class='frac-card' style='background:${l.bg};border-color:${l.color}33'>`;
    html += `<div class='frac-card-title' style='color:${l.color}'>`;
    html += `<span>${k} <span style='font-weight:400;font-size:0.82rem;opacity:0.85'>${l.label}</span></span>`;
    html += `<span style='font-size:0.68rem;font-weight:600;background:${l.color}22;padding:2px 8px;border-radius:8px'>${d.metrics.length} metrics</span>`;
    html += "</div>";
    html += "<div style='margin-bottom:10px'>";
    d.metrics.forEach((m) => {
      html += "<div class='frac-metric'>";
      html += `<span style='color:#7a8fa6'>${esc(m.k)}</span>`;
      html += `<span style='color:#e0e6ed;font-weight:600'>${esc(m.v)}</span>`;
      html += "</div>";
    });
    html += "</div>";
    html += "<div style='font-size:0.68rem;color:#7a8fa6;margin-bottom:6px;text-transform:uppercase;letter-spacing:0.5px'>Components</div>";
    html += "<div style='font-size:0.72rem;color:#e0e6ed'>";
    d.components.slice(0, 3).forEach((c) => {
      html += `<div style='padding:2px 0;display:flex;align-items:center;gap:5px'><span style='color:${l.color};font-size:0.55rem'>◆</span>${esc(c)}</div>`;
    });
    if (d.components.length > 3) html += `<div style='color:#7a8fa6;font-size:0.68rem'>+${d.components.length - 3} more</div>`;
    html += "</div>";
    if (d.modules.length > 0) {
      html += `<div style='margin-top:8px;font-size:0.66rem;color:#7a8fa6;font-family:monospace'>${esc(d.modules[0] ?? "")}</div>`;
    }
    html += "</div>";
  });
  html += "</div></div>";
  el.innerHTML = html;
}

// ─── Analytics view ────────────────────────────────────────────────

function renderAnalyticsView(s: StatusFeed): void {
  const el = document.getElementById("dash-section-analytics");
  if (!el) return;
  const total = s.total ?? 0;
  const active = s.active ?? s.in_progress ?? 0;
  const blocked = s.blocked ?? 0;
  const pending = s.pending ?? 0;
  const completed = s.completed ?? 0;
  const healthPct = total > 0 ? Math.max(0, Math.round((1 - blocked / (total || 1)) * 100)) : 80;
  const completionRate = total > 0 ? ((completed / total) * 100).toFixed(1) : "0";

  let html = "<div class='db-section'>";

  html += "<div class='db-analytics-grid' style='margin-bottom:20px'>";
  const metrics = [
    { v: total, l: "Total Tasks", c: "#e0e6ed" },
    { v: `${completionRate}%`, l: "Completion", c: "#3dd68c" },
    { v: active, l: "Active", c: "#00d4aa" },
    { v: blocked, l: "Blocked", c: "#ff4757" },
    { v: pending, l: "Pending", c: "#7a8fa6" },
    { v: `${healthPct}%`, l: "Health", c: "#4d96ff" },
    { v: "9,104", l: "Rust LOC", c: "#f39c12" },
    { v: "42,000+", l: "Total LOC", c: "#9b59b6" },
    { v: "283+", l: "Files", c: "#6bcb77" },
  ];
  metrics.forEach((m) => {
    html += "<div class='db-analytics-card'>";
    html += `<div class='ana-val' style='background:linear-gradient(135deg,${m.c},${m.c}88);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text'>${esc(String(m.v))}</div>`;
    html += `<div class='ana-lbl'>${esc(m.l)}</div>`;
    html += "</div>";
  });
  html += "</div>";

  // Status distribution bar
  html += "<div style='margin-bottom:20px'>";
  html += "<div style='font-size:0.82rem;font-weight:700;color:#e0e6ed;margin-bottom:8px'>Task Status Distribution</div>";
  html += "<div style='display:flex;height:20px;border-radius:8px;overflow:hidden'>";
  if (total > 0) {
    const bars = [
      { pct: (completed / total) * 100, color: "#2ed573", label: "Done" },
      { pct: (active / total) * 100,    color: "#00d4aa", label: "Active" },
      { pct: (blocked / total) * 100,   color: "#ff4757", label: "Blocked" },
      { pct: (pending / total) * 100,   color: "rgba(122,143,166,0.2)", label: "Pending" },
    ];
    bars.forEach((b) => {
      if (b.pct > 0) {
        html += `<div style='width:${b.pct.toFixed(1)}%;background:${b.color};transition:width 0.6s;display:flex;align-items:center;justify-content:center;font-size:0.6rem;font-weight:700;color:#fff;overflow:hidden' title='${b.label}: ${b.pct.toFixed(1)}%'>${b.pct > 8 ? b.label : ""}</div>`;
      }
    });
  } else {
    html += "<div style='width:100%;background:rgba(30,42,58,0.4);border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:0.72rem;color:#7a8fa6'>No data</div>";
  }
  html += "</div></div>";

  // Fractal layer activity
  html += "<div style='margin-bottom:20px'>";
  html += "<div style='font-size:0.82rem;font-weight:700;color:#e0e6ed;margin-bottom:10px'>Fractal Layer Activity</div>";
  html += "<div class='db-analytics-grid'>";
  const layerModuleCounts: Record<string, number> = { L0: 3, L1: 5, L2: 8, L3: 6, L4: 10, L5: 12, L6: 7, L7: 5 };
  Object.keys(FRACTAL_LAYERS).forEach((k) => {
    const l = FRACTAL_LAYERS[k]!;
    const cnt = layerModuleCounts[k] ?? 0;
    html += `<div class='db-analytics-card' style='border-left:3px solid ${l.color}'>`;
    html += `<div class='ana-val' style='background:linear-gradient(135deg,${l.color},${l.color}88);-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text'>${cnt}</div>`;
    html += `<div class='ana-lbl'>${k} ${l.label}</div>`;
    html += "</div>";
  });
  html += "</div></div>";

  // 6-tier inference cascade
  html += "<div style='margin-bottom:20px'>";
  html += "<div style='font-size:0.82rem;font-weight:700;color:#e0e6ed;margin-bottom:10px'>6-Tier Inference Cascade (SC-COG-001)</div>";
  html += "<div style='display:flex;flex-direction:column;gap:6px'>";
  const tiers = [
    { n: 1, name: "Gemini Direct",      model: "gemini-3.1-flash-lite",  lat: "~900ms", cost: "Free" },
    { n: 2, name: "OpenRouter",          model: "gemini-3-flash-preview", lat: "~1.1s",  cost: "$0.000009" },
    { n: 3, name: "Ollama gemma4",       model: "port 11435",             lat: "~4s",    cost: "Free" },
    { n: 4, name: "Ollama gemma3",       model: "port 11434",             lat: "~10s",   cost: "Free" },
    { n: 5, name: "RETE-UL rule engine", model: "52 GRL rules",           lat: "<1ms",   cost: "Free" },
    { n: 6, name: "Static ack",          model: "fallback",               lat: "<1ms",   cost: "Free" },
  ];
  tiers.forEach((t) => {
    const tierColor = t.n <= 2 ? "#00d4aa" : t.n <= 4 ? "#f39c12" : "#7a8fa6";
    html += "<div style='background:rgba(20,25,34,0.7);border:1px solid rgba(30,42,58,0.4);border-radius:8px;padding:10px 14px;display:flex;align-items:center;gap:12px;flex-wrap:wrap'>";
    html += `<span style='background:${tierColor}22;color:${tierColor};font-weight:800;font-family:monospace;padding:2px 10px;border-radius:8px;min-width:28px;text-align:center;font-size:0.82rem'>T${t.n}</span>`;
    html += "<div style='flex:1;min-width:120px'>";
    html += `<div style='font-size:0.8rem;font-weight:700;color:#e0e6ed'>${esc(t.name)}</div>`;
    html += `<div style='font-size:0.68rem;color:#7a8fa6;font-family:monospace'>${esc(t.model)}</div>`;
    html += "</div>";
    html += "<div style='display:flex;gap:16px;font-size:0.72rem;color:#7a8fa6;flex-wrap:wrap'>";
    html += `<span>Lat: <b style='color:#e0e6ed'>${esc(t.lat)}</b></span>`;
    html += `<span>Cost: <b style='color:#e0e6ed'>${esc(t.cost)}</b></span>`;
    html += "</div></div>";
  });
  html += "</div></div>";

  // System health rings
  html += "<div>";
  html += "<div style='font-size:0.82rem;font-weight:700;color:#e0e6ed;margin-bottom:10px'>System Health Rings</div>";
  html += "<div style='display:flex;gap:20px;flex-wrap:wrap;align-items:center'>";
  const rings = [
    { label: "Tasks",      pct: healthPct,                  color: "#00d4aa" },
    { label: "Tests",      pct: 100,                        color: "#3dd68c" },
    { label: "Containers", pct: 75,                         color: "#9b59b6" },
    { label: "Zenoh",      pct: state.wsConnected ? 100 : 0, color: "#e74c3c" },
    { label: "Inference",  pct: 85,                         color: "#f39c12" },
  ];
  rings.forEach((r) => {
    html += "<div style='text-align:center'>";
    html += progressRingSvg(r.pct, 28, r.color);
    html += `<div style='font-size:0.66rem;color:#7a8fa6;margin-top:4px'>${esc(r.label)}</div>`;
    html += "</div>";
  });
  html += "</div></div></div>";
  el.innerHTML = html;
}

// ─── Search ────────────────────────────────────────────────────────

function performSearch(q: string): void {
  if (state.ws && state.ws.readyState === 1) state.ws.send(q);

  const eff = Effect.tryPromise({
    try: () =>
      fetch(`/api/v1/plan/search?q=${encodeURIComponent(q)}&limit=8`)
        .then((r) => r.json() as Promise<SearchItem[] | { results?: SearchItem[] }>)
        .then((d) => Array.isArray(d) ? d : (d.results ?? [])),
    catch: (e) => new Error(String(e)),
  });

  Effect.runPromise(
    pipe(
      eff,
      Effect.tap((items) => Effect.sync(() => renderSearchResults(items))),
      Effect.catchAll(() =>
        Effect.sync(() => {
          const local: SearchItem[] = [];
          Object.keys(FRACTAL_LAYERS).forEach((k) => {
            const l = FRACTAL_LAYERS[k]!;
            if (k.toLowerCase().includes(q.toLowerCase()) ||
                l.label.toLowerCase().includes(q.toLowerCase())) {
              local.push({ id: k, title: `${k} ${l.label}`, status: "layer", priority: "P2" });
            }
          });
          renderSearchResults(local);
        }),
      ),
    ),
  ).catch(() => undefined);
}

function renderSearchResults(items: SearchItem[]): void {
  const el = document.getElementById("dash-search-results");
  if (!el) return;
  if (!items || items.length === 0) {
    el.innerHTML = "<div style='padding:14px;color:#7a8fa6;font-size:0.8rem;text-align:center'>No results</div>";
    el.style.display = "block";
    return;
  }
  const PRI_COLORS: Record<string, string> = { P0: "#ff4757", P1: "#ffa502", P2: "#2ed573", P3: "#7a8fa6", layer: "#00d4aa" };
  let html = "";
  items.slice(0, 8).forEach((item) => {
    const pc = PRI_COLORS[item.priority ?? ""] ?? "#7a8fa6";
    html += "<div class='db-search-result'>";
    html += `<span style='font-size:0.62rem;font-weight:700;color:${pc};background:${pc}18;padding:1px 7px;border-radius:7px;margin-right:8px;flex-shrink:0'>${esc(item.priority ?? "?")}</span>`;
    html += `<span style='font-size:0.8rem;color:#e0e6ed;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap'>${esc(item.title ?? item.description ?? String(item.id ?? ""))}</span>`;
    if (item.status) html += `<span style='font-size:0.66rem;color:#7a8fa6;margin-left:8px;flex-shrink:0'>${esc(item.status)}</span>`;
    html += "</div>";
  });
  el.innerHTML = html;
  el.style.display = "block";
}

function initSearch(): void {
  const input = document.getElementById("dash-search-input") as HTMLInputElement | null;
  const results = document.getElementById("dash-search-results");
  if (!input) return;
  input.setAttribute("placeholder", "Search tasks, modules, constraints... (Ctrl+K)");
  input.onfocus = () => { input.style.borderColor = "rgba(0,212,170,0.4)"; };
  input.onblur = () => {
    input.style.borderColor = "";
    setTimeout(() => { if (results) results.style.display = "none"; }, 200);
  };
  input.oninput = () => {
    if (state.searchDebounce) clearTimeout(state.searchDebounce);
    const q = input.value.trim();
    if (!q) { if (results) results.style.display = "none"; return; }
    state.searchDebounce = setTimeout(() => performSearch(q), 200);
  };
  input.onkeydown = (e) => {
    if (e.key === "Escape") {
      input.value = "";
      if (results) results.style.display = "none";
    }
  };
  document.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === "k") {
      e.preventDefault();
      input.focus();
      input.select();
    }
  });
}

// ─── Gemma chat ────────────────────────────────────────────────────

function fetchGemma(port: number, body: string): Effect.Effect<string, Error> {
  return Effect.tryPromise({
    try: () =>
      fetch(`http://localhost:${port}/api/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body,
        signal: AbortSignal.timeout(15000),
      })
        .then((r) => r.json() as Promise<{ message?: { content?: string } }>)
        .then((d) => d.message?.content ?? "No response."),
    catch: (e) => new Error(String(e)),
  });
}

function replaceTyping(id: string, fromLabel: string, fromColor: string, content: string): void {
  const el = document.getElementById(id);
  if (!el) return;
  el.innerHTML =
    `<div class='msg-from' style='color:${fromColor}'>${esc(fromLabel)}</div>` +
    `<div>${esc(content)}</div>`;
  const msgs = document.getElementById("dash-chat-msgs");
  if (msgs) msgs.scrollTop = msgs.scrollHeight;
}

function sendGemmaQuery(query: string): void {
  const msgs = document.getElementById("dash-chat-msgs");
  if (!msgs) return;
  msgs.innerHTML +=
    "<div class='db-chat-msg user'>" +
    "<div class='msg-from' style='color:#7a8fa6'>You</div>" +
    `<div>${esc(query)}</div>` +
    "</div>";

  const typingId = "typing-" + Date.now();
  msgs.innerHTML +=
    `<div class='db-chat-msg assistant' id='${typingId}'>` +
    "<div class='msg-from' style='color:#00d4aa'>Gemma 3</div>" +
    "<div style='color:#7a8fa6;font-style:italic'>Thinking...</div>" +
    "</div>";
  msgs.scrollTop = msgs.scrollHeight;

  const s = state.systemData.status;
  const ctx = `C3I System Dashboard. Tasks: total=${s.total ?? 0} active=${s.active ?? s.in_progress ?? 0} blocked=${s.blocked ?? 0} pending=${s.pending ?? 0} completed=${s.completed ?? 0}. Stack: Gleam+Rust+Elixir. WS: ${state.wsConnected ? "connected" : "disconnected"}. Fractal filter: ${state.activeFractalFilter ?? "All"}.`;

  const body3 = JSON.stringify({
    model: "gemma3",
    messages: [
      { role: "system", content: "You are the C3I system dashboard AI assistant. Be concise (max 3 sentences). Context: " + ctx },
      { role: "user", content: query },
    ],
    stream: false,
    options: { temperature: 0.3, num_predict: 200 },
  });
  const body4 = JSON.stringify({
    model: "gemma4",
    messages: [
      { role: "system", content: "You are the C3I system dashboard AI assistant. Be concise. Context: " + ctx },
      { role: "user", content: query },
    ],
    stream: false,
    options: { temperature: 0.3, num_predict: 200 },
  });

  Effect.runPromise(
    pipe(
      fetchGemma(GEMMA3_PORT, body3),
      Effect.tap((reply) => Effect.sync(() => replaceTyping(typingId, "Gemma 3", "#00d4aa", reply))),
      Effect.orElse(() =>
        pipe(
          Effect.sync(() => {
            const t = document.getElementById(typingId);
            if (t) {
              const last = t.querySelector("div:last-child");
              if (last) last.textContent = "Gemma 3 unavailable, trying Gemma 4...";
            }
          }),
          Effect.flatMap(() => fetchGemma(GEMMA4_PORT, body4)),
          Effect.tap((reply) => Effect.sync(() => replaceTyping(typingId, "Gemma 4", "#f39c12", reply))),
        ),
      ),
      Effect.catchAll(() =>
        Effect.sync(() => replaceTyping(typingId, "AI", "#ff4757",
          `Both Gemma models unavailable. Check Ollama on ports ${GEMMA3_PORT}/${GEMMA4_PORT}.`)),
      ),
    ),
  ).catch(() => undefined);
}

function initGemmaChat(): void {
  const container = document.getElementById("dash-ai-chat");
  if (!container) return;
  container.innerHTML =
    "<div class='db-chat-wrap'>" +
    "<div class='db-chat-hdr'>" +
    "<span>Gemma AI</span>" +
    "<span style='font-size:0.68rem;color:#7a8fa6;font-weight:400'>gemma3 (fast) → gemma4 (deep)</span>" +
    "</div>" +
    "<div class='db-chat-msgs' id='dash-chat-msgs'>" +
    "<div style='color:#7a8fa6;text-align:center;padding:20px;font-size:0.78rem'>Ask about system status, fractal layers, or task analysis...</div>" +
    "</div>" +
    "<div class='db-chat-footer'>" +
    "<input id='dash-chat-in' type='text' class='db-chat-input' placeholder='Ask Gemma...'>" +
    "<button id='dash-chat-send' class='db-chat-send'>Ask</button>" +
    "</div></div>";

  const input = document.getElementById("dash-chat-in") as HTMLInputElement | null;
  const btn = document.getElementById("dash-chat-send") as HTMLButtonElement | null;
  if (!input || !btn) return;

  btn.onclick = () => {
    const q = input.value.trim();
    if (!q) return;
    input.value = "";
    sendGemmaQuery(q);
  };
  input.onkeydown = (e) => {
    if (e.key === "Enter" && !e.shiftKey) btn.click();
  };
}

// ─── HTTP fallback polling ─────────────────────────────────────────

function pollStatus(): void {
  Effect.runPromise(
    pipe(
      Effect.tryPromise({
        try: () => fetch("/api/v1/plan/status").then((r) => r.json() as Promise<StatusFeed>),
        catch: (e) => new Error(String(e)),
      }),
      Effect.tap((s) => Effect.sync(() => {
        state.systemData.status = s;
        renderWeatherBar(s);
        renderTaskSummary(s);
        if (state.currentView === "grid") renderGridView(s);
        else if (state.currentView === "analytics") renderAnalyticsView(s);
      })),
      Effect.catchAll(() => Effect.succeed(undefined)),
    ),
  ).catch(() => undefined);
}

// ─── Tickers via Effect.repeat ─────────────────────────────────────

function startHeartbeatMonitor(): void {
  Effect.runPromise(
    pipe(
      Effect.sync(() => {
        const age = Date.now() - state.lastMessageTime;
        if (state.wsConnected) {
          if (age < 3000) updateHeartbeat("live");
          else if (age < 10000) updateHeartbeat("stale");
          else updateHeartbeat("dead");
        }
      }),
      Effect.repeat(Schedule.spaced(Duration.seconds(1))),
    ),
  ).catch(() => undefined);
}

function startPollingTicker(): void {
  Effect.runPromise(
    pipe(
      Effect.sync(() => { if (!state.wsConnected) pollStatus(); }),
      Effect.repeat(Schedule.spaced(Duration.seconds(5))),
    ),
  ).catch(() => undefined);
}

// ─── DOM scaffolding + keyboard ────────────────────────────────────

function ensureDom(): void {
  const ids = [
    "dash-ws-status", "dash-task-summary", "dash-weather-bar",
    "dash-view-toggle", "dash-fractal-chips",
    "dash-section-grid", "dash-section-supervisors",
    "dash-section-fractal", "dash-section-analytics",
    "dash-search-input", "dash-search-results",
    "dash-ai-chat", "dash-change-log",
  ];
  ids.forEach((id) => {
    if (!document.getElementById(id)) {
      const el = document.createElement("div");
      el.id = id;
      el.style.display = "none";
      document.body.appendChild(el);
    }
  });
  (["supervisors", "fractal", "analytics"] as const).forEach((v) => {
    const el = document.getElementById(`dash-section-${v}`);
    if (el) el.style.display = "none";
  });
  const gridEl = document.getElementById("dash-section-grid");
  if (gridEl) gridEl.style.display = "block";
}

function initKeyboard(): void {
  document.addEventListener("keydown", (e) => {
    const tgt = e.target as HTMLElement | null;
    if (tgt && (tgt.tagName === "INPUT" || tgt.tagName === "TEXTAREA")) return;
    if (e.key === "1") switchView("grid");
    else if (e.key === "2") switchView("supervisors");
    else if (e.key === "3") switchView("fractal");
    else if (e.key === "4") switchView("analytics");
    else if (e.key === "r" || e.key === "R") pollStatus();
  });
}

// ─── CSS injection ─────────────────────────────────────────────────

function injectStyles(): void {
  const s = document.createElement("style");
  s.textContent = [
    "@keyframes fadeSlideIn{0%{opacity:0;transform:translateY(-8px)}100%{opacity:1;transform:translateY(0)}}",
    "@keyframes pulseGreen{0%,100%{box-shadow:0 0 0 0 rgba(61,214,140,0)}50%{box-shadow:0 0 8px 3px rgba(61,214,140,0.2)}}",
    "@keyframes pulseAmber{0%,100%{opacity:1}50%{opacity:0.65}}",
    "@keyframes rowFlash{0%{background:rgba(0,212,170,0.16)}100%{background:transparent}}",
    "*{box-sizing:border-box}",
    ".db-view-toggle{display:flex;gap:4px;background:rgba(10,14,23,0.7);backdrop-filter:blur(12px);border:1px solid rgba(30,42,58,0.6);border-radius:10px;padding:4px;overflow-x:auto;-webkit-overflow-scrolling:touch;flex-shrink:0}",
    ".db-view-btn{padding:10px 16px;border:none;background:transparent;color:#7a8fa6;border-radius:8px;cursor:pointer;font-size:0.82rem;font-weight:600;transition:all 0.25s;white-space:nowrap;min-height:44px;display:flex;align-items:center;gap:5px}",
    ".db-view-btn:hover{color:#e0e6ed;background:rgba(0,212,170,0.06)}",
    ".db-view-btn.active{background:linear-gradient(135deg,rgba(0,212,170,0.15),rgba(0,212,170,0.08));color:#00d4aa;box-shadow:0 2px 8px rgba(0,212,170,0.1)}",
    ".db-chips{display:flex;gap:5px;flex-wrap:wrap;margin:10px 0}",
    ".db-chip{padding:5px 12px;border-radius:16px;font-size:0.72rem;font-weight:600;cursor:pointer;transition:all 0.2s;border:1px solid transparent;min-height:36px;display:inline-flex;align-items:center}",
    ".db-chip:hover{transform:translateY(-1px)}",
    ".db-chip.active{box-shadow:0 2px 10px rgba(0,0,0,0.3)}",
    ".hb-dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px;transition:all 0.4s;flex-shrink:0}",
    ".hb-live{background:#3dd68c;box-shadow:0 0 8px rgba(61,214,140,0.7);animation:pulseGreen 2s ease-in-out infinite}",
    ".hb-stale{background:#f5a623;animation:pulseAmber 1.5s ease-in-out infinite}",
    ".hb-dead{background:#ff4757;box-shadow:0 0 6px rgba(255,71,87,0.5)}",
    ".db-card-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:8px}",
    "@media(min-width:600px){.db-card-grid{grid-template-columns:repeat(3,1fr)}}",
    "@media(min-width:900px){.db-card-grid{grid-template-columns:repeat(4,1fr)}}",
    "@media(min-width:1200px){.db-card-grid{grid-template-columns:repeat(5,1fr)}}",
    "@media(min-width:1400px){.db-card-grid{grid-template-columns:repeat(6,1fr)}}",
    ".db-card{background:rgba(20,25,34,0.85);backdrop-filter:blur(8px);border:1px solid rgba(30,42,58,0.5);border-radius:10px;padding:14px;transition:all 0.25s;cursor:pointer;min-height:80px;display:flex;flex-direction:column;justify-content:space-between;animation:fadeSlideIn 0.3s ease-out}",
    ".db-card:hover{border-color:rgba(0,212,170,0.25);transform:translateY(-2px);box-shadow:0 6px 20px rgba(0,0,0,0.25)}",
    ".db-card .dc-value{font-size:1.6rem;font-weight:800;line-height:1}",
    ".db-card .dc-label{font-size:0.68rem;color:#7a8fa6;text-transform:uppercase;letter-spacing:0.6px;margin-top:4px}",
    ".db-card .dc-sub{font-size:0.7rem;color:#7a8fa6;margin-top:6px}",
    ".sup-tree{padding:10px 0}",
    ".sup-root{background:rgba(0,212,170,0.06);border:2px solid rgba(0,212,170,0.3);border-radius:12px;padding:14px 18px;margin-bottom:16px;display:inline-flex;align-items:center;gap:10px;cursor:pointer;transition:all 0.2s}",
    ".sup-row{display:grid;grid-template-columns:1fr;gap:10px}",
    "@media(min-width:768px){.sup-row{grid-template-columns:repeat(2,1fr)}}",
    "@media(min-width:1024px){.sup-row{grid-template-columns:repeat(4,1fr)}}",
    ".sup-col{background:rgba(10,14,23,0.5);border:1px solid rgba(30,42,58,0.5);border-radius:10px;padding:12px;transition:border-color 0.2s}",
    ".sup-col-hdr{font-size:0.78rem;font-weight:700;padding:8px 10px;border-radius:7px;margin-bottom:8px;display:flex;justify-content:space-between;align-items:center;cursor:pointer}",
    ".sup-worker{background:rgba(20,25,34,0.7);border:1px solid rgba(30,42,58,0.4);border-radius:7px;padding:9px 11px;margin-bottom:6px;font-size:0.74rem;display:flex;justify-content:space-between;align-items:center;min-height:44px;transition:all 0.2s}",
    ".sup-status-dot{width:7px;height:7px;border-radius:50%;flex-shrink:0}",
    ".sup-status-active{background:#3dd68c;box-shadow:0 0 6px rgba(61,214,140,0.5)}",
    ".sup-status-idle{background:#7a8fa6}",
    ".sup-status-busy{background:#f5a623;animation:pulseAmber 1.2s infinite}",
    ".thread-grid{display:grid;grid-template-columns:1fr;gap:8px}",
    "@media(min-width:768px){.thread-grid{grid-template-columns:repeat(2,1fr)}}",
    "@media(min-width:1200px){.thread-grid{grid-template-columns:repeat(3,1fr)}}",
    ".thread-card{background:rgba(20,25,34,0.8);border:1px solid rgba(30,42,58,0.5);border-radius:9px;padding:12px;transition:all 0.2s}",
    ".thread-name{font-family:'JetBrains Mono',monospace;font-size:0.8rem;font-weight:700;color:#e0e6ed}",
    ".thread-role{font-size:0.7rem;color:#7a8fa6;margin-top:4px;line-height:1.4}",
    ".thread-bar-wrap{margin-top:8px;height:5px;background:rgba(30,42,58,0.6);border-radius:3px;overflow:hidden}",
    ".thread-bar{height:100%;border-radius:3px;transition:width 0.6s ease}",
    ".frac-grid{display:grid;grid-template-columns:1fr;gap:10px}",
    "@media(min-width:600px){.frac-grid{grid-template-columns:repeat(2,1fr)}}",
    "@media(min-width:1024px){.frac-grid{grid-template-columns:repeat(4,1fr)}}",
    ".frac-card{border-radius:10px;padding:14px;border:1px solid;transition:all 0.25s;cursor:pointer}",
    ".frac-card-title{font-size:0.9rem;font-weight:700;margin-bottom:6px;display:flex;justify-content:space-between;align-items:center}",
    ".frac-metric{display:flex;justify-content:space-between;font-size:0.72rem;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05)}",
    ".frac-metric:last-child{border-bottom:none}",
    ".db-analytics-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:8px}",
    "@media(min-width:600px){.db-analytics-grid{grid-template-columns:repeat(3,1fr)}}",
    "@media(min-width:1024px){.db-analytics-grid{grid-template-columns:repeat(auto-fit,minmax(130px,1fr))}}",
    ".db-analytics-card{background:rgba(20,25,34,0.6);backdrop-filter:blur(4px);border:1px solid rgba(30,42,58,0.4);border-radius:10px;padding:14px;text-align:center;transition:all 0.2s}",
    ".db-analytics-card .ana-val{font-size:1.5rem;font-weight:800}",
    ".db-analytics-card .ana-lbl{font-size:0.66rem;color:#7a8fa6;margin-top:4px;letter-spacing:0.5px;text-transform:uppercase}",
    ".ooda-ring{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0}",
    ".ooda-phase{flex:1;min-width:120px;background:rgba(20,25,34,0.7);border:1px solid rgba(30,42,58,0.4);border-radius:9px;padding:12px;text-align:center;transition:all 0.3s}",
    ".ooda-phase.active-phase{border-color:rgba(0,212,170,0.5);background:rgba(0,212,170,0.06);box-shadow:0 0 12px rgba(0,212,170,0.1)}",
    ".ooda-phase-name{font-size:0.72rem;font-weight:700;text-transform:uppercase;letter-spacing:0.8px;color:#7a8fa6;margin-bottom:4px}",
    ".ooda-phase-val{font-size:1.2rem;font-weight:800;color:#e0e6ed}",
    ".ooda-phase-unit{font-size:0.65rem;color:#7a8fa6}",
    ".sched-bars{display:flex;flex-direction:column;gap:4px}",
    ".sched-row{display:flex;align-items:center;gap:8px;font-size:0.7rem}",
    ".sched-id{width:32px;color:#7a8fa6;font-family:monospace;flex-shrink:0}",
    ".sched-bar-wrap{flex:1;height:12px;background:rgba(30,42,58,0.6);border-radius:3px;overflow:hidden}",
    ".sched-bar{height:100%;transition:width 0.5s ease}",
    ".sched-pct{width:36px;color:#7a8fa6;text-align:right;flex-shrink:0}",
    ".db-change-log{max-height:220px;overflow-y:auto;font-size:0.74rem;padding:4px}",
    ".db-change-entry{padding:6px 8px;border-bottom:1px solid rgba(30,42,58,0.3);display:flex;gap:8px;align-items:flex-start}",
    ".db-change-time{color:#7a8fa6;font-family:monospace;flex-shrink:0;font-size:0.68rem}",
    ".db-change-badge{font-size:0.62rem;font-weight:700;padding:1px 7px;border-radius:8px;flex-shrink:0;white-space:nowrap}",
    ".db-change-detail{color:#e0e6ed;line-height:1.4}",
    ".db-chat-wrap{background:rgba(10,14,23,0.5);backdrop-filter:blur(8px);border:1px solid rgba(30,42,58,0.5);border-radius:12px;overflow:hidden;display:flex;flex-direction:column}",
    ".db-chat-hdr{padding:10px 14px;background:rgba(0,212,170,0.05);border-bottom:1px solid rgba(30,42,58,0.4);display:flex;justify-content:space-between;align-items:center;font-size:0.78rem;font-weight:600;color:#00d4aa}",
    ".db-chat-msgs{flex:1;overflow-y:auto;padding:10px;font-size:0.8rem;max-height:260px;min-height:120px}",
    ".db-chat-msg{padding:8px 10px;margin:5px 0;border-radius:8px;line-height:1.5}",
    ".db-chat-msg.user{background:rgba(224,230,237,0.05);border:1px solid rgba(30,42,58,0.3)}",
    ".db-chat-msg.assistant{background:rgba(0,212,170,0.05);border:1px solid rgba(0,212,170,0.1)}",
    ".db-chat-msg .msg-from{font-size:0.66rem;font-weight:700;margin-bottom:4px}",
    ".db-chat-footer{padding:8px;border-top:1px solid rgba(30,42,58,0.4);display:flex;gap:6px}",
    ".db-chat-input{flex:1;background:rgba(10,14,23,0.6);border:1px solid rgba(30,42,58,0.6);color:#e0e6ed;padding:10px 14px;border-radius:8px;font-size:0.82rem;outline:none;min-height:44px;transition:border-color 0.2s}",
    ".db-chat-send{background:linear-gradient(135deg,#00d4aa,#00b894);color:#0a0e17;border:none;padding:10px 16px;border-radius:8px;font-weight:700;min-height:44px;cursor:pointer;font-size:0.82rem;transition:opacity 0.2s;white-space:nowrap}",
    ".db-search-results{background:rgba(10,14,23,0.95);backdrop-filter:blur(16px);border:1px solid rgba(30,42,58,0.6);border-radius:10px;margin-top:4px;max-height:280px;overflow-y:auto;display:none;animation:fadeSlideIn 0.2s ease-out}",
    ".db-search-result{padding:10px 14px;border-bottom:1px solid rgba(30,42,58,0.3);cursor:pointer;font-size:0.8rem;transition:background 0.15s;min-height:44px;display:flex;align-items:center}",
    ".db-weather-bar{background:rgba(20,25,34,0.6);backdrop-filter:blur(8px);border:1px solid rgba(30,42,58,0.4);border-radius:10px;padding:10px 16px;display:flex;align-items:center;gap:12px;flex-wrap:wrap;font-size:0.8rem;margin-bottom:10px}",
    ".db-weather-mood{font-size:1.1rem}",
    ".db-weather-label{font-weight:700}",
    ".db-weather-score{font-family:monospace;font-size:0.78rem;color:#7a8fa6}",
    ".db-weather-divider{width:1px;height:16px;background:rgba(30,42,58,0.6);flex-shrink:0}",
    ".db-weather-meta{font-size:0.72rem;color:#7a8fa6}",
    ".zenoh-card{background:rgba(20,25,34,0.8);border:1px solid rgba(231,76,60,0.2);border-radius:9px;padding:11px;min-height:44px;display:flex;align-items:center;gap:10px;font-size:0.78rem}",
    ".zenoh-card .z-name{font-family:monospace;font-weight:700;color:#e0e6ed}",
    ".zenoh-card .z-meta{font-size:0.68rem;color:#7a8fa6}",
    ".db-section{animation:fadeSlideIn 0.3s ease-out}",
    "button,a,[role=button]{min-height:44px}",
  ].join("\n");
  document.head.appendChild(s);
}

// ─── Entry ─────────────────────────────────────────────────────────

function init(): void {
  injectStyles();
  ensureDom();
  initViewToggle();
  initFractalChips();
  initSearch();
  initGemmaChat();
  initKeyboard();
  startHeartbeatMonitor();
  initWebSocket();

  renderWeatherBar({});
  renderTaskSummary({});
  renderGridView({});
  renderChangeLog();

  startPollingTicker();
  pollStatus();

  logChange("ws_event", "Dashboard initialized (v2.0 Effect-TS — SC-AGUI-UI-001)");
  document.body.setAttribute("data-dashboard-grid-wired", "1");
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
