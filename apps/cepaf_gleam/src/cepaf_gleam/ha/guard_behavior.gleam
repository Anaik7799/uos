//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/guard_behavior</module>
////     <fsharp-lineage>None — novel behavioral specification (F23)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Behavioral specification — expected behavior for every module at every
////       fractal layer. Defines what "correct" means for each of the 24 standard
////       modules (3 per layer × 8 layers), including the mathematical invariant
////       that must hold at all times.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-ALLIUM-001, SC-VER-001, SC-HA-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Allium behavioral specs ≅ Gleam ModuleBehavior catalog.
////       Each entity maps 1:1; invariant strings are preserved verbatim.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Guard Behavioral Specification — Expected behavior for every module
//// यद्यदाचरति श्रेष्ठः — Whatever the great person does, others follow (Gita 3.21)
////
//// 24 module behaviors are defined (3 modules × 8 fractal layers L0-L7).
//// Each behavior records:
////   - module         : identifier matching the guard grid module name
////   - layer          : which fractal layer owns this module
////   - expected_verdict: normally "PASSED" (what the module should report)
////   - max_consecutive_failures: threshold before escalation fires
////   - recovery_action: which runbook to invoke on violation
////   - criticality    : "safety-critical" | "operational" | "informational"
////   - math_invariant : the formal mathematical property that must hold
////
//// STAMP: SC-ALLIUM-001, SC-VER-001, SC-HA-001, SC-MUDA-001

import gleam/int
import gleam/list
import gleam/result
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Expected behavior specification for one module
pub type ModuleBehavior {
  ModuleBehavior(
    /// Module identifier — matches the guard grid module name
    module: String,
    /// Fractal layer this module belongs to ("L0".."L7")
    layer: String,
    /// Verdict the module should produce when healthy
    expected_verdict: String,
    /// Number of consecutive failures before the recovery action fires
    max_consecutive_failures: Int,
    /// Runbook to invoke when max_consecutive_failures is exceeded
    recovery_action: String,
    /// Operational criticality class
    criticality: String,
    /// Mathematical invariant that MUST hold while expected_verdict is met
    math_invariant: String,
  )
}

// ---------------------------------------------------------------------------
// Behavior catalog — 24 modules (3 per layer × 8 layers)
// ---------------------------------------------------------------------------

/// Full behavioral specification for all 24 standard modules.
pub fn all_behaviors() -> List(ModuleBehavior) {
  [
    // ── L0 Constitutional (safety-critical) ──────────────────────────────
    ModuleBehavior(
      module: "guardian",
      layer: "L0",
      expected_verdict: "PASSED",
      max_consecutive_failures: 1,
      recovery_action: "RB-010",
      criticality: "safety-critical",
      math_invariant: "∀ mutation M: approved(M) ∨ blocked(M)  (total function — no silent mutations)",
    ),
    ModuleBehavior(
      module: "psi_invariants",
      layer: "L0",
      expected_verdict: "PASSED",
      max_consecutive_failures: 1,
      recovery_action: "RB-010",
      criticality: "safety-critical",
      math_invariant: "Ψ₀ ∧ Ψ₁ ∧ Ψ₂ ∧ Ψ₃ ∧ Ψ₄ ∧ Ψ₅ ∧ Ω₀ = true always",
    ),
    ModuleBehavior(
      module: "constitution_hash",
      layer: "L0",
      expected_verdict: "PASSED",
      max_consecutive_failures: 1,
      recovery_action: "RB-007",
      criticality: "safety-critical",
      math_invariant: "hash(constitution) = const_H₀  (immutable reference)",
    ),
    // ── L1 Atomic/Debug ──────────────────────────────────────────────────
    ModuleBehavior(
      module: "nif_bridge",
      layer: "L1",
      expected_verdict: "PASSED",
      max_consecutive_failures: 3,
      recovery_action: "RB-001",
      criticality: "operational",
      math_invariant: "|response| > 0 ∧ parse(response) ∈ JSON  (non-empty valid JSON)",
    ),
    ModuleBehavior(
      module: "otel_exporter",
      layer: "L1",
      expected_verdict: "PASSED",
      max_consecutive_failures: 5,
      recovery_action: "RB-004",
      criticality: "informational",
      math_invariant: "∀ span s: s.trace_id ≠ ∅ ∧ s.start_ms ≤ s.end_ms",
    ),
    ModuleBehavior(
      module: "beam_metrics",
      layer: "L1",
      expected_verdict: "PASSED",
      max_consecutive_failures: 5,
      recovery_action: "RB-008",
      criticality: "informational",
      math_invariant: "memory_words ≥ 0 ∧ process_count ≥ 1  (non-negative counters)",
    ),
    // ── L2 Component ─────────────────────────────────────────────────────
    ModuleBehavior(
      module: "a2ui_renderer",
      layer: "L2",
      expected_verdict: "PASSED",
      max_consecutive_failures: 5,
      recovery_action: "RB-004",
      criticality: "operational",
      math_invariant: "render(spec) ≠ ∅  (renderer is total — no empty output)",
    ),
    ModuleBehavior(
      module: "type_catalog",
      layer: "L2",
      expected_verdict: "PASSED",
      max_consecutive_failures: 10,
      recovery_action: "RB-003",
      criticality: "informational",
      math_invariant: "|catalog| = 233  (fixed component count invariant)",
    ),
    ModuleBehavior(
      module: "wiring_guard",
      layer: "L2",
      expected_verdict: "PASSED",
      max_consecutive_failures: 1,
      recovery_action: "RB-007",
      criticality: "operational",
      math_invariant: "verify_all() = 95  (exactly 95 verified wiring connections)",
    ),
    // ── L3 Transaction ───────────────────────────────────────────────────
    ModuleBehavior(
      module: "plan_status",
      layer: "L3",
      expected_verdict: "PASSED",
      max_consecutive_failures: 3,
      recovery_action: "RB-003",
      criticality: "operational",
      math_invariant: "total = pending + active + completed + blocked  (partition sum)",
    ),
    ModuleBehavior(
      module: "sqlite_store",
      layer: "L3",
      expected_verdict: "PASSED",
      max_consecutive_failures: 2,
      recovery_action: "RB-007",
      criticality: "operational",
      math_invariant: "∀ write W: ∃ read R: R = W  (durability — WAL mode)",
    ),
    ModuleBehavior(
      module: "smriti_zettelkasten",
      layer: "L3",
      expected_verdict: "PASSED",
      max_consecutive_failures: 5,
      recovery_action: "RB-009",
      criticality: "informational",
      math_invariant: "|holons| ≥ 2060 ∧ fts5_index_valid = true  (knowledge base intact)",
    ),
    // ── L4 System ────────────────────────────────────────────────────────
    ModuleBehavior(
      module: "container_genome",
      layer: "L4",
      expected_verdict: "PASSED",
      max_consecutive_failures: 2,
      recovery_action: "RB-004",
      criticality: "operational",
      math_invariant: "healthy_count ≤ container_count ∧ healthy_count ≥ 0",
    ),
    ModuleBehavior(
      module: "podman_client",
      layer: "L4",
      expected_verdict: "PASSED",
      max_consecutive_failures: 3,
      recovery_action: "RB-004",
      criticality: "operational",
      math_invariant: "∀ container C: C.status ∈ {running, stopped, error}  (closed enum)",
    ),
    ModuleBehavior(
      module: "boot_dag",
      layer: "L4",
      expected_verdict: "PASSED",
      max_consecutive_failures: 1,
      recovery_action: "RB-010",
      criticality: "safety-critical",
      math_invariant: "DAG(boot_sequence) ∧ topo_sort(G_boot) is_valid  (no cycles)",
    ),
    // ── L5 Cognitive ─────────────────────────────────────────────────────
    ModuleBehavior(
      module: "ooda_loop",
      layer: "L5",
      expected_verdict: "PASSED",
      max_consecutive_failures: 2,
      recovery_action: "RB-005",
      criticality: "operational",
      math_invariant: "phase ∈ {O,Or,D,A,V} ∧ cycle_latency_ms < 100",
    ),
    ModuleBehavior(
      module: "cortex_agent",
      layer: "L5",
      expected_verdict: "PASSED",
      max_consecutive_failures: 3,
      recovery_action: "RB-005",
      criticality: "operational",
      math_invariant: "∀ intent I: ∃ response R: delivered(R, I)  (no-blackhole guarantee)",
    ),
    ModuleBehavior(
      module: "rule_engine",
      layer: "L5",
      expected_verdict: "PASSED",
      max_consecutive_failures: 3,
      recovery_action: "RB-005",
      criticality: "operational",
      math_invariant: "evaluate_decision(ctx) ∈ {actions}  (total function — always returns)",
    ),
    // ── L6 Ecosystem ─────────────────────────────────────────────────────
    ModuleBehavior(
      module: "zenoh_mesh",
      layer: "L6",
      expected_verdict: "PASSED",
      max_consecutive_failures: 2,
      recovery_action: "RB-002",
      criticality: "operational",
      math_invariant: "connected ⟹ router_count ≥ 1 ∧ latency_ms < 100",
    ),
    ModuleBehavior(
      module: "quorum_router",
      layer: "L6",
      expected_verdict: "PASSED",
      max_consecutive_failures: 2,
      recovery_action: "RB-002",
      criticality: "safety-critical",
      math_invariant: "alive_routers ≥ floor(N/2) + 1  (strict majority quorum)",
    ),
    ModuleBehavior(
      module: "moz_transport",
      layer: "L6",
      expected_verdict: "PASSED",
      max_consecutive_failures: 5,
      recovery_action: "RB-002",
      criticality: "operational",
      math_invariant: "∀ request R: ∃ response Resp: id(Resp) = id(R)  (request-response pairing)",
    ),
    // ── L7 Federation ────────────────────────────────────────────────────
    ModuleBehavior(
      module: "ha_election",
      layer: "L7",
      expected_verdict: "PASSED",
      max_consecutive_failures: 1,
      recovery_action: "RB-010",
      criticality: "safety-critical",
      math_invariant: "exactly_one(Primary) ∧ |Backup| ≥ 1  (leader uniqueness + backup guarantee)",
    ),
    ModuleBehavior(
      module: "gateway_bridge",
      layer: "L7",
      expected_verdict: "PASSED",
      max_consecutive_failures: 3,
      recovery_action: "RB-004",
      criticality: "operational",
      math_invariant: "∀ message M: delivered(M) ∨ retried(M, n ≤ 1)  (at-least-once delivery)",
    ),
    ModuleBehavior(
      module: "version_vector",
      layer: "L7",
      expected_verdict: "PASSED",
      max_consecutive_failures: 5,
      recovery_action: "RB-007",
      criticality: "informational",
      math_invariant: "∀ node n: vv[n] is monotonically non-decreasing over time",
    ),
  ]
}

// ---------------------------------------------------------------------------
// Lookup and violation detection
// ---------------------------------------------------------------------------

/// Retrieve the behavior specification for a named module.
/// Returns Error when the module is not in the catalog.
pub fn behavior_for(module: String) -> Result(ModuleBehavior, String) {
  all_behaviors()
  |> list.find(fn(b) { b.module == module })
  |> result.map_error(fn(_) { "unknown module: " <> module })
}

/// Return True when the actual verdict or consecutive failure count violates
/// this module's behavioral specification.
pub fn is_violation(
  behavior: ModuleBehavior,
  actual_verdict: String,
  consecutive_failures: Int,
) -> Bool {
  actual_verdict != behavior.expected_verdict
  || consecutive_failures > behavior.max_consecutive_failures
}

/// Retrieve the mathematical invariant description for a named module.
/// Returns a generic message when the module is not found.
pub fn invariant_description(module: String) -> String {
  case behavior_for(module) {
    Ok(b) -> b.math_invariant
    Error(_) -> "no invariant defined for module: " <> module
  }
}

/// Total number of behaviors in the catalog.
pub fn behavior_count() -> Int {
  list.length(all_behaviors())
}

/// All modules with the given criticality class.
pub fn by_criticality(criticality: String) -> List(ModuleBehavior) {
  all_behaviors()
  |> list.filter(fn(b) { b.criticality == criticality })
}

/// All modules in a given fractal layer.
pub fn by_layer(layer: String) -> List(ModuleBehavior) {
  all_behaviors()
  |> list.filter(fn(b) { b.layer == layer })
}

/// Safety-critical modules — max_consecutive_failures is always 1 for L0.
/// Returns True when the module is safety-critical and any failure occurred.
pub fn is_safety_halt(
  behavior: ModuleBehavior,
  consecutive_failures: Int,
) -> Bool {
  behavior.criticality == "safety-critical"
  && consecutive_failures >= behavior.max_consecutive_failures
}

/// Summarise catalog as human-readable lines (useful for TUI / logging).
pub fn catalog_summary() -> String {
  all_behaviors()
  |> list.map(fn(b) {
    b.layer
    <> "/"
    <> b.module
    <> " ["
    <> b.criticality
    <> "] max_fail="
    <> int.to_string(b.max_consecutive_failures)
    <> " runbook="
    <> b.recovery_action
  })
  |> string.join("\n")
}
