//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/guard_grid</module>
////     <fsharp-lineage>None — novel ETS-backed guard verdict matrix</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Guard Grid — 2D matrix of guard verdicts across 8 fractal layers
////       × 24 modules. Each cell holds a GuardVerdict from module_guard.
////       Wolfram Rule 110 detects cascade propagation.
////       Shannon entropy measures system predictability.
////       Lyapunov exponent approximation signals stability regime.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>
////       SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-TRUTH-001,
////       SC-MUDA-001, SC-NASA-001, SC-MATH-COV-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Rust health_orchestra check_consensus() ↪ Gleam pure matrix.
////       All state is immutable — record_verdict returns a new GuardGrid.
////       No ETS writes here; callers own persistence in OTP actor state.
////     </morphism>
////     <morphism type="surjective" loss="wall-clock time">
////       last_check_timestamp is a logical monotonic counter, not wall-clock.
////       Mitigation: caller increments counter and passes it explicitly.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// GUARD GRID — ETS-backed verdict matrix with Wolfram emergence detection
//// ऋतं च सत्यं चाभीद्धात् तपसो — From tapas (discipline) arose truth and
//// cosmic order (Rig Veda 10.190.1)
////
//// Architecture:
////   module_guard (sensing) → GuardGrid (memory) → Ruliology (emergence)
////
////   The grid has 24 cells: 8 layers × 3 modules per layer.
////   Every guard verdict is recorded into a cell and the aggregate metrics
////   are recomputed immediately (pure functional, O(n) in cell count).
////
////   Wolfram Rule 110 is applied to the 8-layer failure vector to detect
////   whether failure patterns exhibit chaotic / cascading / stable behavior.
////
////   Lyapunov exponent approximation:
////     λ ≈ log(failure_spread_rate / recovery_rate)
////     λ > 0  → unstable (failures spreading)
////     λ < 0  → stable (recovery faster than spread)
////     λ ≈ 0  → edge of chaos (complex emergent behavior)
////
////   Shannon entropy H = -Σ(p_i × log₂(p_i)) over the 5 verdict types.
////   H < 0.5 bits → healthy (mostly PASSED, predictable)
////   H > 2.0 bits → chaotic (all verdict types equally represented)
////
//// STAMP: SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-TRUTH-001, SC-NASA-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Constants — layer and module topology
// ---------------------------------------------------------------------------

/// The 8 fractal layers of the C3I mesh
const layers: List(String) = ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"]

/// Standard modules for each layer (index must match layers list)
/// 3 modules per layer = 24 cells total
const layer_modules: List(List(String)) = [
  // L0 Constitutional
  ["guardian", "psi_invariants", "emergency_stop"],
  // L1 Atomic/Debug
  ["nif_bridge", "otel_trace", "debug_probes"],
  // L2 Component
  ["a2ui_catalog", "shell_helpers", "lustre_ssr"],
  // L3 Transaction
  ["plan_status", "smriti_db", "planning_db"],
  // L4 System
  ["container_genome", "boot_sequencer", "cpu_governor"],
  // L5 Cognitive
  ["cortex", "ooda_loop", "inference_cascade"],
  // L6 Ecosystem
  ["zenoh_mesh", "quorum", "moz_bridge"],
  // L7 Federation
  ["gateway", "ha_election", "version_vectors"],
]

/// Wolfram Rule 110 lookup table
/// Input: 3-bit neighborhood (left, center, right) as integer 0-7
/// Output: 0 or 1 (the new cell state)
/// 110 in binary = 01101110 — rule 110 is known for complex/universal behavior
const rule_110: List(Int) = [0, 1, 1, 1, 0, 1, 1, 0]

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A single cell in the guard grid: one layer × one module verdict
pub type GridCell {
  GridCell(
    /// Fractal layer identifier, e.g. "L0".."L7"
    layer: String,
    /// Module name, e.g. "dashboard", "planning", "nif_plan_status"
    module: String,
    /// Verdict string: "PASSED" | "FAILED_EMPTY" | "FAILED_MISSING_FIELD" |
    ///                 "FAILED_TOO_SHORT" | "FAILED_CORRUPTED" | "FAILED_STALE"
    verdict: String,
    /// Consecutive failure count for this cell (reset on PASSED)
    failure_count: Int,
    /// Logical monotonic counter acting as timestamp (not wall-clock)
    last_check_timestamp: Int,
    /// Total checks performed for this cell since init
    check_count: Int,
  )
}

/// Aggregate snapshot of the full 24-cell guard grid
pub type GuardGrid {
  GuardGrid(
    /// All 24 cells (8 layers × 3 modules)
    cells: List(GridCell),
    /// Total number of cells (always 24)
    total_cells: Int,
    /// Cells with verdict == "PASSED"
    passed_cells: Int,
    /// Cells with any failure verdict
    failed_cells: Int,
    /// passed_cells / total_cells (0.0 to 1.0)
    health_score: Float,
    /// Shannon entropy of verdict distribution (bits, 0.0 to ~2.32)
    entropy: Float,
    /// True if adjacent layer failures detected (Wolfram cascade signal)
    cascade_detected: Bool,
    /// Layer with the most failed cells
    hotspot_layer: String,
    /// Module with the most failures across all layers
    hotspot_module: String,
  )
}

/// Cellular automata rule result — Wolfram Rule 110 classification
pub type CellularRule {
  /// No meaningful pattern detected
  RuleNone
  /// Failures are spreading to adjacent layers (cascade)
  RuleCascade
  /// Single isolated cell failure, not propagating
  RuleIsolated
  /// Failure repeats in a periodic pattern across layers
  RulePeriodic
  /// Random failures spread across grid — systemic issue
  RuleSystemic
  /// Previously failed cells are returning to PASSED
  RuleRecovering
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialize the guard grid with all 8 layers and standard modules.
/// All cells start with verdict "PASSED", zero failure counts.
pub fn init() -> GuardGrid {
  let cells = build_initial_cells()
  build_grid(cells)
}

/// Record a guard verdict for a specific layer + module.
/// Returns a new GuardGrid with updated metrics.
/// If the layer/module is not found, the grid is returned unchanged.
pub fn record_verdict(
  grid: GuardGrid,
  layer: String,
  module: String,
  verdict: String,
  timestamp: Int,
) -> GuardGrid {
  let updated =
    list.map(grid.cells, fn(cell) {
      case cell.layer == layer && cell.module == module {
        False -> cell
        True -> {
          let is_failure = verdict != "PASSED"
          let new_failure_count = case is_failure {
            True -> cell.failure_count + 1
            False -> 0
          }
          GridCell(
            layer: cell.layer,
            module: cell.module,
            verdict: verdict,
            failure_count: new_failure_count,
            last_check_timestamp: timestamp,
            check_count: cell.check_count + 1,
          )
        }
      }
    })
  build_grid(updated)
}

/// Get the health score: passed_cells / total_cells (0.0..1.0)
pub fn health_score(grid: GuardGrid) -> Float {
  grid.health_score
}

/// Compute Shannon entropy of the verdict distribution across all cells.
/// H = -Σ(p_i × log₂(p_i)) where p_i = count(verdict_type_i) / total
/// H = 0.0 → all same verdict (completely predictable)
/// H → 2.32 → maximum entropy (all 5 verdict types equally likely)
pub fn compute_entropy(grid: GuardGrid) -> Float {
  let total = grid.total_cells
  case total == 0 {
    True -> 0.0
    False -> {
      let counts = count_verdicts(grid.cells)
      let total_f = int.to_float(total)
      list.fold(counts, 0.0, fn(acc, count) {
        case count == 0 {
          True -> acc
          False -> {
            let p = int.to_float(count) /. total_f
            let contribution = p *. log2_approx(p)
            acc -. contribution
          }
        }
      })
    }
  }
}

/// Apply Wolfram Rule 110 to the 8-layer failure vector.
/// Each layer is a binary cell: 1 if ANY module in that layer has failed.
/// Rule 110 evolves the vector one generation and classifies the result.
///
/// Rule 110 truth table (neighborhood: left-center-right → output):
///   111→0, 110→1, 101→1, 100→0, 011→1, 010→1, 001→1, 000→0
pub fn apply_rule_110(grid: GuardGrid) -> CellularRule {
  let state = layer_failure_vector(grid)
  let next_state = evolve_rule_110(state)
  classify_rule_110(state, next_state)
}

/// Detect if failures are spreading between adjacent layers.
/// Returns True if two or more adjacent layers both have failures.
pub fn detect_cascade(grid: GuardGrid) -> Bool {
  let vector = layer_failure_vector(grid)
  has_adjacent_ones(vector)
}

/// Find the hotspot — layer and module with most cumulative failures.
/// Returns #(layer, module).
pub fn find_hotspot(grid: GuardGrid) -> #(String, String) {
  let hotspot_cell =
    list.fold(
      grid.cells,
      GridCell(
        layer: "none",
        module: "none",
        verdict: "PASSED",
        failure_count: 0,
        last_check_timestamp: 0,
        check_count: 0,
      ),
      fn(best, cell) {
        case cell.failure_count > best.failure_count {
          True -> cell
          False -> best
        }
      },
    )
  #(hotspot_cell.layer, hotspot_cell.module)
}

/// Lyapunov exponent approximation.
/// λ = log(failure_spread_rate / max(recovery_rate, epsilon))
///
/// failure_spread_rate = (cells with consecutive_failures > 1) / total_cells
/// recovery_rate       = (cells with failure_count == 0) / total_cells
///
/// λ > 0.0  → failures spreading faster than recovery (unstable)
/// λ < 0.0  → recovery outpacing spread (stable)
/// λ ≈ 0.0  → edge of chaos (complex, interesting behavior)
pub fn lyapunov_estimate(grid: GuardGrid) -> Float {
  let total_f = int.to_float(grid.total_cells)
  case total_f == 0.0 {
    True -> 0.0
    False -> {
      let spreading = list.count(grid.cells, fn(c) { c.failure_count > 1 })
      let recovering = list.count(grid.cells, fn(c) { c.failure_count == 0 })

      let spread_rate = int.to_float(spreading) /. total_f
      let recovery_rate = int.to_float(recovering) /. total_f

      // Avoid log(0) by using epsilon = 0.001
      let safe_recovery = case recovery_rate <. 0.001 {
        True -> 0.001
        False -> recovery_rate
      }
      let safe_spread = case spread_rate <. 0.001 {
        True -> 0.001
        False -> spread_rate
      }

      // λ ≈ log(spread / recovery) — positive means spreading, negative stable
      log_natural_approx(safe_spread /. safe_recovery)
    }
  }
}

/// Predict the next likely failure cell using frequency + adjacency analysis.
/// Returns #(layer, module, probability).
/// The cell with the highest failure_count / check_count ratio is most likely.
pub fn predict_next_failure(grid: GuardGrid) -> #(String, String, Float) {
  let best =
    list.fold(grid.cells, #("none", "none", 0.0), fn(best, cell) {
      case cell.check_count > 0 {
        False -> best
        True -> {
          let fail_rate =
            int.to_float(cell.failure_count) /. int.to_float(cell.check_count)
          let #(_, _, best_rate) = best
          case fail_rate >. best_rate {
            True -> #(cell.layer, cell.module, fail_rate)
            False -> best
          }
        }
      }
    })
  best
}

/// Serialize the guard grid to a JSON string.
pub fn to_json(grid: GuardGrid) -> String {
  let cells_json =
    grid.cells
    |> list.map(cell_to_json)
    |> string.join(",")

  "{"
  <> "\"total_cells\":"
  <> int.to_string(grid.total_cells)
  <> ",\"passed_cells\":"
  <> int.to_string(grid.passed_cells)
  <> ",\"failed_cells\":"
  <> int.to_string(grid.failed_cells)
  <> ",\"health_score\":"
  <> float_to_str(grid.health_score)
  <> ",\"entropy\":"
  <> float_to_str(grid.entropy)
  <> ",\"cascade_detected\":"
  <> bool_to_str(grid.cascade_detected)
  <> ",\"hotspot_layer\":\""
  <> grid.hotspot_layer
  <> "\",\"hotspot_module\":\""
  <> grid.hotspot_module
  <> "\",\"cells\":["
  <> cells_json
  <> "]}"
}

// ---------------------------------------------------------------------------
// Wolfram elementary CA — generic + named rules
// ---------------------------------------------------------------------------

/// Conway's Game of Life pattern classification.
/// Determined by comparing two successive generations of the 8×3 grid.
pub type LifePattern {
  /// Grid is identical to previous — all cells frozen
  StillLife
  /// Grid changed but same as a prior state — cyclic pattern
  Oscillator
  /// Structured moving pattern (simplified: small non-zero popn, change detected)
  Glider
  /// Large unpredictable changes — systemic instability
  Chaos
  /// No live cells in either generation
  Empty
}

/// Apply a specific Wolfram elementary CA rule (0-255) to the 8-layer failure
/// states.  The rule number is used as an 8-bit lookup table.
///
/// Algorithm:
///   1. Extract binary layer vector [L0_fail..L7_fail]
///   2. For each cell i, compute neighborhood = left*4 + self*2 + right (mod 8)
///   3. Bit at position `neighborhood` in `rule_number` = next state
///   4. Compare before/after to classify the result
pub fn apply_wolfram_rule(grid: GuardGrid, rule_number: Int) -> CellularRule {
  let state = layer_failure_vector(grid)
  let rule_table = build_rule_table(rule_number)
  let next_state = evolve_with_table(state, rule_table)
  classify_rule_110(state, next_state)
}

/// Apply Rule 30 — chaos / randomness detection.
/// Rule 30 is known for its pseudo-random, aperiodic output from simple inputs.
/// In the mesh context: detects unpredictable failure spreading.
pub fn apply_rule_30(grid: GuardGrid) -> CellularRule {
  apply_wolfram_rule(grid, 30)
}

/// Apply Rule 184 — traffic flow / backpressure analysis.
/// Rule 184 models particle flow: 1s move right when space available.
/// In the mesh: detects backpressure cascades where failures "flow" downstream.
pub fn apply_rule_184(grid: GuardGrid) -> CellularRule {
  apply_wolfram_rule(grid, 184)
}

/// Apply Rule 90 — fractal / self-similar pattern detection.
/// Rule 90 generates Sierpiński triangle patterns (XOR of left and right neighbors).
/// In the mesh: detects fractal failure patterns that repeat across layers.
pub fn apply_rule_90(grid: GuardGrid) -> CellularRule {
  apply_wolfram_rule(grid, 90)
}

/// Apply Rule 54 — oscillation / periodic pattern detection.
/// Rule 54 produces stable oscillators from simple inputs.
/// In the mesh: detects periodic failure patterns (ping-pong between layers).
pub fn apply_rule_54(grid: GuardGrid) -> CellularRule {
  apply_wolfram_rule(grid, 54)
}

/// Apply Rule 126 — rapid growth detection.
/// Rule 126 causes rapid expansion of activated cells.
/// In the mesh: signals explosive failure growth (high-urgency cascade).
pub fn apply_rule_126(grid: GuardGrid) -> CellularRule {
  apply_wolfram_rule(grid, 126)
}

/// Run all 6 rules (110, 30, 184, 90, 54, 126) and return the consensus pattern.
/// Returns a list of #(rule_number, CellularRule) tuples.
pub fn multi_rule_analysis(grid: GuardGrid) -> List(#(Int, CellularRule)) {
  [
    #(110, apply_rule_110(grid)),
    #(30, apply_rule_30(grid)),
    #(184, apply_rule_184(grid)),
    #(90, apply_rule_90(grid)),
    #(54, apply_rule_54(grid)),
    #(126, apply_rule_126(grid)),
  ]
}

// ---------------------------------------------------------------------------
// Conway's Game of Life on the 8×3 grid
// ---------------------------------------------------------------------------

/// Conway's Game of Life step on the 8×3 guard grid.
/// Each cell: failed = alive (1), passed = dead (0).
/// Rules: B3/S23 — a dead cell with exactly 3 live neighbors is born;
///         a live cell survives with 2 or 3 live neighbors, else it dies.
/// Grid topology: rows = layers (0..7), cols = modules (0..2).
/// Boundary: edges wrap (toroidal).
pub fn game_of_life_step(grid: GuardGrid) -> GuardGrid {
  // Build 8×3 binary matrix indexed by (layer_idx, module_idx)
  let matrix = build_life_matrix(grid)
  // Apply GoL rules to each cell
  let next_matrix =
    list.index_map(matrix, fn(row, row_idx) {
      list.index_map(row, fn(cell, col_idx) {
        let neighbors = count_live_neighbors(matrix, row_idx, col_idx)
        case cell == 1 {
          // Alive: survives with 2 or 3 neighbors
          True ->
            case neighbors == 2 || neighbors == 3 {
              True -> 1
              False -> 0
            }
          // Dead: born with exactly 3 neighbors
          False ->
            case neighbors == 3 {
              True -> 1
              False -> 0
            }
        }
      })
    })
  // Convert next_matrix back to a GuardGrid by applying verdicts
  matrix_to_grid(next_matrix)
}

/// Classify the Conway Game of Life pattern by comparing two grid generations.
///
///   Empty     — both grids have no live cells
///   StillLife — grids are identical (no change)
///   Oscillator — grids differ but population is the same size
///   Glider    — small population (≤ 5) that changed position
///   Chaos     — large-scale unpredictable change (many births + deaths)
pub fn classify_life_pattern(
  current: GuardGrid,
  previous: GuardGrid,
) -> LifePattern {
  let prev_alive = previous.failed_cells
  let curr_alive = current.failed_cells
  case prev_alive == 0 && curr_alive == 0 {
    True -> Empty
    False ->
      case current.cells == previous.cells {
        True -> StillLife
        False -> {
          let total_cells = current.total_cells
          case prev_alive == curr_alive {
            // Same population, different configuration → oscillator
            True -> Oscillator
            False ->
              // Population changed: small moving pattern vs large chaos
              case curr_alive <= 5 && curr_alive > 0 {
                True -> Glider
                False ->
                  case curr_alive > total_cells / 2 {
                    True -> Chaos
                    False -> Oscillator
                  }
              }
          }
        }
      }
  }
}

// ---------------------------------------------------------------------------
// Brian's Brain — 3-state cellular automaton
// ---------------------------------------------------------------------------
// अनन्तं विश्वम् — The universe is infinite

/// Brian's Brain state — 3 states for recovery cycle modeling.
/// Models the failure-recovery lifecycle of mesh nodes:
///   Off       = healthy (quiescent)
///   Firing    = actively failing (anomaly detected)
///   Recovering = refractory period (just recovered, not yet trusted)
pub type BrainState {
  BrainOff
  BrainFiring
  BrainRecovering
}

/// Apply one Brian's Brain generation to a list of 24 BrainState values.
/// Rules (hard-wired, no configuration):
///   Off + exactly 2 Firing neighbors → Firing
///   Firing → Recovering (unconditional)
///   Recovering → Off (unconditional)
/// The list is treated as a flat 24-element 1D ring (toroidal boundary).
/// This maps naturally to the 24 guard-grid cells in linear order.
pub fn brians_brain_step(states: List(BrainState)) -> List(BrainState) {
  let n = list.length(states)
  case n == 0 {
    True -> []
    False ->
      list.index_map(states, fn(state, i) {
        case state {
          // Firing → Recovering (unconditional)
          BrainFiring -> BrainRecovering
          // Recovering → Off (unconditional)
          BrainRecovering -> BrainOff
          // Off → Firing only if exactly 2 neighbors are Firing
          BrainOff -> {
            let left = get_brain_cell(states, modulo(i - 1 + n, n))
            let right = get_brain_cell(states, modulo(i + 1, n))
            let firing_neighbors = brain_firing_count([left, right])
            case firing_neighbors == 2 {
              True -> BrainFiring
              False -> BrainOff
            }
          }
        }
      })
  }
}

/// Check if any cells are stuck in Recovering state.
/// A cell that lingers in Recovering indicates a slow-recovery hotspot —
/// a node that fired but has not yet returned to Off (trusted baseline).
/// In guard-grid terms: FAILED cells that have acknowledged the fault but
/// are not yet re-verified as PASSED.
pub fn has_stuck_recovery(states: List(BrainState)) -> Bool {
  list.any(states, fn(s) { s == BrainRecovering })
}

/// Count Firing cells in a BrainState list.
pub fn count_firing(states: List(BrainState)) -> Int {
  list.count(states, fn(s) { s == BrainFiring })
}

/// Convert a GuardGrid to a Brian's Brain initial state.
/// PASSED → BrainOff, any failure verdict → BrainFiring.
/// Useful for seeding the automaton from real grid state.
pub fn grid_to_brain_states(grid: GuardGrid) -> List(BrainState) {
  list.map(grid.cells, fn(c) {
    case c.verdict == "PASSED" {
      True -> BrainOff
      False -> BrainFiring
    }
  })
}

// ---------------------------------------------------------------------------
// Langton's Ant — failure-propagation trace
// ---------------------------------------------------------------------------

/// Direction the ant faces on the 8×3 guard grid.
pub type AntDirection {
  AntUp
  AntDown
  AntLeft
  AntRight
}

/// Langton's Ant state — position + orientation + path history.
/// The ant moves across the 24-cell guard grid and its path traces
/// how failures (marked cells) propagate through the system topology.
pub type AntState {
  AntState(
    /// 0-23: cell index in row-major order (row = layer, col = module).
    position: Int,
    /// Current facing direction.
    direction: AntDirection,
    /// Total steps taken so far.
    steps: Int,
    /// Ordered list of cells visited (head = most recently visited).
    path: List(Int),
  )
}

/// Initialize the ant at the center of the 8×3 grid (position 12 = L4/col1).
pub fn init_ant() -> AntState {
  AntState(position: 12, direction: AntUp, steps: 0, path: [])
}

/// Take one Langton's Ant step.
/// On a PASSED cell (False in grid_states): turn right, mark cell FAILED (True), move forward.
/// On a FAILED cell (True in grid_states): turn left, mark cell PASSED (False), move forward.
/// Returns the new ant state and the updated grid state list.
pub fn ant_step(
  ant: AntState,
  grid_states: List(Bool),
) -> #(AntState, List(Bool)) {
  let pos = ant.position
  let n = list.length(grid_states)
  let is_failed = get_bool_cell(grid_states, pos)
  // Determine new direction and flip cell
  let new_dir = case is_failed {
    // On FAILED cell → turn left
    True -> turn_left(ant.direction)
    // On PASSED cell → turn right
    False -> turn_right(ant.direction)
  }
  let flipped = set_bool_cell(grid_states, pos, !is_failed)
  // Move forward one step in the new direction (toroidal 8×3 grid)
  let new_pos = move_ant(pos, new_dir, n)
  let new_ant =
    AntState(position: new_pos, direction: new_dir, steps: ant.steps + 1, path: [
      pos,
      ..ant.path
    ])
  #(new_ant, flipped)
}

/// Run the ant for `steps` iterations and return the ordered cell-visit path.
/// Path head = first visited, path tail = last visited.
pub fn ant_trace(grid_states: List(Bool), steps: Int) -> List(Int) {
  let ant = init_ant()
  let #(final_ant, _) = run_ant_steps(ant, grid_states, steps)
  list.reverse(final_ant.path)
}

// ---------------------------------------------------------------------------
// Totalistic 1D CA — density-of-failure detection
// ---------------------------------------------------------------------------

/// Apply a totalistic 1D CA rule to the guard grid's layer failure vector.
/// The next state of each cell depends only on the SUM of its neighborhood
/// (itself + left + right) — i.e., the density of failures in a window of 3.
///
/// `threshold` is the minimum sum that produces a 1 (failure) in the next
/// generation.  Values 0-3 are meaningful:
///   0 → always fires (all outputs 1)
///   1 → fires if ANY neighbor or self is failing
///   2 → fires only if 2+ in neighborhood are failing (majority rule)
///   3 → fires only if ALL three in neighborhood are failing
///
/// Returns a CellularRule classifying the resulting pattern, identical in
/// semantics to the Wolfram rules above but derived from density, not position.
pub fn apply_totalistic_rule(grid: GuardGrid, threshold: Int) -> CellularRule {
  let state = layer_failure_vector(grid)
  let n = list.length(state)
  let next_state =
    list.index_map(state, fn(_cell, i) {
      let left = get_cell(state, modulo(i - 1 + n, n))
      let center = get_cell(state, i)
      let right = get_cell(state, modulo(i + 1, n))
      let sum = left + center + right
      case sum >= threshold {
        True -> 1
        False -> 0
      }
    })
  classify_rule_110(state, next_state)
}

/// Human-readable summary line for logging and TUI display.
pub fn summary(grid: GuardGrid) -> String {
  "GuardGrid: "
  <> int.to_string(grid.passed_cells)
  <> "/"
  <> int.to_string(grid.total_cells)
  <> " PASSED | health="
  <> float_to_str(grid.health_score)
  <> " | H="
  <> float_to_str(grid.entropy)
  <> "bits | cascade="
  <> bool_to_str(grid.cascade_detected)
  <> " | hotspot="
  <> grid.hotspot_layer
  <> "/"
  <> grid.hotspot_module
}

// ---------------------------------------------------------------------------
// Private helpers — grid construction
// ---------------------------------------------------------------------------

/// Build the initial 24 cells from the static layer/module topology.
fn build_initial_cells() -> List(GridCell) {
  list.zip(layers, layer_modules)
  |> list.flat_map(fn(pair) {
    let #(layer, modules) = pair
    list.map(modules, fn(mod_name) {
      GridCell(
        layer: layer,
        module: mod_name,
        verdict: "PASSED",
        failure_count: 0,
        last_check_timestamp: 0,
        check_count: 0,
      )
    })
  })
}

/// Recompute all aggregate metrics from the current cell list.
fn build_grid(cells: List(GridCell)) -> GuardGrid {
  let total = list.length(cells)
  let passed = list.count(cells, fn(c) { c.verdict == "PASSED" })
  let failed = total - passed
  let health = case total == 0 {
    True -> 1.0
    False -> int.to_float(passed) /. int.to_float(total)
  }
  let grid_partial =
    GuardGrid(
      cells: cells,
      total_cells: total,
      passed_cells: passed,
      failed_cells: failed,
      health_score: health,
      entropy: 0.0,
      cascade_detected: False,
      hotspot_layer: "none",
      hotspot_module: "none",
    )
  let h = compute_entropy(grid_partial)
  let cascade = detect_cascade(grid_partial)
  let #(hot_layer, hot_module) = find_hotspot(grid_partial)
  GuardGrid(
    cells: cells,
    total_cells: total,
    passed_cells: passed,
    failed_cells: failed,
    health_score: health,
    entropy: h,
    cascade_detected: cascade,
    hotspot_layer: hot_layer,
    hotspot_module: hot_module,
  )
}

// ---------------------------------------------------------------------------
// Private helpers — Wolfram Rule 110
// ---------------------------------------------------------------------------

/// Build an 8-element binary list: 1 if layer has any failure, 0 otherwise.
fn layer_failure_vector(grid: GuardGrid) -> List(Int) {
  list.map(layers, fn(layer) {
    let has_failure =
      list.any(grid.cells, fn(c) { c.layer == layer && c.verdict != "PASSED" })
    case has_failure {
      True -> 1
      False -> 0
    }
  })
}

/// Evolve one generation of the 8-cell automaton using Rule 110.
/// Boundary: wrap-around (toroidal).
fn evolve_rule_110(state: List(Int)) -> List(Int) {
  let n = list.length(state)
  case n == 0 {
    True -> []
    False -> {
      // list.index_map signature: fn(element, index) -> result
      list.index_map(state, fn(_cell, i) {
        let left_idx = modulo(i - 1 + n, n)
        let right_idx = modulo(i + 1, n)
        let left = get_cell(state, left_idx)
        let center = get_cell(state, i)
        let right = get_cell(state, right_idx)
        let neighborhood = left * 4 + center * 2 + right
        get_cell(rule_110, neighborhood)
      })
    }
  }
}

/// Safe modulo for non-negative inputs (avoids int.remainder Result type).
fn modulo(a: Int, b: Int) -> Int {
  case b == 0 {
    True -> 0
    False -> a - b * { a / b }
  }
}

/// Classify the Rule 110 evolution result.
fn classify_rule_110(before: List(Int), after: List(Int)) -> CellularRule {
  let ones_before = list.fold(before, 0, fn(acc, x) { acc + x })
  let ones_after = list.fold(after, 0, fn(acc, x) { acc + x })
  let n = list.length(before)

  case ones_before == 0 && ones_after == 0 {
    True -> RuleNone
    False ->
      case before == after {
        True ->
          case ones_before == 1 {
            True -> RuleIsolated
            False -> RulePeriodic
          }
        False ->
          case ones_after > ones_before {
            True -> RuleCascade
            False ->
              case ones_after < ones_before {
                True -> RuleRecovering
                False ->
                  case ones_before > n / 2 {
                    True -> RuleSystemic
                    False -> RulePeriodic
                  }
              }
          }
      }
  }
}

/// Detect two adjacent 1s in a list (adjacent layer failures).
fn has_adjacent_ones(lst: List(Int)) -> Bool {
  case lst {
    [] | [_] -> False
    [a, b, ..rest] ->
      case a == 1 && b == 1 {
        True -> True
        False -> has_adjacent_ones([b, ..rest])
      }
  }
}

// ---------------------------------------------------------------------------
// Private helpers — verdict counting for entropy
// ---------------------------------------------------------------------------

/// Count occurrences of each of the 5 verdict types.
/// Returns [count_passed, count_failed_empty, count_failed_missing,
///          count_failed_too_short, count_failed_corrupted_or_stale]
fn count_verdicts(cells: List(GridCell)) -> List(Int) {
  let passed = list.count(cells, fn(c) { c.verdict == "PASSED" })
  let empty = list.count(cells, fn(c) { c.verdict == "FAILED_EMPTY" })
  let missing = list.count(cells, fn(c) { c.verdict == "FAILED_MISSING_FIELD" })
  let short = list.count(cells, fn(c) { c.verdict == "FAILED_TOO_SHORT" })
  let other =
    list.count(cells, fn(c) {
      c.verdict != "PASSED"
      && c.verdict != "FAILED_EMPTY"
      && c.verdict != "FAILED_MISSING_FIELD"
      && c.verdict != "FAILED_TOO_SHORT"
    })
  [passed, empty, missing, short, other]
}

// ---------------------------------------------------------------------------
// Private helpers — math
// ---------------------------------------------------------------------------

/// log₂(x) approximation using the identity log₂(x) = ln(x) / ln(2).
/// Uses a rational approximation of ln(x) valid for x in (0.0, 1.0].
fn log2_approx(x: Float) -> Float {
  // ln(x) / ln(2), ln(2) ≈ 0.693147
  log_natural_approx(x) /. 0.693147
}

/// Natural log approximation for x in (0.0, 1.5].
/// Uses the series: ln(x) ≈ 2 × Σ((z^(2k+1))/(2k+1)) where z = (x-1)/(x+1)
/// Accurate to ~4 decimal places for x in [0.001, 1.5].
fn log_natural_approx(x: Float) -> Float {
  case x <=. 0.0 {
    True -> -100.0
    False -> {
      let z = { x -. 1.0 } /. { x +. 1.0 }
      let z2 = z *. z
      // 6-term series: 2*(z + z^3/3 + z^5/5 + z^7/7 + z^9/9 + z^11/11)
      let z3 = z2 *. z
      let z5 = z3 *. z2
      let z7 = z5 *. z2
      let z9 = z7 *. z2
      let z11 = z9 *. z2
      2.0
      *. {
        z +. z3 /. 3.0 +. z5 /. 5.0 +. z7 /. 7.0 +. z9 /. 9.0 +. z11 /. 11.0
      }
    }
  }
}

/// Safe index into a list. Returns 0 for out-of-range indices.
fn get_cell(lst: List(Int), idx: Int) -> Int {
  case idx < 0 {
    True -> 0
    False ->
      lst
      |> list.drop(idx)
      |> list.first()
      |> fn(r) {
        case r {
          Ok(v) -> v
          Error(_) -> 0
        }
      }
  }
}

// ---------------------------------------------------------------------------
// Private helpers — generic Wolfram rule evolution
// ---------------------------------------------------------------------------

/// Build an 8-element rule lookup table from an integer rule number (0-255).
/// rule_table[i] = bit i of rule_number.
fn build_rule_table(rule_number: Int) -> List(Int) {
  [0, 1, 2, 3, 4, 5, 6, 7]
  |> list.map(fn(bit) {
    // Extract bit `bit` from rule_number
    { rule_number / int_pow2(bit) } % 2
  })
}

/// 2^n for small non-negative n (used only for rule table extraction).
fn int_pow2(n: Int) -> Int {
  case n {
    0 -> 1
    1 -> 2
    2 -> 4
    3 -> 8
    4 -> 16
    5 -> 32
    6 -> 64
    7 -> 128
    _ -> 1
  }
}

/// Evolve one generation using the supplied 8-element rule table.
/// Boundary: toroidal (wrap-around).
fn evolve_with_table(state: List(Int), rule_table: List(Int)) -> List(Int) {
  let n = list.length(state)
  case n == 0 {
    True -> []
    False ->
      list.index_map(state, fn(_cell, i) {
        let left = get_cell(state, modulo(i - 1 + n, n))
        let center = get_cell(state, i)
        let right = get_cell(state, modulo(i + 1, n))
        let neighborhood = left * 4 + center * 2 + right
        get_cell(rule_table, neighborhood)
      })
  }
}

// ---------------------------------------------------------------------------
// Private helpers — Conway's Game of Life
// ---------------------------------------------------------------------------

/// The static list of layer names used as row identifiers (mirrors `layers`).
const life_layers: List(String) = [
  "L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7",
]

/// Build an 8×3 binary matrix from the guard grid.
/// Row i = layer i, column j = module j.  1 = failed, 0 = passed.
fn build_life_matrix(grid: GuardGrid) -> List(List(Int)) {
  list.zip(life_layers, layer_modules)
  |> list.map(fn(pair) {
    let #(layer, modules) = pair
    list.map(modules, fn(mod_name) {
      case
        list.any(grid.cells, fn(c) {
          c.layer == layer && c.module == mod_name && c.verdict != "PASSED"
        })
      {
        True -> 1
        False -> 0
      }
    })
  })
}

/// Count the live (=1) neighbors of cell (row, col) in the 8×3 toroidal grid.
fn count_live_neighbors(matrix: List(List(Int)), row: Int, col: Int) -> Int {
  let num_rows = list.length(matrix)
  let num_cols = 3
  let offsets = [
    #(-1, -1),
    #(-1, 0),
    #(-1, 1),
    #(0, -1),
    #(0, 1),
    #(1, -1),
    #(1, 0),
    #(1, 1),
  ]
  list.fold(offsets, 0, fn(acc, offset) {
    let #(dr, dc) = offset
    let nr = modulo(row + dr + num_rows, num_rows)
    let nc = modulo(col + dc + num_cols, num_cols)
    acc + get_cell_2d(matrix, nr, nc)
  })
}

/// Safe 2D cell access: get matrix[row][col], returns 0 for any error.
fn get_cell_2d(matrix: List(List(Int)), row: Int, col: Int) -> Int {
  matrix
  |> list.drop(row)
  |> list.first()
  |> fn(r) {
    case r {
      Ok(row_list) -> get_cell(row_list, col)
      Error(_) -> 0
    }
  }
}

/// Convert an 8×3 binary matrix back to a GuardGrid.
/// 1 = FAILED_EMPTY, 0 = PASSED.  All other cell metadata reset.
fn matrix_to_grid(matrix: List(List(Int))) -> GuardGrid {
  let cells =
    list.zip(life_layers, list.zip(layer_modules, matrix))
    |> list.flat_map(fn(outer) {
      let #(layer, pair) = outer
      let #(modules, row) = pair
      list.zip(modules, row)
      |> list.map(fn(inner) {
        let #(mod_name, alive) = inner
        let verdict = case alive == 1 {
          True -> "FAILED_EMPTY"
          False -> "PASSED"
        }
        GridCell(
          layer: layer,
          module: mod_name,
          verdict: verdict,
          failure_count: alive,
          last_check_timestamp: 0,
          check_count: 1,
        )
      })
    })
  build_grid(cells)
}

// ---------------------------------------------------------------------------
// Private helpers — serialization
// ---------------------------------------------------------------------------

fn cell_to_json(c: GridCell) -> String {
  "{"
  <> "\"layer\":\""
  <> c.layer
  <> "\",\"module\":\""
  <> c.module
  <> "\",\"verdict\":\""
  <> c.verdict
  <> "\",\"failure_count\":"
  <> int.to_string(c.failure_count)
  <> ",\"last_check_timestamp\":"
  <> int.to_string(c.last_check_timestamp)
  <> ",\"check_count\":"
  <> int.to_string(c.check_count)
  <> "}"
}

fn float_to_str(f: Float) -> String {
  // Round to 4 decimal places for clean output
  let scaled = float.round(f *. 10_000.0)
  let whole = scaled / 10_000
  let frac = int.absolute_value(scaled % 10_000)
  int.to_string(whole) <> "." <> pad_left(int.to_string(frac), 4)
}

fn bool_to_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

fn pad_left(s: String, width: Int) -> String {
  let len = string.length(s)
  case len >= width {
    True -> s
    False -> string.repeat("0", width - len) <> s
  }
}

// ---------------------------------------------------------------------------
// Private helpers — Brian's Brain
// ---------------------------------------------------------------------------

/// Count the number of BrainFiring entries in a list.
fn brain_firing_count(states: List(BrainState)) -> Int {
  list.count(states, fn(s) { s == BrainFiring })
}

/// Safe index into a BrainState list. Returns BrainOff for out-of-range.
fn get_brain_cell(lst: List(BrainState), idx: Int) -> BrainState {
  case idx < 0 {
    True -> BrainOff
    False ->
      lst
      |> list.drop(idx)
      |> list.first()
      |> fn(r) {
        case r {
          Ok(v) -> v
          Error(_) -> BrainOff
        }
      }
  }
}

// ---------------------------------------------------------------------------
// Private helpers — Langton's Ant
// ---------------------------------------------------------------------------

/// Turn right from the current direction (clockwise 90°).
fn turn_right(dir: AntDirection) -> AntDirection {
  case dir {
    AntUp -> AntRight
    AntRight -> AntDown
    AntDown -> AntLeft
    AntLeft -> AntUp
  }
}

/// Turn left from the current direction (counter-clockwise 90°).
fn turn_left(dir: AntDirection) -> AntDirection {
  case dir {
    AntUp -> AntLeft
    AntLeft -> AntDown
    AntDown -> AntRight
    AntRight -> AntUp
  }
}

/// Move position forward by one step on the toroidal 8×3 grid.
/// Row = pos / 3, Col = pos % 3.  Rows 0-7 (L0..L7), Cols 0-2.
fn move_ant(pos: Int, dir: AntDirection, n: Int) -> Int {
  let rows = 8
  let cols = 3
  let row = pos / cols
  let col = pos % cols
  let #(new_row, new_col) = case dir {
    AntUp -> #(modulo(row - 1 + rows, rows), col)
    AntDown -> #(modulo(row + 1, rows), col)
    AntLeft -> #(row, modulo(col - 1 + cols, cols))
    AntRight -> #(row, modulo(col + 1, cols))
  }
  new_row * cols + new_col
  // Clamp to valid range just in case
  |> fn(p) { modulo(p + n, n) }
}

/// Safe index into a Bool list. Returns False for out-of-range.
fn get_bool_cell(lst: List(Bool), idx: Int) -> Bool {
  case idx < 0 {
    True -> False
    False ->
      lst
      |> list.drop(idx)
      |> list.first()
      |> fn(r) {
        case r {
          Ok(v) -> v
          Error(_) -> False
        }
      }
  }
}

/// Return a new Bool list with element at `idx` replaced by `value`.
fn set_bool_cell(lst: List(Bool), idx: Int, value: Bool) -> List(Bool) {
  list.index_map(lst, fn(cell, i) {
    case i == idx {
      True -> value
      False -> cell
    }
  })
}

/// Recursively run the ant for `steps` steps.
fn run_ant_steps(
  ant: AntState,
  grid: List(Bool),
  steps: Int,
) -> #(AntState, List(Bool)) {
  case steps <= 0 {
    True -> #(ant, grid)
    False -> {
      let #(next_ant, next_grid) = ant_step(ant, grid)
      run_ant_steps(next_ant, next_grid, steps - 1)
    }
  }
}
