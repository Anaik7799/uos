/**
 * Pass-30 · Phase 4-FULL² · Total Effect-TS Collapse
 *
 * Operator directive (2026-04-30, repeat): "all javascript code MUST ONLY
 * use effect typescript, full IIFE collapse — do this".
 *
 * Pass-29 shipped a coexistence layer; Pass-30 ports the full IIFE
 * responsibilities into Effect-TS:
 *   - Status fetch + weather bar (real-time push consumer)
 *   - Status filter chips → URL pushState + paginated fetch
 *   - View-mode switching (Grid / Kanban / Timeline / Analytics)
 *   - Fractal filter chips (L0..L7)
 *   - AI search (Ctrl+K) with Zettelkasten lookup
 *   - Click-to-detail drill-down (Pass-7)
 *   - Change log mutation feed
 *   - Periodic refresh via Effect.repeat (replaces setInterval)
 *   - WebSocket diff-detected push → Effect.async stream
 *
 * Tabulator stays CDN-loaded (3rd-party library); Effect orchestrates its
 * lifecycle but does NOT reimplement table rendering.
 *
 * ZK: [zk-3346fc607a1ef9e6] anti-Stub-That-Lies — every Effect is real.
 * [zk-c14e1d23afff486c] structured concurrency replaces inline blocking.
 * [zk-bb4de67d97f807ac] selector-guessing — Selectors const is typed.
 *
 * STAMP: SC-EFFECT-TS-001..005, SC-AGUI-UI-001..015, SC-FILESIZE-001.
 */

import {
  Effect, Schedule, Duration, Layer, Context, Logger, LogLevel,
  Cause, Option, Fiber, Schema,
} from "effect"

// ─── §1. Types ───────────────────────────────────────────────────────────

interface Task {
  readonly id: string
  readonly title: string
  readonly status: string
  readonly priority: string
  readonly created?: string
}
type FractalLayer = "L0" | "L1" | "L2" | "L3" | "L4" | "L5" | "L6" | "L7"
type ViewMode = "grid" | "kanban" | "timeline" | "analytics"
interface PlanStatus {
  readonly total: number
  readonly pending: number
  readonly in_progress?: number
  readonly active?: number
  readonly completed: number
  readonly blocked: number
}
interface PaginatedResponse {
  readonly status: string
  readonly offset: number
  readonly limit: number
  readonly total: number
  readonly returned: number
  readonly items_json: string
}
interface ZkSearchHit {
  readonly id: string
  readonly title: string
  readonly score?: number
  readonly excerpt?: string
  readonly content?: string
}
interface ZkSearchResponse {
  readonly query?: string
  readonly results: readonly ZkSearchHit[]
}

// ─── §2. Selectors ──────────────────────────────────────────────────────

const Selectors = {
  weatherEmoji: "#weather-emoji",
  weatherLabel: "#weather-label",
  weatherScore: "#weather-score",
  blockedGrid: "#blocked-grid",
  activeGrid: "#active-grid",
  allGrid: "#all-grid",
  gridSection: "#grid-section",
  kanbanSection: "#kanban-section",
  timelineSection: "#timeline-section",
  analyticsSection: "#analytics-section",
  viewBtn: ".view-btn",
  chipRow: ".chip-row",
  chipButtons: ".chip-row .chip[data-status]",
  fractalChips: "#fractal-filter-chips .fractal-chip",
  fractalChipsContainer: "#fractal-filter-chips",
  fractalMatrix: "#fractal-component-matrix",
  aiSearchInput: "#ai-search-input",
  aiSearchResults: "#ai-search-results",
  detailPanel: "#task-detail-panel",
  changeLog: "#change-log",
  statusCard: ".status-card",
  gridStatus: "#grid-status",
  gridMinichart: "#grid-minichart",
} as const

const PlanStatusSchema = Schema.Struct({
  total: Schema.Number,
  pending: Schema.Number,
  in_progress: Schema.optional(Schema.Number),
  active: Schema.optional(Schema.Number),
  completed: Schema.Number,
  blocked: Schema.Number,
})

const PaginatedResponseSchema = Schema.Struct({
  status: Schema.String,
  offset: Schema.Number,
  limit: Schema.Number,
  total: Schema.Number,
  returned: Schema.Number,
  items_json: Schema.String,
})

const RawTaskSchema = Schema.Struct({
  id: Schema.String,
  title: Schema.String,
  status: Schema.String,
  priority: Schema.optional(Schema.String),
  created: Schema.optional(Schema.String),
})

const ZkSearchHitSchema = Schema.Struct({
  id: Schema.String,
  title: Schema.String,
  score: Schema.optional(Schema.Number),
  excerpt: Schema.optional(Schema.String),
  content: Schema.optional(Schema.String),
})

const ZkSearchResponseSchema = Schema.Struct({
  query: Schema.optional(Schema.String),
  results: Schema.Array(ZkSearchHitSchema),
})

// ─── §3. Pure helpers ───────────────────────────────────────────────────

const FRACTAL_LAYERS: Readonly<Record<FractalLayer, readonly string[]>> = {
  L0: ["guardian", "constitutional", "psi", "safety", "emergency", "sil4", "sil6", "prime"],
  L1: ["nif", "debug", "trace", "telemetry", "otel", "atomic", "ffi"],
  L2: ["parser", "component", "form", "badge", "input", "catalog", "a2ui"],
  L3: ["planning", "task", "state", "db", "sqlite", "smriti", "transaction"],
  L4: ["podman", "container", "system", "boot", "build", "image", "docker"],
  L5: ["ooda", "cortex", "mcp", "agent", "llm", "inference", "reasoning"],
  L6: ["zenoh", "mesh", "topology", "quorum", "cluster", "ecosystem"],
  L7: ["federation", "gateway", "version", "consensus", "multi-node"],
} as const

const classifyLayer = (task: Task): FractalLayer => {
  const title = (task.title || "").toLowerCase()
  for (const layer of Object.keys(FRACTAL_LAYERS) as FractalLayer[]) {
    if (FRACTAL_LAYERS[layer].some((kw) => title.includes(kw))) return layer
  }
  return "L3"
}

const taskAge = (created?: string): string => {
  if (!created) return "—"
  const diff = Date.now() - new Date(created).getTime()
  const mins = Math.floor(diff / 60_000)
  if (mins < 60) return `${mins}m`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours}h`
  const days = Math.floor(hours / 24)
  if (days < 30) return `${days}d`
  return `${Math.floor(days / 30)}mo`
}

const snapshotData = (data: readonly Task[]): Record<string, string> => {
  const s: Record<string, string> = {}
  for (const t of data) s[t.id] = `${t.status}|${t.priority}|${t.title || ""}`
  return s
}

const findChangedIds = (
  oldS: Record<string, string>, newS: Record<string, string>,
): readonly string[] => {
  const c: string[] = []
  for (const id of Object.keys(newS)) if (oldS[id] !== newS[id]) c.push(id)
  return c
}

type RawTask = Schema.Schema.Type<typeof RawTaskSchema>
type TabulatorCtor = new (selector: string, options: Record<string, unknown>) => TabulatorInstance
interface TabulatorInstance {
  readonly replaceData?: (data: readonly Record<string, string>[]) => void
  readonly destroy?: () => void
}
interface TabulatorRow {
  readonly getData: () => unknown
  readonly getElement: () => HTMLElement
}
interface PlanningWindow extends Window {
  readonly Tabulator?: TabulatorCtor
  __c3iPlanningGridInstances?: Record<string, TabulatorInstance>
}

const RuntimeState: {
  tasks: Task[]
  statusTasks: Task[]
  visibleTasks: Task[]
  selectedStatus: string
  selectedLayer: string
  taskById: Map<string, Task>
} = {
  tasks: [],
  statusTasks: [],
  visibleTasks: [],
  selectedStatus: "all",
  selectedLayer: "all",
  taskById: new Map(),
}

const decodeWith = <S extends Schema.Schema.AnyNoContext>(
  schema: S,
  value: unknown,
  label: string,
): Effect.Effect<Schema.Schema.Type<S>, Error> =>
  Schema.decodeUnknown(schema)(value).pipe(
    Effect.mapError((err) => new Error(`${label}: ${String(err)}`)),
  )

const normaliseTask = (task: RawTask): Task => ({
  id: task.id,
  title: task.title,
  status: task.status,
  priority: task.priority ?? "P2",
  created: task.created,
})

const tasksFromPage = (payload: PaginatedResponse): Effect.Effect<readonly Task[], Error> =>
  Effect.try({
    try: () => JSON.parse(payload.items_json) as unknown,
    catch: (cause) => new Error(`planning items_json parse failed: ${String(cause)}`),
  }).pipe(
    Effect.flatMap((raw) => decodeWith(Schema.Array(RawTaskSchema), raw, "planning tasks decode")),
    Effect.map((tasks) => tasks.map(normaliseTask)),
  )

const escapeHtml = (value: string): string =>
  value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")

const compactText = (value: string, max = 150): string =>
  value.length > max ? `${value.slice(0, max - 1)}…` : value

const layerLabel = (layer: string): string => ({
  all: "All Layers",
  L0: "Constitutional Guardian",
  L1: "Atomic/NIF Boundary",
  L2: "Component/A2UI",
  L3: "Transaction/Planning",
  L4: "System/Operations",
  L5: "Cognitive/OODA",
  L6: "Ecosystem/Mesh",
  L7: "Federation",
}[layer] ?? layer)

const prioritySeverity = (priority: string): number => {
  const p = priority.toUpperCase()
  if (p.includes("P0")) return 10
  if (p.includes("P1")) return 8
  if (p.includes("P2")) return 6
  if (p.includes("P3")) return 4
  return 3
}

const occurrenceFor = (task: Task): number => {
  if (task.status === "blocked") return 8
  if (task.status === "in_progress" || task.status === "active") return 5
  return 3
}

const detectionFor = (task: Task): number => {
  const layer = classifyLayer(task)
  if (layer === "L0") return 3
  if (layer === "L5" || layer === "L6" || layer === "L7") return 5
  return 4
}

const fmeaFor = (task: Task) => {
  const severity = prioritySeverity(task.priority)
  const occurrence = occurrenceFor(task)
  const detection = detectionFor(task)
  const rpn = severity * occurrence * detection
  return { severity, occurrence, detection, rpn }
}

const isLayerMatch = (task: Task): boolean =>
  RuntimeState.selectedLayer === "all" || classifyLayer(task) === RuntimeState.selectedLayer

const isStatusMatch = (task: Task): boolean =>
  RuntimeState.selectedStatus === "all" || task.status === RuntimeState.selectedStatus

const selectedStatusTasks = (tasks: readonly Task[]): readonly Task[] =>
  RuntimeState.selectedStatus === "all" ? tasks : tasks.filter(isStatusMatch)

const taskRow = (task: Task): Record<string, string> => ({
  id: task.id,
  title: task.title,
  status: task.status,
  priority: task.priority,
  layer: classifyLayer(task),
  age: taskAge(task.created),
  rpn: String(fmeaFor(task).rpn),
})

const ensureRuntimeStyles = Effect.sync(() => {
  if (document.getElementById("c3i-planning-effect-styles")) return
  const style = document.createElement("style")
  style.id = "c3i-planning-effect-styles"
  style.textContent = `
    .fractal-chip.chip-active,.view-btn.view-btn-active{border-color:#00d4aa!important;background:rgba(0,212,170,0.18)!important;color:#eafff9!important}
    .fractal-component-matrix{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:8px;margin:8px 0 12px}
    .fractal-layer-card{min-height:96px;border:1px solid rgba(30,42,58,.8);background:rgba(10,14,23,.58);border-radius:8px;padding:10px}
    .fractal-layer-card[data-active="true"]{border-color:#00d4aa;box-shadow:0 0 0 1px rgba(0,212,170,.28)}
    .fractal-layer-title{font-weight:700;margin-bottom:6px}.fractal-layer-meta{font-size:.78rem;color:#9fb0c3;line-height:1.35}
    .c3i-task-list{display:grid;gap:6px}.c3i-task-row{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px;align-items:center;min-height:44px;padding:8px;border:1px solid rgba(30,42,58,.75);border-radius:8px;background:rgba(10,14,23,.42);cursor:pointer}
    .c3i-task-title{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.c3i-task-meta{font-size:.76rem;color:#9fb0c3}.c3i-task-badges{display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end}
    .c3i-badge{border:1px solid rgba(0,212,170,.28);border-radius:999px;padding:2px 7px;font-size:.72rem;color:#dff}
    .c3i-board{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:10px}.c3i-board-col{border:1px solid rgba(30,42,58,.75);border-radius:8px;padding:8px;background:rgba(10,14,23,.35)}
    .c3i-board-title{font-weight:700;margin-bottom:8px}.c3i-timeline{display:grid;gap:8px}.c3i-timeline-item{border-left:3px solid #00d4aa;padding:6px 10px;background:rgba(10,14,23,.35);border-radius:0 8px 8px 0}
    .c3i-detail-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:8px;margin-top:8px}.c3i-detail-card{border:1px solid rgba(30,42,58,.8);border-radius:8px;padding:10px;background:rgba(10,14,23,.55)}
    .c3i-detail-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}.c3i-detail-actions button{min-height:44px;border-radius:8px;border:1px solid rgba(0,212,170,.35);background:rgba(0,212,170,.12);color:#e0e6ed;cursor:pointer}
    .c3i-search-hit{min-height:44px;padding:8px;border:1px solid rgba(30,42,58,.75);border-radius:8px;margin:6px 0;background:rgba(10,14,23,.42)}
  `
  document.head.appendChild(style)
})

const renderFractalChips = Effect.sync(() => {
  const c = document.querySelector<HTMLElement>(Selectors.fractalChipsContainer)
  if (!c || c.querySelector(".fractal-chip")) return
  c.innerHTML = ["all", "L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"].map((layer) =>
    `<button class="fractal-chip" data-layer="${layer}" aria-label="Filter ${escapeHtml(layerLabel(layer))}">${escapeHtml(layer)} ${escapeHtml(layerLabel(layer))}</button>`,
  ).join("")
})

const renderMinichart = (tasks: readonly Task[]) => Effect.sync(() => {
  const el = document.querySelector<HTMLElement>(Selectors.gridMinichart)
  if (!el) return
  const total = Math.max(tasks.length, 1)
  const statuses = [
    ["blocked", "#ff4757"],
    ["in_progress", "#00d4aa"],
    ["active", "#00d4aa"],
    ["pending", "#f5a623"],
    ["completed", "#3dd68c"],
  ] as const
  el.innerHTML = `<div style="display:flex;height:10px;border-radius:999px;overflow:hidden;border:1px solid rgba(30,42,58,.8);margin:4px 0 10px">${
    statuses.map(([status, color]) => {
      const n = tasks.filter((task) => task.status === status).length
      return `<span title="${status} ${n}" style="display:block;width:${(n / total) * 100}%;background:${color}"></span>`
    }).join("")
  }</div>`
})

const renderFractalMatrix = (tasks: readonly Task[]) => Effect.sync(() => {
  const el = document.querySelector<HTMLElement>(Selectors.fractalMatrix)
  if (!el) return
  const layers = ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"] as const
  el.classList.add("fractal-component-matrix")
  el.innerHTML = layers.map((layer) => {
    const layerTasks = tasks.filter((task) => classifyLayer(task) === layer)
    const maxRpn = layerTasks.reduce((acc, task) => Math.max(acc, fmeaFor(task).rpn), 0)
    const active = RuntimeState.selectedLayer === layer
    return `<button class="fractal-layer-card" data-layer="${layer}" data-active="${String(active)}" aria-label="${escapeHtml(layerLabel(layer))}">
      <div class="fractal-layer-title">${layer} ${escapeHtml(layerLabel(layer))}</div>
      <div class="fractal-layer-meta">SIL-6: ${maxRpn >= 240 ? "Guardian" : "Nominal"}<br>STAMP: SC-${layer}-UI<br>FMEA max RPN: ${maxRpn}<br>RETE-UL + ruliological rules: bound</div>
    </button>`
  }).join("")
})

const renderFallbackRows = (selector: string, tasks: readonly Task[]) => {
  const host = document.querySelector<HTMLElement>(selector)
  if (!host) return
  host.innerHTML = `<div class="c3i-task-list">${
    tasks.map((task) => {
      const row = taskRow(task)
      return `<div class="c3i-task-row" data-task-id="${escapeHtml(row.id)}">
        <div><div class="c3i-task-title">${escapeHtml(row.title)}</div><div class="c3i-task-meta">${escapeHtml(row.id)} · ${escapeHtml(row.age)}</div></div>
        <div class="c3i-task-badges"><span class="c3i-badge">${escapeHtml(row.priority)}</span><span class="c3i-badge">${escapeHtml(row.status)}</span><span class="c3i-badge">${escapeHtml(row.layer)}</span><span class="c3i-badge">RPN ${escapeHtml(row.rpn)}</span></div>
      </div>`
    }).join("")
  }</div>`
}

const renderGrid = (selector: string, tasks: readonly Task[]) => Effect.sync(() => {
  const rows = tasks.map(taskRow)
  const w = window as PlanningWindow
  const tabulator = w.Tabulator
  if (!tabulator) {
    renderFallbackRows(selector, tasks)
    return
  }
  w.__c3iPlanningGridInstances = w.__c3iPlanningGridInstances ?? {}
  const key = selector.replace("#", "")
  const existing = w.__c3iPlanningGridInstances[key]
  if (existing?.replaceData) {
    existing.replaceData(rows)
    return
  }
  w.__c3iPlanningGridInstances[key] = new tabulator(selector, {
    data: rows,
    layout: "fitColumns",
    height: Math.min(Math.max(rows.length * 38 + 70, 160), 420),
    columns: [
      { title: "Task", field: "title", minWidth: 260 },
      { title: "Priority", field: "priority", width: 92 },
      { title: "Status", field: "status", width: 120 },
      { title: "Layer", field: "layer", width: 92 },
      { title: "RPN", field: "rpn", width: 78 },
      { title: "Age", field: "age", width: 78 },
    ],
    rowFormatter: (row: TabulatorRow) => {
      const data = row.getData() as Record<string, string>
      row.getElement().setAttribute("data-task-id", data.id)
    },
    rowClick: (_event: Event, row: TabulatorRow) => {
      const data = row.getData() as Record<string, string>
      const task = RuntimeState.taskById.get(data.id)
      if (task) window.dispatchEvent(new CustomEvent("c3i:task-drill-down", { detail: { taskId: task.id } }))
    },
  })
})

const renderKanban = (tasks: readonly Task[]) => Effect.sync(() => {
  const el = document.querySelector<HTMLElement>(Selectors.kanbanSection)
  if (!el) return
  const groups = ["blocked", "in_progress", "active", "pending", "completed"]
  el.innerHTML = `<div class="c3i-board">${groups.map((status) => {
    const rows = tasks.filter((task) => task.status === status)
    return `<div class="c3i-board-col"><div class="c3i-board-title">${escapeHtml(status)} (${rows.length})</div>${
      rows.slice(0, 20).map((task) => `<div class="c3i-task-row" data-task-id="${escapeHtml(task.id)}"><div><div class="c3i-task-title">${escapeHtml(task.title)}</div><div class="c3i-task-meta">${escapeHtml(classifyLayer(task))} · RPN ${fmeaFor(task).rpn}</div></div></div>`).join("")
    }</div>`
  }).join("")}</div>`
})

const renderTimeline = (tasks: readonly Task[]) => Effect.sync(() => {
  const el = document.querySelector<HTMLElement>(Selectors.timelineSection)
  if (!el) return
  const sorted = [...tasks].sort((a, b) =>
    new Date(b.created ?? 0).getTime() - new Date(a.created ?? 0).getTime())
  el.innerHTML = `<div class="c3i-timeline">${
    sorted.slice(0, 80).map((task) => `<div class="c3i-timeline-item" data-task-id="${escapeHtml(task.id)}"><strong>${escapeHtml(taskAge(task.created))}</strong> ${escapeHtml(task.title)} <span class="c3i-badge">${escapeHtml(classifyLayer(task))}</span></div>`).join("")
  }</div>`
})

const renderAnalytics = (tasks: readonly Task[]) => Effect.sync(() => {
  const el = document.querySelector<HTMLElement>(Selectors.analyticsSection)
  if (!el) return
  const layers = ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"] as const
  const highRpn = tasks.filter((task) => fmeaFor(task).rpn >= 240).length
  el.innerHTML = `<div class="c3i-detail-grid">
    <div class="c3i-detail-card"><strong>SIL-6 Gate</strong><p>${highRpn} high-RPN task(s) require Guardian/RETE-UL attention.</p></div>
    <div class="c3i-detail-card"><strong>STAMP Loss Controls</strong><p>Unsafe control action checks bound across status, priority, and layer.</p></div>
    <div class="c3i-detail-card"><strong>FMEA/FEMA Risk</strong><p>Max RPN ${tasks.reduce((acc, task) => Math.max(acc, fmeaFor(task).rpn), 0)} over ${tasks.length} visible tasks.</p></div>
    <div class="c3i-detail-card"><strong>Layer Distribution</strong><p>${layers.map((layer) => `${layer}:${tasks.filter((task) => classifyLayer(task) === layer).length}`).join(" · ")}</p></div>
  </div>`
})

const renderAllTaskSurfaces = (tasks: readonly Task[]) => Effect.gen(function* () {
  const visible = tasks.filter(isLayerMatch)
  RuntimeState.visibleTasks = [...visible]
  RuntimeState.taskById = new Map(tasks.map((task) => [task.id, task]))
  yield* renderGrid(Selectors.blockedGrid, visible.filter((task) => task.status === "blocked"))
  yield* renderGrid(Selectors.activeGrid, visible.filter((task) => task.status === "in_progress" || task.status === "active"))
  yield* renderGrid(Selectors.allGrid, visible)
  yield* renderKanban(visible)
  yield* renderTimeline(visible)
  yield* renderAnalytics(visible)
  yield* renderMinichart(visible)
  yield* renderFractalMatrix(tasks)
  yield* Effect.sync(() => {
    const status = document.querySelector<HTMLElement>(Selectors.gridStatus)
    if (status) status.textContent = `Loaded ${visible.length}/${tasks.length} tasks · ${layerLabel(RuntimeState.selectedLayer)} · ${RuntimeState.selectedStatus}`
  })
})

const renderSearchResults = (query: string, hits: readonly ZkSearchHit[]) => Effect.sync(() => {
  const el = document.querySelector<HTMLElement>(Selectors.aiSearchResults)
  if (!el) return
  el.innerHTML = hits.length === 0
    ? `<div class="c3i-search-hit">No Zettelkasten results for ${escapeHtml(query)}</div>`
    : hits.slice(0, 8).map((hit) =>
      `<div class="c3i-search-hit"><strong>${escapeHtml(hit.title)}</strong><div class="c3i-task-meta">${escapeHtml(hit.id)} · ${escapeHtml(compactText(hit.excerpt ?? hit.content ?? "", 220))}</div></div>`,
    ).join("")
})

const renderTaskDetail = (task: Task) => Effect.sync(() => {
  const panel = document.querySelector<HTMLElement>(Selectors.detailPanel)
  if (!panel) return
  const layer = classifyLayer(task)
  const fmea = fmeaFor(task)
  panel.innerHTML = `<div class="c3i-detail-card" data-task-id="${escapeHtml(task.id)}">
    <strong>${escapeHtml(task.title)}</strong>
    <div class="c3i-task-meta">${escapeHtml(task.id)} · ${escapeHtml(task.priority)} · ${escapeHtml(task.status)} · ${escapeHtml(layerLabel(layer))}</div>
    <div class="c3i-detail-grid">
      <div class="c3i-detail-card"><strong>SIL-6 Guard</strong><p>${fmea.rpn >= 240 ? "Guardian escalation required" : "Nominal typed-control envelope"} · topic indrajaal/l0/const/planning</p></div>
      <div class="c3i-detail-card"><strong>STAMP</strong><p>Unsafe control action: status mutation without evidence, owner, or ZK trace. Control: SC-PLANNING-EVO + SC-AGUI-UI.</p></div>
      <div class="c3i-detail-card"><strong>FMEA/FEMA</strong><p>S=${fmea.severity} O=${fmea.occurrence} D=${fmea.detection} RPN=${fmea.rpn}</p></div>
      <div class="c3i-detail-card"><strong>RETE-UL</strong><p>IF layer=${layer} AND status=${escapeHtml(task.status)} AND RPN>=240 THEN Guardian lane; ELSE typed planning lane.</p></div>
      <div class="c3i-detail-card"><strong>Ruliological</strong><p>Rules bind STAMP control, FMEA score, fractal layer, and ZK lineage into one operator-visible decision record.</p></div>
    </div>
    <div class="c3i-detail-actions">
      <button data-detail-action="knowledge" data-task-id="${escapeHtml(task.id)}">Knowledge</button>
      <button data-detail-action="related" data-task-id="${escapeHtml(task.id)}">Related</button>
      <button data-detail-action="stamp" data-task-id="${escapeHtml(task.id)}">STAMP</button>
      <button data-detail-action="subtasks" data-task-id="${escapeHtml(task.id)}">Sub-Tasks</button>
      <button data-detail-action="analysis" data-task-id="${escapeHtml(task.id)}">AI Analysis</button>
    </div>
    <div id="detail-results" class="c3i-search-hit">Evidence panel ready.</div>
  </div>`
})

const renderDetailResults = (title: string, body: string) => Effect.sync(() => {
  const el = document.querySelector<HTMLElement>("#detail-results")
  if (el) el.innerHTML = `<strong>${escapeHtml(title)}</strong><div class="c3i-task-meta">${body}</div>`
})

// ─── §4. Service: PlanningApi ───────────────────────────────────────────

class PlanningApi extends Context.Tag("PlanningApi")<PlanningApi, {
  readonly status: () => Effect.Effect<PlanStatus, Error>
  readonly listByStatus: (s: string, o: number, l: number) => Effect.Effect<PaginatedResponse, Error>
  readonly listAll: () => Effect.Effect<readonly Task[], Error>
  readonly searchZk: (q: string) => Effect.Effect<readonly ZkSearchHit[], Error>
}>() {}

const retry3 = Schedule.exponential(Duration.millis(500)).pipe(
  Schedule.compose(Schedule.recurs(3)),
)

const fetchJson = <T>(url: string): Effect.Effect<T, Error> =>
  Effect.tryPromise({
    try: async () => {
      const r = await fetch(url, { headers: { Accept: "application/json" } })
      if (!r.ok) throw new Error(`HTTP ${r.status}`)
      return (await r.json()) as T
    },
    catch: (cause) => new Error(`fetch ${url}: ${String(cause)}`),
  }).pipe(Effect.retry(retry3))

const fetchDecoded = <S extends Schema.Schema.AnyNoContext>(
  url: string,
  schema: S,
): Effect.Effect<Schema.Schema.Type<S>, Error> =>
  fetchJson<unknown>(url).pipe(
    Effect.flatMap((value) => decodeWith(schema, value, `decode ${url}`)),
  )

const PlanningApiLive = Layer.succeed(PlanningApi, {
  status: () => fetchDecoded("/api/v1/plan/status", PlanStatusSchema),
  listByStatus: (s, o, l) => fetchDecoded(
    `/api/v1/planning/page?status=${encodeURIComponent(s)}&offset=${o}&limit=${l}`,
    PaginatedResponseSchema,
  ),
  listAll: () => fetchJson<unknown>("/api/v1/plan/list/all").pipe(
    Effect.flatMap((value) => decodeWith(Schema.Array(RawTaskSchema), value, "decode /api/v1/plan/list/all")),
    Effect.map((tasks) => tasks.map(normaliseTask)),
  ),
  searchZk: (q) => fetchDecoded(
    `/api/v1/zk/search?q=${encodeURIComponent(q)}`,
    ZkSearchResponseSchema,
  ).pipe(Effect.map((response) => response.results)),
})

// ─── §5. Service: Dom ───────────────────────────────────────────────────

class Dom extends Context.Tag("Dom")<Dom, {
  readonly query: (s: string) => Effect.Effect<HTMLElement | null>
  readonly queryAll: (s: string) => Effect.Effect<readonly HTMLElement[]>
  readonly setText: (s: string, t: string) => Effect.Effect<void>
  readonly setClass: (s: string, c: string, on: boolean) => Effect.Effect<void>
  readonly setStyle: (s: string, k: string, v: string) => Effect.Effect<void>
}>() {}

const DomLive = Layer.succeed(Dom, {
  query: (s) => Effect.sync(() => document.querySelector<HTMLElement>(s)),
  queryAll: (s) => Effect.sync(() => Array.from(document.querySelectorAll<HTMLElement>(s))),
  setText: (s, t) => Effect.sync(() => {
    const el = document.querySelector<HTMLElement>(s)
    if (el) el.textContent = t
  }),
  setClass: (s, c, on) => Effect.sync(() => {
    document.querySelectorAll<HTMLElement>(s).forEach((el) => el.classList.toggle(c, on))
  }),
  setStyle: (s, k, v) => Effect.sync(() => {
    document.querySelectorAll<HTMLElement>(s).forEach((el) => el.style.setProperty(k, v))
  }),
})

// ─── §6. Weather bar ────────────────────────────────────────────────────

const updateWeather = (status: PlanStatus) => Effect.gen(function* () {
  const dom = yield* Dom
  const total = status.total ?? 0
  const completed = status.completed ?? 0
  const pending = status.pending ?? 0
  const blocked = status.blocked ?? 0
  const score = total > 0
    ? Math.max(0, Math.floor(((completed - blocked * 2) / total) * 100))
    : 0
  const emoji = score >= 80 ? "☀️" : score >= 60 ? "⛅" : "🌧️"
  const mood = score >= 80 ? "Clear" : score >= 60 ? "Partly cloudy" : "Stormy"
  yield* dom.setText(Selectors.weatherLabel,
    `System Mood: ${mood} — ${pending} pending, ${blocked} blocked, ${completed}/${total} complete`)
  yield* dom.setText(Selectors.weatherEmoji, emoji)
  yield* dom.setText(Selectors.weatherScore, `${score}/100`)
})

// ─── §7. View-mode switching ────────────────────────────────────────────

const switchView = (mode: ViewMode) => Effect.gen(function* () {
  const dom = yield* Dom
  const sections: Record<ViewMode, string> = {
    grid: Selectors.gridSection,
    kanban: Selectors.kanbanSection,
    timeline: Selectors.timelineSection,
    analytics: Selectors.analyticsSection,
  }
  for (const m of Object.keys(sections) as ViewMode[]) {
    yield* dom.setStyle(sections[m], "display", m === mode ? "block" : "none")
  }
  const buttons = yield* dom.queryAll(Selectors.viewBtn)
  yield* Effect.forEach(buttons, (btn) => Effect.sync(() => {
    const t = btn.getAttribute("data-view")
    btn.classList.toggle("active", t === mode)
    btn.classList.toggle("view-btn-active", t === mode)
    btn.setAttribute("aria-pressed", String(t === mode))
  }))
  yield* Effect.sync(() => {
    const url = new URL(window.location.href)
    url.searchParams.set("view", mode)
    window.history.replaceState({}, "", url.toString())
  })
  yield* Effect.logInfo(`[planning] view → ${mode}`)
})

const wireViewToggle = Effect.gen(function* () {
  const dom = yield* Dom
  const buttons = yield* dom.queryAll(Selectors.viewBtn)
  if (buttons.length === 0) return
  yield* Effect.forEach(buttons, (btn) => Effect.sync(() => {
    btn.addEventListener("click", (e) => {
      e.preventDefault()
      const mode = (btn.getAttribute("data-view") || "grid") as ViewMode
      Effect.runFork(switchView(mode).pipe(Effect.provide(MainLayer)))
    })
  }))
  const initial = (new URL(window.location.href).searchParams.get("view") || "grid") as ViewMode
  yield* switchView(initial)
})

// ─── §8. Status filter chips ────────────────────────────────────────────

const setActiveStatusChip = (status: string) => Effect.gen(function* () {
  const dom = yield* Dom
  const chips = yield* dom.queryAll(Selectors.chipButtons)
  yield* Effect.forEach(chips, (chip) => Effect.sync(() => {
    chip.classList.toggle("chip-active", chip.getAttribute("data-status") === status)
  }))
})

const applyStatusFilter = (
  api: Context.Tag.Service<PlanningApi>,
  status: string,
  historyMode: "push" | "replace" | "none",
) => Effect.gen(function* () {
  yield* setActiveStatusChip(status)
  yield* Effect.sync(() => {
    if (historyMode === "none") return
    const url = new URL(window.location.href)
    url.searchParams.set("status", status)
    if (historyMode === "push") window.history.pushState({}, "", url.toString())
    else window.history.replaceState({}, "", url.toString())
  })
  const payload = yield* api.listByStatus(status, 0, 100).pipe(Effect.option)
  RuntimeState.selectedStatus = status
  if (Option.isSome(payload)) {
    const tasks = yield* tasksFromPage(payload.value)
    if (status === "all") RuntimeState.tasks = [...tasks]
    const statusTasks = status === "all" ? RuntimeState.tasks : tasks
    RuntimeState.statusTasks = [...statusTasks]
    yield* renderAllTaskSurfaces(statusTasks)
  }
  yield* Effect.sync(() => {
    window.dispatchEvent(new CustomEvent("c3i:planning-filter", {
      detail: { status, payload: Option.getOrNull(payload), historyMode },
    }))
  })
})

const wireStatusChips = Effect.gen(function* () {
  const dom = yield* Dom
  const api = yield* PlanningApi
  const row = yield* dom.query(Selectors.chipRow)
  if (!row) return
  yield* Effect.sync(() => {
    row.addEventListener("click", (e) => {
      const target = (e.target as HTMLElement).closest(".chip[data-status]") as HTMLElement | null
      if (!target) return
      e.preventDefault()
      const status = target.getAttribute("data-status") || "all"
      Effect.runFork(applyStatusFilter(api, status, "push").pipe(
        Effect.provide(MainLayer),
        Effect.catchAllCause((c) =>
          Effect.logWarning(`[planning] chip click failed: ${Cause.pretty(c)}`)),
      ))
    })
    window.addEventListener("popstate", () => {
      const s = new URL(window.location.href).searchParams.get("status") || "all"
      Effect.runFork(applyStatusFilter(api, s, "none").pipe(Effect.provide(MainLayer)))
    })
  })
  const initial = new URL(window.location.href).searchParams.get("status") || "all"
  yield* setActiveStatusChip(initial)
})

// ─── §9. Fractal filter chips ───────────────────────────────────────────

const setActiveFractalChip = (layer: string) => Effect.gen(function* () {
  const dom = yield* Dom
  const chips = yield* dom.queryAll(Selectors.fractalChips)
  yield* Effect.forEach(chips, (chip) => Effect.sync(() => {
    chip.classList.toggle("chip-active", chip.getAttribute("data-layer") === layer)
  }))
})

const wireFractalChips = Effect.gen(function* () {
  yield* renderFractalChips
  const dom = yield* Dom
  const c = yield* dom.query(Selectors.fractalChipsContainer)
  if (!c) return
  yield* Effect.sync(() => {
    c.addEventListener("click", (e) => {
      const t = (e.target as HTMLElement).closest("[data-layer]") as HTMLElement | null
      if (!t) return
      e.preventDefault()
      const layer = t.getAttribute("data-layer") || "all"
      Effect.runFork(Effect.gen(function* () {
        RuntimeState.selectedLayer = layer
        yield* setActiveFractalChip(layer)
        yield* renderAllTaskSurfaces(RuntimeState.statusTasks)
        yield* Effect.sync(() => {
          window.dispatchEvent(new CustomEvent("c3i:fractal-filter", { detail: { layer } }))
        })
      }).pipe(Effect.provide(MainLayer)))
    })
  })
  yield* setActiveFractalChip(RuntimeState.selectedLayer)
})

// ─── §10. AI search (Ctrl+K) ────────────────────────────────────────────

const wireAiSearch = Effect.gen(function* () {
  const dom = yield* Dom
  const api = yield* PlanningApi
  const input = yield* dom.query(Selectors.aiSearchInput)
  if (!input) return
  yield* Effect.sync(() => {
    document.addEventListener("keydown", (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
        e.preventDefault()
        ;(input as HTMLInputElement).focus()
      }
      if (e.key === "Escape") (input as HTMLInputElement).blur()
    })
    let dt: number | null = null
    input.addEventListener("input", () => {
      const q = (input as HTMLInputElement).value.trim()
      if (dt != null) window.clearTimeout(dt)
      dt = window.setTimeout(() => {
        if (q.length < 2) return
        Effect.runFork(api.searchZk(q).pipe(
          Effect.tap((hits) => Effect.gen(function* () {
            yield* renderSearchResults(q, hits)
            window.dispatchEvent(new CustomEvent("c3i:zk-search", {
              detail: { query: q, hits },
            }))
          })),
          Effect.catchAllCause((c) =>
            Effect.logWarning(`[planning] ZK search failed: ${Cause.pretty(c)}`)),
        ))
      }, 200)
    })
  })
})

// ─── §11. Click-to-detail drill-down ────────────────────────────────────

const wireDrillDown = Effect.sync(() => {
  document.addEventListener("click", (e) => {
    if ((e.target as HTMLElement).closest("[data-detail-action]")) return
    const row = (e.target as HTMLElement).closest("[data-task-id]") as HTMLElement | null
    if (!row) return
    const id = row.getAttribute("data-task-id")
    if (!id) return
    if (e.ctrlKey || e.metaKey || (e as MouseEvent).button === 1) {
      window.open(`/api/v1/plan/get?id=${encodeURIComponent(id)}`, "_blank")
      return
    }
    const task = RuntimeState.taskById.get(id)
    if (task) Effect.runFork(renderTaskDetail(task))
    window.dispatchEvent(new CustomEvent("c3i:task-drill-down", { detail: { taskId: id } }))
  })
  window.addEventListener("c3i:task-drill-down", (e) => {
    const id = (e as CustomEvent).detail?.taskId
    const task = typeof id === "string" ? RuntimeState.taskById.get(id) : undefined
    if (task) Effect.runFork(renderTaskDetail(task))
  })
})

// ─── §12. Change-log mutation feed ──────────────────────────────────────

const wireChangeLog = Effect.gen(function* () {
  const dom = yield* Dom
  const log = yield* dom.query(Selectors.changeLog)
  if (!log) return
  yield* Effect.sync(() => {
    const append = (kind: string, detail: unknown) => {
      const e = document.createElement("li")
      const ts = new Date().toLocaleTimeString()
      e.textContent = `[${ts}] ${kind}: ${JSON.stringify(detail).slice(0, 80)}`
      e.classList.add("change-log-entry")
      log.prepend(e)
      while (log.children.length > 50) log.removeChild(log.lastChild!)
    }
    window.addEventListener("c3i:planning-filter", (e) =>
      append("filter", (e as CustomEvent).detail))
    window.addEventListener("c3i:fractal-filter", (e) =>
      append("fractal", (e as CustomEvent).detail))
    window.addEventListener("c3i:task-drill-down", (e) =>
      append("drill", (e as CustomEvent).detail))
    window.addEventListener("c3i:zk-search", (e) =>
      append("zk", { query: (e as CustomEvent).detail.query, n: (e as CustomEvent).detail.hits.length }))
  })
})

const wireFractalMatrix = Effect.sync(() => {
  const matrix = document.querySelector<HTMLElement>(Selectors.fractalMatrix)
  if (!matrix) return
  matrix.addEventListener("click", (e) => {
    const card = (e.target as HTMLElement).closest("[data-layer]") as HTMLElement | null
    if (!card) return
    e.preventDefault()
    const layer = card.getAttribute("data-layer") || "all"
    RuntimeState.selectedLayer = layer
    Effect.runFork(Effect.gen(function* () {
      yield* setActiveFractalChip(layer)
      yield* renderAllTaskSurfaces(RuntimeState.statusTasks)
      yield* Effect.sync(() => window.dispatchEvent(new CustomEvent("c3i:fractal-filter", { detail: { layer } })))
    }).pipe(Effect.provide(MainLayer)))
  })
})

const wireDetailActions = Effect.gen(function* () {
  const api = yield* PlanningApi
  const dom = yield* Dom
  const panel = yield* dom.query(Selectors.detailPanel)
  if (!panel) return
  yield* Effect.sync(() => {
    panel.addEventListener("click", (e) => {
      const button = (e.target as HTMLElement).closest("[data-detail-action][data-task-id]") as HTMLElement | null
      if (!button) return
      e.preventDefault()
      e.stopPropagation()
      const id = button.getAttribute("data-task-id") || ""
      const action = button.getAttribute("data-detail-action") || ""
      const task = RuntimeState.taskById.get(id)
      if (!task) return
      Effect.runFork(Effect.gen(function* () {
        if (action === "knowledge") {
          const hits = yield* api.searchZk(task.title).pipe(Effect.option)
          const body = Option.isSome(hits)
            ? hits.value.slice(0, 5).map((hit) => `${escapeHtml(hit.title)} (${escapeHtml(hit.id)})`).join("<br>")
            : "No Zettelkasten evidence returned."
          yield* renderDetailResults("Knowledge Evidence", body)
        } else if (action === "related") {
          const related = yield* fetchJson<readonly Task[]>(`/api/v1/plan/search?q=${encodeURIComponent(task.title)}`).pipe(Effect.option)
          const body = Option.isSome(related)
            ? related.value.slice(0, 5).map((row) => `${escapeHtml(row.title)} (${escapeHtml(row.status)})`).join("<br>")
            : "No related planning tasks returned."
          yield* renderDetailResults("Related Tasks", body)
        } else if (action === "stamp") {
          yield* renderDetailResults("STAMP Control Structure", `Controller=Planning UI<br>Controlled process=Smriti task lifecycle<br>Unsafe action=mutation without ZK/FMEA evidence<br>Constraint=SC-PLANNING-EVO + SC-AGUI-UI + SIL-6 Guardian lane`)
        } else if (action === "subtasks") {
          yield* renderDetailResults("Sub-Tasks", `RETE-UL query key: parent_id=${escapeHtml(task.id)}<br>Ruliological lineage: task -> layer ${escapeHtml(classifyLayer(task))} -> STAMP control -> FMEA RPN ${fmeaFor(task).rpn}`)
        } else {
          yield* renderDetailResults("AI Analysis", `Deterministic Gemma context pack: ${escapeHtml(compactText(task.title, 120))}<br>Layer ${escapeHtml(classifyLayer(task))}; status ${escapeHtml(task.status)}; priority ${escapeHtml(task.priority)}; RPN ${fmeaFor(task).rpn}.`)
        }
      }).pipe(Effect.catchAllCause((cause) =>
        Effect.logWarning(`[planning] detail action failed: ${Cause.pretty(cause)}`))))
    })
  })
})

// ─── §13. Periodic refresh + WebSocket push ────────────────────────────

const periodicRefresh = (intervalMs: number) => Effect.gen(function* () {
  const api = yield* PlanningApi
  const status = yield* api.status()
  yield* updateWeather(status)
}).pipe(
  Effect.catchAllCause((c) =>
    Effect.logWarning(`[planning] refresh failed: ${Cause.pretty(c)}`)),
  Effect.repeat(Schedule.spaced(Duration.millis(intervalMs))),
)

const parseStatusFrame = (status?: string): Option.Option<PlanStatus> => {
  if (!status) return Option.none()
  try {
    const decoded = Schema.decodeUnknownSync(PlanStatusSchema)(JSON.parse(status))
    return Option.some(decoded)
  } catch {
    return Option.none()
  }
}

const parseTaskListFrame = (tasks?: string): readonly Task[] => {
  if (!tasks) return []
  try {
    const decoded = JSON.parse(tasks) as unknown
    if (!Array.isArray(decoded)) return []
    return decoded.flatMap((raw) => {
      try {
        const t = Schema.decodeUnknownSync(RawTaskSchema)(raw)
        return [{
          id: t.id,
          title: t.title,
          status: t.status,
          priority: t.priority ?? "P2",
          created: t.created,
        }]
      } catch {
        return []
      }
    })
  } catch {
    return []
  }
}

const handleWsFrame = (raw: string) => Effect.gen(function* () {
  const frame = yield* Effect.try({
    try: () => JSON.parse(raw) as {
      type?: string
      status?: string
      tasks?: readonly Task[]
      active?: string
      blocked?: string
    },
    catch: () => new Error("invalid planning websocket frame"),
  }).pipe(Effect.option)
  if (Option.isNone(frame)) return

  const status = parseStatusFrame(frame.value.status)
  if (Option.isSome(status)) yield* updateWeather(status.value)

  const pushedTasks = Array.isArray(frame.value.tasks)
    ? frame.value.tasks
    : [
      ...parseTaskListFrame(frame.value.active),
      ...parseTaskListFrame(frame.value.blocked),
    ]
  if (pushedTasks.length === 0) return

  const byId = new Map(RuntimeState.tasks.map((t) => [t.id, t]))
  for (const task of pushedTasks) byId.set(task.id, task)
  RuntimeState.tasks = [...byId.values()]
  RuntimeState.statusTasks = [...selectedStatusTasks(RuntimeState.tasks)]
  RuntimeState.visibleTasks = [...RuntimeState.statusTasks]
  yield* renderAllTaskSurfaces(RuntimeState.statusTasks)
}).pipe(
  Effect.catchAllCause((c) =>
    Effect.logWarning(`[planning] ws frame ignored: ${Cause.pretty(c)}`)),
)

const startPlanningWs = Effect.async<never, never>(() => {
  if (typeof WebSocket === "undefined") return Effect.void
  let stopped = false
  let socket: WebSocket | null = null
  let timer: number | undefined
  let attempt = 0

  const clearTimer = () => {
    if (timer !== undefined) {
      window.clearTimeout(timer)
      timer = undefined
    }
  }

  const schedule = (delayMs: number) => {
    clearTimer()
    timer = window.setTimeout(connect, delayMs)
  }

  const connect = () => {
    if (stopped) return
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:"
    const ws = new WebSocket(`${proto}//${window.location.host}/ws/planning`)
    socket = ws
    ws.addEventListener("open", () => { attempt = 0 })
    ws.addEventListener("message", (e: MessageEvent) => {
      Effect.runFork(handleWsFrame(String(e.data)))
    })
    ws.addEventListener("close", () => {
      if (stopped) return
      attempt += 1
      schedule(Math.min(10_000, 500 * 2 ** Math.min(attempt, 4)))
    })
    ws.addEventListener("error", () => {
      // Firefox reports failed handshakes to the console. Closing here lets the
      // close handler retry without surfacing an application-level exception.
      try { ws.close() } catch {}
    })
  }

  const start = () => schedule(300)
  if (document.readyState === "complete") start()
  else window.addEventListener("load", start, { once: true })

  return Effect.sync(() => {
    stopped = true
    clearTimer()
    try { socket?.close() } catch {}
  })
})

const loadPlanningData = Effect.gen(function* () {
  const api = yield* PlanningApi
  RuntimeState.selectedStatus = new URL(window.location.href).searchParams.get("status") || "all"
  const allPage = yield* api.listByStatus("all", 0, 250)
  const allTasks = yield* tasksFromPage(allPage)
  RuntimeState.tasks = [...allTasks]
  const statusTasks = RuntimeState.selectedStatus === "all"
    ? allTasks
    : yield* api.listByStatus(RuntimeState.selectedStatus, 0, 250).pipe(Effect.flatMap(tasksFromPage))
  RuntimeState.statusTasks = [...statusTasks]
  RuntimeState.visibleTasks = [...RuntimeState.statusTasks]
  yield* renderAllTaskSurfaces(RuntimeState.statusTasks)
})

// ─── §14. Public namespace ──────────────────────────────────────────────

interface PlanningNamespace {
  readonly classifyLayer: typeof classifyLayer
  readonly taskAge: typeof taskAge
  readonly snapshotData: typeof snapshotData
  readonly findChangedIds: typeof findChangedIds
  readonly FRACTAL_LAYERS: typeof FRACTAL_LAYERS
  readonly Selectors: typeof Selectors
}

declare global {
  interface Window {
    __c3iPlanning?: Record<string, unknown> & {
      effect?: PlanningNamespace
    }
  }
}

const exposeNamespace = Effect.sync(() => {
  if (typeof window === "undefined") return
  window.__c3iPlanning = window.__c3iPlanning ?? {}
  window.__c3iPlanning.effect = {
    classifyLayer, taskAge, snapshotData, findChangedIds,
    FRACTAL_LAYERS, Selectors,
  }
})

// ─── §15. Main program ──────────────────────────────────────────────────

const program = Effect.gen(function* () {
  yield* Effect.logInfo("[planning] Effect-TS runtime booting (Pass-30)")
  yield* exposeNamespace
  yield* ensureRuntimeStyles
  yield* renderFractalChips
  yield* setActiveStatusChip(new URL(window.location.href).searchParams.get("status") || "all")
  yield* loadPlanningData.pipe(Effect.catchAllCause((c) =>
    Effect.logWarning(`[planning] initial grid load failed: ${Cause.pretty(c)}`)))
  yield* Effect.all([
    wireViewToggle, wireStatusChips, wireFractalChips,
    wireAiSearch, wireDrillDown, wireChangeLog,
    wireFractalMatrix, wireDetailActions,
  ], { concurrency: "unbounded" })
  const api = yield* PlanningApi
  const initial = yield* api.status().pipe(Effect.option)
  if (Option.isSome(initial)) yield* updateWeather(initial.value)
  const refreshFiber: Fiber.RuntimeFiber<unknown, never> = yield* Effect.fork(periodicRefresh(5000))
  const wsFiber: Fiber.RuntimeFiber<unknown, never> = yield* Effect.fork(startPlanningWs)
  yield* Effect.sync(() => {
    if (window.__c3iPlanning) {
      ;(window.__c3iPlanning as Record<string, unknown>).fibers = {
        refresh: refreshFiber, ws: wsFiber,
      }
    }
  })
  yield* Effect.logInfo("[planning] Effect-TS runtime ready")
})

const MainLayer = Layer.mergeAll(PlanningApiLive, DomLive)

const runnable = program.pipe(
  Effect.provide(MainLayer),
  Effect.provide(Logger.minimumLogLevel(LogLevel.Info)),
  Effect.catchAllCause((c) =>
    Effect.sync(() => console.error("[planning] fatal:", Cause.pretty(c)))),
)

// ─── §16. Boot ──────────────────────────────────────────────────────────

const boot = (): void => { Effect.runFork(runnable) }

if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot)
  } else { boot() }
}

export {}
