//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/slo_tracker</module>
////     <fsharp-lineage>None — novel quantitative reliability management layer (F02/F29)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       SLI/SLO Dashboard (F02) and Error Budget Tracking (F29).
////       Implements Google SRE quantitative reliability management:
////       tracks Service Level Indicators, Service Level Objectives,
////       and the remaining error budget for C3I's 4 core reliability targets.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-ZEN-001, SC-MUDA-001, SC-FUNC-002</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Google SRE SLO model ↪ Gleam pure functions.
////       SLI = good_events / total_events (ratio in [0.0, 1.0]).
////       Error budget = 1.0 - (1.0 - target) consumed by violations.
////       All state passed by value; zero side-effects; caller owns persistence.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// SLI/SLO DASHBOARD — QUANTITATIVE RELIABILITY MANAGEMENT
//// यो मामजमनादिं च — One who knows the unborn, beginningless (Gita 10.3)
////
//// Implements F02 (SLI/SLO Dashboard) and F29 (Error Budget Tracking) from the
//// Google SRE reliability model. The system tracks four core reliability targets:
////
////   1. truth_slo     — 99.999999% of renders show truthful data (P(lie) < 10⁻⁸)
////   2. freshness_slo — 99.9% of data < 60s old
////   3. availability_slo — 99.9% of health checks return "ok"
////   4. latency_slo   — 99% of renders complete in < 100ms
////
//// Design principles:
////   1. PURE — no IO, no side effects; all state passed by value
////   2. INCREMENTAL — good/total counters updated atomically per event
////   3. BUDGET-AWARE — error budget consumed = (violations / total) / (1 - target)
////   4. STATUS-DRIVEN — SLOMet / SLOAtRisk / SLOViolated thresholds
////   5. OBSERVABLE — to_json / summary give structured + human-readable output
////
//// Error budget arithmetic (Google SRE §4):
////   allowed_errors  = total_events * (1.0 - target)
////   bad_events      = total_events - good_events
////   budget_consumed = bad_events / allowed_errors   (clamped to [0.0, 1.0])
////   budget_remaining = 1.0 - budget_consumed
////
//// Status thresholds:
////   SLOMet      — budget_consumed <  50%
////   SLOAtRisk   — budget_consumed >= 50% and < 100%
////   SLOViolated — budget_consumed >= 100%
////
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-ZEN-001, SC-MUDA-001, SC-FUNC-002

import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Pipeline-oriented types (request-level SLO tracking)
// ---------------------------------------------------------------------------

/// A single HTTP request measurement captured in the pipeline.
///
/// endpoint    — path or route label (e.g. "/api/v1/health")
/// latency_ms  — elapsed wall-clock milliseconds for the request
/// status_code — HTTP response status code (200, 404, 500, …)
/// timestamp_ms — Unix epoch in milliseconds at request arrival
pub type SloMetric {
  SloMetric(
    endpoint: String,
    latency_ms: Int,
    status_code: Int,
    timestamp_ms: Int,
  )
}

/// Accumulated pipeline SLO budget — pure value, caller owns persistence.
///
/// latency_target_ms     — target: requests faster than this count as "fast"
/// latency_slo_percent   — objective, e.g. 99.9 means 99.9 % must be fast
/// availability_slo_percent — objective, e.g. 99.5 means 99.5 % must be non-5xx
/// total_requests        — total events observed
/// fast_requests         — requests that met the latency target
/// successful_requests   — requests with status_code < 500
pub type SloBudget {
  SloBudget(
    latency_target_ms: Int,
    latency_slo_percent: Float,
    availability_slo_percent: Float,
    total_requests: Int,
    fast_requests: Int,
    successful_requests: Int,
  )
}

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Service Level Indicator — a single measurable signal.
///
/// value = good_events / total_events, clamped to [0.0, 1.0].
/// When total_events = 0, value = 1.0 (assume healthy until measured).
pub type SLI {
  SLI(
    /// Stable identifier, e.g. "truth_rate", "freshness", "render_latency"
    name: String,
    /// Events that met the objective (good path)
    good_events: Int,
    /// Total events measured (good + bad)
    total_events: Int,
    /// Computed ratio: good_events / total_events in [0.0, 1.0]
    value: Float,
  )
}

/// Service Level Objective — a reliability target backed by an SLI.
pub type SLO {
  SLO(
    /// Stable identifier, e.g. "truth_slo"
    name: String,
    /// Target SLI value, e.g. 0.99999999 for eight-nines
    target: Float,
    /// Measurement window in seconds (e.g. 86_400 for 1 day)
    window_seconds: Int,
    /// Current SLI reading in [0.0, 1.0]
    current_sli: Float,
    /// Fraction of error budget still available [0.0, 1.0]
    budget_remaining: Float,
    /// Fraction of error budget consumed [0.0, 1.0] (clamped)
    budget_consumed_pct: Float,
    /// Tracking status
    status: SLOStatus,
  )
}

/// Three-state SLO health signal.
pub type SLOStatus {
  /// Budget consumed < 50% — on track
  SLOMet
  /// Budget consumed >= 50% and < 100% — watch carefully
  SLOAtRisk
  /// Budget consumed >= 100% — objective window violated
  SLOViolated
}

/// Internal per-SLO event counter — accumulates raw measurements.
pub type SLOCounter {
  SLOCounter(
    /// Stable identifier matching SLO.name
    name: String,
    /// Target carried through for budget computation
    target: Float,
    /// Measurement window in seconds
    window_seconds: Int,
    /// Total good events recorded
    good_events: Int,
    /// Total events recorded (good + bad)
    total_events: Int,
  )
}

/// SLO Tracker state — holds all counters and a monotonic check counter.
pub type SLOTrackerState {
  SLOTrackerState(
    /// Raw per-SLO event accumulators
    counters: List(SLOCounter),
    /// Total number of record_event calls across all SLOs
    total_checks: Int,
    /// Monotonic counter used as a logical timestamp
    last_check_timestamp: Int,
  )
}

// ---------------------------------------------------------------------------
// C3I core SLO definitions
// ---------------------------------------------------------------------------

/// C3I's four core SLO targets (production-grade, Google SRE §4).
const truth_target: Float = 0.99999999

const freshness_target: Float = 0.999

const availability_target: Float = 0.999

const latency_target: Float = 0.99

const one_day_seconds: Int = 86_400

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise the tracker with C3I's four core SLOs, all counters at zero.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Bootstrap ↪ SLOTrackerState with zero counters</morphism>
///   <formal-proof>
///     <P> Pre: none </P>
///     <C> init() </C>
///     <Q> Post: 4 counters present, all good_events = 0, all total_events = 0,
///         total_checks = 0, last_check_timestamp = 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init() -> SLOTrackerState {
  SLOTrackerState(
    counters: [
      SLOCounter(
        name: "truth_slo",
        target: truth_target,
        window_seconds: one_day_seconds,
        good_events: 0,
        total_events: 0,
      ),
      SLOCounter(
        name: "freshness_slo",
        target: freshness_target,
        window_seconds: one_day_seconds,
        good_events: 0,
        total_events: 0,
      ),
      SLOCounter(
        name: "availability_slo",
        target: availability_target,
        window_seconds: one_day_seconds,
        good_events: 0,
        total_events: 0,
      ),
      SLOCounter(
        name: "latency_slo",
        target: latency_target,
        window_seconds: one_day_seconds,
        good_events: 0,
        total_events: 0,
      ),
    ],
    total_checks: 0,
    last_check_timestamp: 0,
  )
}

/// Record one event (good or bad) against the named SLO.
///
/// If slo_name does not match any known SLO, the state is returned unchanged.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Event ↪ updated SLOTrackerState</morphism>
///   <formal-proof>
///     <P> Pre: state is valid; slo_name is a known SLO identifier </P>
///     <C> record_event(state, slo_name, is_good) </C>
///     <Q> Post: matching counter has total_events + 1;
///         if is_good then good_events + 1 else good_events unchanged;
///         total_checks incremented; last_check_timestamp incremented </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn record_event(
  state: SLOTrackerState,
  slo_name: String,
  is_good: Bool,
) -> SLOTrackerState {
  let new_counters =
    list.map(state.counters, fn(c) {
      case c.name == slo_name {
        False -> c
        True ->
          SLOCounter(
            ..c,
            good_events: case is_good {
              True -> c.good_events + 1
              False -> c.good_events
            },
            total_events: c.total_events + 1,
          )
      }
    })
  SLOTrackerState(
    counters: new_counters,
    total_checks: state.total_checks + 1,
    last_check_timestamp: state.last_check_timestamp + 1,
  )
}

/// Return the current status of every SLO.
pub fn check_budgets(state: SLOTrackerState) -> List(#(String, SLOStatus)) {
  list.map(state.counters, fn(c) {
    let slo = counter_to_slo(c)
    #(slo.name, slo.status)
  })
}

/// Remaining error budget for a specific SLO, in [0.0, 1.0].
///
/// Returns 1.0 (full budget) when the SLO name is unknown or no events
/// have been recorded yet.
pub fn budget_remaining(state: SLOTrackerState, slo_name: String) -> Float {
  case list.find(state.counters, fn(c) { c.name == slo_name }) {
    Error(_) -> 1.0
    Ok(c) -> {
      let slo = counter_to_slo(c)
      slo.budget_remaining
    }
  }
}

/// Serialise the full tracker state to a JSON string.
///
/// Output shape:
///   { "page": "SLO Dashboard", "slos": [ { ... } ], "total_checks": N }
pub fn to_json(state: SLOTrackerState) -> String {
  let slos = list.map(state.counters, fn(c) { slo_to_json_object(c) })
  json.object([
    #("page", json.string("SLO Dashboard")),
    #("slos", json.array(slos, fn(x) { x })),
    #("total_checks", json.int(state.total_checks)),
    #("last_check_timestamp", json.int(state.last_check_timestamp)),
  ])
  |> json.to_string()
}

/// Human-readable summary of all SLO statuses.
pub fn summary(state: SLOTrackerState) -> String {
  let lines =
    list.map(state.counters, fn(c) {
      let slo = counter_to_slo(c)
      let status_label = status_to_string(slo.status)
      let pct_remaining =
        float.to_string(
          float.round(slo.budget_remaining *. 1000.0)
          |> int.to_float()
          |> float.divide(10.0)
          |> result_to_float(),
        )
      "  ["
      <> status_label
      <> "] "
      <> slo.name
      <> " — SLI: "
      <> float_to_pct_string(slo.current_sli)
      <> "  budget remaining: "
      <> pct_remaining
      <> "%"
    })
  let header =
    "SLO Tracker — " <> int.to_string(state.total_checks) <> " checks recorded"
  string.join([header, ..lines], "\n")
}

// ---------------------------------------------------------------------------
// Pipeline-oriented API (SloBudget / SloMetric)
// ---------------------------------------------------------------------------

/// Initialise a fresh SloBudget with C3I defaults.
///
/// Defaults:
///   latency_target_ms     = 500  (Google SRE p99 guideline for internal APIs)
///   latency_slo_percent   = 99.9 (three-nines)
///   availability_slo_percent = 99.5
///   all counters          = 0
pub fn init_budget() -> SloBudget {
  SloBudget(
    latency_target_ms: 500,
    latency_slo_percent: 99.9,
    availability_slo_percent: 99.5,
    total_requests: 0,
    fast_requests: 0,
    successful_requests: 0,
  )
}

/// Record one HTTP request observation into the budget.
///
/// A request is "fast" if metric.latency_ms <= budget.latency_target_ms.
/// A request is "successful" if metric.status_code < 500.
pub fn record(budget: SloBudget, metric: SloMetric) -> SloBudget {
  let is_fast = metric.latency_ms <= budget.latency_target_ms
  let is_successful = metric.status_code < 500
  SloBudget(
    ..budget,
    total_requests: budget.total_requests + 1,
    fast_requests: case is_fast {
      True -> budget.fast_requests + 1
      False -> budget.fast_requests
    },
    successful_requests: case is_successful {
      True -> budget.successful_requests + 1
      False -> budget.successful_requests
    },
  )
}

/// Current latency SLI as a percentage (0.0–100.0).
///
/// Returns 100.0 when no requests have been recorded (assume healthy).
pub fn latency_sli(budget: SloBudget) -> Float {
  case budget.total_requests {
    0 -> 100.0
    _ -> {
      let fast_f = int.to_float(budget.fast_requests)
      let total_f = int.to_float(budget.total_requests)
      clamp01(
        float.divide(fast_f, total_f)
        |> result_to_float(),
      )
      *. 100.0
    }
  }
}

/// Current availability SLI as a percentage (0.0–100.0).
///
/// Returns 100.0 when no requests have been recorded (assume healthy).
pub fn availability_sli(budget: SloBudget) -> Float {
  case budget.total_requests {
    0 -> 100.0
    _ -> {
      let ok_f = int.to_float(budget.successful_requests)
      let total_f = int.to_float(budget.total_requests)
      clamp01(
        float.divide(ok_f, total_f)
        |> result_to_float(),
      )
      *. 100.0
    }
  }
}

/// Remaining error budget as a fraction in [0.0, 1.0].
///
/// Uses the latency SLO as the primary budget signal.
/// 1.0 = full budget remaining; 0.0 = budget fully exhausted.
///
/// Formula (Google SRE §4):
///   allowed_errors = total * (1 - latency_slo_percent / 100)
///   bad_requests   = total - fast_requests
///   consumed       = bad_requests / allowed_errors   clamped to [0, 1]
///   remaining      = 1 - consumed
pub fn error_budget_remaining(budget: SloBudget) -> Float {
  case budget.total_requests {
    0 -> 1.0
    _ -> {
      let target = budget.latency_slo_percent /. 100.0
      let total_f = int.to_float(budget.total_requests)
      let allowed = total_f *. { 1.0 -. target }
      let bad = int.to_float(budget.total_requests - budget.fast_requests)
      case allowed <=. 0.0 {
        True ->
          case bad >. 0.0 {
            True -> 0.0
            False -> 1.0
          }
        False ->
          clamp01(
            1.0
            -. clamp01(
              float.divide(bad, allowed)
              |> result_to_float(),
            ),
          )
      }
    }
  }
}

/// Human-readable summary of the pipeline SloBudget.
pub fn budget_summary(budget: SloBudget) -> String {
  let lat = float_to_pct_string(latency_sli(budget) /. 100.0)
  let avail = float_to_pct_string(availability_sli(budget) /. 100.0)
  let eb = float_to_pct_string(error_budget_remaining(budget))
  "Pipeline SLO — "
  <> int.to_string(budget.total_requests)
  <> " requests  |  latency SLI: "
  <> lat
  <> "  |  availability SLI: "
  <> avail
  <> "  |  error budget remaining: "
  <> eb
}

// ---------------------------------------------------------------------------
// Helpers — SLI / budget arithmetic
// ---------------------------------------------------------------------------

/// Compute a derived SLO record from a raw counter.
fn counter_to_slo(c: SLOCounter) -> SLO {
  let current_sli = compute_sli(c.good_events, c.total_events)
  let consumed = compute_consumed(current_sli, c.target, c.total_events)
  let remaining = clamp01(1.0 -. consumed)
  SLO(
    name: c.name,
    target: c.target,
    window_seconds: c.window_seconds,
    current_sli: current_sli,
    budget_remaining: remaining,
    budget_consumed_pct: clamp01(consumed),
    status: classify_status(consumed),
  )
}

/// SLI = good / total.  Returns 1.0 when total = 0 (no data ⇒ assume healthy).
fn compute_sli(good: Int, total: Int) -> Float {
  case total {
    0 -> 1.0
    _ -> {
      let g = int.to_float(good)
      let t = int.to_float(total)
      clamp01(
        float.divide(g, t)
        |> result_to_float(),
      )
    }
  }
}

/// Error budget consumed fraction.
///
///   allowed_errors = total * (1 - target)
///   bad_events     = total - good
///   consumed       = bad_events / allowed_errors   (clamped [0, 1])
///
/// When allowed_errors == 0 (nine-nines on small sample) we return 0.0
/// unless actual bad events exist, in which case we return 1.0 (fully spent).
fn compute_consumed(current_sli: Float, target: Float, total: Int) -> Float {
  case total {
    0 -> 0.0
    _ -> {
      let total_f = int.to_float(total)
      let allowed = total_f *. { 1.0 -. target }
      let bad = total_f *. { 1.0 -. current_sli }
      case allowed <=. 0.0 {
        True ->
          case bad >. 0.0 {
            True -> 1.0
            False -> 0.0
          }
        False ->
          clamp01(
            float.divide(bad, allowed)
            |> result_to_float(),
          )
      }
    }
  }
}

/// Classify SLO status from consumed fraction.
fn classify_status(consumed: Float) -> SLOStatus {
  case consumed >=. 1.0 {
    True -> SLOViolated
    False ->
      case consumed >=. 0.5 {
        True -> SLOAtRisk
        False -> SLOMet
      }
  }
}

// ---------------------------------------------------------------------------
// Helpers — JSON serialisation
// ---------------------------------------------------------------------------

fn slo_to_json_object(c: SLOCounter) -> json.Json {
  let slo = counter_to_slo(c)
  json.object([
    #("name", json.string(slo.name)),
    #("target", json.float(slo.target)),
    #("window_seconds", json.int(slo.window_seconds)),
    #("current_sli", json.float(slo.current_sli)),
    #("good_events", json.int(c.good_events)),
    #("total_events", json.int(c.total_events)),
    #("budget_remaining", json.float(slo.budget_remaining)),
    #("budget_consumed_pct", json.float(slo.budget_consumed_pct)),
    #("status", json.string(status_to_string(slo.status))),
  ])
}

fn status_to_string(s: SLOStatus) -> String {
  case s {
    SLOMet -> "met"
    SLOAtRisk -> "at_risk"
    SLOViolated -> "violated"
  }
}

// ---------------------------------------------------------------------------
// Helpers — float utilities
// ---------------------------------------------------------------------------

/// Clamp a float to [0.0, 1.0].
fn clamp01(x: Float) -> Float {
  case x <. 0.0 {
    True -> 0.0
    False ->
      case x >. 1.0 {
        True -> 1.0
        False -> x
      }
  }
}

/// Unwrap a Result(Float, _), returning 0.0 on Error.
fn result_to_float(r: Result(Float, _)) -> Float {
  case r {
    Ok(v) -> v
    Error(_) -> 0.0
  }
}

/// Format a float in [0.0, 1.0] as a percentage string, e.g. "99.9%".
fn float_to_pct_string(v: Float) -> String {
  // Multiply by 10_000, round, divide back to get 2 decimal places.
  let scaled = float.round(v *. 10_000.0)
  let whole = scaled / 100
  let frac = scaled % 100
  let frac_str = case frac < 10 {
    True -> "0" <> int.to_string(frac)
    False -> int.to_string(frac)
  }
  int.to_string(whole) <> "." <> frac_str <> "%"
}
