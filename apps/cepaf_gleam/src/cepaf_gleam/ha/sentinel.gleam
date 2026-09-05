//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/sentinel</module>
////     <fsharp-lineage>None — novel sentinel patrol actor (Symbiosis Sprint)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Sentinel patrol — walks all 35 pages in round-robin order,
////       verifies truth at each, raises alarm when a page lies.
////       Implements the SC-SATYA-002 self-observation loop.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SATYA-002, SC-TRUTH-001, SC-SIL4-001, SC-FUNC-002</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Watchman patrol pattern ↪ Gleam pure state machine.
////       Patrol advances one page per tick; alarm fires on first lie detected.
////       No IO — caller owns persistence and scheduling.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// SENTINEL PATROL AGENT — ROUND-ROBIN TRUTH VERIFICATION
//// यत्र योगेश्वरः कृष्णो यत्र पार्थो धनुर्धरः
//// Where the guardian patrols, there is truth (Gita 18.78, adapted)
////
//// The sentinel walks all 35 pages in a circuit.
//// At each stop it checks whether the page reports truth.
//// A single lie raises an alarm; the alarm clears when that page passes.
////
//// STAMP: SC-SATYA-002, SC-TRUTH-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Static metadata about a page in the patrol circuit.
pub type PageInfo {
  PageInfo(
    /// Page name used in logs and alarms
    name: String,
    /// HTTP route path
    route: String,
    /// Number of invariants that the sentinel checks on this page
    invariant_count: Int,
  )
}

/// Result of a single page truth-check.
pub type PageCheckResult {
  PageCheckResult(
    /// Name of the checked page
    page: String,
    /// True when all invariants passed
    truthful: Bool,
    /// Wall-clock milliseconds (modelled as Int; real impl fills from system)
    check_time_ms: Int,
    /// Which patrol cycle this result belongs to (1-based)
    cycle: Int,
  )
}

/// Mutable sentinel patrol state — pure record, caller owns storage.
pub type SentinelState {
  SentinelState(
    /// Index into `pages` list — next page to check
    current_index: Int,
    /// Ordered patrol circuit (35 pages)
    pages: List(PageInfo),
    /// How many complete circuits have finished
    patrol_count: Int,
    /// All check results accumulated (most-recent first)
    results: List(PageCheckResult),
    /// True when the last check raised an alarm
    alarm_active: Bool,
    /// Name of the page that triggered the current alarm ("" when none)
    alarm_page: String,
    /// Running total of all checks performed
    total_checks: Int,
  )
}

/// Outcome of one patrol step.
pub type SentinelAction {
  /// Page passed truth check — all nominal
  SentinelOk
  /// Page failed truth check — sentinel raises alarm
  /// #(page_name, route)
  SentinelAlarm(page_name: String, route: String)
  /// Completed a full circuit; carries the patrol count
  CircuitComplete(patrol_count: Int)
}

// ---------------------------------------------------------------------------
// Canonical page list — 35 pages
// ---------------------------------------------------------------------------

/// The complete patrol circuit — all 35 C3I pages.
pub fn all_pages() -> List(PageInfo) {
  [
    PageInfo("dashboard", "/dashboard", 12),
    PageInfo("planning", "/planning", 8),
    PageInfo("immune", "/immune", 10),
    PageInfo("knowledge", "/knowledge", 6),
    PageInfo("zenoh", "/zenoh", 9),
    PageInfo("cockpit", "/cockpit", 11),
    PageInfo("verification", "/verification", 14),
    PageInfo("substrate", "/substrate", 5),
    PageInfo("metabolic", "/metabolic", 7),
    PageInfo("podman", "/podman", 8),
    PageInfo("mcp", "/mcp", 6),
    PageInfo("kms", "/kms", 9),
    PageInfo("telemetry", "/telemetry", 7),
    PageInfo("agents", "/agents", 10),
    PageInfo("bridge", "/bridge", 5),
    PageInfo("config", "/config", 4),
    PageInfo("database", "/database", 6),
    PageInfo("git", "/git", 4),
    PageInfo("holon", "/holon", 5),
    PageInfo("prajna", "/prajna", 8),
    PageInfo("smriti", "/smriti", 7),
    PageInfo("planning_dashboard", "/planning-dashboard", 6),
    PageInfo("integrity", "/integrity", 11),
    PageInfo("evolution", "/evolution", 8),
    PageInfo("biomorphic", "/biomorphic", 9),
    PageInfo("homeostasis", "/homeostasis", 10),
    PageInfo("bicameral", "/bicameral", 7),
    PageInfo("singularity", "/singularity", 6),
    PageInfo("federation", "/federation", 8),
    PageInfo("health_grid", "/health-grid", 9),
    PageInfo("component_demo", "/component-demo", 4),
    PageInfo("zenoh_browser", "/zenoh-browser", 5),
    PageInfo("heartbeat", "/heartbeat", 6),
    PageInfo("health_product", "/health-product", 7),
    PageInfo("sentinel", "/sentinel", 8),
  ]
}

// ---------------------------------------------------------------------------
// Initialisation
// ---------------------------------------------------------------------------

/// Create a fresh sentinel state ready to patrol.
pub fn init() -> SentinelState {
  SentinelState(
    current_index: 0,
    pages: all_pages(),
    patrol_count: 0,
    results: [],
    alarm_active: False,
    alarm_page: "",
    total_checks: 0,
  )
}

// ---------------------------------------------------------------------------
// Core patrol logic
// ---------------------------------------------------------------------------

/// Check a single page for truth.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Proprioception probe ↪ PageCheckResult</morphism>
///   <formal-proof>
///     <P> Pre: page is a valid PageInfo </P>
///     <C> check_page(page) </C>
///     <Q> Post: result.page = page.name; result.truthful = True (stub — real impl queries self_observer) </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn check_page(page: PageInfo) -> PageCheckResult {
  // Stub implementation — truth always passes.
  // Real implementation would call self_observer.check_invariants(page.name).
  PageCheckResult(page: page.name, truthful: True, check_time_ms: 1, cycle: 0)
}

/// Advance the patrol by one step: check the current page, then move forward.
///
/// Returns the updated state and the action that describes what happened.
pub fn patrol_next(state: SentinelState) -> #(SentinelState, SentinelAction) {
  let page_count = list.length(state.pages)
  case page_count {
    0 -> #(state, SentinelOk)
    _ -> {
      let safe_index = state.current_index % page_count
      let maybe_page =
        state.pages
        |> list.drop(safe_index)
        |> list.first()

      case maybe_page {
        Error(_) -> #(state, SentinelOk)
        Ok(page) -> {
          let raw_result = check_page(page)
          let cycle = state.total_checks / page_count + 1
          let result = PageCheckResult(..raw_result, cycle: cycle)

          let next_index = safe_index + 1
          let #(wrapped_index, new_patrol_count) = case
            next_index >= page_count
          {
            True -> #(0, state.patrol_count + 1)
            False -> #(next_index, state.patrol_count)
          }

          let new_results = [result, ..state.results]
          let new_total = state.total_checks + 1

          case result.truthful {
            True -> {
              let alarm_still_active = case state.alarm_active {
                True -> state.alarm_page != page.name
                False -> False
              }
              let new_state =
                SentinelState(
                  ..state,
                  current_index: wrapped_index,
                  patrol_count: new_patrol_count,
                  results: new_results,
                  alarm_active: alarm_still_active,
                  alarm_page: case alarm_still_active {
                    True -> state.alarm_page
                    False -> ""
                  },
                  total_checks: new_total,
                )
              let action = case wrapped_index == 0 && next_index >= page_count {
                True -> CircuitComplete(new_patrol_count)
                False -> SentinelOk
              }
              #(new_state, action)
            }
            False -> {
              let new_state =
                SentinelState(
                  ..state,
                  current_index: wrapped_index,
                  patrol_count: new_patrol_count,
                  results: new_results,
                  alarm_active: True,
                  alarm_page: page.name,
                  total_checks: new_total,
                )
              #(new_state, SentinelAlarm(page.name, page.route))
            }
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Query helpers
// ---------------------------------------------------------------------------

/// Names of pages that failed their most recent truth check.
pub fn alarm_pages(state: SentinelState) -> List(String) {
  state.results
  |> list.filter(fn(r) { r.truthful == False })
  |> list.map(fn(r) { r.page })
}

/// Patrol health score in [0.0, 1.0].
/// Returns 1.0 when no checks have been performed yet (optimistic start).
pub fn patrol_health(state: SentinelState) -> Float {
  case state.total_checks {
    0 -> 1.0
    _ -> {
      let failed =
        state.results
        |> list.filter(fn(r) { r.truthful == False })
        |> list.length()
      let failed_f = int.to_float(failed)
      let total_f = int.to_float(state.total_checks)
      let ratio = failed_f /. total_f
      case ratio >. 1.0 {
        True -> 0.0
        False -> 1.0 -. ratio
      }
    }
  }
}

/// Human-readable summary of sentinel state.
pub fn summary(state: SentinelState) -> String {
  let page_count = list.length(state.pages)
  let health_pct = float.round(patrol_health(state) *. 100.0)
  let alarm_str = case state.alarm_active {
    True -> " ALARM:" <> state.alarm_page
    False -> ""
  }
  string.join(
    [
      "Sentinel[pages=",
      int.to_string(page_count),
      " checks=",
      int.to_string(state.total_checks),
      " circuits=",
      int.to_string(state.patrol_count),
      " health=",
      int.to_string(health_pct),
      "%",
      alarm_str,
      "]",
    ],
    "",
  )
}
