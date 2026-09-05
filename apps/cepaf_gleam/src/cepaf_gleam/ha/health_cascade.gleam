//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/health_cascade</module>
////     <fsharp-lineage>None — novel health cascade (F21)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Ordered health check cascade across L0-L7 fractal layers.
////       Each layer verifies its own dependencies before reporting healthy.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-SIL4-001, SC-VER-001, SC-HA-001, SC-FUNC-002, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Rust health_orchestra.rs check_consensus() ↪ Gleam pure cascade function.
////       Results are immutable values — no shared mutable health state (SC-SIL4-001).
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Health Check Cascade — F21
//// सर्वारम्भाः हि दोषेण धूमेनाग्निरिवावृताः
//// All undertakings are shrouded by imperfection as fire by smoke (Gita 18.48)
////
//// Dependency graph (checked in order L0 → L7):
////
////   L0 Constitutional : []              (foundation — no dependencies)
////   L1 Atomic/Debug   : [L0]
////   L2 Component      : [L0, L1]
////   L3 Transaction    : [L0, L1, L2]
////   L4 System         : [L0, L3]
////   L5 Cognitive      : [L0, L3, L4]
////   L6 Ecosystem      : [L0, L4]
////   L7 Federation     : [L0, L5, L6]
////
//// The cascade halts at the FIRST layer that fails, setting cascade_depth.
//// All layers up to and including the failure layer are included in `layers`.
////
//// STAMP: SC-SIL4-001, SC-VER-001, SC-HA-001, SC-FUNC-002, SC-MUDA-001

import gleam/json
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Health status of a single fractal layer.
pub type LayerHealth {
  LayerHealth(
    /// Layer identifier, e.g. "L0", "L1", …, "L7".
    layer: String,
    /// True iff all internal checks for this layer pass.
    healthy: Bool,
    /// True iff all declared dependency layers are healthy.
    dependencies_met: Bool,
    /// Number of checks that passed.
    checks_passed: Int,
    /// Total checks performed for this layer.
    checks_total: Int,
    /// Human-readable summary.
    message: String,
  )
}

/// Result of a full L0→L7 cascade.
pub type CascadeResult {
  CascadeResult(
    /// All layers checked (in order), up to and including the first failure.
    layers: List(LayerHealth),
    /// True iff every layer from L0 to L7 is healthy.
    all_healthy: Bool,
    /// "none" when all pass; otherwise the label of the first failing layer.
    first_failure: String,
    /// Number of layers checked before stopping (= 8 when all_healthy).
    cascade_depth: Int,
  )
}

// ---------------------------------------------------------------------------
// Layer dependency graph
// ---------------------------------------------------------------------------

/// Return the dependency labels for the given layer.
///
/// The dependency list is the single source of truth for the cascade order.
pub fn dependencies_for(layer: String) -> List(String) {
  case layer {
    "L0" -> []
    "L1" -> ["L0"]
    "L2" -> ["L0", "L1"]
    "L3" -> ["L0", "L1", "L2"]
    "L4" -> ["L0", "L3"]
    "L5" -> ["L0", "L3", "L4"]
    "L6" -> ["L0", "L4"]
    "L7" -> ["L0", "L5", "L6"]
    _ -> []
  }
}

// ---------------------------------------------------------------------------
// Internal check helpers — deterministic, no IO
// ---------------------------------------------------------------------------

/// Return the number of internal checks defined for the layer.
fn layer_check_total(layer: String) -> Int {
  case layer {
    "L0" -> 4
    // Guardian, Psi invariants, constitution hash, emergency stop
    "L1" -> 3
    // NIF load, OTel exporter, trace buffer
    "L2" -> 3
    // A2UI catalog, component registry, form validator
    "L3" -> 4
    // SQLite WAL, Smriti FTS5, planning DB, state snapshot
    "L4" -> 5
    // Podman socket, container count, build history, boot DAG, CPU governor
    "L5" -> 4
    // OODA FSM, MCP tools, Gemma endpoint, cortex actor
    "L6" -> 3
    // Zenoh router, topic subscriptions, mesh topology
    "L7" -> 3
    // Federation gateway, version vectors, consensus quorum
    _ -> 1
  }
}

/// Simulate an internal check result for the layer.
///
/// In production this would call into NIFs / system checks; here we provide
/// a deterministic pure implementation so the cascade logic can be tested
/// without side effects. The function is pure: same layer → same result.
fn run_layer_checks(layer: String) -> #(Int, String) {
  let total = layer_check_total(layer)
  // All simulated checks pass — replace with real NIF calls in production.
  #(total, "all checks nominal")
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Check a single layer and return its health record.
///
/// `checked_layers` is the accumulator of already-checked layers, used to
/// evaluate dependency health inline.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> layer is a valid L0-L7 string; checked_layers contains results for all declared deps. </P>
///     <C> check_layer(layer, checked_layers) </C>
///     <Q> Returns LayerHealth with dependencies_met = (all deps in checked_layers are healthy). </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn check_layer(
  layer: String,
  checked_layers: List(LayerHealth),
) -> LayerHealth {
  let deps = dependencies_for(layer)

  // For each declared dependency, find its result in checked_layers.
  let deps_met =
    list.all(deps, fn(dep) {
      list.any(checked_layers, fn(lh) { lh.layer == dep && lh.healthy })
    })

  let #(passed, msg) = case deps_met {
    False ->
      // Short-circuit: do not run own checks if dependencies are unmet.
      #(0, "dependency not met: " <> string.join(deps, ", "))
    True -> run_layer_checks(layer)
  }

  let total = layer_check_total(layer)
  let is_healthy = deps_met && passed == total

  LayerHealth(
    layer: layer,
    healthy: is_healthy,
    dependencies_met: deps_met,
    checks_passed: passed,
    checks_total: total,
    message: case is_healthy {
      True -> msg
      False ->
        case deps_met {
          False -> "dependency not met: " <> string.join(deps, ", ")
          True ->
            "checks failed: "
            <> string.inspect(passed)
            <> "/"
            <> string.inspect(total)
        }
    },
  )
}

/// Run the full L0→L7 health cascade, halting at the first failing layer.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> No preconditions — pure computation. </P>
///     <C> check_cascade() </C>
///     <Q>
///       Returns CascadeResult where:
///         layers contains all checked LayerHealth records (in order),
///         all_healthy == (every layer is healthy),
///         first_failure == "none" when all_healthy,
///         cascade_depth == 8 when all_healthy.
///     </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn check_cascade() -> CascadeResult {
  let layer_order = ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"]
  run_cascade(layer_order, [], "none")
}

/// Recursive cascade runner.
fn run_cascade(
  remaining: List(String),
  checked: List(LayerHealth),
  first_failure: String,
) -> CascadeResult {
  case remaining {
    [] ->
      // All layers checked.
      CascadeResult(
        layers: checked,
        all_healthy: first_failure == "none",
        first_failure: first_failure,
        cascade_depth: list.length(checked),
      )
    [layer, ..rest] -> {
      // If a failure is already recorded, stop the cascade.
      case first_failure != "none" {
        True ->
          CascadeResult(
            layers: checked,
            all_healthy: False,
            first_failure: first_failure,
            cascade_depth: list.length(checked),
          )
        False -> {
          let lh = check_layer(layer, checked)
          let next_checked = list.append(checked, [lh])
          let next_failure = case lh.healthy {
            True -> "none"
            False -> layer
          }
          run_cascade(rest, next_checked, next_failure)
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// JSON serialisation (SC-GLM-UI-003 — typed gleam/json, no string concat)
// ---------------------------------------------------------------------------

/// Serialise a single LayerHealth to a JSON object value.
pub fn layer_health_to_json(lh: LayerHealth) -> json.Json {
  json.object([
    #("layer", json.string(lh.layer)),
    #("healthy", json.bool(lh.healthy)),
    #("dependencies_met", json.bool(lh.dependencies_met)),
    #("checks_passed", json.int(lh.checks_passed)),
    #("checks_total", json.int(lh.checks_total)),
    #("message", json.string(lh.message)),
  ])
}

/// Serialise the full CascadeResult to a JSON string.
pub fn to_json(result: CascadeResult) -> String {
  json.object([
    #("layers", json.array(result.layers, fn(lh) { layer_health_to_json(lh) })),
    #("all_healthy", json.bool(result.all_healthy)),
    #("first_failure", json.string(result.first_failure)),
    #("cascade_depth", json.int(result.cascade_depth)),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// Convenience accessors
// ---------------------------------------------------------------------------

/// Find the LayerHealth for a specific layer label (returns None if absent).
pub fn find_layer(
  result: CascadeResult,
  layer: String,
) -> Result(LayerHealth, Nil) {
  list.find(result.layers, fn(lh) { lh.layer == layer })
}

/// True iff a specific layer is healthy in the cascade result.
pub fn layer_is_healthy(result: CascadeResult, layer: String) -> Bool {
  case find_layer(result, layer) {
    Ok(lh) -> lh.healthy
    Error(Nil) -> False
  }
}

/// Return a one-line summary of the cascade result (for TUI / logging).
pub fn summary(result: CascadeResult) -> String {
  case result.all_healthy {
    True ->
      "cascade OK — all 8 layers healthy (depth="
      <> string.inspect(result.cascade_depth)
      <> ")"
    False ->
      "cascade FAIL — first failure at "
      <> result.first_failure
      <> " (depth="
      <> string.inspect(result.cascade_depth)
      <> ")"
  }
}
