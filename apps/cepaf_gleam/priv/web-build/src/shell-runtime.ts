/**
 * shell-runtime.ts - Effect TypeScript IIFE for CSP-safe global cockpit UI.
 *
 * Replaces inline Lustre shell and Allium viewer scripts. The HTML CSP stays
 * at `script-src 'self'`; browser behavior is delivered by this bundled
 * same-origin asset.
 */

import { Effect, Schema, pipe } from "effect"

const Selectors = {
  help: "#c3i-help",
  healthDot: "#c3i-health-dot",
  activity: "#c3i-activity",
  alliumContent: "#allium-content",
} as const

const AlliumSpecSchema = Schema.Struct({
  name: Schema.optional(Schema.String),
  path: Schema.optional(Schema.String),
  content: Schema.optional(Schema.String),
  lines: Schema.optional(Schema.Number),
  viewer_url: Schema.optional(Schema.String),
  error: Schema.optional(Schema.String),
})

type AlliumSpec = Schema.Schema.Type<typeof AlliumSpecSchema>

const decodeWith = <S extends Schema.Schema.AnyNoContext>(
  schema: S,
  value: unknown,
  label: string,
): Effect.Effect<Schema.Schema.Type<S>, Error> =>
  Schema.decodeUnknown(schema)(value).pipe(
    Effect.mapError((err) => new Error(`${label}: ${String(err)}`)),
  )

const ready = (fn: () => void): void => {
  if (document.readyState !== "loading") fn()
  else document.addEventListener("DOMContentLoaded", fn)
}

const getOrCreate = (id: string, className: string): HTMLElement => {
  const existing = document.getElementById(id)
  if (existing) return existing
  const el = document.createElement("div")
  el.id = id
  el.className = className
  document.body.appendChild(el)
  return el
}

const installHelpOverlay = (): void => {
  const help = getOrCreate("c3i-help", "c3i-help-overlay")
  help.setAttribute("role", "dialog")
  help.setAttribute("aria-label", "C3I keyboard help")
  help.style.cssText = [
    "display:none",
    "position:fixed",
    "right:18px",
    "bottom:18px",
    "max-width:360px",
    "z-index:9998",
    "background:#0f1724",
    "color:#e0e6ed",
    "border:1px solid #3dd68c",
    "border-radius:8px",
    "box-shadow:0 16px 40px rgba(0,0,0,.45)",
    "font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace",
    "padding:14px 16px",
  ].join(";")
  help.innerHTML = [
    "<strong style=\"color:#3dd68c\">C3I shortcuts</strong>",
    "<div>? toggle help</div>",
    "<div>1-9 / 0 open top navigation entries</div>",
    "<div>[ and ] move through navigation</div>",
    "<div>Ctrl+K focus AI search when present</div>",
  ].join("")

  document.addEventListener("keydown", (event) => {
    const target = event.target as HTMLElement | null
    const tagName = target?.tagName.toLowerCase()
    const isEditable =
      tagName === "input" ||
      tagName === "textarea" ||
      target?.isContentEditable === true
    const isQuestion = event.key === "?" || (event.key === "/" && event.shiftKey)
    if (!isQuestion || isEditable) return
    event.preventDefault()
    help.style.display = help.style.display === "none" ? "block" : "none"
  })
}

const installHealthDot = (): void => {
  const dot = getOrCreate("c3i-health-dot", "c3i-health-dot")
  dot.setAttribute("aria-label", "C3I browser runtime health")
  dot.setAttribute("title", "C3I browser runtime active")
  dot.style.cssText = [
    "position:fixed",
    "right:14px",
    "top:14px",
    "width:12px",
    "height:12px",
    "border-radius:50%",
    "background:#3dd68c",
    "box-shadow:0 0 0 4px rgba(61,214,140,.14),0 0 18px rgba(61,214,140,.75)",
    "z-index:9999",
  ].join(";")

  const activity = getOrCreate("c3i-activity", "c3i-activity")
  activity.setAttribute("aria-live", "polite")
  activity.textContent = `runtime active: ${location.pathname}`
  activity.style.cssText = [
    "position:fixed",
    "left:-9999px",
    "width:1px",
    "height:1px",
    "overflow:hidden",
  ].join(";")
}

const installTableFilters = (): void => {
  document.querySelectorAll<HTMLTableElement>("table").forEach((table, index) => {
    if (table.dataset.c3iFilter === "1") return
    const rowCount = table.querySelectorAll("tbody tr").length
    if (rowCount < 4) return
    table.dataset.c3iFilter = "1"
    const input = document.createElement("input")
    input.type = "search"
    input.id = document.getElementById("c3i-search") === null ? "c3i-search" : `c3i-search-${index + 1}`
    input.placeholder = "Filter rows"
    input.setAttribute("aria-label", `Filter table ${index + 1}`)
    input.style.cssText = [
      "display:block",
      "width:min(100%,320px)",
      "margin:.5rem 0",
      "padding:.55rem .7rem",
      "background:#0f1724",
      "color:#e0e6ed",
      "border:1px solid #314966",
      "border-radius:6px",
    ].join(";")
    table.parentElement?.insertBefore(input, table)
    input.addEventListener("input", () => {
      const query = input.value.trim().toLowerCase()
      table.querySelectorAll<HTMLTableRowElement>("tbody tr").forEach((row) => {
        const hit = (row.textContent ?? "").toLowerCase().includes(query)
        row.style.display = query === "" || hit ? "" : "none"
      })
    })
  })
}

const isEditableTarget = (target: EventTarget | null): boolean => {
  const el = target as HTMLElement | null
  const tagName = el?.tagName.toLowerCase()
  return (
    tagName === "input" ||
    tagName === "textarea" ||
    tagName === "select" ||
    el?.isContentEditable === true
  )
}

const installKeyboardNavigation = (): void => {
  document.addEventListener("keydown", (event) => {
    if (isEditableTarget(event.target)) return

    const navLinks = Array.from(
      document.querySelectorAll<HTMLAnchorElement>("nav a[href]:not(.nav-brand)"),
    )
    const activeIndex = navLinks.findIndex((link) => link.classList.contains("active"))

    if (event.key === "j") {
      event.preventDefault()
      window.scrollBy(0, 80)
      return
    }

    if (event.key === "k") {
      event.preventDefault()
      window.scrollBy(0, -80)
      return
    }

    if (event.key >= "1" && event.key <= "9") {
      const index = Number(event.key) - 1
      const link = navLinks[index]
      if (link) {
        event.preventDefault()
        window.location.href = link.href
      }
      return
    }

    if (event.key === "0") {
      const link = navLinks[9]
      if (link) {
        event.preventDefault()
        window.location.href = link.href
      }
      return
    }

    if (event.key === "[" && activeIndex > 0) {
      event.preventDefault()
      window.location.href = navLinks[activeIndex - 1].href
      return
    }

    if (event.key === "]" && activeIndex >= 0 && activeIndex < navLinks.length - 1) {
      event.preventDefault()
      window.location.href = navLinks[activeIndex + 1].href
      return
    }

    if (event.key === "/" && !event.ctrlKey && !event.metaKey && !event.shiftKey) {
      const search = document.getElementById("c3i-search") as HTMLInputElement | null
      if (search) {
        event.preventDefault()
        search.focus()
      }
    }
  })
}

const escapeHtml = (input: string): string =>
  input
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")

const highlightAllium = (content: string): string =>
  escapeHtml(content)
    .replace(/^(--.*)$/gm, "<span style=\"color:#7a8fa6\">$1</span>")
    .replace(
      /\b(entity|rule|contract|config|invariant|surface|transitions|when|then|ensure|reject|requires|ensures)\b/g,
      "<span style=\"color:#3dd68c;font-weight:bold\">$1</span>",
    )
    .replace(
      /\b(salience|terminal|status|criticality)\b/g,
      "<span style=\"color:#f5a623\">$1</span>",
    )
    .replace(/&quot;([^&]*)&quot;/g, "<span style=\"color:#e0c882\">&quot;$1&quot;</span>")
    .replace(/"([^"]*)"/g, "<span style=\"color:#e0c882\">\"$1\"</span>")

const fetchAlliumSpec = (name: string): Effect.Effect<AlliumSpec, Error> =>
  pipe(
    Effect.tryPromise({
      try: async (): Promise<unknown> => {
        const response = await fetch(`/api/v1/allium/${encodeURIComponent(name)}`, {
          cache: "no-store",
        })
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`)
        }
        return response.json()
      },
      catch: (err) => new Error(String(err)),
    }),
    Effect.flatMap((value) => decodeWith(AlliumSpecSchema, value, "decode allium spec")),
  )

const installAlliumViewer = (): void => {
  const el = document.querySelector<HTMLElement>(Selectors.alliumContent)
  const spec = el?.dataset.spec
  if (!el || !spec) return

  const program = pipe(
    fetchAlliumSpec(spec),
    Effect.tap((data) =>
      Effect.sync(() => {
        if (data.content) {
          el.innerHTML = highlightAllium(data.content)
          el.style.color = "#e0e6ed"
          el.setAttribute("data-loaded", "true")
        } else {
          el.textContent = `Error: ${data.error ?? "unknown"}`
          el.setAttribute("data-loaded", "false")
        }
      }),
    ),
    Effect.catchAll((err) =>
      Effect.sync(() => {
        el.textContent = `Fetch error: ${err.message}`
        el.setAttribute("data-loaded", "false")
      }),
    ),
  )

  Effect.runPromise(program).catch(() => undefined)
}

ready(() => {
  installHealthDot()
  installHelpOverlay()
  installKeyboardNavigation()
  installTableFilters()
  installAlliumViewer()
  document.body.setAttribute("data-shell-runtime", "1")
})
