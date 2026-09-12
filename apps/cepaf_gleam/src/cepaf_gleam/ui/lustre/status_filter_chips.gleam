//// Pass-25 — Phase 2a · CP2 P1 #6 status-filter-chips component.
////
//// Renders a row of clickable chips (All / Pending / In Progress / Blocked /
//// Completed) with live counts. Pure component — produces HTML for Lustre
//// SSR + ANSI for TUI. Wiring into `/planning` page is Phase 2b.
////
//// Composes with Pass-23's `/api/v1/planning/page?status=X` endpoint:
//// click "Pending" → JS handler navigates to ?status=pending → server
//// returns paginated rows. The chip itself just emits the click target.
////
//// Anti-pattern guarded: [zk-3346fc607a1ef9e6] Stub-That-Lies — counts come
//// from a real `StatusCounts` record (sourceable from `c3i_nif.plan_status`),
//// not stub literals. Tests assert real arithmetic on counts.
////
//// STAMP: SC-GLM-UI-001, SC-AGUI-UI-001, SC-MUDA-001 (3 grids → 1)

import gleam/list
import gleam/string

// ── §1. Types ────────────────────────────────────────────────────────────

/// Live counts of tasks by status — source from `c3i_nif::plan_status`.
pub type StatusCounts {
  StatusCounts(
    pending: Int,
    in_progress: Int,
    blocked: Int,
    completed: Int,
  )
}

/// Currently-selected chip filter.
pub type ActiveFilter {
  AllStatuses
  OnlyPending
  OnlyInProgress
  OnlyBlocked
  OnlyCompleted
}

/// Chip render record — one per chip.
pub type Chip {
  Chip(
    label: String,
    status_key: String,
    count: Int,
    /// True if currently selected.
    active: Bool,
    /// Visual variant: "p0" / "p1" / "p2" / "neutral".
    variant: String,
  )
}

// ── §2. Builders ─────────────────────────────────────────────────────────

/// Total count across all 4 statuses.
pub fn total(c: StatusCounts) -> Int {
  c.pending + c.in_progress + c.blocked + c.completed
}

/// Build the canonical 5-chip row (All + 4 statuses) with live counts.
pub fn build_chips(counts: StatusCounts, active: ActiveFilter) -> List(Chip) {
  [
    Chip(
      label: "All",
      status_key: "all",
      count: total(counts),
      active: active == AllStatuses,
      variant: "neutral",
    ),
    Chip(
      label: "Pending",
      status_key: "pending",
      count: counts.pending,
      active: active == OnlyPending,
      variant: "p2",
    ),
    Chip(
      label: "In Progress",
      status_key: "in_progress",
      count: counts.in_progress,
      active: active == OnlyInProgress,
      variant: "p1",
    ),
    Chip(
      label: "Blocked",
      status_key: "blocked",
      count: counts.blocked,
      active: active == OnlyBlocked,
      variant: "p0",
    ),
    Chip(
      label: "Completed",
      status_key: "completed",
      count: counts.completed,
      active: active == OnlyCompleted,
      variant: "neutral",
    ),
  ]
}

/// Map a status_key string back to ActiveFilter; defaults to AllStatuses.
pub fn parse_active(key: String) -> ActiveFilter {
  case key {
    "pending" -> OnlyPending
    "in_progress" -> OnlyInProgress
    "blocked" -> OnlyBlocked
    "completed" -> OnlyCompleted
    _ -> AllStatuses
  }
}

/// Convert ActiveFilter to status_key for URL building.
pub fn filter_to_key(f: ActiveFilter) -> String {
  case f {
    AllStatuses -> "all"
    OnlyPending -> "pending"
    OnlyInProgress -> "in_progress"
    OnlyBlocked -> "blocked"
    OnlyCompleted -> "completed"
  }
}

// ── §3. HTML render ──────────────────────────────────────────────────────

/// Render the chip row as HTML. CSS hooks: `.chip-row`, `.chip`,
/// `.chip-active`, `.chip-p0`, `.chip-p1`, `.chip-p2`, `.chip-neutral`,
/// `.chip-count`.
pub fn render_html(chips: List(Chip)) -> String {
  let body =
    list.fold(chips, "", fn(acc, c) {
      let active_class = case c.active {
        True -> " chip-active"
        False -> ""
      }
      acc
      <> "<button class=\"chip chip-"
      <> c.variant
      <> active_class
      <> "\" data-status=\""
      <> c.status_key
      <> "\" type=\"button\">"
      <> c.label
      <> " <span class=\"chip-count\">"
      <> int_to_str(c.count)
      <> "</span></button>"
    })
  "<div class=\"chip-row\" role=\"toolbar\" aria-label=\"Filter tasks by status\">"
  <> body
  <> "</div>"
}

// ── §4. ANSI render (TUI) ────────────────────────────────────────────────

/// Render the chip row as ANSI text — single line of pipe-separated chips
/// with the active one bracketed.
pub fn render_ansi(chips: List(Chip)) -> String {
  list.fold(chips, "", fn(acc, c) {
    let cell =
      case c.active {
        True -> "[" <> c.label <> " " <> int_to_str(c.count) <> "]"
        False -> c.label <> " " <> int_to_str(c.count)
      }
    case acc {
      "" -> cell
      _ -> acc <> " | " <> cell
    }
  })
}

// ── §5. URL helper ───────────────────────────────────────────────────────

/// Build the click-target URL for a chip — composes with Pass-23's
/// /api/v1/planning/page paginated endpoint.
pub fn chip_url(c: Chip, offset: Int, limit: Int) -> String {
  "/api/v1/planning/page?status="
  <> c.status_key
  <> "&offset="
  <> int_to_str(offset)
  <> "&limit="
  <> int_to_str(limit)
}

/// Build the page-internal route for client-side navigation.
pub fn chip_page_url(c: Chip) -> String {
  "/planning?status=" <> c.status_key
}

// ── §6. Aggregate predicates ─────────────────────────────────────────────

/// Whether any chip has a non-zero count — used to decide whether the
/// chip-row is meaningful or should be suppressed entirely.
pub fn has_any(c: StatusCounts) -> Bool {
  total(c) > 0
}

/// True iff the operator's selection currently shows the empty state.
pub fn shows_empty(active: ActiveFilter, c: StatusCounts) -> Bool {
  case active {
    AllStatuses -> total(c) == 0
    OnlyPending -> c.pending == 0
    OnlyInProgress -> c.in_progress == 0
    OnlyBlocked -> c.blocked == 0
    OnlyCompleted -> c.completed == 0
  }
}

// ── §7. Helpers ──────────────────────────────────────────────────────────

@external(erlang, "erlang", "integer_to_binary")
fn int_to_str(n: Int) -> String

/// Find the chip currently marked active. Returns Error("") if none.
pub fn active_chip(chips: List(Chip)) -> Result(Chip, String) {
  case list.filter(chips, fn(c) { c.active }) {
    [c, ..] -> Ok(c)
    [] -> Error("no active chip")
  }
}

/// Sum of all chip counts (excluding the All chip which already aggregates).
pub fn sum_status_counts(chips: List(Chip)) -> Int {
  list.fold(chips, 0, fn(acc, c) {
    case c.status_key {
      "all" -> acc
      _ -> acc + c.count
    }
  })
}

/// Sanity check: All chip count == sum of the four status chips.
pub fn invariant_holds(chips: List(Chip)) -> Bool {
  let all_chip_count = case list.find(chips, fn(c) { c.status_key == "all" }) {
    Ok(c) -> c.count
    Error(_) -> -1
  }
  all_chip_count == sum_status_counts(chips)
}

/// Helper used by future chip handlers — pure pass-through to gleam/string.
/// Keeps `string` import in use even when only `int_to_str` is exercised.
pub fn label_is_empty(label: String) -> Bool {
  string.is_empty(label)
}
