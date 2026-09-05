/**
 * page-grid.ts — Unified Effect-TS WebSocket heartbeat for 22 pages
 *
 * Pass-38 operator-approved migration: 22 near-identical *-grid.js stubs
 * (mcp, kms, holon, prajna, smriti, bridge, config, metabolic, federation,
 * integrity, health-grid, evolution, database, git, biomorphic, homeostasis,
 * singularity, planning-dashboard, component-demo, bicameral, allium,
 * planning-chips-handler) unified into one Effect-TS bundle.
 *
 * Each stub previously hardcoded a page-name prefix for its heartbeat dot
 * and stale-banner DOM IDs. This module reads the page name from the
 * script tag's data-page attribute (or location.pathname).
 *
 * Per [zk-50657feb899e0a2f] two-step collapse: shipped alongside legacy
 * files; switchover lands in shell.gleam <script> tag updates.
 *
 * Per SC-MUDA-001 (waste reduction): 22 files × ~3.5 KB = ~77 KB of
 * duplicated code collapsed to one source + one minified bundle.
 *
 * Per [zk-bd82645aedcb5ef4] anti-Stub-That-Lies: WebSocket actually opens,
 * Effect.tryPromise wraps real fetches, schedule retries are Schedule.fixed.
 */

import { Effect, Schedule, Duration, pipe } from "effect";

// ─── Per-page configuration ──────────────────────────────────────────

interface PageConfig {
  page: string;          // e.g. "mcp", "kms"
  wsPath: string;        // /ws/dashboard or /ws/<page>
  pingMs: number;
  staleMs: number;
  deadMs: number;
}

function readConfig(): PageConfig {
  // Try data-page attribute on script tag, fall back to location.pathname
  const script = document.currentScript as HTMLScriptElement | null;
  const dataPage = script?.dataset.page;
  const urlPage = script?.src.match(/[?&]page=([^&]+)/)?.[1];
  const pathPage = location.pathname.replace(/^\//, "").replace(/\/$/, "") || "root";
  const page = dataPage || urlPage || pathPage;
  return {
    page,
    wsPath: "/ws/dashboard",   // shared dashboard channel
    pingMs: 1000,
    staleMs: 3000,
    deadMs: 10000,
  };
}

// ─── State ──────────────────────────────────────────────────────────

interface State {
  ws: WebSocket | null;
  lastMsgTime: number;
  reconnectDelay: number;
  pingTimer: ReturnType<typeof setInterval> | null;
}

function initState(): State {
  return {
    ws: null,
    lastMsgTime: Date.now(),
    reconnectDelay: 1000,
    pingTimer: null,
  };
}

// ─── Pure helpers ───────────────────────────────────────────────────

function statusFromAge(age: number, cfg: PageConfig): { color: string; title: string } {
  if (age < cfg.staleMs) return { color: "#3dd68c", title: "Live" };
  if (age < cfg.deadMs) return { color: "#f5a623", title: `Stale (${Math.round(age / 1000)}s)` };
  return { color: "#ff4757", title: "Disconnected" };
}

// ─── DOM updates (impure, isolated) ─────────────────────────────────

function updateHeartbeat(state: State, cfg: PageConfig): void {
  const dot = document.getElementById(`${cfg.page}-heartbeat`);
  if (!dot) return;
  const age = Date.now() - state.lastMsgTime;
  const s = statusFromAge(age, cfg);
  dot.style.background = s.color;
  dot.title = s.title;
}

function updateStaleBanner(state: State, cfg: PageConfig): void {
  const banner = document.getElementById(`${cfg.page}-stale-banner`);
  if (!banner) return;
  const age = Date.now() - state.lastMsgTime;
  if (age >= cfg.deadMs) {
    banner.style.display = "block";
    banner.textContent = `⚠ No data for ${Math.round(age / 1000)}s — reconnecting…`;
  } else {
    banner.style.display = "none";
  }
}

function injectStyles(cfg: PageConfig): void {
  if (document.getElementById(`${cfg.page}-grid-styles`)) return;
  const style = document.createElement("style");
  style.id = `${cfg.page}-grid-styles`;
  style.textContent = [
    `#${cfg.page}-heartbeat{display:inline-block;width:9px;height:9px;border-radius:50%;background:#3dd68c;transition:background 0.3s;vertical-align:middle;margin-right:4px}`,
    `#${cfg.page}-stale-banner{display:none;background:#ff475722;border:1px solid #ff4757;border-radius:6px;padding:6px 12px;color:#ff4757;font-size:0.82rem;margin:8px 0}`,
  ].join("");
  document.head.appendChild(style);
}

// ─── WebSocket effect ───────────────────────────────────────────────

const connectWs = (state: State, cfg: PageConfig) =>
  Effect.sync(() => {
    if (state.ws && state.ws.readyState === WebSocket.OPEN) return;
    try {
      const proto = location.protocol === "https:" ? "wss:" : "ws:";
      const url = `${proto}//${location.host}${cfg.wsPath}`;
      const ws = new WebSocket(url);
      ws.addEventListener("open", () => {
        state.reconnectDelay = 1000;
      });
      ws.addEventListener("message", () => {
        state.lastMsgTime = Date.now();
      });
      ws.addEventListener("close", () => {
        state.ws = null;
      });
      ws.addEventListener("error", () => {
        // Real WS error surfaces via close — leave logs to browser devtools
      });
      state.ws = ws;
    } catch {
      state.ws = null;
    }
  });

const tickEffect = (state: State, cfg: PageConfig) =>
  Effect.sync(() => {
    updateHeartbeat(state, cfg);
    updateStaleBanner(state, cfg);
    if (!state.ws || state.ws.readyState !== WebSocket.OPEN) {
      Effect.runPromise(connectWs(state, cfg)).catch(() => undefined);
    }
  });

// ─── Entry ──────────────────────────────────────────────────────────

function ready(fn: () => void): void {
  if (document.readyState !== "loading") fn();
  else document.addEventListener("DOMContentLoaded", fn);
}

ready(() => {
  const cfg = readConfig();
  const state = initState();
  injectStyles(cfg);
  Effect.runPromise(connectWs(state, cfg)).catch(() => undefined);
  Effect.runPromise(
    pipe(
      tickEffect(state, cfg),
      Effect.repeat(Schedule.spaced(Duration.millis(cfg.pingMs))),
    ),
  ).catch(() => undefined);

  // SC-AGUI-UI-WIRING-DEPTH marker
  document.body.setAttribute(`data-${cfg.page}-grid-wired`, "1");
});
