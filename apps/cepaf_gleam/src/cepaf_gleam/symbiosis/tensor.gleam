//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/symbiosis/tensor</module>
////     <fsharp-lineage>None — novel Gleam implementation</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-BIO-EVO-001..007, SC-MOKSHA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="constructive">
////       Biomorphic tensor: 7 properties of life × 8 fractal layers = 56 cells.
////       Each cell has a status (Active/Partial/Missing) and a health score [0,1].
////       Coverage = |Active cells| / 56. Target: 100%.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// भग्नात्मक जैवरूपी प्रसार — Fractal Biomorphic Tensor
//// Maps the 7 properties of living organisms across all 8 fractal layers.
////
//// STAMP: SC-BIO-EVO-001..007, SC-MOKSHA-001, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/list

/// The 7 properties of living organisms (जीवन के ७ गुण).
pub type BiomorphicProperty {
  /// समस्थिति — Dashboard weather bar + OODA monitoring
  Homeostasis
  /// चयापचय — CPU Governor adaptive parallelism
  Metabolism
  /// वृद्धि — Template-driven page evolution
  Growth
  /// प्रजनन — Autopoiesis, self-generation
  Reproduction
  /// प्रतिक्रिया — WebSocket 1s push, auto-build hook
  Response
  /// अनुकूलन — RL policy, fitness function
  Adaptation
  /// विकास — Hot code reload, genetic algorithm
  Evolution
}

/// Cell status in the biomorphic tensor.
pub type CellStatus {
  /// Fully implemented and verified
  Active
  /// Partially implemented
  Partial
  /// Not yet implemented
  Missing
  /// Not applicable at this layer
  NotApplicable
}

/// A single cell in the 7×8 tensor.
pub type TensorCell {
  TensorCell(
    property: BiomorphicProperty,
    layer: Int,
    status: CellStatus,
    score: Float,
    implementation: String,
  )
}

/// The full biomorphic tensor: 7 properties × 8 layers = 56 cells.
pub type BiomorphicTensor {
  BiomorphicTensor(cells: List(TensorCell), coverage: Float, health: Float)
}

/// Build the canonical biomorphic tensor with current implementation state.
/// This is the single source of truth for biomorphic coverage.
pub fn build() -> BiomorphicTensor {
  let cells = [
    // ── Homeostasis (समस्थिति) ──────────────────────────────────
    cell(Homeostasis, 0, Active, 0.95, "Guardian approval, emergency stop"),
    cell(Homeostasis, 1, Active, 0.9, "Auto-build hook response"),
    cell(Homeostasis, 2, Active, 0.85, "Component health badges"),
    cell(
      Homeostasis,
      3,
      Active,
      0.9,
      "State diff viewer + 3-gate DQ ingest (NIF/Rust/SQL CHECK)",
    ),
    cell(
      Homeostasis,
      4,
      Active,
      0.95,
      "Container health consensus + 4 cron schedules (DQ + page-checker)",
    ),
    cell(
      Homeostasis,
      5,
      Active,
      0.95,
      "Dark Cockpit 5-mode + OODA + RETE-UL data_quality (7 rules)",
    ),
    cell(Homeostasis, 6, Active, 0.9, "Zenoh mesh health monitoring"),
    cell(Homeostasis, 7, Active, 0.85, "Federation peer health"),
    // ── Metabolism (चयापचय) ──────────────────────────────────────
    cell(Metabolism, 0, Active, 0.9, "Safety kernel resource limits"),
    cell(Metabolism, 1, Active, 0.85, "NIF bridge throughput + 14 NIFs"),
    cell(Metabolism, 2, Active, 0.8, "Component render budgets"),
    cell(
      Metabolism,
      3,
      Active,
      0.92,
      "Transaction rate + dq_scan SQL scanner (Pass-15)",
    ),
    cell(
      Metabolism,
      4,
      Active,
      0.95,
      "CPU Governor adaptive parallelism + oban dispatch",
    ),
    cell(
      Metabolism,
      5,
      Active,
      0.92,
      "OODA <100ms + ruliology DQ Rule30/110/Lyapunov (Pass-14)",
    ),
    cell(Metabolism, 6, Active, 0.85, "Zenoh bandwidth management"),
    cell(Metabolism, 7, Active, 0.8, "Federation sync bandwidth"),
    // ── Growth (वृद्धि) ─────────────────────────────────────────
    cell(
      Growth,
      0,
      Active,
      0.82,
      "SC-* constraint count + SC-PD-RUST-ONLY (10 IDs Pass-14)",
    ),
    cell(
      Growth,
      1,
      Active,
      0.87,
      "NIF function count grows (125+) + proptest validators (Pass-16)",
    ),
    cell(Growth, 2, Active, 0.8, "A2UI catalog expands (233 components)"),
    cell(
      Growth,
      3,
      Active,
      0.92,
      "Test count grows: DQ family 0→29 in 3 passes (14/15/16)",
    ),
    cell(
      Growth,
      4,
      Active,
      0.87,
      "Container genome (16) + worker registry 21→22 (dq_scan)",
    ),
    cell(
      Growth,
      5,
      Active,
      0.92,
      "Rule engine + ruliology DQ submodule (3 Wolfram constructs)",
    ),
    cell(Growth, 6, Active, 0.8, "Agent mesh topology grows"),
    cell(Growth, 7, Active, 0.75, "Federation peer discovery"),
    // ── Reproduction (प्रजनन) ───────────────────────────────────
    // L0/L1: NotApplicable — safety kernel MUST NOT self-generate (SC-SAFETY-001)
    cell(
      Reproduction,
      0,
      NotApplicable,
      0.0,
      "Safety kernel: human-only (SC-SAFETY-001)",
    ),
    cell(
      Reproduction,
      1,
      NotApplicable,
      0.0,
      "NIF bridge: infrastructure, not autopoietic",
    ),
    // L2: A2UI agents propose components via JSON → catalog grows autopoietically
    cell(
      Reproduction,
      2,
      Active,
      0.75,
      "A2UI agents propose components via JSON schema",
    ),
    cell(Reproduction, 3, Active, 0.85, "Template-driven page generation"),
    // L4: Container genome defines specs → sa-plan-daemon rebuilds from spec
    cell(
      Reproduction,
      4,
      Active,
      0.7,
      "Genome spec → sa-plan-daemon auto-rebuild",
    ),
    cell(Reproduction, 5, Active, 0.9, "OODA generates rules + tests + docs"),
    // L6: Zenoh gossip auto-discovery → mesh self-organizes
    cell(Reproduction, 6, Active, 0.7, "Zenoh gossip peer auto-discovery"),
    cell(
      Reproduction,
      7,
      Active,
      0.8,
      "Autopoietic loop: rules→agents→code→rules",
    ),
    // ── Response (प्रतिक्रिया) ──────────────────────────────────
    cell(Response, 0, Active, 0.95, "Emergency stop <5s"),
    cell(Response, 1, Active, 0.9, "Auto-build <200ms"),
    cell(Response, 2, Active, 0.85, "Component re-render <100ms"),
    cell(Response, 3, Active, 0.9, "WebSocket 1s push"),
    cell(Response, 4, Active, 0.9, "Container restart <60s"),
    cell(Response, 5, Active, 0.95, "OODA Act phase <30ms"),
    cell(Response, 6, Active, 0.9, "Zenoh pub/sub <1ms"),
    cell(Response, 7, Active, 0.85, "Federation event propagation"),
    // ── Adaptation (अनुकूलन) ────────────────────────────────────
    cell(Adaptation, 0, Active, 0.7, "Guardian gate adapts severity thresholds"),
    cell(
      Adaptation,
      1,
      Active,
      0.72,
      "NIF + validate_priority/status proven over ~10⁴ random samples (Pass-16)",
    ),
    cell(Adaptation, 2, Active, 0.8, "A2UI dynamic component spec"),
    cell(
      Adaptation,
      3,
      Active,
      0.87,
      "Fitness-driven strategy selection + DQ scan-and-classify",
    ),
    cell(
      Adaptation,
      4,
      Active,
      0.85,
      "Container image staleness + auto-rebuild",
    ),
    cell(
      Adaptation,
      5,
      Active,
      0.95,
      "30 evolution strategies + RL policy + Wolfram-rule classifier",
    ),
    cell(Adaptation, 6, Active, 0.85, "Zenoh topic auto-discovery"),
    cell(Adaptation, 7, Active, 0.8, "Federated reconciliation"),
    // ── Evolution (विकास) ───────────────────────────────────────
    cell(
      Evolution,
      0,
      Active,
      0.65,
      "Psi invariants evolve via Guardian approval",
    ),
    cell(Evolution, 1, Active, 0.8, "NIF hot reload (restart required)"),
    cell(Evolution, 2, Active, 0.85, "Component catalog waves"),
    cell(Evolution, 3, Active, 0.9, "Hot code reload (BEAM)"),
    cell(Evolution, 4, Active, 0.85, "Rolling container upgrades"),
    cell(Evolution, 5, Active, 0.95, "Genetic algorithm + Cambrian explosion"),
    cell(Evolution, 6, Active, 0.8, "Mesh topology evolution"),
    cell(Evolution, 7, Active, 0.85, "Version vector reconciliation"),
  ]
  // Exclude NotApplicable from coverage denominator (they're by-design gaps)
  let applicable = list.filter(cells, fn(c) { c.status != NotApplicable })
  let active_count =
    list.length(list.filter(applicable, fn(c) { c.status == Active }))
  let partial_count =
    list.length(list.filter(applicable, fn(c) { c.status == Partial }))
  let applicable_total = list.length(applicable)
  let coverage = case applicable_total {
    0 -> 0.0
    _ -> {
      let effective =
        int_to_float(active_count) +. { int_to_float(partial_count) *. 0.5 }
      effective /. int_to_float(applicable_total)
    }
  }
  let health = case applicable_total {
    0 -> 0.0
    _ -> {
      let sum = list.fold(applicable, 0.0, fn(acc, c) { acc +. c.score })
      sum /. int_to_float(applicable_total)
    }
  }
  BiomorphicTensor(cells: cells, coverage: coverage, health: health)
}

/// Get cells for a specific property (row of tensor).
pub fn row(
  tensor: BiomorphicTensor,
  prop: BiomorphicProperty,
) -> List(TensorCell) {
  list.filter(tensor.cells, fn(c) { c.property == prop })
}

/// Get cells for a specific layer (column of tensor).
pub fn column(tensor: BiomorphicTensor, layer: Int) -> List(TensorCell) {
  list.filter(tensor.cells, fn(c) { c.layer == layer })
}

/// Count active cells.
pub fn active_count(tensor: BiomorphicTensor) -> Int {
  list.length(list.filter(tensor.cells, fn(c) { c.status == Active }))
}

/// Count missing cells.
pub fn missing_count(tensor: BiomorphicTensor) -> Int {
  list.length(list.filter(tensor.cells, fn(c) { c.status == Missing }))
}

/// Pass-17 — Pass-history accessor. Returns the cells annotated by a given
/// evolution pass (matched on the implementation string containing "Pass-N").
/// Used by the cockpit "what changed in pass N?" tile.
pub fn cells_upgraded_in_pass(
  tensor: BiomorphicTensor,
  pass: Int,
) -> List(TensorCell) {
  let needle = "Pass-" <> int.to_string(pass)
  list.filter(tensor.cells, fn(c) { string_contains(c.implementation, needle) })
}

/// Pass-17 — Aggregate evolution-pass index.
/// Returns the list of distinct passes referenced in current annotations.
pub fn pass_history(tensor: BiomorphicTensor) -> List(Int) {
  let candidates = [7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
  list.filter(candidates, fn(p) {
    let n = list.length(cells_upgraded_in_pass(tensor, p))
    n > 0
  })
}

/// Polyfill — gleam/string.contains lives in gleam_stdlib; we inline the
/// minimal substring check here to keep this module's import surface stable.
fn string_contains(haystack: String, needle: String) -> Bool {
  case needle {
    "" -> True
    _ -> {
      let h_len = string_length(haystack)
      let n_len = string_length(needle)
      case h_len < n_len {
        True -> False
        False -> string_contains_at(haystack, needle, 0, h_len - n_len)
      }
    }
  }
}

fn string_contains_at(
  haystack: String,
  needle: String,
  i: Int,
  max_i: Int,
) -> Bool {
  case i > max_i {
    True -> False
    False -> {
      let slice = string_slice(haystack, i, string_length(needle))
      case slice == needle {
        True -> True
        False -> string_contains_at(haystack, needle, i + 1, max_i)
      }
    }
  }
}

@external(erlang, "erlang", "byte_size")
fn string_length(s: String) -> Int

@external(erlang, "binary", "part")
fn string_slice(s: String, start: Int, length: Int) -> String

/// Property to string.
pub fn property_to_string(p: BiomorphicProperty) -> String {
  case p {
    Homeostasis -> "Homeostasis"
    Metabolism -> "Metabolism"
    Growth -> "Growth"
    Reproduction -> "Reproduction"
    Response -> "Response"
    Adaptation -> "Adaptation"
    Evolution -> "Evolution"
  }
}

/// Property to Sanskrit.
pub fn property_to_sanskrit(p: BiomorphicProperty) -> String {
  case p {
    Homeostasis -> "समस्थिति"
    Metabolism -> "चयापचय"
    Growth -> "वृद्धि"
    Reproduction -> "प्रजनन"
    Response -> "प्रतिक्रिया"
    Adaptation -> "अनुकूलन"
    Evolution -> "विकास"
  }
}

/// Cell status to string.
pub fn status_to_string(s: CellStatus) -> String {
  case s {
    Active -> "Active"
    Partial -> "Partial"
    Missing -> "Missing"
    NotApplicable -> "N/A"
  }
}

/// Layer number to label.
pub fn layer_label(n: Int) -> String {
  case n {
    0 -> "L0 Constitutional"
    1 -> "L1 Atomic"
    2 -> "L2 Component"
    3 -> "L3 Transaction"
    4 -> "L4 System"
    5 -> "L5 Cognitive"
    6 -> "L6 Ecosystem"
    7 -> "L7 Federation"
    _ -> "Unknown"
  }
}

// -- Internal ----------------------------------------------------------------

fn cell(
  property: BiomorphicProperty,
  layer: Int,
  status: CellStatus,
  score: Float,
  implementation: String,
) -> TensorCell {
  TensorCell(
    property: property,
    layer: layer,
    status: status,
    score: score,
    implementation: implementation,
  )
}

fn int_to_float(n: Int) -> Float {
  let assert Ok(f) = float.parse(int.to_string(n) <> ".0")
  f
}
