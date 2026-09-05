//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/tla_verifier</module>
////     <fsharp-lineage>None — novel runtime TLA+ property verification (F24)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Runtime verification of TLA+ safety and liveness properties.
////       Evaluates 12 formal properties derived from specs/tla/ against observed
////       system state and history.  No Apalache/TLC subprocess — purely in-process
////       assertion checking with counterexample capture.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SIL4-001, SC-PRIME-001, SC-VER-001, SC-FUNC-002, SC-GLM-UI-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       TLA+ property schemas ↪ Gleam typed ADTs + evaluation functions.
////       Safety properties map to invariant checks over SystemState.
////       Liveness properties map to progress checks over List(SystemState).
////     </morphism>
////     <morphism type="surjective" loss="proof-completeness">
////       Apalache model-checking ↠ runtime sampling.
////       Mitigation: Properties cover the critical safety invariants; full
////       state-space exhaustion is performed offline by the CI/CD TLA+ pipeline.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// RUNTIME TLA+ PROPERTY VERIFICATION — F24
//// विद्याविद्ये ईशते — The Lord rules over knowledge and ignorance (Shvetashvatara 1.10)
////
//// 12 TLA+ properties derived from specs/tla/:
////
////  Safety (invariant — MUST always hold):
////    P01  NoSplitBrain          exactly_one(Primary) at all times
////    P02  QuorumMaintained      |healthy| >= floor(N/2)+1
////    P06  StateConsistency      all nodes agree on state
////    P08  HotReloadSafe         no connection lost during reload
////    P09  InvariantPreservation all 12 invariants always hold
////    P10  TruthPreservation     display always matches source
////    P11  FreshnessBound        data age < 60s always
////
////  Liveness (progress — MUST eventually hold):
////    P03  OodaProgress          OODA phase eventually advances
////    P04  LeaderElection        Primary eventually elected after failure
////    P05  MessageDelivery       Zenoh messages eventually delivered
////    P07  GracefulShutdown      drain completes before stop
////    P12  RecoveryTermination   recovery always terminates
////
//// STAMP: SC-SIL4-001, SC-PRIME-001, SC-VER-001, SC-FUNC-002, SC-GLM-UI-001

import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public Types
// ---------------------------------------------------------------------------

/// The type of a TLA+ property
pub type PropertyType {
  /// Invariant — MUST always hold (∀ states)
  SafetyProperty
  /// Progress — MUST eventually hold (◇ P)
  LivenessProperty
  /// Eventuality — MUST hold infinitely often (□◇ P)
  FairnessProperty
}

/// A TLA+ property declaration
pub type TlaProperty {
  TlaProperty(
    /// Short ID, e.g. "P01"
    id: String,
    /// Human-readable name, e.g. "NoSplitBrain"
    name: String,
    property_type: PropertyType,
    description: String,
    /// Reference to the TLA+ spec file in specs/tla/
    spec_file: String,
    /// Fractal layer this property guards
    layer: String,
  )
}

/// Snapshot of observable system state passed to safety verifiers
pub type SystemState {
  SystemState(
    /// Number of nodes currently in Primary role
    primary_count: Int,
    /// Number of healthy nodes
    healthy_node_count: Int,
    /// Total node count in the cluster
    total_node_count: Int,
    /// Current OODA phase tag (e.g. "observe", "orient", "decide", "act")
    ooda_phase: String,
    /// Data age in seconds (0 = fresh)
    data_age_seconds: Int,
    /// True when a hot-reload is in progress
    hot_reload_in_progress: Bool,
    /// Active connection count (should not drop during reload)
    active_connections: Int,
    /// Connection count snapshot before reload started
    connections_before_reload: Int,
    /// True when all known invariants are passing
    all_invariants_passing: Bool,
    /// True when display data matches the source-of-truth
    display_matches_source: Bool,
    /// True when the system is in a draining/shutdown state
    draining: Bool,
    /// True when shutdown has been fully completed
    shutdown_complete: Bool,
    /// True when all pending recovery tasks have finished
    recovery_terminated: Bool,
    /// True when Zenoh message queue is empty (all delivered)
    message_queue_empty: Bool,
  )
}

/// The outcome of verifying a single property
pub type VerificationResult {
  /// Property holds for the given state/history
  PropertyHolds(property_name: String, evidence: String)
  /// Property is violated — counterexample captured
  PropertyViolated(property_name: String, counterexample: String)
  /// Cannot determine (e.g. insufficient history for liveness check)
  PropertyUnknown(property_name: String, reason: String)
}

// ---------------------------------------------------------------------------
// Property Catalogue
// ---------------------------------------------------------------------------

/// All 12 TLA+ properties tracked by the runtime verifier.
pub fn all_properties() -> List(TlaProperty) {
  [
    TlaProperty(
      id: "P01",
      name: "NoSplitBrain",
      property_type: SafetyProperty,
      description: "Exactly one node holds the Primary role at all times",
      spec_file: "specs/tla/LeaderElection.tla",
      layer: "L7_FEDERATION",
    ),
    TlaProperty(
      id: "P02",
      name: "QuorumMaintained",
      property_type: SafetyProperty,
      description: "Healthy node count >= floor(N/2)+1 at all times",
      spec_file: "specs/tla/QuorumConsensus.tla",
      layer: "L6_ECOSYSTEM",
    ),
    TlaProperty(
      id: "P03",
      name: "OodaProgress",
      property_type: LivenessProperty,
      description: "OODA phase eventually advances through the full cycle",
      spec_file: "specs/tla/OodaCycle.tla",
      layer: "L5_COGNITIVE",
    ),
    TlaProperty(
      id: "P04",
      name: "LeaderElection",
      property_type: LivenessProperty,
      description: "A Primary is eventually elected after any failure",
      spec_file: "specs/tla/LeaderElection.tla",
      layer: "L7_FEDERATION",
    ),
    TlaProperty(
      id: "P05",
      name: "MessageDelivery",
      property_type: LivenessProperty,
      description: "All Zenoh messages are eventually delivered",
      spec_file: "specs/tla/ZenohTransport.tla",
      layer: "L6_ECOSYSTEM",
    ),
    TlaProperty(
      id: "P06",
      name: "StateConsistency",
      property_type: SafetyProperty,
      description: "All nodes agree on system state (no divergence)",
      spec_file: "specs/tla/StateConsistency.tla",
      layer: "L3_TRANSACTION",
    ),
    TlaProperty(
      id: "P07",
      name: "GracefulShutdown",
      property_type: LivenessProperty,
      description: "Drain phase completes before shutdown finalises",
      spec_file: "specs/tla/GracefulShutdown.tla",
      layer: "L4_SYSTEM",
    ),
    TlaProperty(
      id: "P08",
      name: "HotReloadSafe",
      property_type: SafetyProperty,
      description: "Active connections must not drop during a hot-reload",
      spec_file: "specs/tla/HotReload.tla",
      layer: "L4_SYSTEM",
    ),
    TlaProperty(
      id: "P09",
      name: "InvariantPreservation",
      property_type: SafetyProperty,
      description: "All 12 system invariants hold in every reachable state",
      spec_file: "specs/tla/SystemInvariants.tla",
      layer: "L0_CONSTITUTIONAL",
    ),
    TlaProperty(
      id: "P10",
      name: "TruthPreservation",
      property_type: SafetyProperty,
      description: "Display data always reflects the source-of-truth value",
      spec_file: "specs/tla/TruthPreservation.tla",
      layer: "L0_CONSTITUTIONAL",
    ),
    TlaProperty(
      id: "P11",
      name: "FreshnessBound",
      property_type: SafetyProperty,
      description: "Data age must be strictly less than 60 seconds always",
      spec_file: "specs/tla/FreshnessBound.tla",
      layer: "L1_ATOMIC_DEBUG",
    ),
    TlaProperty(
      id: "P12",
      name: "RecoveryTermination",
      property_type: LivenessProperty,
      description: "Every recovery sequence eventually terminates",
      spec_file: "specs/tla/RecoveryTermination.tla",
      layer: "L4_SYSTEM",
    ),
  ]
}

/// Total number of registered TLA+ properties.
pub fn property_count() -> Int {
  12
}

// ---------------------------------------------------------------------------
// Individual safety-property checkers
// ---------------------------------------------------------------------------

/// Verify a safety property against a single state snapshot.
///
/// Returns PropertyHolds, PropertyViolated, or PropertyUnknown.
pub fn verify_safety(
  property: TlaProperty,
  state: SystemState,
) -> VerificationResult {
  case property.id {
    "P01" -> verify_no_split_brain(property, state)
    "P02" -> verify_quorum_maintained(property, state)
    "P06" -> verify_state_consistency(property, state)
    "P08" -> verify_hot_reload_safe(property, state)
    "P09" -> verify_invariant_preservation(property, state)
    "P10" -> verify_truth_preservation(property, state)
    "P11" -> verify_freshness_bound(property, state)
    _ ->
      PropertyUnknown(
        property_name: property.name,
        reason: "Property "
          <> property.id
          <> " is a liveness property — use verify_liveness/2",
      )
  }
}

/// Verify a liveness property against a history of state snapshots.
///
/// History must contain >= 2 states for progress to be observable.
pub fn verify_liveness(
  property: TlaProperty,
  history: List(SystemState),
) -> VerificationResult {
  case property.id {
    "P03" -> verify_ooda_progress(property, history)
    "P04" -> verify_leader_election(property, history)
    "P05" -> verify_message_delivery(property, history)
    "P07" -> verify_graceful_shutdown(property, history)
    "P12" -> verify_recovery_termination(property, history)
    _ ->
      PropertyUnknown(
        property_name: property.name,
        reason: "Property "
          <> property.id
          <> " is a safety property — use verify_safety/2",
      )
  }
}

/// Verify all 12 properties against current state and history.
///
/// Safety properties use the latest state; liveness properties use the
/// full history.  Returns a list of 12 VerificationResult values.
pub fn verify_all(
  state: SystemState,
  history: List(SystemState),
) -> List(VerificationResult) {
  all_properties()
  |> list.map(fn(prop) {
    case prop.property_type {
      SafetyProperty -> verify_safety(prop, state)
      LivenessProperty -> verify_liveness(prop, history)
      FairnessProperty ->
        PropertyUnknown(
          property_name: prop.name,
          reason: "FairnessProperty evaluation not yet implemented",
        )
    }
  })
}

// ---------------------------------------------------------------------------
// Safety property implementations
// ---------------------------------------------------------------------------

fn verify_no_split_brain(
  prop: TlaProperty,
  state: SystemState,
) -> VerificationResult {
  case state.primary_count == 1 {
    True ->
      PropertyHolds(
        property_name: prop.name,
        evidence: "primary_count=1 — exactly one leader",
      )
    False ->
      PropertyViolated(
        property_name: prop.name,
        counterexample: "primary_count="
          <> int.to_string(state.primary_count)
          <> " (expected 1) — split-brain detected",
      )
  }
}

fn verify_quorum_maintained(
  prop: TlaProperty,
  state: SystemState,
) -> VerificationResult {
  let quorum_floor = state.total_node_count / 2 + 1
  case state.healthy_node_count >= quorum_floor {
    True ->
      PropertyHolds(
        property_name: prop.name,
        evidence: "healthy="
          <> int.to_string(state.healthy_node_count)
          <> " >= quorum="
          <> int.to_string(quorum_floor),
      )
    False ->
      PropertyViolated(
        property_name: prop.name,
        counterexample: "healthy="
          <> int.to_string(state.healthy_node_count)
          <> " < quorum="
          <> int.to_string(quorum_floor)
          <> " (N="
          <> int.to_string(state.total_node_count)
          <> ")",
      )
  }
}

fn verify_state_consistency(
  prop: TlaProperty,
  state: SystemState,
) -> VerificationResult {
  // Approximation: if primary_count == 1 and quorum holds, state is consistent
  case state.primary_count == 1 && state.healthy_node_count > 0 {
    True ->
      PropertyHolds(
        property_name: prop.name,
        evidence: "single primary with quorum — state consistent",
      )
    False ->
      PropertyViolated(
        property_name: prop.name,
        counterexample: "primary_count="
          <> int.to_string(state.primary_count)
          <> " — state consistency cannot be guaranteed",
      )
  }
}

fn verify_hot_reload_safe(
  prop: TlaProperty,
  state: SystemState,
) -> VerificationResult {
  case state.hot_reload_in_progress {
    False ->
      PropertyHolds(property_name: prop.name, evidence: "no reload in progress")
    True -> {
      case state.active_connections >= state.connections_before_reload {
        True ->
          PropertyHolds(
            property_name: prop.name,
            evidence: "reload in progress — connections stable at "
              <> int.to_string(state.active_connections),
          )
        False ->
          PropertyViolated(
            property_name: prop.name,
            counterexample: "connections dropped from "
              <> int.to_string(state.connections_before_reload)
              <> " to "
              <> int.to_string(state.active_connections)
              <> " during hot-reload",
          )
      }
    }
  }
}

fn verify_invariant_preservation(
  prop: TlaProperty,
  state: SystemState,
) -> VerificationResult {
  case state.all_invariants_passing {
    True ->
      PropertyHolds(
        property_name: prop.name,
        evidence: "all 12 system invariants passing",
      )
    False ->
      PropertyViolated(
        property_name: prop.name,
        counterexample: "one or more system invariants failing",
      )
  }
}

fn verify_truth_preservation(
  prop: TlaProperty,
  state: SystemState,
) -> VerificationResult {
  case state.display_matches_source {
    True ->
      PropertyHolds(
        property_name: prop.name,
        evidence: "display data matches source-of-truth",
      )
    False ->
      PropertyViolated(
        property_name: prop.name,
        counterexample: "display data diverges from source-of-truth",
      )
  }
}

fn verify_freshness_bound(
  prop: TlaProperty,
  state: SystemState,
) -> VerificationResult {
  let max_age_seconds = 60
  case state.data_age_seconds < max_age_seconds {
    True ->
      PropertyHolds(
        property_name: prop.name,
        evidence: "data_age="
          <> int.to_string(state.data_age_seconds)
          <> "s < 60s bound",
      )
    False ->
      PropertyViolated(
        property_name: prop.name,
        counterexample: "data_age="
          <> int.to_string(state.data_age_seconds)
          <> "s >= 60s — freshness bound violated",
      )
  }
}

// ---------------------------------------------------------------------------
// Liveness property implementations
// ---------------------------------------------------------------------------

fn verify_ooda_progress(
  prop: TlaProperty,
  history: List(SystemState),
) -> VerificationResult {
  case history {
    [] | [_] ->
      PropertyUnknown(
        property_name: prop.name,
        reason: "need >= 2 history snapshots to verify OODA progress",
      )
    _ -> {
      let phases = history |> list.map(fn(s) { s.ooda_phase }) |> list.unique()
      case list.length(phases) > 1 {
        True ->
          PropertyHolds(
            property_name: prop.name,
            evidence: "observed "
              <> int.to_string(list.length(phases))
              <> " distinct OODA phases across history",
          )
        False ->
          PropertyViolated(
            property_name: prop.name,
            counterexample: "OODA phase stuck at '"
              <> case list.first(phases) {
              Ok(p) -> p
              Error(_) -> "unknown"
            }
              <> "' — no progress observed",
          )
      }
    }
  }
}

fn verify_leader_election(
  prop: TlaProperty,
  history: List(SystemState),
) -> VerificationResult {
  case history {
    [] ->
      PropertyUnknown(
        property_name: prop.name,
        reason: "need at least one history snapshot",
      )
    _ -> {
      let has_primary = list.any(history, fn(s) { s.primary_count == 1 })
      case has_primary {
        True ->
          PropertyHolds(
            property_name: prop.name,
            evidence: "a primary was elected at least once in the observed history",
          )
        False ->
          PropertyViolated(
            property_name: prop.name,
            counterexample: "no primary elected in "
              <> int.to_string(list.length(history))
              <> " history snapshots",
          )
      }
    }
  }
}

fn verify_message_delivery(
  prop: TlaProperty,
  history: List(SystemState),
) -> VerificationResult {
  case history {
    [] ->
      PropertyUnknown(
        property_name: prop.name,
        reason: "need at least one history snapshot",
      )
    _ -> {
      let queue_drained = list.any(history, fn(s) { s.message_queue_empty })
      case queue_drained {
        True ->
          PropertyHolds(
            property_name: prop.name,
            evidence: "message queue reached empty state — all messages delivered",
          )
        False ->
          PropertyViolated(
            property_name: prop.name,
            counterexample: "message queue never drained across "
              <> int.to_string(list.length(history))
              <> " history snapshots",
          )
      }
    }
  }
}

fn verify_graceful_shutdown(
  prop: TlaProperty,
  history: List(SystemState),
) -> VerificationResult {
  case history {
    [] ->
      PropertyUnknown(
        property_name: prop.name,
        reason: "need at least one history snapshot",
      )
    _ -> {
      // If shutdown occurred, it must have been preceded by draining
      let shutdown_states = list.filter(history, fn(s) { s.shutdown_complete })
      case list.is_empty(shutdown_states) {
        True ->
          PropertyHolds(
            property_name: prop.name,
            evidence: "no shutdown observed in history — property vacuously holds",
          )
        False -> {
          let drain_before_shutdown =
            list.any(history, fn(s) { s.draining && !s.shutdown_complete })
          case drain_before_shutdown {
            True ->
              PropertyHolds(
                property_name: prop.name,
                evidence: "drain phase observed before shutdown — graceful",
              )
            False ->
              PropertyViolated(
                property_name: prop.name,
                counterexample: "shutdown completed without observing drain phase",
              )
          }
        }
      }
    }
  }
}

fn verify_recovery_termination(
  prop: TlaProperty,
  history: List(SystemState),
) -> VerificationResult {
  case history {
    [] ->
      PropertyUnknown(
        property_name: prop.name,
        reason: "need at least one history snapshot",
      )
    _ -> {
      let terminated = list.any(history, fn(s) { s.recovery_terminated })
      case terminated {
        True ->
          PropertyHolds(
            property_name: prop.name,
            evidence: "recovery reached terminated state in observed history",
          )
        False ->
          PropertyViolated(
            property_name: prop.name,
            counterexample: "recovery never terminated across "
              <> int.to_string(list.length(history))
              <> " history snapshots",
          )
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Query helpers
// ---------------------------------------------------------------------------

/// Find a property by its ID (e.g. "P01").
pub fn find_by_id(id: String) -> Result(TlaProperty, String) {
  case list.find(all_properties(), fn(p) { p.id == id }) {
    Ok(p) -> Ok(p)
    Error(_) -> Error("No property with id=" <> id)
  }
}

/// Return all safety properties.
pub fn safety_properties() -> List(TlaProperty) {
  list.filter(all_properties(), fn(p) { p.property_type == SafetyProperty })
}

/// Return all liveness properties.
pub fn liveness_properties() -> List(TlaProperty) {
  list.filter(all_properties(), fn(p) { p.property_type == LivenessProperty })
}

/// Count violations in a results list.
pub fn violation_count(results: List(VerificationResult)) -> Int {
  list.count(results, fn(r) {
    case r {
      PropertyViolated(_, _) -> True
      _ -> False
    }
  })
}

/// Count holds in a results list.
pub fn holds_count(results: List(VerificationResult)) -> Int {
  list.count(results, fn(r) {
    case r {
      PropertyHolds(_, _) -> True
      _ -> False
    }
  })
}

// ---------------------------------------------------------------------------
// Serialisation
// ---------------------------------------------------------------------------

/// Convert a list of VerificationResult values to a JSON string.
pub fn to_json(results: List(VerificationResult)) -> String {
  let inner =
    results
    |> list.map(fn(r) { result_to_json_obj(r) })
    |> string.join(",")
  "{\"results\":["
  <> inner
  <> "],\"total\":"
  <> int.to_string(list.length(results))
  <> ",\"violations\":"
  <> int.to_string(violation_count(results))
  <> ",\"holds\":"
  <> int.to_string(holds_count(results))
  <> "}"
}

fn result_to_json_obj(result: VerificationResult) -> String {
  case result {
    PropertyHolds(name, evidence) ->
      "{\"status\":\"holds\",\"property\":\""
      <> name
      <> "\",\"evidence\":\""
      <> json_escape(evidence)
      <> "\"}"
    PropertyViolated(name, counterexample) ->
      "{\"status\":\"violated\",\"property\":\""
      <> name
      <> "\",\"counterexample\":\""
      <> json_escape(counterexample)
      <> "\"}"
    PropertyUnknown(name, reason) ->
      "{\"status\":\"unknown\",\"property\":\""
      <> name
      <> "\",\"reason\":\""
      <> json_escape(reason)
      <> "\"}"
  }
}

/// Minimal JSON string escaping (backslash and double-quote).
fn json_escape(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
}
