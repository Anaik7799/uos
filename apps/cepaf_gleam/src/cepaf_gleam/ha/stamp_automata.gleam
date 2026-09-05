//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/stamp_automata</module>
////     <fsharp-lineage>None — novel STAMP constraint CA mapping (RETE5)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Maps STAMP constraint violations to cellular automaton transitions.
////       Each STAMP constraint is a cell in a 1D grid with state
////       Compliant | AtRisk | Violated.  The evaluation step propagates
////       violation influence to neighbours (one step in each direction):
////         - Violated cells make neighbours AtRisk
////         - AtRisk cells remain AtRisk unless all neighbours are Compliant
////         - Compliant cells recover if no Violated neighbour exists
////       This models the real-world contagion of STAMP constraint failures
////       across interdependent safety requirements.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>
////       SC-SIL4-001, SC-FUNC-001, SC-SAFETY-001, SC-GLM-UI-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       STAMP constraint list ↪ StampCell ADT grid.
////       CA transition rules encode safety-contagion semantics.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// STAMP CONSTRAINT AUTOMATA — RETE5
//// अहिंसा परमो धर्मः — Non-violation is the highest duty (Mahabharata)
////
//// Models STAMP constraint compliance as a cellular automaton where violations
//// propagate to neighbouring constraints.  Suitable for health-grid page
//// visualization and for formal analysis of constraint failure cascades.
////
//// STAMP: SC-SIL4-001, SC-FUNC-001, SC-SAFETY-001, SC-GLM-UI-001, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Compliance status of a single STAMP constraint.
pub type StampStatus {
  /// Constraint is fully satisfied
  Compliant
  /// Constraint is at risk — a neighbour is violated or evidence is weakening
  AtRisk
  /// Constraint is violated — safety invariant breached
  Violated
}

/// A single cell in the STAMP constraint grid.
pub type StampCell {
  StampCell(
    /// The constraint identifier, e.g. "SC-SIL4-001"
    constraint_id: String,
    /// Current compliance status
    status: StampStatus,
    /// Generation (step) at which this cell last changed status
    generation: Int,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise a grid of STAMP cells from a list of constraint IDs.
///
/// All cells start as Compliant at generation 0.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">List(String) ↪ List(StampCell) all Compliant</morphism>
///   <formal-proof>
///     <P> constraints is non-empty list of non-empty strings </P>
///     <C> init_grid(constraints) </C>
///     <Q> |grid| = |constraints|; all cells Compliant; generation = 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init_grid(constraints: List(String)) -> List(StampCell) {
  list.map(constraints, fn(id) {
    StampCell(constraint_id: id, status: Compliant, generation: 0)
  })
}

/// Advance the STAMP grid one evaluation step.
///
/// Transition rules (safety-contagion semantics):
///   - If any neighbour is Violated → cell becomes AtRisk (or stays Violated)
///   - If cell is Violated → stays Violated (violations require explicit recovery)
///   - If cell is AtRisk and no Violated neighbour → becomes Compliant
///   - If cell is Compliant and no Violated neighbour → stays Compliant
///
/// Boundary: cells at edges have only one neighbour.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">List(StampCell) ↪ next-step List(StampCell)</morphism>
///   <formal-proof>
///     <P> cells is non-empty </P>
///     <C> evaluate_step(cells) </C>
///     <Q> |new| = |old|; Violated cells never self-heal;
///         Compliant neighbours of Violated become AtRisk </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn evaluate_step(cells: List(StampCell)) -> List(StampCell) {
  let n = list.length(cells)
  list.index_map(cells, fn(cell, i) {
    let left_status = case i > 0 {
      True ->
        cells
        |> list.drop(i - 1)
        |> list.first
        |> fn(r) {
          case r {
            Ok(c) -> c.status
            Error(_) -> Compliant
          }
        }
      False -> Compliant
    }
    let right_status = case i < n - 1 {
      True ->
        cells
        |> list.drop(i + 1)
        |> list.first
        |> fn(r) {
          case r {
            Ok(c) -> c.status
            Error(_) -> Compliant
          }
        }
      False -> Compliant
    }
    let has_violated_neighbour =
      left_status == Violated || right_status == Violated
    let new_status = case cell.status {
      Violated -> Violated
      AtRisk ->
        case has_violated_neighbour {
          True -> AtRisk
          False -> Compliant
        }
      Compliant ->
        case has_violated_neighbour {
          True -> AtRisk
          False -> Compliant
        }
    }
    let new_gen = case new_status != cell.status {
      True -> cell.generation + 1
      False -> cell.generation
    }
    StampCell(
      constraint_id: cell.constraint_id,
      status: new_status,
      generation: new_gen,
    )
  })
}

/// Count the number of Violated cells in the grid.
pub fn violation_count(cells: List(StampCell)) -> Int {
  cells
  |> list.filter(fn(c) { c.status == Violated })
  |> list.length
}

/// Count the number of AtRisk cells.
pub fn at_risk_count(cells: List(StampCell)) -> Int {
  cells
  |> list.filter(fn(c) { c.status == AtRisk })
  |> list.length
}

/// Ratio of Compliant cells to total cells [0.0, 1.0].
///
/// Returns 1.0 for an empty grid (vacuously compliant).
pub fn compliance_ratio(cells: List(StampCell)) -> Float {
  let n = list.length(cells)
  case n == 0 {
    True -> 1.0
    False -> {
      let compliant =
        cells
        |> list.filter(fn(c) { c.status == Compliant })
        |> list.length
      int.to_float(compliant) /. int.to_float(n)
    }
  }
}

/// Serialise the cell grid to a compact JSON array.
pub fn to_json(cells: List(StampCell)) -> String {
  let inner =
    cells
    |> list.map(fn(c) {
      "{\"constraint_id\":\""
      <> escape_json(c.constraint_id)
      <> "\",\"status\":\""
      <> status_to_string(c.status)
      <> "\",\"generation\":"
      <> int.to_string(c.generation)
      <> "}"
    })
    |> string.join(",")
  "[" <> inner <> "]"
}

/// Human-readable one-line summary of the grid state.
pub fn summary(cells: List(StampCell)) -> String {
  let n = list.length(cells)
  let v = violation_count(cells)
  let a = at_risk_count(cells)
  let c = n - v - a
  let ratio = compliance_ratio(cells)
  "STAMP["
  <> int.to_string(n)
  <> " constraints | compliant="
  <> int.to_string(c)
  <> " at_risk="
  <> int.to_string(a)
  <> " violated="
  <> int.to_string(v)
  <> " ratio="
  <> float4(ratio)
  <> "]"
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Convert StampStatus to a string for JSON / display.
pub fn status_to_string(s: StampStatus) -> String {
  case s {
    Compliant -> "compliant"
    AtRisk -> "at_risk"
    Violated -> "violated"
  }
}

/// Minimal JSON string escaping.
fn escape_json(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
}

/// Render a float with 4 decimal places.
fn float4(v: Float) -> String {
  let millis = float.round(v *. 10_000.0)
  let whole = millis / 10_000
  let frac = millis % 10_000
  let frac_str = case frac < 10 {
    True -> "000" <> int.to_string(frac)
    False ->
      case frac < 100 {
        True -> "00" <> int.to_string(frac)
        False ->
          case frac < 1000 {
            True -> "0" <> int.to_string(frac)
            False -> int.to_string(frac)
          }
      }
  }
  int.to_string(whole) <> "." <> frac_str
}
