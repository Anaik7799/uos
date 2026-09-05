//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/digital_twin</module>
////     <fsharp-lineage>None — novel Gleam module for mesh digital twin (SC-HA-001, SC-TRUTH-001)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Digital Twin of the 16-container SIL-6 mesh. Mirrors desired vs actual
////       state for each component, computes a drift score, and recommends typed
////       SyncActions (Converge / Alert / NoSync) for the OODA reconciliation loop.
////       SC-TRUTH-001: only verified actual state is stored — no speculation.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-TRUTH-001, SC-FUNC-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Kubernetes / Podman runtime state ↪ Gleam ComponentMirror ADT.
////       Drift detection ↪ Boolean field + aggregated Float score.
////       All state transitions are pure functions; callers own persistence.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Digital Twin — द्विगुण (Digital Double / Mirror Self)
//// "The self is the friend of the self for those who have conquered the self." (Gita 6.6)
////
//// Design invariants:
////   I1: drift_score(twin) = drifted_count / max(1, total_count) ∈ [0.0, 1.0].
////   I2: twin_health = 1.0 - drift_score ∈ [0.0, 1.0].
////   I3: detect_drift returns exactly the mirrors where desired_state != actual_state.
////   I4: sync_component sets drifted = False when new_actual == desired_state.
////   I5: reconciliation_actions: drifted -> Converge; health < 0.5 -> Alert; else NoSync.
////
//// STAMP: SC-HA-001, SC-TRUTH-001, SC-FUNC-001, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/list

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A mirror of one component's desired vs actual state.
pub type ComponentMirror {
  ComponentMirror(
    /// Component identifier (container name, service name, etc.).
    name: String,
    /// The state we want the component to be in.
    desired_state: String,
    /// The state the component is actually in right now.
    actual_state: String,
    /// Normalised health score ∈ [0.0, 1.0].
    health: Float,
    /// Unix-epoch milliseconds of the last telemetry sync.
    last_sync: Int,
    /// True when desired_state != actual_state.
    drifted: Bool,
  )
}

/// Recommended action for a drifted or degraded component.
pub type SyncAction {
  /// Component has drifted; request convergence to the desired state.
  Converge(name: String, target_state: String)
  /// Component health is critically low; raise an alert.
  Alert(name: String, reason: String)
  /// Component is healthy and converged; nothing to do.
  NoSync(name: String)
}

/// Aggregate state of the digital twin.
pub type TwinState {
  TwinState(
    /// Mirrors for all tracked components.
    components: List(ComponentMirror),
    /// Unix-epoch milliseconds of the last full twin sync.
    sync_timestamp: Int,
    /// Fraction of components that are drifted ∈ [0.0, 1.0].
    drift_score: Float,
  )
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Returns a fresh, empty digital twin.
pub fn twin_new() -> TwinState {
  TwinState(components: [], sync_timestamp: 0, drift_score: 0.0)
}

// ---------------------------------------------------------------------------
// Mutation
// ---------------------------------------------------------------------------

/// Records or updates a component mirror in the twin.
///
/// Computes the drifted flag automatically.
/// Recalculates the aggregate drift_score after insertion.
pub fn mirror_component(
  twin: TwinState,
  name: String,
  desired: String,
  actual: String,
  health: Float,
  timestamp: Int,
) -> TwinState {
  let drifted = desired != actual
  let mirror =
    ComponentMirror(
      name: name,
      desired_state: desired,
      actual_state: actual,
      health: health,
      last_sync: timestamp,
      drifted: drifted,
    )
  // Replace existing mirror with the same name, or append.
  let updated =
    list.filter(twin.components, fn(c) { c.name != name })
    |> list.append([mirror])
  let score = compute_drift_score(updated)
  TwinState(components: updated, sync_timestamp: timestamp, drift_score: score)
}

/// Updates the actual_state of one component and recalculates drift.
pub fn sync_component(
  twin: TwinState,
  name: String,
  new_actual: String,
  timestamp: Int,
) -> TwinState {
  let updated =
    list.map(twin.components, fn(c) {
      case c.name == name {
        False -> c
        True ->
          ComponentMirror(
            ..c,
            actual_state: new_actual,
            last_sync: timestamp,
            drifted: c.desired_state != new_actual,
          )
      }
    })
  let score = compute_drift_score(updated)
  TwinState(components: updated, sync_timestamp: timestamp, drift_score: score)
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

/// Returns the list of components where desired_state != actual_state.
pub fn detect_drift(twin: TwinState) -> List(ComponentMirror) {
  list.filter(twin.components, fn(c) { c.drifted })
}

/// Returns the fraction of components that are drifted ∈ [0.0, 1.0].
pub fn drift_score(twin: TwinState) -> Float {
  twin.drift_score
}

/// Returns the overall twin health = 1.0 - drift_score.
pub fn twin_health(twin: TwinState) -> Float {
  clamp(1.0 -. twin.drift_score, 0.0, 1.0)
}

/// Produces a SyncAction for every component in the twin.
///
/// Priority:
///   1. If health < 0.5 -> Alert (degraded, regardless of drift).
///   2. Else if drifted  -> Converge.
///   3. Else             -> NoSync.
pub fn reconciliation_actions(twin: TwinState) -> List(SyncAction) {
  list.map(twin.components, fn(c) {
    case c.health <. 0.5 {
      True ->
        Alert(
          c.name,
          "health=" <> float.to_string(c.health) <> " below threshold 0.5",
        )
      False ->
        case c.drifted {
          True -> Converge(c.name, c.desired_state)
          False -> NoSync(c.name)
        }
    }
  })
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

/// Returns a human-readable summary of the twin state.
pub fn summary(twin: TwinState) -> String {
  let total = list.length(twin.components)
  let drifted = list.length(detect_drift(twin))
  let health_str =
    float.to_string(float.floor(twin_health(twin) *. 100.0) /. 100.0)
  "TwinState{components="
  <> int.to_string(total)
  <> ",drifted="
  <> int.to_string(drifted)
  <> ",drift_score="
  <> float.to_string(twin.drift_score)
  <> ",health="
  <> health_str
  <> ",sync_ts="
  <> int.to_string(twin.sync_timestamp)
  <> "}"
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn compute_drift_score(components: List(ComponentMirror)) -> Float {
  let total = list.length(components)
  case total {
    0 -> 0.0
    _ -> {
      let drifted =
        list.filter(components, fn(c) { c.drifted }) |> list.length()
      int.to_float(drifted) /. int.to_float(total)
    }
  }
}

fn clamp(v: Float, lo: Float, hi: Float) -> Float {
  case v <. lo {
    True -> lo
    False ->
      case v >. hi {
        True -> hi
        False -> v
      }
  }
}

/// Returns the string representation of a SyncAction (for logging/testing).
pub fn action_to_string(action: SyncAction) -> String {
  case action {
    Converge(name, target) -> "Converge(" <> name <> "," <> target <> ")"
    Alert(name, reason) -> "Alert(" <> name <> "," <> reason <> ")"
    NoSync(name) -> "NoSync(" <> name <> ")"
  }
}

/// Returns True when the action is a Converge.
pub fn is_converge(action: SyncAction) -> Bool {
  case action {
    Converge(_, _) -> True
    _ -> False
  }
}

/// Returns True when the action is an Alert.
pub fn is_alert(action: SyncAction) -> Bool {
  case action {
    Alert(_, _) -> True
    _ -> False
  }
}

/// Returns True when the action is a NoSync.
pub fn is_no_sync(action: SyncAction) -> Bool {
  case action {
    NoSync(_) -> True
    _ -> False
  }
}

/// Returns the name field of any SyncAction.
pub fn action_name(action: SyncAction) -> String {
  case action {
    Converge(name, _) -> name
    Alert(name, _) -> name
    NoSync(name) -> name
  }
}
