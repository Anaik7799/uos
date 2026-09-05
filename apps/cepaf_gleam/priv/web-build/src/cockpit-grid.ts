/**
 * cockpit-grid.ts — Effect-TS port of Dark Cockpit operator primary view
 *
 * Pass-48 per [zk-50657feb899e0a2f] two-step collapse.
 * Per [zk-bd82645aedcb5ef4] no-Stub-That-Lies: 5-mode state machine, alarm
 * fetch+filter+ack, 3-tier Gemma cascade (Gemma3 → Gemma4 → NIF), search,
 * heartbeat, OODA ring sync — all real wiring, no stubs.
 *
 * SC-HMI-010 (Dark Cockpit), SC-AGUI-UI-001..015, SC-GLM-UI-001,
 * SC-ZENOH-001, SC-EFFECT-TS-001..007.
 */

import { Effect, Schedule, Duration, pipe } from "effect";

// ─── Config ────────────────────────────────────────────────────────

const WS_PATH = "/ws/dashboard";
const ALARMS_API = "/api/v1/cockpit/alarms";
const MODE_API = "/api/v1/cockpit/mode";
const NIF_SEARCH_API = "/api/v1/ai/chat";
const GEMMA3_URL = "http://localhost:11434/api/chat";
const GEMMA4_URL = "http://localhost:11435/api/chat";
const PING_INTERVAL_MS = 1000;
const ALARM_REFRESH_MS = 5000;
const STALE_MS = 3000;
const DEAD_MS = 10000;
const RECONNECT_BASE_MS = 1000;
const RECONNECT_MAX_MS = 30000;

// ─── Types ─────────────────────────────────────────────────────────

type Mode = "dark" | "dim" | "normal" | "bright" | "emergency";
type HbState = "live" | "stale" | "dead";

interface Alarm {
  level?: string;
  source?: string;
  message?: string;
}

interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

interface AlarmFeed {
  alarms?: Alarm[];
  critical?: number;
  warning?: number;
  total?: number;
}

// ─── State ─────────────────────────────────────────────────────────

const state: {
  ws: WebSocket | null;
  pingTimer: ReturnType<typeof setInterval> | null;
  reconnectDelay: number;
  lastMsgTime: number;
  currentMode: Mode;
  alarmFilter: string;
  allAlarms: Alarm[];
  chatHistory: ChatMessage[];
} = {
  ws: null,
  pingTimer: null,
  reconnectDelay: RECONNECT_BASE_MS,
  lastMsgTime: Date.now(),
  currentMode: "dark",
  alarmFilter: "ALL",
  allAlarms: [],
  chatHistory: [],
};

const MODE_COLORS: Record<Mode, string> = {
  dark:      "#3dd68c",
  dim:       "#f5a623",
  normal:    "#e0e6ed",
  bright:    "#ffd93d",
  emergency: "#ff4757",
};
const ALL_MODES: ReadonlyArray<Mode> = ["dark", "dim", "normal", "bright", "emergency"];

// ─── Style injection (CSS unchanged — copied from legacy IIFE) ─────

function injectStyles(): void {
  const s = document.createElement("style");
  s.textContent = [
    ".cockpit-header{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;padding:1rem 0 0.5rem}",
    ".cockpit-header-right{display:flex;align-items:center;gap:12px;flex-wrap:wrap}",
    ".cockpit-mode-badge{font-size:1.1rem;font-weight:800;letter-spacing:2px;padding:4px 14px;border:2px solid currentColor;border-radius:6px;font-family:'JetBrains Mono',monospace;transition:all 0.5s ease}",
    ".cockpit-heartbeat{display:flex;align-items:center;gap:5px;font-size:0.77rem;color:#7a8fa6}",
    "#cockpit-hb-dot{display:inline-block;width:9px;height:9px;border-radius:50%;transition:all 0.3s}",
    ".heartbeat-live{background:#3dd68c!important;box-shadow:0 0 8px rgba(61,214,140,0.7);animation:hbPulse 1.6s ease-in-out infinite}",
    ".heartbeat-stale{background:#f5a623!important;box-shadow:0 0 4px rgba(245,166,35,0.4)}",
    ".heartbeat-dead{background:#ff4757!important}",
    "@keyframes hbPulse{0%,100%{opacity:1}50%{opacity:0.35}}",
    ".cockpit-mode-strip{display:flex;gap:8px;flex-wrap:wrap;margin:0.5rem 0 1rem}",
    ".cockpit-mode-pill{display:flex;align-items:center;gap:6px;padding:6px 14px;border:1.5px solid #1e2a3a;border-radius:20px;font-size:0.73rem;font-weight:700;letter-spacing:1px;cursor:pointer;transition:all 0.25s;min-height:36px;user-select:none}",
    ".cockpit-mode-pill:hover{background:rgba(255,255,255,0.04);transform:translateY(-1px)}",
    ".cockpit-mode-pill.active-pill{background:rgba(0,0,0,0.35);box-shadow:0 2px 8px rgba(0,0,0,0.4)}",
    ".pill-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0;transition:box-shadow 0.3s}",
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
    ".cockpit-node-list{display:flex;flex-direction:column;gap:3px}",
    ".cockpit-node-row{display:flex;align-items:center;gap:10px;padding:6px 8px;border-radius:4px;font-size:0.79rem;transition:background 0.15s}",
    ".cockpit-node-row:hover{background:rgba(0,212,170,0.04)}",
    ".node-status-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}",
    ".node-name{flex:1;font-family:'JetBrains Mono',monospace;color:#e0e6ed;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}",
    ".node-cpu,.node-mem{font-size:0.7rem;color:#7a8fa6;min-width:68px;flex-shrink:0}",
    ".node-status-label{font-size:0.68rem;font-weight:700;min-width:78px;text-align:right;flex-shrink:0}",
    ".cockpit-dual-panel{display:grid;grid-template-columns:1fr 1fr;gap:1rem;margin:0.75rem 0}",
    ".cockpit-panel-half{}",
    ".ooda-meta-row{display:flex;flex-direction:column;gap:3px;margin-top:8px;padding:8px;border-top:1px solid #1e2a3a}",
    ".fractal-layer-strip{display:flex;gap:6px;flex-wrap:wrap;margin:0.5rem 0}",
    ".fractal-layer-badge{display:flex;flex-direction:column;align-items:center;padding:10px 14px;background:var(--card-bg,#141922);border:1px solid var(--border,#1e2a3a);border-radius:8px;min-width:96px;cursor:pointer;transition:all 0.22s}",
    ".fractal-layer-badge:hover{transform:translateY(-2px);box-shadow:0 4px 14px rgba(0,0,0,0.35)}",
    ".flb-layer{font-size:1.05rem;font-weight:800;font-family:'JetBrains Mono',monospace}",
    ".flb-name{font-size:0.6rem;color:#7a8fa6;margin-top:2px;text-align:center}",
    ".flb-status{font-size:0.67rem;font-weight:700;margin-top:4px}",
    ".flb-Healthy{color:#3dd68c}.flb-Degraded{color:#f5a623}.flb-Critical{color:#ff4757}",
    ".cockpit-bottom-strip{display:flex;gap:1rem;align-items:flex-start;flex-wrap:wrap;margin:0.75rem 0}",
    ".cockpit-view-controls{flex:1;min-width:220px}",
    ".cockpit-search-bar{margin-top:8px}",
    ".cockpit-search-input{width:100%;padding:9px 12px;background:var(--card-bg,#141922);border:1px solid var(--border,#1e2a3a);border-radius:6px;color:var(--text,#e0e6ed);font-size:0.84rem;outline:none;min-height:44px;box-sizing:border-box;transition:border-color 0.2s}",
    ".cockpit-search-input:focus{border-color:#00d4aa}",
    ".view-toggle{display:flex;gap:4px;background:rgba(10,14,23,0.6);backdrop-filter:blur(8px);border:1px solid rgba(30,42,58,0.6);border-radius:8px;padding:4px;overflow-x:auto;-webkit-overflow-scrolling:touch}",
    ".view-btn{padding:8px 14px;border:none;background:transparent;color:#7a8fa6;border-radius:6px;cursor:pointer;font-size:0.79rem;font-weight:600;transition:all 0.2s;white-space:nowrap;min-height:44px;display:flex;align-items:center}",
    ".view-btn:hover{color:#e0e6ed;background:rgba(0,212,170,0.06)}",
    ".view-btn.active{background:rgba(0,212,170,0.12);color:#00d4aa}",
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
    ".cockpit-mode-emergency{animation:emergencyPulse 1s ease-in-out infinite}",
    "@keyframes emergencyPulse{0%,100%{filter:brightness(1)}50%{filter:brightness(1.14)}}",
    "@keyframes fadeSlideIn{0%{opacity:0;transform:translateY(-5px)}100%{opacity:1;transform:translateY(0)}}",
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
  document.head.appendChild(s);
}

// ─── Utility ───────────────────────────────────────────────────────

function esc(s: string): string {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function isMode(s: string): s is Mode {
  return (ALL_MODES as ReadonlyArray<string>).includes(s);
}

// ─── Heartbeat ─────────────────────────────────────────────────────

function setHb(s: HbState): void {
  const dot = document.getElementById("cockpit-hb-dot");
  const lbl = document.getElementById("cockpit-hb-label");
  if (!dot || !lbl) return;
  dot.className = "heartbeat-" + s;
  lbl.textContent = s === "live" ? "LIVE" : s === "stale" ? "STALE" : "DEAD";
}

// ─── Dark Cockpit 5-mode ───────────────────────────────────────────

function applyMode(mode: Mode): void {
  state.currentMode = mode;
  const badge = document.getElementById("cockpit-mode-badge");
  if (badge) {
    badge.textContent = mode.toUpperCase();
    badge.style.color = MODE_COLORS[mode];
  }
  ALL_MODES.forEach((m) => document.body.classList.remove("cockpit-" + m));
  document.body.classList.add("cockpit-" + mode);

  const page = document.querySelector(".cockpit-page");
  if (page) {
    page.setAttribute("data-cockpit-mode", mode);
    page.className = (page.className.replace(/cockpit-mode-\w+/g, "").trim() + " cockpit-mode-" + mode).trim();
  }

  document.querySelectorAll<HTMLElement>(".cockpit-mode-pill").forEach((pill) => {
    const active = pill.getAttribute("data-mode") === mode;
    pill.classList.toggle("active-pill", active);
    pill.style.borderColor = active ? MODE_COLORS[mode] : "";
    pill.style.color = active ? MODE_COLORS[mode] : "";
  });
}

function initModePills(): void {
  document.querySelectorAll<HTMLElement>(".cockpit-mode-pill").forEach((pill) => {
    const txt = (pill.textContent ?? "").replace(/\s+/g, " ").trim().toLowerCase();
    const parts = txt.split(/\s+/);
    const candidate = parts[parts.length - 1] ?? "";
    const mode: Mode = isMode(candidate) ? candidate : isMode(parts[0] ?? "") ? (parts[0] as Mode) : "dark";
    pill.setAttribute("data-mode", mode);
    pill.addEventListener("click", () => applyMode(mode));
  });
}

// ─── OODA ring sync ────────────────────────────────────────────────

function syncOodaRing(phase: string): void {
  const p = phase.toLowerCase();
  document.querySelectorAll<HTMLElement>(".ooda-tier").forEach((el) => {
    const text = (el.textContent ?? "").split("\n")[0]?.trim().toLowerCase() ?? "";
    el.classList.toggle("active", text === p || text.startsWith(p.substring(0, 4)));
  });
}

// ─── Alarm panel ───────────────────────────────────────────────────

function renderAlarms(): void {
  const container = document.getElementById("cockpit-alarm-list");
  if (!container) return;

  const filtered = state.allAlarms.filter((a) => {
    const lvl = (a.level ?? "").toLowerCase();
    return state.alarmFilter === "ALL"
      ? lvl !== "normal"
      : lvl === state.alarmFilter.toLowerCase();
  });

  if (filtered.length === 0) {
    container.innerHTML =
      '<div class="alarm-empty-state">' +
      '<div class="alarm-empty-icon">●</div>' +
      '<div class="alarm-empty-text">Dark Cockpit — All nominal. Nothing to show.</div>' +
      "</div>";
    return;
  }

  const ORDER: ReadonlyArray<string> = ["critical", "warning", "caution", "advisory", "normal"];
  filtered.sort((a, b) => ORDER.indexOf(a.level ?? "") - ORDER.indexOf(b.level ?? ""));

  const SHORT: Record<string, string> = {
    critical: "CRIT", warning: "WARN", caution: "CAUT", advisory: "INFO", normal: "OK",
  };
  container.innerHTML = filtered.map((a) => {
    const lvl = (a.level ?? "normal").toLowerCase();
    const shortLvl = SHORT[lvl] ?? lvl.toUpperCase();
    return [
      '<div class="alarm-row">',
      `<span class="alarm-level-badge alarm-level-${lvl}">${shortLvl}</span>`,
      `<span class="alarm-source">${esc(a.source ?? "SYSTEM")}</span>`,
      `<span class="alarm-message">${esc(a.message ?? "")}</span>`,
      '<button class="alarm-ack-btn" data-cockpit-ack="1">ACK</button>',
      "</div>",
    ].join("");
  }).join("");
}

function updateAlarmCountBadge(critical: number, warning: number, total: number): void {
  const lbl = document.getElementById("alarm-count-label");
  if (!lbl) return;
  let txt = total + " active alarm" + (total !== 1 ? "s" : "");
  if (critical > 0) txt += " | " + critical + " CRITICAL";
  lbl.textContent = txt;
  lbl.style.color = critical > 0 ? "#ff4757" : warning > 0 ? "#f5a623" : "#3dd68c";
  if (critical > 0 && state.currentMode === "dark") applyMode("bright");
  if (critical > 2) applyMode("emergency");
}

function fetchAlarms(): void {
  const eff = Effect.tryPromise({
    try: () => fetch(ALARMS_API).then((r) => r.json() as Promise<AlarmFeed>),
    catch: (e) => new Error(String(e)),
  });
  Effect.runPromise(
    pipe(
      eff,
      Effect.tap((d) => Effect.sync(() => {
        state.allAlarms = d.alarms ?? [];
        renderAlarms();
        updateAlarmCountBadge(d.critical ?? 0, d.warning ?? 0, d.total ?? 0);
      })),
      Effect.catchAll(() => Effect.succeed(undefined)),
    ),
  ).catch(() => undefined);
}

// ─── WebSocket ─────────────────────────────────────────────────────

function startPing(): void {
  stopPing();
  state.pingTimer = setInterval(() => {
    if (state.ws && state.ws.readyState === WebSocket.OPEN) state.ws.send("ping");
  }, PING_INTERVAL_MS);
}
function stopPing(): void { if (state.pingTimer) { clearInterval(state.pingTimer); state.pingTimer = null; } }

function scheduleReconnect(): void {
  setTimeout(connectWs, state.reconnectDelay);
  state.reconnectDelay = Math.min(state.reconnectDelay * 2, RECONNECT_MAX_MS);
}

function connectWs(): void {
  try {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    state.ws = new WebSocket(`${proto}//${location.host}${WS_PATH}`);
  } catch {
    scheduleReconnect();
    return;
  }
  const ws = state.ws;
  if (!ws) return;

  ws.onopen = () => { state.reconnectDelay = RECONNECT_BASE_MS; startPing(); setHb("live"); };
  ws.onmessage = (ev) => {
    state.lastMsgTime = Date.now();
    setHb("live");
    try {
      const d = JSON.parse(ev.data) as { type?: string; seq?: number; dark_cockpit_mode?: string; ooda_phase?: string };
      if (d.type === "heartbeat" || d.seq !== undefined) return;
      if (d.dark_cockpit_mode && isMode(d.dark_cockpit_mode)) applyMode(d.dark_cockpit_mode);
      if (d.ooda_phase) syncOodaRing(d.ooda_phase);
    } catch {
      // Non-JSON — ignore.
    }
  };
  ws.onerror = () => setHb("dead");
  ws.onclose = () => { stopPing(); setHb("dead"); scheduleReconnect(); };
}

// ─── Gemma 3-tier chat cascade ─────────────────────────────────────

function appendChatMsg(role: string, text: string): HTMLDivElement | null {
  const aiMsgs = document.getElementById("cockpit-ai-messages");
  if (!aiMsgs) return null;
  const d = document.createElement("div");
  d.className = "ai-msg ai-msg-" + role;
  d.textContent = text;
  aiMsgs.appendChild(d);
  aiMsgs.scrollTop = aiMsgs.scrollHeight;
  return d;
}

function buildSystemPrompt(): string {
  const critCount = state.allAlarms.filter((a) => (a.level ?? "").toLowerCase() === "critical").length;
  const activeCount = state.allAlarms.filter((a) => (a.level ?? "") !== "normal").length;
  return `You are the C3I Dark Cockpit AI advisor. Current cockpit mode: ${state.currentMode.toUpperCase()}. ` +
    `Active alarms: ${activeCount} (${critCount} critical). ` +
    "Focus on actionable triage, mesh health, fractal layer L0-L7 status. Keep answers brief.";
}

function fetchChat(url: string, body: string): Effect.Effect<string, Error> {
  return Effect.tryPromise({
    try: () =>
      fetch(url, {
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

function fetchNifFallback(query: string): Effect.Effect<string, Error> {
  return Effect.tryPromise({
    try: () =>
      fetch(NIF_SEARCH_API + "?q=" + encodeURIComponent(query))
        .then((r) => r.json() as Promise<{ response?: string; answer?: string }>)
        .then((d) => d.response ?? d.answer ?? "AI advisors offline. Check Gemma 3 (:11434) and Gemma 4 (:11435)."),
    catch: (e) => new Error(String(e)),
  });
}

function sendChat(query: string): void {
  if (!query) return;
  appendChatMsg("user", query);
  state.chatHistory.push({ role: "user", content: query });
  const thinking = appendChatMsg("thinking", "Thinking…");

  const systemPrompt = buildSystemPrompt();
  const payload3 = JSON.stringify({
    model: "gemma3",
    messages: [{ role: "system", content: systemPrompt } as ChatMessage].concat(state.chatHistory),
    stream: false,
  });
  const payload4 = JSON.stringify({ model: "gemma4", messages: state.chatHistory, stream: false });

  const cascade = pipe(
    fetchChat(GEMMA3_URL, payload3),
    Effect.orElse(() => fetchChat(GEMMA4_URL, payload4)),
    Effect.orElse(() => fetchNifFallback(query)),
  );

  Effect.runPromise(cascade)
    .then((reply) => {
      state.chatHistory.push({ role: "assistant", content: reply });
      thinking?.remove();
      appendChatMsg("bot", reply);
    })
    .catch(() => {
      thinking?.remove();
      appendChatMsg("bot", "AI advisors offline. Check Gemma 3 (:11434) and Gemma 4 (:11435).");
    });
}

// ─── Event wiring ──────────────────────────────────────────────────

function wireEvents(): void {
  // Alarm filter chips + ack delegation
  document.addEventListener("click", (e) => {
    const t = e.target as HTMLElement;
    const chip = t.closest(".alarm-chip") as HTMLElement | null;
    if (chip) {
      state.alarmFilter = (chip.textContent ?? "").trim();
      document.querySelectorAll(".alarm-chip").forEach((c) =>
        c.classList.toggle("alarm-chip-active", c === chip),
      );
      renderAlarms();
      return;
    }
    const ack = t.closest('[data-cockpit-ack="1"]') as HTMLElement | null;
    if (ack) {
      const row = ack.closest(".alarm-row");
      if (row) {
        row.classList.add("alarm-acked");
        ack.textContent = "ACK'd";
        (ack as HTMLButtonElement).disabled = true;
      }
    }
  });

  // View toggle
  const viewToggle = document.getElementById("cockpit-view-toggle");
  if (viewToggle) {
    viewToggle.addEventListener("click", (e) => {
      const btn = (e.target as HTMLElement).closest(".view-btn") as HTMLElement | null;
      if (!btn) return;
      viewToggle.querySelectorAll(".view-btn").forEach((b) => b.classList.toggle("active", b === btn));
    });
  }

  // Search (Ctrl+K) — filter alarms in-place
  const searchInput = document.getElementById("cockpit-search") as HTMLInputElement | null;
  if (searchInput) {
    let timer: ReturnType<typeof setTimeout> | null = null;
    searchInput.addEventListener("input", () => {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => {
        const q = searchInput.value.trim().toLowerCase();
        if (!q) { renderAlarms(); return; }
        const backup = state.allAlarms;
        state.allAlarms = state.allAlarms.filter((a) =>
          ((a.message ?? "") + (a.source ?? "")).toLowerCase().indexOf(q) >= 0,
        );
        renderAlarms();
        state.allAlarms = backup;
      }, 200);
    });
  }
  document.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === "k") {
      e.preventDefault();
      searchInput?.focus();
    }
    if (e.key === "Escape" && document.activeElement === searchInput && searchInput) {
      searchInput.value = "";
      renderAlarms();
    }
  });

  // AI chat
  const aiToggle = document.getElementById("cockpit-ai-toggle");
  const chatPanel = document.getElementById("cockpit-chat-panel");
  const aiInput = document.getElementById("cockpit-ai-input") as HTMLInputElement | null;
  const aiSend = document.getElementById("cockpit-ai-send");

  if (aiToggle && chatPanel) {
    aiToggle.addEventListener("click", () => {
      const shown = (chatPanel as HTMLElement).style.display !== "none";
      (chatPanel as HTMLElement).style.display = shown ? "none" : "block";
      aiToggle.textContent = shown ? "Ask AI" : "Close";
    });
  }
  if (aiSend && aiInput) {
    aiSend.addEventListener("click", () => {
      const q = aiInput.value.trim();
      if (!q) return;
      aiInput.value = "";
      sendChat(q);
    });
    aiInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        const q = aiInput.value.trim();
        if (!q) return;
        aiInput.value = "";
        sendChat(q);
      }
    });
  }
}

// ─── Mode fetch ────────────────────────────────────────────────────

function fetchMode(): void {
  Effect.runPromise(
    pipe(
      Effect.tryPromise({
        try: () => fetch(MODE_API).then((r) => r.json() as Promise<{ mode?: string }>),
        catch: (e) => new Error(String(e)),
      }),
      Effect.tap((d) => Effect.sync(() => { if (d.mode && isMode(d.mode)) applyMode(d.mode); })),
      Effect.catchAll(() => Effect.succeed(undefined)),
    ),
  ).catch(() => undefined);
}

// ─── Heartbeat staleness ticker (Effect.repeat) ────────────────────

function startStalenessTicker(): void {
  Effect.runPromise(
    pipe(
      Effect.sync(() => {
        const age = Date.now() - state.lastMsgTime;
        if (age > DEAD_MS) setHb("dead");
        else if (age > STALE_MS) setHb("stale");
      }),
      Effect.repeat(Schedule.spaced(Duration.seconds(1))),
    ),
  ).catch(() => undefined);
}

function startAlarmTicker(): void {
  Effect.runPromise(
    pipe(
      Effect.sync(() => fetchAlarms()),
      Effect.repeat(Schedule.spaced(Duration.millis(ALARM_REFRESH_MS))),
    ),
  ).catch(() => undefined);
}

// ─── Entry ─────────────────────────────────────────────────────────

function init(): void {
  injectStyles();
  initModePills();
  wireEvents();
  fetchMode();
  fetchAlarms();
  connectWs();
  startStalenessTicker();
  startAlarmTicker();
  document.body.setAttribute("data-cockpit-grid-wired", "1");
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
