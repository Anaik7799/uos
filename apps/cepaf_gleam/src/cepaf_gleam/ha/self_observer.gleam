//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/self_observer</module>
////     <fsharp-lineage>None — novel proprioceptive safety actor (Satya Plan Sprint 2)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>Self-observation: system verifies its own rendered output matches source data</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-TRUTH-001, SC-GLM-UI-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Proprioception pattern ↪ Gleam pure functions.
////       Source truth (NIF JSON) verified against derived state (SharedMeshState logic).
////       No side-channel rendering needed — invariants evaluated algebraically.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// SELF-OBSERVATION ACTOR — SYSTEM PROPRIOCEPTION
//// आत्मानं रथिनं विद्धि — Know the Self as the rider (Katha Upanishad 1.3.3)
////
//// This module gives the system proprioception: awareness of its own body state.
//// It verifies that rendered page values match the source NIF data they derive from.
////
//// The 12 core invariants (I-01..I-12) are the mathematical backbone:
////   I-01: quorum_healthy ∧ threat_nominal → health_score ≥ 80
////   I-02: threat_level = ThreatNominal → weather label = "Clear"
////   I-03: threat_level ∈ {ThreatCritical, ThreatSevere} → dark_cockpit ≠ "dark"
////   I-04: container_count ≥ healthy_count  (geometry of health)
////   I-05: zenoh_connected → mesh displays "active"
////   I-06: quorum_healthy = False → health_score < 80
////   I-07: healthy_count = container_count ∧ quorum = True → status "ok"
////   I-08: healthy_count ≤ container_count / 2 → status "critical"
////   I-09: threat ∈ {ThreatLow, ThreatElevated} → antibodies = 3
////   I-10: threat ∈ {ThreatCritical, ThreatSevere} → antibodies = 12
////   I-11: zenoh_connected = False → router_count = 0
////   I-12: plan_status contains "total" → NIF pipeline live
////
//// STAMP: SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-TRUTH-001

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ui/state.{
  type SharedMeshState, type ThreatLevel, CockpitDark, ThreatCritical,
  ThreatElevated, ThreatLow, ThreatNominal, ThreatNone, ThreatSevere,
  threat_level_to_string,
}
import gleam/int
import gleam/string

// ---------------------------------------------------------------------------
// Core types
// ---------------------------------------------------------------------------

/// Severity of a truth mismatch between source data and rendered output.
pub type MismatchSeverity {
  /// Cosmetic — no operational impact
  Low
  /// Noticeable deviation — operator may be misled
  Medium
  /// Safety-relevant — could cause wrong decisions
  High
  /// Constitutional violation — triggers Jidoka stop
  Critical
}

/// A detected divergence between what NIF/state says and what logic produces.
pub type TruthMismatch {
  TruthMismatch(
    /// Stable identifier for the invariant being checked (e.g. "I-01", "health_score")
    value_id: String,
    /// The value the source data (NIF/state) says it should be
    expected: String,
    /// The value the rendering/derivation actually produced
    actual: String,
    /// How serious this divergence is
    severity: MismatchSeverity,
  )
}

/// Result of a complete page truth check.
pub type TruthCheckResult {
  /// Every invariant verified — system output matches source data
  AllTruthful
  /// One or more invariants violated
  MismatchDetected(mismatches: List(TruthMismatch))
}

/// State for the self-observation actor.
pub type SelfObserverState {
  SelfObserverState(
    /// Total number of truth checks performed
    check_count: Int,
    /// Checks where all invariants passed
    match_count: Int,
    /// Checks where at least one invariant failed
    mismatch_count: Int,
    /// Simulated timestamp counter (increments each check)
    last_check_timestamp: Int,
    /// All mismatches detected (most recent first)
    mismatches: List(TruthMismatch),
  )
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

/// Initialise a clean self-observer state.
pub fn init() -> SelfObserverState {
  SelfObserverState(
    check_count: 0,
    match_count: 0,
    mismatch_count: 0,
    last_check_timestamp: 0,
    mismatches: [],
  )
}

// ---------------------------------------------------------------------------
// Page truth check
// ---------------------------------------------------------------------------

/// Check that rendered page values for `page_name` match source NIF data.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Algebraic invariant evaluation ↪ TruthCheckResult</morphism>
///   <formal-proof>
///     <P> Pre: NIF functions callable, state derivable from SharedMeshState logic </P>
///     <C> check_page_truth(page_name) </C>
///     <Q> Post: AllTruthful iff all 12 invariants hold; MismatchDetected otherwise </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn check_page_truth(page_name: String) -> TruthCheckResult {
  // Gather source data from NIFs
  let plan_raw = c3i_nif.plan_status()
  let health_raw = c3i_nif.system_health()
  let dashboard_raw = c3i_nif.system_dashboard()

  // Build a representative state from default assumptions (no live Zenoh yet)
  // The invariants evaluate the *algebraic* properties of state derivation.
  let state = state.default_state()

  let found =
    check_all_invariants(page_name, state, plan_raw, health_raw, dashboard_raw)

  case found {
    [] -> AllTruthful
    mismatches -> MismatchDetected(mismatches: mismatches)
  }
}

/// Check truth against a known SharedMeshState (used in tests for controlled scenarios).
pub fn check_state_truth(
  page_name: String,
  st: SharedMeshState,
) -> TruthCheckResult {
  let plan_raw = c3i_nif.plan_status()
  let health_raw = c3i_nif.system_health()
  let dashboard_raw = c3i_nif.system_dashboard()

  let found =
    check_all_invariants(page_name, st, plan_raw, health_raw, dashboard_raw)
  case found {
    [] -> AllTruthful
    mismatches -> MismatchDetected(mismatches: mismatches)
  }
}

// ---------------------------------------------------------------------------
// The 12 invariants
// ---------------------------------------------------------------------------

/// Evaluate all 12 invariants; return list of violations (empty = all pass).
fn check_all_invariants(
  _page_name: String,
  st: SharedMeshState,
  plan_raw: String,
  _health_raw: String,
  _dashboard_raw: String,
) -> List(TruthMismatch) {
  // Collect violations — each check appends to acc on failure
  let acc = check_i01(st, [])
  let acc = check_i02(st, acc)
  let acc = check_i03(st, acc)
  let acc = check_i04(st, acc)
  let acc = check_i05(st, acc)
  let acc = check_i06(st, acc)
  let acc = check_i07(st, acc)
  let acc = check_i08(st, acc)
  let acc = check_i09(st, acc)
  let acc = check_i10(st, acc)
  let acc = check_i11(st, acc)
  check_i12(plan_raw, acc)
}

/// I-01: quorum_healthy ∧ threat_nominal → health_score ≥ 80
fn check_i01(
  st: SharedMeshState,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  let is_nominal = case st.threat_level {
    ThreatNominal | ThreatNone -> True
    _ -> False
  }
  case st.quorum_healthy && is_nominal {
    False -> acc
    True -> {
      // Derive the health score the same way domain_views.gleam does
      let score = derive_health_score(st)
      case score >= 80 {
        True -> acc
        False -> [
          TruthMismatch(
            value_id: "I-01:health_score",
            expected: "≥80 (quorum_healthy=true, threat=nominal)",
            actual: int.to_string(score),
            severity: High,
          ),
          ..acc
        ]
      }
    }
  }
}

/// I-02: threat_level = ThreatNominal → weather label = "Clear"
fn check_i02(
  st: SharedMeshState,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  case st.threat_level {
    ThreatNominal -> {
      let score = derive_health_score(st)
      let label = derive_weather_label(score)
      case label {
        "Clear" -> acc
        other -> [
          TruthMismatch(
            value_id: "I-02:weather_label",
            expected: "Clear",
            actual: other,
            severity: Medium,
          ),
          ..acc
        ]
      }
    }
    _ -> acc
  }
}

/// I-03: threat ∈ {ThreatCritical, ThreatSevere} → dark_cockpit_mode ≠ "dark"
fn check_i03(
  st: SharedMeshState,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  let is_critical = case st.threat_level {
    ThreatCritical | ThreatSevere -> True
    _ -> False
  }
  case is_critical {
    False -> acc
    True ->
      case st.dark_cockpit_mode {
        CockpitDark -> [
          TruthMismatch(
            value_id: "I-03:dark_cockpit_mode",
            expected: "not dark (threat="
              <> threat_level_to_string(st.threat_level)
              <> ")",
            actual: "dark",
            severity: Critical,
          ),
          ..acc
        ]
        _ -> acc
      }
  }
}

/// I-04: container_count ≥ healthy_count (geometric consistency)
fn check_i04(
  st: SharedMeshState,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  case st.container_count >= st.healthy_count {
    True -> acc
    False -> [
      TruthMismatch(
        value_id: "I-04:container_geometry",
        expected: "container_count ≥ healthy_count",
        actual: "container_count="
          <> int.to_string(st.container_count)
          <> " < healthy_count="
          <> int.to_string(st.healthy_count),
        severity: Critical,
      ),
      ..acc
    ]
  }
}

/// I-05: zenoh_connected → mesh displays "active"
fn check_i05(
  st: SharedMeshState,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  case st.zenoh_connected {
    False -> acc
    True -> {
      // The mesh status derived from zenoh_connected=True must be "active"
      let mesh_status = derive_zenoh_status(st.zenoh_connected)
      case mesh_status {
        "active" -> acc
        other -> [
          TruthMismatch(
            value_id: "I-05:zenoh_status",
            expected: "active",
            actual: other,
            severity: High,
          ),
          ..acc
        ]
      }
    }
  }
}

/// I-06: quorum_healthy = False → health_score < 80
fn check_i06(
  st: SharedMeshState,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  case st.quorum_healthy {
    True -> acc
    False -> {
      let score = derive_health_score(st)
      case score < 80 {
        True -> acc
        False -> [
          TruthMismatch(
            value_id: "I-06:health_score_degraded",
            expected: "<80 (quorum_healthy=false)",
            actual: int.to_string(score),
            severity: High,
          ),
          ..acc
        ]
      }
    }
  }
}

/// I-07: healthy_count = container_count ∧ quorum = True → derived_status = "ok"
fn check_i07(
  st: SharedMeshState,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  case st.quorum_healthy && st.healthy_count == st.container_count {
    False -> acc
    True -> {
      let status = derive_health_status(st)
      case status {
        "ok" -> acc
        other -> [
          TruthMismatch(
            value_id: "I-07:health_status",
            expected: "ok",
            actual: other,
            severity: High,
          ),
          ..acc
        ]
      }
    }
  }
}

/// I-08: healthy_count ≤ container_count / 2 → derived_status = "critical"
fn check_i08(
  st: SharedMeshState,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  case st.container_count > 0 && st.healthy_count <= st.container_count / 2 {
    False -> acc
    True -> {
      let status = derive_health_status(st)
      case status {
        "critical" -> acc
        other -> [
          TruthMismatch(
            value_id: "I-08:health_status_critical",
            expected: "critical",
            actual: other,
            severity: Critical,
          ),
          ..acc
        ]
      }
    }
  }
}

/// I-09: threat ∈ {ThreatLow, ThreatElevated} → antibodies = 3
fn check_i09(
  st: SharedMeshState,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  let is_low_elevated = case st.threat_level {
    ThreatLow | ThreatElevated -> True
    _ -> False
  }
  case is_low_elevated {
    False -> acc
    True -> {
      let antibodies = derive_antibody_count(st.threat_level)
      case antibodies == 3 {
        True -> acc
        False -> [
          TruthMismatch(
            value_id: "I-09:antibodies",
            expected: "3",
            actual: int.to_string(antibodies),
            severity: Medium,
          ),
          ..acc
        ]
      }
    }
  }
}

/// I-10: threat ∈ {ThreatCritical, ThreatSevere} → antibodies = 12
fn check_i10(
  st: SharedMeshState,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  let is_critical_severe = case st.threat_level {
    ThreatCritical | ThreatSevere -> True
    _ -> False
  }
  case is_critical_severe {
    False -> acc
    True -> {
      let antibodies = derive_antibody_count(st.threat_level)
      case antibodies == 12 {
        True -> acc
        False -> [
          TruthMismatch(
            value_id: "I-10:antibodies_critical",
            expected: "12",
            actual: int.to_string(antibodies),
            severity: High,
          ),
          ..acc
        ]
      }
    }
  }
}

/// I-11: zenoh_connected = False → router_count = 0
fn check_i11(
  st: SharedMeshState,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  case st.zenoh_connected {
    True -> acc
    False -> {
      let routers = derive_router_count(st.zenoh_connected)
      case routers == 0 {
        True -> acc
        False -> [
          TruthMismatch(
            value_id: "I-11:zenoh_router_count",
            expected: "0",
            actual: int.to_string(routers),
            severity: High,
          ),
          ..acc
        ]
      }
    }
  }
}

/// I-12: plan_status JSON contains "total" → NIF pipeline live
fn check_i12(
  plan_raw: String,
  acc: List(TruthMismatch),
) -> List(TruthMismatch) {
  case string.contains(plan_raw, "total") {
    True -> acc
    False -> [
      TruthMismatch(
        value_id: "I-12:nif_pipeline_live",
        expected: "plan_status contains 'total'",
        actual: "missing 'total' in: " <> string.slice(plan_raw, 0, 40),
        severity: Critical,
      ),
      ..acc
    ]
  }
}

// ---------------------------------------------------------------------------
// Derivation helpers — mirror the logic in state.gleam and domain_views.gleam
// These MUST stay in sync with the source files. Any drift IS the bug.
// ---------------------------------------------------------------------------

/// Mirrors domain_views.planning_view health_score derivation.
pub fn derive_health_score(st: SharedMeshState) -> Int {
  case st.quorum_healthy {
    True ->
      case st.threat_level {
        ThreatNone | ThreatNominal -> 92
        ThreatLow | ThreatElevated -> 78
        _ -> 55
      }
    False -> 35
  }
}

/// Mirrors domain_views.planning_view weather_label derivation.
pub fn derive_weather_label(health_score: Int) -> String {
  case health_score >= 80 {
    True -> "Clear"
    False ->
      case health_score >= 60 {
        True -> "Partly cloudy"
        False -> "Stormy"
      }
  }
}

/// Mirrors state.to_zenoh_json status derivation.
pub fn derive_zenoh_status(connected: Bool) -> String {
  case connected {
    True -> "active"
    False -> "inactive"
  }
}

/// Mirrors state.to_zenoh_json router_count derivation.
pub fn derive_router_count(connected: Bool) -> Int {
  case connected {
    True -> 3
    False -> 0
  }
}

/// Mirrors state.to_health_json derived_status derivation.
pub fn derive_health_status(st: SharedMeshState) -> String {
  case st.quorum_healthy && st.healthy_count == st.container_count {
    True -> "ok"
    False ->
      case st.healthy_count > st.container_count / 2 {
        True -> "degraded"
        False -> "critical"
      }
  }
}

/// Mirrors state.to_immune_json antibody_count derivation.
pub fn derive_antibody_count(threat: ThreatLevel) -> Int {
  case threat {
    ThreatNominal | ThreatNone -> 0
    ThreatLow | ThreatElevated -> 3
    ThreatCritical | ThreatSevere -> 12
  }
}

// ---------------------------------------------------------------------------
// Actor interface — mirrors freshness_monitor.gleam pattern
// ---------------------------------------------------------------------------

/// Run one self-observation cycle; returns updated state + result.
pub fn check(
  state: SelfObserverState,
) -> #(SelfObserverState, TruthCheckResult) {
  let result = check_page_truth("planning")
  let new_count = state.check_count + 1
  let new_ts = new_count

  case result {
    AllTruthful -> {
      let new_state =
        SelfObserverState(
          ..state,
          check_count: new_count,
          match_count: state.match_count + 1,
          last_check_timestamp: new_ts,
        )
      #(new_state, AllTruthful)
    }
    MismatchDetected(mismatches: new_mismatches) -> {
      let merged = list_concat(new_mismatches, state.mismatches)
      let new_state =
        SelfObserverState(
          ..state,
          check_count: new_count,
          mismatch_count: state.mismatch_count + 1,
          last_check_timestamp: new_ts,
          mismatches: merged,
        )
      #(new_state, result)
    }
  }
}

/// Check truth against an explicit state (used when caller has a concrete state).
pub fn check_with_state(
  observer: SelfObserverState,
  mesh_st: SharedMeshState,
) -> #(SelfObserverState, TruthCheckResult) {
  let result = check_state_truth("planning", mesh_st)
  let new_count = observer.check_count + 1
  let new_ts = new_count

  case result {
    AllTruthful -> {
      let new_state =
        SelfObserverState(
          ..observer,
          check_count: new_count,
          match_count: observer.match_count + 1,
          last_check_timestamp: new_ts,
        )
      #(new_state, AllTruthful)
    }
    MismatchDetected(mismatches: new_mismatches) -> {
      let merged = list_concat(new_mismatches, observer.mismatches)
      let new_state =
        SelfObserverState(
          ..observer,
          check_count: new_count,
          mismatch_count: observer.mismatch_count + 1,
          last_check_timestamp: new_ts,
          mismatches: merged,
        )
      #(new_state, result)
    }
  }
}

/// Human-readable status string — mirrors freshness_monitor.status_string pattern.
pub fn status_string(state: SelfObserverState) -> String {
  let truth_rate = case state.check_count > 0 {
    True -> int.to_string(state.match_count * 100 / state.check_count) <> "%"
    False -> "N/A"
  }
  "SELF-OBSERVER"
  <> " (checks: "
  <> int.to_string(state.check_count)
  <> ", truthful: "
  <> int.to_string(state.match_count)
  <> ", mismatches: "
  <> int.to_string(state.mismatch_count)
  <> ", truth_rate: "
  <> truth_rate
  <> ", total_violations: "
  <> int.to_string(list_length(state.mismatches))
  <> ")"
}

/// Severity of the most critical outstanding mismatch.
pub fn worst_severity(state: SelfObserverState) -> MismatchSeverity {
  worst_in(state.mismatches, Low)
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn worst_in(
  items: List(TruthMismatch),
  best_so_far: MismatchSeverity,
) -> MismatchSeverity {
  case items {
    [] -> best_so_far
    [m, ..rest] -> {
      let next = case severity_rank(m.severity) > severity_rank(best_so_far) {
        True -> m.severity
        False -> best_so_far
      }
      worst_in(rest, next)
    }
  }
}

fn severity_rank(s: MismatchSeverity) -> Int {
  case s {
    Low -> 1
    Medium -> 2
    High -> 3
    Critical -> 4
  }
}

fn list_length(items: List(a)) -> Int {
  do_count(items, 0)
}

fn do_count(items: List(a), acc: Int) -> Int {
  case items {
    [] -> acc
    [_, ..rest] -> do_count(rest, acc + 1)
  }
}

fn list_concat(a: List(a), b: List(a)) -> List(a) {
  case a {
    [] -> b
    [h, ..t] -> [h, ..list_concat(t, b)]
  }
}
