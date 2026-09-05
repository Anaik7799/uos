//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/ruliology_viz</module>
////     <fsharp-lineage>None — novel Wolfram CA visualization for health-grid page (RETE4)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Visualization types for Wolfram cellular automata state on the
////       health-grid page.  Each CA snapshot captures a 1D generation of cells
////       (Alive/Dead/Dying), the Wolfram rule number (0-255), a generation
////       counter, and two information-theoretic metrics:
////         - Shannon entropy H = -Σ p_i log₂ p_i  over {Alive, Dead, Dying}
////         - Lyapunov exponent λ approximated as fraction of cells that
////           changed state vs the previous generation
////       The module is purely functional; callers own state persistence.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-MUDA-001, SC-HA-001, SC-OODA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Wolfram elementary CA rules (256 possible) ↪ typed CaSnapshot ADT.
////       Rule application is deterministic; rule_number mod 256 guards range.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 ↠ Erlang float for entropy/Lyapunov.
////       Mitigation: values clamped to [0.0, 1.0] where semantics require it.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// WOLFRAM CA VISUALIZATION — RETE4
//// रूपं रूपं प्रतिरूपो बभूव — Form takes form in reflection (Rig Veda 6.47.18)
////
//// Implements typed Wolfram elementary cellular automaton snapshots for the
//// health-grid dashboard page.  Wolfram Rule 30 produces maximum entropy
//// (chaos indicator); Rule 110 produces complex / Turing-complete patterns;
//// Rule 184 models traffic flow / task-queue backpressure.
////
//// STAMP: SC-GLM-UI-001, SC-MUDA-001, SC-HA-001, SC-OODA-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// State of a single cell in the automaton.
pub type CellState {
  /// Cell is alive — active, firing, healthy
  Alive
  /// Cell is dead — quiescent, idle, inactive
  Dead
  /// Cell is transitioning from Alive toward Dead
  Dying
}

/// A complete snapshot of one CA generation.
pub type CaSnapshot {
  CaSnapshot(
    /// Current cell row (length == size)
    cells: List(CellState),
    /// Wolfram rule number [0, 255]
    rule_number: Int,
    /// Zero-based generation counter
    generation: Int,
    /// Shannon entropy H across {Alive, Dead, Dying} states (bits, [0.0, log2 3])
    entropy: Float,
    /// Lyapunov exponent approximation: fraction of cells differing from prev gen
    lyapunov: Float,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise a snapshot with a single central Alive seed.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">rule × size ↪ CaSnapshot with one seed</morphism>
///   <formal-proof>
///     <P> rule in [0, 255]; size >= 1 </P>
///     <C> init_snapshot(rule, size) </C>
///     <Q> CaSnapshot with exactly one Alive cell at centre; generation = 0;
///         entropy and lyapunov computed from initial row </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init_snapshot(rule: Int, size: Int) -> CaSnapshot {
  let safe_size = case size < 1 {
    True -> 1
    False -> size
  }
  let safe_rule = rule % 256
  let cells =
    list.repeat(Dead, safe_size)
    |> list.index_map(fn(_, i) {
      case i == safe_size / 2 {
        True -> Alive
        False -> Dead
      }
    })
  CaSnapshot(
    cells: cells,
    rule_number: safe_rule,
    generation: 0,
    entropy: entropy_of(cells),
    lyapunov: 0.0,
  )
}

/// Advance the automaton one generation using the stored Wolfram rule.
///
/// Boundary condition: dead cells beyond the edges (wrap with Dead).
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">CaSnapshot ↪ next-generation CaSnapshot</morphism>
///   <formal-proof>
///     <P> snapshot.cells is non-empty </P>
///     <C> evolve(snapshot) </C>
///     <Q> len(new.cells) = len(old.cells);
///         new.generation = old.generation + 1;
///         new.entropy computed from new cells;
///         new.lyapunov = fraction of changed cells </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn evolve(snapshot: CaSnapshot) -> CaSnapshot {
  let old = snapshot.cells
  let n = list.length(old)
  let arr = list.index_map(old, fn(c, i) { #(i, c) })
  let new_cells =
    arr
    |> list.map(fn(pair) {
      let #(i, _) = pair
      let left = cell_at(old, i - 1)
      let centre = cell_at(old, i)
      let right = cell_at(old, i + 1)
      apply_rule(snapshot.rule_number, left, centre, right)
    })
  let changed =
    list.zip(old, new_cells)
    |> list.filter(fn(p) { p.0 != p.1 })
    |> list.length
  let lya = case n > 0 {
    True -> int.to_float(changed) /. int.to_float(n)
    False -> 0.0
  }
  CaSnapshot(
    cells: new_cells,
    rule_number: snapshot.rule_number,
    generation: snapshot.generation + 1,
    entropy: entropy_of(new_cells),
    lyapunov: lya,
  )
}

/// Compute Shannon entropy of the cell state distribution (bits).
///
/// H = -Σ p_i log₂ p_i  for i ∈ {Alive, Dead, Dying}
/// Maximum is log₂ 3 ≈ 1.585 bits (uniform over 3 states).
pub fn entropy(snapshot: CaSnapshot) -> Float {
  snapshot.entropy
}

/// Serialise a CaSnapshot to a compact JSON string.
pub fn to_json(snapshot: CaSnapshot) -> String {
  let cells_json =
    snapshot.cells
    |> list.map(cell_to_string)
    |> list.map(fn(s) { "\"" <> s <> "\"" })
    |> string.join(",")
  "{"
  <> "\"rule_number\":"
  <> int.to_string(snapshot.rule_number)
  <> ",\"generation\":"
  <> int.to_string(snapshot.generation)
  <> ",\"entropy\":"
  <> float4(snapshot.entropy)
  <> ",\"lyapunov\":"
  <> float4(snapshot.lyapunov)
  <> ",\"cells\":["
  <> cells_json
  <> "]}"
}

/// Human-readable one-line summary.
pub fn summary(snapshot: CaSnapshot) -> String {
  let alive_count =
    snapshot.cells
    |> list.filter(fn(c) { c == Alive })
    |> list.length
  let dead_count =
    snapshot.cells
    |> list.filter(fn(c) { c == Dead })
    |> list.length
  let dying_count =
    snapshot.cells
    |> list.filter(fn(c) { c == Dying })
    |> list.length
  "CA[rule="
  <> int.to_string(snapshot.rule_number)
  <> " gen="
  <> int.to_string(snapshot.generation)
  <> " H="
  <> float4(snapshot.entropy)
  <> " λ="
  <> float4(snapshot.lyapunov)
  <> " alive="
  <> int.to_string(alive_count)
  <> " dead="
  <> int.to_string(dead_count)
  <> " dying="
  <> int.to_string(dying_count)
  <> "]"
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Safe cell accessor with Dead boundary condition.
fn cell_at(cells: List(CellState), i: Int) -> CellState {
  case i < 0 || i >= list.length(cells) {
    True -> Dead
    False ->
      cells
      |> list.drop(i)
      |> list.first
      |> fn(r) {
        case r {
          Ok(c) -> c
          Error(_) -> Dead
        }
      }
  }
}

/// Apply a Wolfram elementary rule to three neighbouring cells.
///
/// Encodes the three-cell neighbourhood as a 3-bit integer (left=2, centre=1, right=0).
/// Dying cells contribute 0 to the neighbourhood index (same as Dead) but are
/// tracked separately in state to represent transitional health.
fn apply_rule(
  rule: Int,
  left: CellState,
  centre: CellState,
  right: CellState,
) -> CellState {
  let l = case left {
    Alive -> 1
    _ -> 0
  }
  let c = case centre {
    Alive -> 1
    _ -> 0
  }
  let r = case right {
    Alive -> 1
    _ -> 0
  }
  let idx = l * 4 + c * 2 + r
  let bit = rule / power2(idx) % 2
  case bit {
    1 ->
      case centre {
        Dying -> Alive
        _ -> Alive
      }
    _ ->
      case centre {
        Alive -> Dying
        Dying -> Dead
        Dead -> Dead
      }
  }
}

/// Integer power of 2, capped at reasonable range.
fn power2(n: Int) -> Int {
  case n {
    0 -> 1
    1 -> 2
    2 -> 4
    3 -> 8
    4 -> 16
    5 -> 32
    6 -> 64
    7 -> 128
    _ -> 256
  }
}

/// Compute Shannon entropy over cell states.
fn entropy_of(cells: List(CellState)) -> Float {
  let n = list.length(cells)
  case n == 0 {
    True -> 0.0
    False -> {
      let alive = cells |> list.filter(fn(c) { c == Alive }) |> list.length
      let dead = cells |> list.filter(fn(c) { c == Dead }) |> list.length
      let dying = cells |> list.filter(fn(c) { c == Dying }) |> list.length
      let nf = int.to_float(n)
      entropy_term(int.to_float(alive), nf)
      +. entropy_term(int.to_float(dead), nf)
      +. entropy_term(int.to_float(dying), nf)
    }
  }
}

/// Single entropy term: -p log₂ p (returns 0.0 when count == 0).
fn entropy_term(count: Float, total: Float) -> Float {
  case count == 0.0 || total == 0.0 {
    True -> 0.0
    False -> {
      let p = count /. total
      let log2p = log2_approx(p)
      0.0 -. p *. log2p
    }
  }
}

/// log₂ approximation via natural log identity: log₂(x) = ln(x) / ln(2).
/// Uses Erlang's :math.log/1 FFI.
@external(erlang, "math", "log")
fn erlang_log(x: Float) -> Float

fn log2_approx(x: Float) -> Float {
  case x <=. 0.0 {
    True -> 0.0
    False -> erlang_log(x) /. erlang_log(2.0)
  }
}

/// Convert CellState to a short string for JSON.
fn cell_to_string(c: CellState) -> String {
  case c {
    Alive -> "alive"
    Dead -> "dead"
    Dying -> "dying"
  }
}

/// Render a float with 4 decimal places for JSON / summary output.
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
