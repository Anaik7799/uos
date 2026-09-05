/**
 * grid-base.ts — shared Effect-TS skeleton for per-page mid-size grid bundles
 *
 * Pass-41 architectural foundation. Each *-grid page (immune, knowledge,
 * substrate, podman, agents, zenoh, telemetry, cockpit, dashboard) shares
 * the same WebSocket + heartbeat skeleton with page-specific rendering.
 * This module exports typed primitives that per-page modules import.
 *
 * Per [zk-bd82645aedcb5ef4] no-Stub-That-Lies: WebSocket actually connects,
 * Effect.repeat actually ticks, prefix-parameterised DOM IDs land on the
 * real page.
 *
 * SC-EFFECT-TS-001..020, SC-MUDA-001 (waste reduction via shared base).
 */

import { Effect, Schedule, Duration, pipe } from "effect";

// ─── Types ──────────────────────────────────────────────────────────

export interface GridConfig {
  /** DOM-ID prefix, e.g. "imm" for immune-grid → #imm-heartbeat */
  prefix: string;
  /** WebSocket endpoint, e.g. "/ws/dashboard" */
  wsPath: string;
  /** Initial heartbeat status text */
  initialStatus: string;
  /** Live heartbeat status text after first WS message */
  liveStatus: string;
  /** Optional STAMP family for reflection */
  stampRef?: string;
}

export interface GridState {
  cfg: GridConfig;
  lastMsgTime: number;
  ws: WebSocket | null;
  wsConnected: boolean;
  reconnectDelay: number;
  pingTimer: ReturnType<typeof setInterval> | null;
  heartbeatEl: HTMLDivElement | null;
  /** Per-page WS message handler */
  onMessage: (data: unknown) => void;
}

// ─── Constants ──────────────────────────────────────────────────────

const STALE_MS = 3000;
const DEAD_MS = 10000;

// ─── State helpers ──────────────────────────────────────────────────

export function makeState(cfg: GridConfig, onMessage: (data: unknown) => void): GridState {
  return {
    cfg,
    lastMsgTime: Date.now(),
    ws: null,
    wsConnected: false,
    reconnectDelay: 1000,
    pingTimer: null,
    heartbeatEl: null,
    onMessage,
  };
}

// ─── Heartbeat ──────────────────────────────────────────────────────

export function injectHeartbeatBase(state: GridState): void {
  const el = document.createElement("div");
  el.id = `${state.cfg.prefix}-heartbeat`;
  el.innerHTML = `<span class="${state.cfg.prefix}-dot"></span><span id="${state.cfg.prefix}-hb-text">${state.cfg.initialStatus}</span>`;
  const hdr = document.querySelector(".page-header");
  if (hdr) hdr.insertAdjacentElement("afterend", el);
  else document.body.prepend(el);
  state.heartbeatEl = el;
}

export function injectHeartbeatStyles(prefix: string): string {
  return [
    `#${prefix}-heartbeat{display:inline-flex;align-items:center;gap:6px;font-size:0.78rem;`,
    "padding:4px 12px;border-radius:20px;background:rgba(0,212,170,0.1);",
    "border:1px solid rgba(0,212,170,0.3);margin-bottom:12px;transition:all 0.3s}",
    `#${prefix}-heartbeat.stale{border-color:rgba(245,166,35,0.4);background:rgba(245,166,35,0.1)}`,
    `#${prefix}-heartbeat.dead{border-color:rgba(255,71,87,0.4);background:rgba(255,71,87,0.1)}`,
    `.${prefix}-dot{width:8px;height:8px;border-radius:50%;background:#3dd68c;animation:${prefix}pulse 1.5s infinite}`,
    `@keyframes ${prefix}pulse{0%,100%{opacity:1}50%{opacity:0.3}}`,
  ].join("");
}

export function updateHeartbeat(state: GridState): void {
  if (!state.heartbeatEl) return;
  const age = Date.now() - state.lastMsgTime;
  const dot = state.heartbeatEl.querySelector<HTMLElement>(`.${state.cfg.prefix}-dot`);
  const txt = document.getElementById(`${state.cfg.prefix}-hb-text`);
  state.heartbeatEl.className = age > DEAD_MS ? "dead" : age > STALE_MS ? "stale" : "";
  if (dot) dot.style.background = age > DEAD_MS ? "#ff4757" : age > STALE_MS ? "#f5a623" : "#3dd68c";
  if (txt) {
    txt.textContent = state.wsConnected
      ? state.cfg.liveStatus
      : age > DEAD_MS ? `${state.cfg.prefix.toUpperCase()} mesh disconnected` : "Reconnecting...";
  }
}

// ─── WebSocket ──────────────────────────────────────────────────────

export function connectWs(state: GridState): void {
  if (state.ws) {
    try { state.ws.close(); } catch { /* closed-on-closed is no-op */ }
  }
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  const ws = new WebSocket(`${proto}//${location.host}${state.cfg.wsPath}`);
  state.ws = ws;

  ws.onopen = () => {
    state.wsConnected = true;
    state.reconnectDelay = 1000;
    state.lastMsgTime = Date.now();
    state.pingTimer = setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) ws.send("ping");
    }, 1000);
  };

  ws.onmessage = (e) => {
    state.lastMsgTime = Date.now();
    try {
      const d = JSON.parse(e.data);
      state.onMessage(d);
    } catch {
      // Non-JSON message — ignored.
    }
    updateHeartbeat(state);
  };

  ws.onclose = () => {
    state.wsConnected = false;
    if (state.pingTimer) clearInterval(state.pingTimer);
    setTimeout(() => connectWs(state), Math.min(state.reconnectDelay, 30000));
    state.reconnectDelay *= 2;
  };

  ws.onerror = () => { ws.close(); };
}

// ─── Heartbeat ticker — Effect.repeat replaces hand-rolled setInterval ──

export function startHeartbeatTicker(state: GridState): void {
  Effect.runPromise(
    pipe(
      Effect.sync(() => updateHeartbeat(state)),
      Effect.repeat(Schedule.spaced(Duration.seconds(1))),
    ),
  ).catch(() => undefined);
}

// ─── DOM ready helper ──────────────────────────────────────────────

export function ready(fn: () => void): void {
  if (document.readyState !== "loading") fn();
  else document.addEventListener("DOMContentLoaded", fn);
}

// ─── Convenience entry that wires the standard skeleton ────────────

export function startGrid(
  cfg: GridConfig,
  setup: (state: GridState) => void,
  onMessage: (data: unknown) => void,
): void {
  ready(() => {
    const state = makeState(cfg, onMessage);
    setup(state);
    injectHeartbeatBase(state);
    connectWs(state);
    startHeartbeatTicker(state);
    document.body.setAttribute(`data-${cfg.prefix}-grid-wired`, "1");
  });
}
