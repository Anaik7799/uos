/**
 * planning-utils.ts — Effect-TS port of priv/static/planning-utils.js
 *
 * Pass-39 operator-approved migration. Pure helper functions (no DOM,
 * no side-effects) exposed on window.__c3iPlanning.utils for the planning-
 * grid bundle. Per [zk-50657feb899e0a2f] two-step collapse: shipped
 * alongside legacy .js until soak verifies parity.
 *
 * Behaviour byte-equivalent to the IIFE version per
 * [zk-3346fc607a1ef9e6] no-Stub-That-Lies. Self-tests run when
 * window.__c3iPlanning.runUtilsTests is truthy.
 *
 * Effect-TS additions over the IIFE:
 *   - fetchWithRetry uses Effect.retry + Schedule.exponential
 *   - Schema-aligned types (Task, Snapshot)
 *   - Typed exports for downstream TS modules
 */

import { Effect, Schedule, Duration, pipe } from "effect";

// ─── Types ──────────────────────────────────────────────────────────

export interface Task {
  id: string;
  status: string;
  priority: string;
  title?: string;
}

export type Snapshot = Record<string, string>;

interface FractalLayerSpec {
  color: string;
  keywords: ReadonlyArray<string>;
}

// ─── Constants ──────────────────────────────────────────────────────

export const FRACTAL_LAYERS: Record<string, FractalLayerSpec> = {
  L0: { color: "#ff6b6b", keywords: ["guardian", "constitutional", "psi", "safety", "emergency", "sil4", "sil6", "prime"] },
  L1: { color: "#ffd93d", keywords: ["nif", "debug", "trace", "telemetry", "otel", "atomic", "ffi"] },
  L2: { color: "#6bcb77", keywords: ["parser", "component", "form", "badge", "input", "catalog", "a2ui"] },
  L3: { color: "#4d96ff", keywords: ["planning", "task", "state", "db", "sqlite", "smriti", "transaction"] },
  L4: { color: "#9b59b6", keywords: ["podman", "container", "system", "boot", "build", "image", "docker"] },
  L5: { color: "#00d4aa", keywords: ["ooda", "cortex", "mcp", "agent", "llm", "inference", "reasoning"] },
  L6: { color: "#e74c3c", keywords: ["zenoh", "mesh", "topology", "quorum", "cluster", "ecosystem"] },
  L7: { color: "#f39c12", keywords: ["federation", "gateway", "version", "consensus", "multi-node"] },
};

// ─── Pure helpers ───────────────────────────────────────────────────

export function taskAge(created: string | null | undefined): string {
  if (!created) return "—";
  const ms = Date.now() - new Date(created).getTime();
  if (!isFinite(ms) || ms < 0) return "—";
  const mins = Math.floor(ms / 60000);
  if (mins < 60) return mins + "m";
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return hrs + "h";
  const days = Math.floor(hrs / 24);
  return days + "d";
}

export function classifyFractalLayer(task: { title?: string }): string {
  const title = (task.title || "").toLowerCase();
  for (const layer of Object.keys(FRACTAL_LAYERS)) {
    const kws = FRACTAL_LAYERS[layer]!.keywords;
    for (const kw of kws) if (title.indexOf(kw) !== -1) return layer;
  }
  return "L3";
}

export function snapshotData(data: ReadonlyArray<Task>): Snapshot {
  const snap: Snapshot = {};
  data.forEach((t) => {
    snap[t.id] = t.status + "|" + t.priority + "|" + (t.title || "");
  });
  return snap;
}

export function findChangedIds(oldSnap: Snapshot, newSnap: Snapshot): string[] {
  const changed: string[] = [];
  Object.keys(newSnap).forEach((id) => {
    if (!oldSnap[id] || oldSnap[id] !== newSnap[id]) changed.push(id);
  });
  return changed;
}

// ─── fetchWithRetry — Effect-TS version ─────────────────────────────

export function fetchWithRetry(url: string, maxRetries = 3, baseDelayMs = 200): Promise<Response> {
  const eff = Effect.tryPromise({
    try: () =>
      fetch(url).then((r) => {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r;
      }),
    catch: (e) => new Error(String(e)),
  });
  const retried = pipe(
    eff,
    Effect.retry({
      times: maxRetries,
      schedule: Schedule.exponential(Duration.millis(baseDelayMs)),
    }),
  );
  return Effect.runPromise(retried);
}

// ─── Expose on namespace (byte-equivalent contract) ─────────────────

interface PlanningNamespace {
  utils?: {
    taskAge: typeof taskAge;
    classifyFractalLayer: typeof classifyFractalLayer;
    fetchWithRetry: typeof fetchWithRetry;
    snapshotData: typeof snapshotData;
    findChangedIds: typeof findChangedIds;
    FRACTAL_LAYERS: typeof FRACTAL_LAYERS;
  };
  runUtilsTests?: boolean;
}

const w = window as unknown as { __c3iPlanning?: PlanningNamespace };
w.__c3iPlanning = w.__c3iPlanning || {};
w.__c3iPlanning.utils = {
  taskAge,
  classifyFractalLayer,
  fetchWithRetry,
  snapshotData,
  findChangedIds,
  FRACTAL_LAYERS,
};

// ─── Self-tests (anti-Stub-That-Lies guard) ─────────────────────────

if (typeof window !== "undefined" && w.__c3iPlanning.runUtilsTests) {
  let fails = 0;
  const assert = (cond: boolean, msg: string) => {
    if (!cond) { fails++; console.error("[planning-utils] FAIL:", msg); }
  };
  assert(taskAge(null) === "—", "null → em-dash");
  assert(taskAge(new Date().toISOString()) === "0m", "now → 0m");
  assert(classifyFractalLayer({ title: "Guardian approval gate" }) === "L0", "guardian → L0");
  assert(classifyFractalLayer({ title: "Plan a new task" }) === "L3", "plan → L3");
  assert(classifyFractalLayer({ title: "OODA decide phase" }) === "L5", "ooda → L5");
  assert(classifyFractalLayer({ title: "completely random" }) === "L3", "no-match defaults L3");

  const d1: Task[] = [
    { id: "a", status: "pending", priority: "P0", title: "Task A" },
    { id: "b", status: "pending", priority: "P1", title: "Task B" },
  ];
  const d2: Task[] = [
    { id: "a", status: "completed", priority: "P0", title: "Task A" },
    { id: "b", status: "pending", priority: "P1", title: "Task B" },
  ];
  const snap1 = snapshotData(d1);
  const snap2 = snapshotData(d2);
  const changed = findChangedIds(snap1, snap2);
  assert(changed.length === 1, "1 changed");
  assert(changed[0] === "a", "task a changed");
  assert(FRACTAL_LAYERS.L0!.keywords.indexOf("guardian") >= 0, "L0 contains guardian");

  if (fails === 0) console.log("[planning-utils] all self-tests passed");
  else console.error("[planning-utils] " + fails + " self-test failures");
}
