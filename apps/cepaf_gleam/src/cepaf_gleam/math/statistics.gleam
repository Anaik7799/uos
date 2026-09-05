//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/math/statistics</module>
////     <fsharp-lineage>Cepaf.Math.Statistics (novel Gleam)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-MATH-001, SC-BIO-EVO-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// गणितीय आधार — Mathematical Foundation
//// Pure functional statistical and information-theoretic functions.
//// Shannon entropy, Lyapunov exponents, EMA, FMEA/RPN, PID controller.
////
//// STAMP: SC-MATH-001, SC-BIO-EVO-001..007

import gleam/float
import gleam/int
import gleam/list
import gleam/result

// =============================================================================
// FFI: Erlang math module
// =============================================================================

@external(erlang, "math", "log")
fn math_log(x: Float) -> Float

@external(erlang, "math", "sqrt")
fn math_sqrt(x: Float) -> Float

fn log2(x: Float) -> Float {
  float.divide(math_log(x), math_log(2.0)) |> result.unwrap(0.0)
}

fn to_float(n: Int) -> Float {
  let assert Ok(f) = float.parse(int.to_string(n) <> ".0")
  f
}

// =============================================================================
// Shannon Entropy (शैनन एन्ट्रापी)
// =============================================================================

/// Shannon entropy H = -sum(p_i * log2(p_i)) for a probability distribution.
/// Input: list of non-negative counts (frequencies).
/// Output: entropy in bits. Range [0, log2(N)] where N = number of categories.
pub fn shannon_entropy(counts: List(Int)) -> Float {
  let total = to_float(list.fold(counts, 0, fn(a, c) { a + c }))
  case total >. 0.0 {
    False -> 0.0
    True -> {
      list.fold(counts, 0.0, fn(acc, c) {
        let p = to_float(c) /. total
        case p >. 0.0 {
          True -> acc -. p *. log2(p)
          False -> acc
        }
      })
    }
  }
}

/// Maximum possible entropy for N categories = log2(N).
pub fn max_entropy(n: Int) -> Float {
  case n > 1 {
    True -> log2(to_float(n))
    False -> 0.0
  }
}

/// Normalized entropy H_norm = H / H_max. Range [0, 1].
pub fn normalized_entropy(counts: List(Int)) -> Float {
  let h = shannon_entropy(counts)
  let h_max = max_entropy(list.length(counts))
  case h_max >. 0.0 {
    True -> h /. h_max
    False -> 0.0
  }
}

// =============================================================================
// Basic Statistics (मूलभूत सांख्यिकी)
// =============================================================================

/// Arithmetic mean of a float list.
pub fn mean(values: List(Float)) -> Float {
  let n = list.length(values)
  case n {
    0 -> 0.0
    _ -> list.fold(values, 0.0, fn(a, v) { a +. v }) /. to_float(n)
  }
}

/// Variance (population variance, sigma^2).
pub fn variance(values: List(Float)) -> Float {
  let n = list.length(values)
  case n {
    0 -> 0.0
    _ -> {
      let m = mean(values)
      let sum_sq =
        list.fold(values, 0.0, fn(a, v) {
          let d = v -. m
          a +. d *. d
        })
      sum_sq /. to_float(n)
    }
  }
}

/// Standard deviation (population).
pub fn std_dev(values: List(Float)) -> Float {
  math_sqrt(variance(values))
}

/// Exponential Moving Average update.
/// new_ema = alpha * value + (1 - alpha) * prev_ema
pub fn ema_update(prev: Float, value: Float, alpha: Float) -> Float {
  alpha *. value +. { 1.0 -. alpha } *. prev
}

/// Compute full EMA series from a list of values.
pub fn ema_series(values: List(Float), alpha: Float) -> List(Float) {
  case values {
    [] -> []
    [first, ..rest] ->
      list.fold(rest, [first], fn(acc, v) {
        let prev = case acc {
          [h, ..] -> h
          [] -> 0.0
        }
        [ema_update(prev, v, alpha), ..acc]
      })
      |> list.reverse()
  }
}

// =============================================================================
// FMEA / RPN Scoring (विफलता मोड विश्लेषण)
// =============================================================================

/// FMEA failure mode with RPN scoring.
pub type FailureMode {
  FailureMode(
    name: String,
    severity: Int,
    occurrence: Int,
    detection: Int,
    rpn: Int,
    mitigation: String,
  )
}

/// Compute Risk Priority Number = Severity × Occurrence × Detection.
/// Each factor in [1, 10]. RPN in [1, 1000].
pub fn rpn(severity: Int, occurrence: Int, detection: Int) -> Int {
  let s = int.clamp(severity, min: 1, max: 10)
  let o = int.clamp(occurrence, min: 1, max: 10)
  let d = int.clamp(detection, min: 1, max: 10)
  s * o * d
}

/// Create a failure mode with computed RPN.
pub fn failure_mode(
  name: String,
  severity: Int,
  occurrence: Int,
  detection: Int,
  mitigation: String,
) -> FailureMode {
  FailureMode(
    name: name,
    severity: severity,
    occurrence: occurrence,
    detection: detection,
    rpn: rpn(severity, occurrence, detection),
    mitigation: mitigation,
  )
}

/// Sort failure modes by RPN descending (highest risk first).
pub fn sort_by_rpn(modes: List(FailureMode)) -> List(FailureMode) {
  list.sort(modes, fn(a, b) { int.compare(b.rpn, a.rpn) })
}

/// Filter failure modes requiring immediate action (RPN >= threshold).
pub fn critical_modes(
  modes: List(FailureMode),
  threshold: Int,
) -> List(FailureMode) {
  list.filter(modes, fn(m) { m.rpn >= threshold })
}

// =============================================================================
// PID Controller (PID नियंत्रक)
// =============================================================================

/// PID controller state.
pub type PidState {
  PidState(
    kp: Float,
    ki: Float,
    kd: Float,
    setpoint: Float,
    integral: Float,
    prev_error: Float,
    output: Float,
  )
}

/// Create a new PID controller.
pub fn pid_new(kp: Float, ki: Float, kd: Float, setpoint: Float) -> PidState {
  PidState(
    kp: kp,
    ki: ki,
    kd: kd,
    setpoint: setpoint,
    integral: 0.0,
    prev_error: 0.0,
    output: 0.0,
  )
}

/// PID update: compute control output for a measured value.
pub fn pid_update(state: PidState, measured: Float, dt: Float) -> PidState {
  let error = state.setpoint -. measured
  let integral = state.integral +. error *. dt
  let derivative = case dt >. 0.0 {
    True -> { error -. state.prev_error } /. dt
    False -> 0.0
  }
  let output =
    state.kp *. error +. state.ki *. integral +. state.kd *. derivative
  PidState(..state, integral: integral, prev_error: error, output: output)
}

// =============================================================================
// Lyapunov Exponent (ल्यापुनोव घातांक)
// =============================================================================

/// Estimate maximal Lyapunov exponent from a time series.
/// Positive λ → system diverging (chaotic). Negative λ → stable (converging).
/// Uses simple method: λ ≈ (1/N) * sum(ln|x_{i+1} - x_i| / |x_i|)
pub fn lyapunov_estimate(series: List(Float)) -> Float {
  case series {
    [] | [_] -> 0.0
    _ -> {
      let pairs = list.window_by_2(series)
      let n = list.length(pairs)
      case n {
        0 -> 0.0
        _ -> {
          let sum =
            list.fold(pairs, 0.0, fn(acc, pair) {
              let #(x_i, x_next) = pair
              let diff = float.absolute_value(x_next -. x_i)
              let base = float.absolute_value(x_i)
              case base >. 1.0e-15 && diff >. 1.0e-15 {
                True -> acc +. math_log(diff /. base)
                False -> acc
              }
            })
          sum /. to_float(n)
        }
      }
    }
  }
}

/// Classify Lyapunov exponent.
pub type StabilityClass {
  Stable
  Marginal
  Chaotic
}

pub fn classify_stability(lambda: Float) -> StabilityClass {
  case lambda <. -0.01 {
    True -> Stable
    False ->
      case lambda >. 0.01 {
        True -> Chaotic
        False -> Marginal
      }
  }
}

// =============================================================================
// Wolfram Cellular Automaton (वोल्फ्राम कोशिकीय स्वचालन)
// =============================================================================

/// Elementary cellular automaton state (1D, radius-1, 256 rules).
pub type CellularAutomaton {
  CellularAutomaton(
    rule_number: Int,
    cells: List(Int),
    generation: Int,
    width: Int,
  )
}

/// Create a new 1D cellular automaton with a single center cell active.
pub fn ca_new(rule_number: Int, width: Int) -> CellularAutomaton {
  let cells = list.repeat(0, width)
  let mid = width / 2
  let cells_with_seed =
    list.index_map(cells, fn(_, i) {
      case i == mid {
        True -> 1
        False -> 0
      }
    })
  CellularAutomaton(
    rule_number: int.clamp(rule_number, min: 0, max: 255),
    cells: cells_with_seed,
    generation: 0,
    width: width,
  )
}

/// Step the cellular automaton one generation using the Wolfram rule.
pub fn ca_step(ca: CellularAutomaton) -> CellularAutomaton {
  let new_cells =
    list.index_map(ca.cells, fn(_, i) {
      let left = cell_at(ca.cells, i - 1, ca.width)
      let center = cell_at(ca.cells, i, ca.width)
      let right = cell_at(ca.cells, i + 1, ca.width)
      let neighborhood = left * 4 + center * 2 + right
      // Extract bit from rule number
      case
        int.bitwise_and(
          int.bitwise_shift_right(ca.rule_number, neighborhood),
          1,
        )
      {
        1 -> 1
        _ -> 0
      }
    })
  CellularAutomaton(..ca, cells: new_cells, generation: ca.generation + 1)
}

/// Run N generations.
pub fn ca_run(ca: CellularAutomaton, steps: Int) -> CellularAutomaton {
  case steps <= 0 {
    True -> ca
    False -> ca_run(ca_step(ca), steps - 1)
  }
}

/// Count active cells in current generation.
pub fn ca_active_count(ca: CellularAutomaton) -> Int {
  list.fold(ca.cells, 0, fn(a, c) { a + c })
}

/// Compute density (fraction of active cells).
pub fn ca_density(ca: CellularAutomaton) -> Float {
  case ca.width {
    0 -> 0.0
    _ -> to_float(ca_active_count(ca)) /. to_float(ca.width)
  }
}

/// Classify Wolfram rule by behavior class.
pub type WolframClass {
  /// Class I: evolution to uniform state
  ClassI
  /// Class II: evolution to periodic/stable patterns
  ClassII
  /// Class III: chaotic aperiodic behavior
  ClassIII
  /// Class IV: complex localized structures (edge of chaos)
  ClassIV
}

/// Known classifications for key rules used in C3I.
pub fn classify_rule(rule_number: Int) -> WolframClass {
  case rule_number {
    0 | 8 | 32 | 40 | 128 | 136 | 160 | 168 -> ClassI
    1 | 2 | 3 | 4 | 5 | 6 | 7 | 9 | 10 | 184 -> ClassII
    18 | 22 | 30 | 45 | 60 | 90 | 105 | 150 -> ClassIII
    54 | 106 | 110 | 124 | 137 | 193 -> ClassIV
    _ -> ClassII
  }
}

pub fn wolfram_class_to_string(c: WolframClass) -> String {
  case c {
    ClassI -> "I (Uniform)"
    ClassII -> "II (Periodic)"
    ClassIII -> "III (Chaotic)"
    ClassIV -> "IV (Complex)"
  }
}

// =============================================================================
// Causal Graph (कारण ग्राफ)
// =============================================================================

/// Causal edge with weight.
pub type CausalEdge {
  CausalEdge(from: String, to: String, weight: Float)
}

/// Causal graph.
pub type CausalGraph {
  CausalGraph(nodes: List(String), edges: List(CausalEdge))
}

/// Create an empty causal graph.
pub fn causal_new() -> CausalGraph {
  CausalGraph(nodes: [], edges: [])
}

/// Add a causal edge.
pub fn causal_add_edge(
  g: CausalGraph,
  from: String,
  to: String,
  weight: Float,
) -> CausalGraph {
  let edge = CausalEdge(from: from, to: to, weight: weight)
  let nodes =
    [from, to, ..g.nodes]
    |> list.unique()
  CausalGraph(nodes: nodes, edges: [edge, ..g.edges])
}

/// Causal cone: all nodes reachable from a source (BFS).
pub fn causal_cone(g: CausalGraph, source: String) -> List(String) {
  causal_bfs(g, [source], [source])
}

fn causal_bfs(
  g: CausalGraph,
  frontier: List(String),
  visited: List(String),
) -> List(String) {
  case frontier {
    [] -> visited
    _ -> {
      let next =
        list.flat_map(frontier, fn(node) {
          list.filter_map(g.edges, fn(e) {
            case e.from == node && !list.contains(visited, e.to) {
              True -> Ok(e.to)
              False -> Error(Nil)
            }
          })
        })
        |> list.unique()
      causal_bfs(g, next, list.append(visited, next))
    }
  }
}

// =============================================================================
// Multiway System (बहुमार्ग प्रणाली)
// =============================================================================

/// A state in a multiway system with multiple possible successors.
pub type MultiwayState {
  MultiwayState(id: String, value: String, successors: List(String))
}

/// Multiway graph: all reachable states from all possible rule applications.
pub type MultiwayGraph {
  MultiwayGraph(states: List(MultiwayState), total_branches: Int)
}

/// Create an empty multiway graph.
pub fn multiway_new() -> MultiwayGraph {
  MultiwayGraph(states: [], total_branches: 0)
}

/// Add a state with its successors.
pub fn multiway_add(
  g: MultiwayGraph,
  id: String,
  value: String,
  successors: List(String),
) -> MultiwayGraph {
  let state = MultiwayState(id: id, value: value, successors: successors)
  MultiwayGraph(
    states: [state, ..g.states],
    total_branches: g.total_branches + list.length(successors),
  )
}

/// Branching factor: average number of successors per state.
pub fn multiway_branching_factor(g: MultiwayGraph) -> Float {
  let n = list.length(g.states)
  case n {
    0 -> 0.0
    _ -> to_float(g.total_branches) /. to_float(n)
  }
}

// =============================================================================
// Helpers
// =============================================================================

fn cell_at(cells: List(Int), index: Int, width: Int) -> Int {
  let wrapped = case index < 0 {
    True -> index + width
    False ->
      case index >= width {
        True -> index - width
        False -> index
      }
  }
  list_get(cells, wrapped, 0)
}

fn list_get(lst: List(Int), index: Int, default: Int) -> Int {
  case index, lst {
    _, [] -> default
    0, [head, ..] -> head
    n, [_, ..tail] -> list_get(tail, n - 1, default)
  }
}

// =============================================================================
// Autonomous System Functions — Sensor Fusion, Swarm, Network, Chaos
// =============================================================================

/// Weighted sensor fusion: combine N readings with confidence weights.
/// Each tuple is (reading, weight). Returns weighted average.
pub fn sensor_fusion(readings: List(#(Float, Float))) -> Float {
  let #(sum_weighted, sum_weights) =
    list.fold(readings, #(0.0, 0.0), fn(acc, pair) {
      #(acc.0 +. { pair.0 *. pair.1 }, acc.1 +. pair.1)
    })
  case sum_weights >. 0.0 {
    True -> sum_weighted /. sum_weights
    False -> 0.0
  }
}

/// Sensor health: fraction of sensors reporting valid data.
pub fn sensor_health(statuses: List(Bool)) -> Float {
  let total = list.length(statuses)
  case total {
    0 -> 0.0
    _ -> {
      let alive = list.length(list.filter(statuses, fn(s) { s }))
      int.to_float(alive) /. int.to_float(total)
    }
  }
}

/// Swarm consensus: majority vote and agreement ratio.
/// Returns (winning_vote, ratio) where ratio = count(winner)/total.
pub fn swarm_consensus(votes: List(String)) -> #(String, Float) {
  let total = list.length(votes)
  case total {
    0 -> #("none", 0.0)
    _ -> {
      let counted = count_votes(votes, [])
      let sorted = list.sort(counted, fn(a, b) { int.compare(b.1, a.1) })
      case sorted {
        [#(winner, count), ..] -> #(
          winner,
          int.to_float(count) /. int.to_float(total),
        )
        [] -> #("none", 0.0)
      }
    }
  }
}

fn count_votes(
  votes: List(String),
  acc: List(#(String, Int)),
) -> List(#(String, Int)) {
  case votes {
    [] -> acc
    [v, ..rest] -> {
      let new_acc = increment_vote(acc, v, [])
      count_votes(rest, new_acc)
    }
  }
}

fn increment_vote(
  counts: List(#(String, Int)),
  vote: String,
  checked: List(#(String, Int)),
) -> List(#(String, Int)) {
  case counts {
    [] -> list.reverse([#(vote, 1), ..checked])
    [#(k, n), ..rest] ->
      case k == vote {
        True -> list.append(list.reverse([#(k, n + 1), ..checked]), rest)
        False -> increment_vote(rest, vote, [#(k, n), ..checked])
      }
  }
}

/// Load imbalance: coefficient of variation across agent loads.
/// Returns std_dev / mean. Higher = more imbalanced.
pub fn load_imbalance(loads: List(Float)) -> Float {
  let m = mean(loads)
  case m >. 0.0 {
    True -> std_dev(loads) /. m
    False -> 0.0
  }
}

/// Mesh connectivity: ratio of actual edges to maximum possible.
/// For undirected graph: max = n*(n-1)/2.
pub fn mesh_connectivity(nodes: Int, edges: Int) -> Float {
  case nodes < 2 {
    True -> 0.0
    False -> {
      let max_edges = nodes * { nodes - 1 } / 2
      case max_edges {
        0 -> 0.0
        _ -> int.to_float(edges) /. int.to_float(max_edges)
      }
    }
  }
}

/// Partition probability estimate based on independent failure rate.
/// P(partition) = 1 - (1 - failure_rate)^node_count.
pub fn partition_probability(failure_rate: Float, node_count: Int) -> Float {
  case node_count {
    0 -> 0.0
    _ -> 1.0 -. pow(1.0 -. failure_rate, node_count)
  }
}

fn pow(base: Float, exp: Int) -> Float {
  case exp {
    0 -> 1.0
    1 -> base
    n -> base *. pow(base, n - 1)
  }
}

/// Blast radius: fraction of system affected by failure injection.
pub fn blast_radius(affected: Int, total: Int) -> Float {
  case total {
    0 -> 0.0
    _ -> int.to_float(affected) /. int.to_float(total)
  }
}

/// Mean time to recovery from chaos injection.
pub fn mttr(recovery_times: List(Float)) -> Float {
  mean(recovery_times)
}

/// System resilience score: 1 - (degradation * normalized_recovery_time).
/// Budget is the maximum acceptable recovery time.
pub fn resilience_score(
  degradation: Float,
  recovery_time: Float,
  budget: Float,
) -> Float {
  case budget >. 0.0 {
    True -> {
      let normalized = recovery_time /. budget
      let score = 1.0 -. { degradation *. normalized }
      case score <. 0.0 {
        True -> 0.0
        False -> score
      }
    }
    False -> 0.0
  }
}
