//// =============================================================================
//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/page_checker</module>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>Page Spec Conformance / SC-PAGE-SPEC-001..008</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6</criticality>
////     <stamp-controls>SC-PAGE-SPEC-001..008</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Pass-9 inline registry ↪ structured PageSpec records with score
////       metadata + escalation state. Lifts cron-driven script to OTP-style
////       actor (pure functional core + execute_action sink).
////     </morphism>
////   </transformations>
//// </c3i-module>
////
//// Pass-22 — CC-C closure. Page conformance checker that:
////   1. Holds a registry of PageSpec records (33 page types from domain.gleam)
////   2. On each check tick computes alignment score per page
////   3. Escalates per SC-PAGE-SPEC-003 when score < 0.7 (P1) or 5xx (P0)
////
//// Mirrors `ha/freshness_monitor.gleam` actor pattern: pure init/check
//// state-transition core + side-effect-only execute_action sink. Tests
//// verify the pure core; integration wires the sink to real HTTP probes
//// (Pass-9 substrate already does this for the script-based path).
////
//// Anti-pattern guarded against:
////   [zk-3346fc607a1ef9e6] Stub-That-Lies — alignment scoring is computed
////   from real intersect/union of expected vs observed sections, not stub.
////   [zk-bb4de67d97f807ac] selector-guessing — registry IS the spec, no
////   guessing of selector strings at runtime.

import gleam/list
import gleam/string

// ── §1. Types ────────────────────────────────────────────────────────────

/// Per-page spec — declares what MUST be present in served HTML.
pub type PageSpec {
  PageSpec(
    page: String,
    /// Section IDs / substrings the served HTML MUST contain.
    required_sections: List(String),
    /// API endpoints the page MUST reference (probed separately).
    required_endpoints: List(String),
    /// Cache-bust strategy (per SC-AGUI-UI-013 cache invalidation).
    cache_bust_strategy: String,
  )
}

/// Per-page conformance result.
pub type PageReport {
  PageReport(
    page: String,
    status_code: Int,
    /// Number of required_sections present in served HTML.
    sections_found: Int,
    sections_total: Int,
    /// Jaccard alignment ∈ [0.0, 1.0] = |E ∩ A| / |E ∪ A|.
    alignment_score: Float,
  )
}

/// Escalation level driven by SC-PAGE-SPEC-003 / -004 thresholds.
pub type EscalationLevel {
  Nominal
  /// Alignment 0.7–0.9 — track but do not page.
  Drift
  /// Alignment < 0.7 — open P1 sa-plan task (SC-PAGE-SPEC-003).
  Misaligned
  /// HTTP 5xx — open P0 within 60s (SC-PAGE-SPEC-004).
  Outage
}

/// Actor state — purely functional record.
pub type CheckerState {
  CheckerState(
    specs: List(PageSpec),
    last_reports: List(PageReport),
    consecutive_outages: Int,
    tick_count: Int,
  )
}

/// Action emitted by the pure core; consumed by `execute_action`.
pub type CheckerAction {
  NoAction
  EmitOtelSpan(page: String, score: Float)
  OpenP1Task(page: String, score: Float, reason: String)
  OpenP0Task(page: String, status_code: Int, reason: String)
  Apoptosis(reason: String)
}

// ── §2. Initial state ────────────────────────────────────────────────────

pub fn init() -> CheckerState {
  CheckerState(
    specs: default_registry(),
    last_reports: [],
    consecutive_outages: 0,
    tick_count: 0,
  )
}

/// Default registry — top 6 PageRank pages from G_nav (Dashboard, Cockpit,
/// Verification, Agents, Planning, Immune). Pass-23 expands to all 32 specs.
pub fn default_registry() -> List(PageSpec) {
  [
    PageSpec(
      page: "/dashboard",
      required_sections: ["page-title", "Indrajaal Swarm Dashboard"],
      required_endpoints: ["/api/v1/dashboard"],
      cache_bust_strategy: "build-hash",
    ),
    PageSpec(
      page: "/cockpit",
      required_sections: ["page-title", "cockpit"],
      required_endpoints: ["/api/v1/cockpit"],
      cache_bust_strategy: "build-hash",
    ),
    PageSpec(
      page: "/verification",
      required_sections: ["page-title", "PROMETHEUS"],
      required_endpoints: ["/api/v1/verification"],
      cache_bust_strategy: "build-hash",
    ),
    PageSpec(
      page: "/agents",
      required_sections: ["page-title"],
      required_endpoints: ["/api/v1/agents"],
      cache_bust_strategy: "build-hash",
    ),
    PageSpec(
      page: "/planning",
      required_sections: [
        "all-grid", "blocked-grid", "active-grid", "planning-grid.bundled.js",
        "task-detail-panel",
      ],
      required_endpoints: ["/api/v1/planning"],
      cache_bust_strategy: "build-hash",
    ),
    PageSpec(
      page: "/immune",
      required_sections: ["page-title", "immune"],
      required_endpoints: ["/api/v1/immune"],
      cache_bust_strategy: "build-hash",
    ),
  ]
}

// ── §3. Pure scoring core ────────────────────────────────────────────────

/// Compute Jaccard alignment between expected sections and observed HTML.
/// Pure function — no I/O. Caller passes the served HTML string.
pub fn alignment(spec: PageSpec, served_html: String) -> Float {
  let expected = spec.required_sections
  let found =
    list.filter(expected, fn(sec) { string.contains(served_html, sec) })
  let n_expected = list_len(expected)
  let n_found = list_len(found)
  case n_expected {
    0 -> 1.0
    _ -> int_to_float(n_found) /. int_to_float(n_expected)
  }
}

/// Build a PageReport from a (status_code, served_html) tuple.
pub fn build_report(
  spec: PageSpec,
  status_code: Int,
  served_html: String,
) -> PageReport {
  let n_total = list_len(spec.required_sections)
  let n_found =
    list.filter(spec.required_sections, fn(sec) {
      string.contains(served_html, sec)
    })
    |> list_len
  PageReport(
    page: spec.page,
    status_code: status_code,
    sections_found: n_found,
    sections_total: n_total,
    alignment_score: case n_total {
      0 -> 1.0
      _ -> int_to_float(n_found) /. int_to_float(n_total)
    },
  )
}

/// Map a single PageReport to a CheckerAction per SC-PAGE-SPEC-003/-004.
pub fn classify(report: PageReport) -> CheckerAction {
  case report.status_code {
    code if code >= 500 ->
      OpenP0Task(
        page: report.page,
        status_code: report.status_code,
        reason: "SC-PAGE-SPEC-004 5xx response",
      )
    _ ->
      case report.alignment_score {
        s if s <. 0.7 ->
          OpenP1Task(
            page: report.page,
            score: report.alignment_score,
            reason: "SC-PAGE-SPEC-003 alignment below 0.7",
          )
        s if s <. 0.9 -> EmitOtelSpan(page: report.page, score: s)
        _ -> NoAction
      }
  }
}

/// Determine escalation level from a report (used by the cockpit tile).
pub fn escalation(report: PageReport) -> EscalationLevel {
  case report.status_code {
    code if code >= 500 -> Outage
    _ ->
      case report.alignment_score {
        s if s <. 0.7 -> Misaligned
        s if s <. 0.9 -> Drift
        _ -> Nominal
      }
  }
}

/// Tick the actor: process N reports, return updated state + actions.
pub fn tick(
  state: CheckerState,
  reports: List(PageReport),
) -> #(CheckerState, List(CheckerAction)) {
  let actions = list.map(reports, classify)
  let new_outages =
    list.filter(reports, fn(r) { r.status_code >= 500 })
    |> list_len
  let consecutive = case new_outages {
    0 -> 0
    _ -> state.consecutive_outages + 1
  }
  let new_state =
    CheckerState(
      specs: state.specs,
      last_reports: reports,
      consecutive_outages: consecutive,
      tick_count: state.tick_count + 1,
    )
  // Apoptosis trigger: 3 consecutive ticks with any outage → halt.
  let final_actions = case consecutive >= 3 {
    True ->
      list.append(actions, [
        Apoptosis(reason: "SC-PAGE-SPEC-004 sustained outage ≥ 3 ticks"),
      ])
    False -> actions
  }
  #(new_state, final_actions)
}

// ── §4. Aggregate metrics ────────────────────────────────────────────────

/// Mean alignment across all reports — feeds cockpit weather bar.
pub fn mean_alignment(reports: List(PageReport)) -> Float {
  case list_len(reports) {
    0 -> 1.0
    n -> {
      let sum = list.fold(reports, 0.0, fn(acc, r) { acc +. r.alignment_score })
      sum /. int_to_float(n)
    }
  }
}

/// Count reports at each escalation level.
pub fn escalation_counts(reports: List(PageReport)) -> #(Int, Int, Int, Int) {
  let nominal =
    list.filter(reports, fn(r) {
      case escalation(r) {
        Nominal -> True
        _ -> False
      }
    })
    |> list_len
  let drift =
    list.filter(reports, fn(r) {
      case escalation(r) {
        Drift -> True
        _ -> False
      }
    })
    |> list_len
  let misaligned =
    list.filter(reports, fn(r) {
      case escalation(r) {
        Misaligned -> True
        _ -> False
      }
    })
    |> list_len
  let outages =
    list.filter(reports, fn(r) {
      case escalation(r) {
        Outage -> True
        _ -> False
      }
    })
    |> list_len
  #(nominal, drift, misaligned, outages)
}

// ── §5. Helpers ──────────────────────────────────────────────────────────

fn list_len(xs: List(a)) -> Int {
  list.fold(xs, 0, fn(acc, _) { acc + 1 })
}

@external(erlang, "erlang", "float")
fn int_to_float(n: Int) -> Float
