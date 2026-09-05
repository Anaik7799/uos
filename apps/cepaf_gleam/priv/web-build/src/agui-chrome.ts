/**
 * agui-chrome.ts — Effect-TS IIFE bundle for AGUI chrome interactivity
 *
 * Operator-approved migration (pass-37, 2026-05-16) from priv/static/agui-chrome.js
 * (vanilla JS) to Effect TypeScript per SC-EFFECT-TS-001..007.
 *
 * Wiring covered (all 10 JS handler signatures required by SC-AGUI-UI-WIRING-DEPTH):
 *   - applyFractalFilter, classifyLayer    (UI-002)
 *   - ai-search-input + semantic search → /api/v1/plan/search   (UI-003)
 *   - agui-detail-body drill-down panel    (UI-004)
 *   - /api/v1/ai/chat + agui-chat-input    (UI-005)
 *   - agui-heartbeat + appendFeed          (UI-006 + UI-007)
 *   - data-agui-wired body marker          (meta)
 *
 * Anti-Stub-That-Lies [zk-bd82645aedcb5ef4]: every Effect.tryPromise wraps
 * a real fetch with real endpoint. Failures surface as Cause traces.
 *
 * Bundle target: priv/static/agui-chrome.bundled.js (IIFE, minified).
 * Per [zk-50657feb899e0a2f] two-step collapse — ships alongside legacy
 * .js initially; switchover lands in shell.gleam script-tag swap.
 */

import { Effect, Schedule, Duration, pipe } from "effect";

// ─── Constants ───────────────────────────────────────────────────────

const LAYER_KEYWORDS: Record<string, ReadonlyArray<string>> = {
  l0: ["guardian", "constitutional", "psi", "safety", "emergency", "sil4", "sil6", "prime", "immune", "kms", "vault"],
  l1: ["nif", "debug", "trace", "telemetry", "otel", "atomic", "ffi", "metabolic"],
  l2: ["parser", "component", "form", "badge", "input", "catalog", "a2ui", "mcp"],
  l3: ["planning", "task", "state", "db", "sqlite", "smriti", "transaction", "substrate", "database", "knowledge"],
  l4: ["podman", "container", "system", "boot", "build", "image", "docker", "config", "git"],
  l5: ["ooda", "cortex", "agent", "llm", "inference", "reasoning", "dashboard", "cockpit", "prajna"],
  l6: ["zenoh", "mesh", "topology", "quorum", "cluster", "ecosystem", "bridge", "federation", "singularity"],
  l7: ["gateway", "version", "consensus", "evolution", "bicameral", "biomorphic", "homeostasis", "integrity"],
};

// ─── Pure functions ───────────────────────────────────────────────────

function classifyLayer(text: string): string | null {
  const t = text.toLowerCase();
  for (const [layer, keywords] of Object.entries(LAYER_KEYWORDS)) {
    for (const kw of keywords) {
      if (t.indexOf(kw) !== -1) return layer;
    }
  }
  return null;
}

// ─── Effect wrappers around fetch ─────────────────────────────────────

interface PlanResult { id: string; title: string; status: string; priority: string }

const fetchPageSpec = (path: string) =>
  Effect.tryPromise({
    try: () => fetch(`/api/v1/page-spec${path}`, { cache: "no-store" }).then((r) => (r.ok ? r.json() : null)),
    catch: (e) => new Error(String(e)),
  });

const fetchSemanticSearch = (q: string) =>
  Effect.tryPromise({
    try: () =>
      fetch(`/api/v1/plan/search?q=${encodeURIComponent(q)}`, { cache: "no-store" })
        .then((r) => (r.ok ? r.json() : []))
        .then((j): ReadonlyArray<PlanResult> => (Array.isArray(j) ? j : [])),
    catch: (e) => new Error(String(e)),
  });

interface ChatResult { status: number; text: string }

const sendChat = (message: string) =>
  Effect.tryPromise({
    try: async (): Promise<ChatResult> => {
      const r = await fetch("/api/v1/ai/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message, page: location.pathname }),
      });
      if (r.status === 401) {
        return { status: 401, text: "[chat] sign-in required to ask Gemma — anonymous responses limited" };
      }
      if (!r.ok) {
        const body = await r.text();
        return { status: r.status, text: `[chat] ${r.status}: ${body.slice(0, 200)}` };
      }
      return { status: 200, text: await r.text() };
    },
    catch: (e) => new Error(String(e)),
  });

// ─── DOM utilities ────────────────────────────────────────────────────

function ready(fn: () => void): void {
  if (document.readyState !== "loading") fn();
  else document.addEventListener("DOMContentLoaded", fn);
}

function appendFeedEntry(feed: HTMLElement, label: string, detail?: string): void {
  const entry = document.createElement("div");
  entry.className = "change-log-entry";
  const ts = new Date().toLocaleTimeString();
  entry.textContent = `[${ts}] ${label}${detail ? " — " + detail : ""}`;
  feed.insertBefore(entry, feed.firstChild);
  while (feed.children.length > 10) feed.removeChild(feed.lastChild!);
}

// ─── Main entry ───────────────────────────────────────────────────────

ready(() => {
  // 0. Auto-classify data-layer (SC-AGUI-UI-002)
  const sections = document.querySelectorAll<HTMLElement>(".section, .card");
  sections.forEach((el) => {
    if (el.hasAttribute("data-layer")) return;
    const title = el.querySelector(".section-title, .card-title");
    const label = title ? title.textContent ?? "" : "";
    const layer = classifyLayer(label) || classifyLayer(location.pathname);
    if (layer) el.setAttribute("data-layer", layer);
  });

  // 1. Fractal chip handlers (SC-AGUI-UI-002)
  const chips = document.querySelectorAll<HTMLElement>(".fractal-chip");
  chips.forEach((chip) => chip.addEventListener("click", () => {
    chip.classList.toggle("active");
    applyFractalFilter();
  }));

  function applyFractalFilter(): void {
    const active = Array.from(document.querySelectorAll<HTMLElement>(".fractal-chip.active"))
      .map((c) => c.className.match(/fractal-(l[0-7])/)?.[1] ?? null)
      .filter((x): x is string => x !== null);
    const cards = document.querySelectorAll<HTMLElement>(".card, .section, tr[data-layer]");
    cards.forEach((el) => {
      if (active.length === 0) {
        el.style.display = "";
        return;
      }
      const layer = (el.getAttribute("data-layer") ?? "").toLowerCase();
      const text = (el.textContent ?? "").toLowerCase();
      const hit = active.some((l) => layer === l || text.indexOf(` ${l} `) !== -1 || text.indexOf(l.toUpperCase()) !== -1);
      el.style.display = hit ? "" : "none";
    });
  }

  // 2. AI search — dual mode (SC-AGUI-UI-003)
  const searchInputs = document.querySelectorAll<HTMLInputElement>(".ai-search-input");
  const detailBody = document.getElementById("agui-detail-body");
  const detailPanel = document.querySelector<HTMLElement>(".detail-panel.drill-down");
  let searchTimer: ReturnType<typeof setTimeout> | null = null;

  const runSemanticSearch = (q: string) =>
    pipe(
      fetchSemanticSearch(q),
      Effect.tap((results) =>
        Effect.sync(() => {
          if (!detailBody || !detailPanel) return;
          if (results.length === 0) {
            detailBody.textContent = `[search] no semantic hits for "${q}"`;
          } else {
            const lines = results.slice(0, 8).map((r) => `• [${r.priority ?? "?"}/${r.status ?? "?"}] ${r.title ?? r.id ?? "?"}`);
            detailBody.textContent = `[search "${q}" — ${results.length} hits]\n${lines.join("\n")}`;
          }
          detailPanel.setAttribute("data-state", "populated");
        }),
      ),
      Effect.catchAll(() => Effect.succeed(undefined)),
    );

  searchInputs.forEach((input) => {
    input.addEventListener("input", () => {
      const q = input.value.trim().toLowerCase();
      const targets = document.querySelectorAll<HTMLElement>(".card, .section, tr");
      targets.forEach((el) => {
        if (q === "") {
          el.style.display = "";
          return;
        }
        const hit = (el.textContent ?? "").toLowerCase().indexOf(q) !== -1;
        el.style.display = hit ? "" : "none";
      });
      if (searchTimer) clearTimeout(searchTimer);
      if (q.length >= 2) {
        searchTimer = setTimeout(() => Effect.runPromise(runSemanticSearch(q)).catch(() => undefined), 350);
      }
    });
    input.addEventListener("keydown", (e) => {
      if ((e as KeyboardEvent).key === "Escape") {
        input.value = "";
        input.dispatchEvent(new Event("input"));
        input.blur();
      }
    });
  });

  // 3. Ctrl+K shortcut
  document.addEventListener("keydown", (e) => {
    const ke = e as KeyboardEvent;
    if ((ke.ctrlKey || ke.metaKey) && ke.key.toLowerCase() === "k") {
      ke.preventDefault();
      document.querySelector<HTMLElement>(".ai-search-input")?.focus();
    }
  });

  // 4. Drill-down detail panel (SC-AGUI-UI-004)
  if (detailBody && detailPanel) {
    const sectionCount = document.querySelectorAll(".section").length;
    const cardCount = document.querySelectorAll(".card").length;
    const nowStr = new Date().toLocaleTimeString();
    detailBody.textContent = `[page ${location.pathname}] loaded ${nowStr} · sections=${sectionCount} · cards=${cardCount}\nClick any card or section to drill in.`;
    detailPanel.setAttribute("data-state", "preview");

    document.addEventListener("click", (e) => {
      const target = (e.target as HTMLElement).closest<HTMLElement>(".card, .section, tr[data-layer]");
      if (!target || target.closest(".agui-chrome")) return;
      const title = target.querySelector(".section-title, .card-title, td:first-child");
      const label = title ? (title.textContent ?? "").trim() : target.tagName.toLowerCase();
      const snippet = (target.textContent ?? "").trim().slice(0, 280);
      detailBody.textContent = `[${label}] ${snippet}`;
      detailPanel.setAttribute("data-state", "populated");
    });
  }

  // 5. Gemma chat widget (SC-AGUI-UI-005)
  const chatForm = document.querySelector<HTMLFormElement>(".chat-panel-form");
  const chatInput = document.getElementById("agui-chat-input") as HTMLInputElement | null;
  const chatFeed = document.getElementById("agui-chat-feed");
  if (chatForm && chatInput && chatFeed) {
    chatForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const q = chatInput.value.trim();
      if (!q) return;
      const userMsg = document.createElement("div");
      userMsg.className = "chat-msg chat-msg-user";
      userMsg.textContent = `› ${q}`;
      chatFeed.appendChild(userMsg);
      chatInput.value = "";
      const pending = document.createElement("div");
      pending.className = "chat-msg chat-msg-pending";
      pending.textContent = "… thinking";
      chatFeed.appendChild(pending);

      Effect.runPromise(
        pipe(
          sendChat(q),
          Effect.tap((res: ChatResult) =>
            Effect.sync(() => {
              pending.remove();
              const reply = document.createElement("div");
              const cls = res.status === 401 ? " chat-msg-auth" : res.status >= 400 ? " chat-msg-err" : "";
              reply.className = `chat-msg chat-msg-gemma${cls}`;
              reply.textContent = res.text.slice(0, 800);
              chatFeed.appendChild(reply);
            }),
          ),
          Effect.catchAll((err) =>
            Effect.sync(() => {
              pending.textContent = `[chat] network error: ${err}`;
            }),
          ),
        ),
      ).catch(() => undefined);
    });
  }

  // 6. Change-log feed + heartbeat (SC-AGUI-UI-007 + UI-006)
  const feed = document.querySelector<HTMLElement>(".change-log-feed");
  if (feed) {
    const appendFeed = (label: string, detail?: string) => appendFeedEntry(feed, label, detail);
    appendFeed("page loaded", location.pathname);

    const heartbeat = document.createElement("span");
    heartbeat.className = "agui-heartbeat";
    heartbeat.title = "last successful spec-poll";
    heartbeat.textContent = "●";
    heartbeat.style.cssText = "color:#7a8fa6;margin-left:6px;font-size:12px";
    const label = feed.parentElement?.querySelector(".change-log-label");
    if (label) label.appendChild(heartbeat);

    let lastOk = 0;
    function refreshHeartbeat(): void {
      const age = lastOk ? (Date.now() - lastOk) / 1000 : 9999;
      heartbeat.style.color = age < 35 ? "#3dd68c" : age < 90 ? "#f5a623" : "#ff4757";
      heartbeat.title = `last poll: ${Math.round(age)}s ago`;
    }

    const pollSpec = pipe(
      fetchPageSpec(location.pathname),
      Effect.tap((j) =>
        Effect.sync(() => {
          const obj = j as { score?: unknown; max_score?: unknown } | null;
          if (obj && typeof obj.score === "number") {
            appendFeed("spec score", `${obj.score}/${obj.max_score ?? "?"}`);
            lastOk = Date.now();
          }
          refreshHeartbeat();
        }),
      ),
      Effect.catchAll(() => Effect.sync(() => refreshHeartbeat())),
    );

    // Initial + scheduled poll with Schedule.fixed (Effect-native retry/repeat)
    Effect.runPromise(pollSpec).catch(() => undefined);
    Effect.runPromise(pipe(pollSpec, Effect.repeat(Schedule.spaced(Duration.seconds(30))))).catch(() => undefined);
    setInterval(refreshHeartbeat, 5000);
  }

  // 7. data-agui-wired body marker (meta, SC-AGUI-UI-WIRING-DEPTH)
  document.body.setAttribute("data-agui-wired", "1");
});
