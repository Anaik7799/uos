//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/math_analysis</module>
////     <fsharp-lineage>None — novel information-theoretic analysis (F24)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Advanced mathematical analysis for the guard grid verdict matrix.
////       Five complementary measures provide a multi-dimensional view of
////       failure-pattern complexity, causal coupling, and temporal structure:
////
////         1. Kolmogorov complexity estimate  — compressibility of the pattern
////         2. Mutual information I(X;Y)        — informational coupling between layers
////         3. Transfer entropy TE(X→Y)         — causal direction of failure propagation
////         4. Fractal dimension D_f            — self-similarity across grid scales
////         5. Hurst exponent H                 — long-range dependence in health time series
////
////       All functions are pure (zero I/O), total (always return a Float), and
////       numerically stable under degenerate inputs (empty lists, constant series).
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>
////       SC-MATH-COV-001, SC-HA-001, SC-MUDA-001, SC-FUNC-002,
////       SC-SIL4-001, SC-ALLIUM-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Shannon entropy ↪ Gleam pure functions over List(String).
////       All Float arithmetic is IEEE 754; log/sqrt delegated to Erlang math NIF.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       R/S analysis and box-counting require Float division.
////       Mitigation: degenerate cases guarded; results clamped to [0.0, 2.0].
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// ADVANCED MATHEMATICAL ANALYSIS — guard grid information theory
//// गणितं सत्यस्य भाषा — Mathematics is the language of truth
////
//// Five analysis pillars:
////
////   Kolmogorov (K): unique_patterns / total_patterns
////     K → 0  simple / compressible  (e.g. all PASSED)
////     K → 1  random / incompressible (maximum complexity)
////
////   Mutual Information I(X;Y) = H(X) + H(Y) - H(X,Y)
////     I → 0  independent layers
////     I > 0  informationally coupled (failures correlate)
////
////   Transfer Entropy TE(X→Y) = H(Yt|Yt-1) - H(Yt|Yt-1,Xt-1)
////     TE → 0  no causal influence from X on Y
////     TE > 0  X's past predicts Y's future (causal direction)
////
////   Fractal Dimension D_f — box-counting on binary 8-layer grid
////     D_f ≈ 1.0  linear (simple failure pattern)
////     D_f ≈ 1.5  fractal (self-similar failures)
////     D_f ≈ 2.0  space-filling (all layers equally affected)
////
////   Hurst Exponent H — R/S analysis on health time series
////     H > 0.5  persistent (trending failures)
////     H = 0.5  random walk (memoryless)
////     H < 0.5  anti-persistent (mean-reverting)
////
//// STAMP: SC-MATH-COV-001, SC-HA-001, SC-MUDA-001, SC-FUNC-002

import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/string

// ---------------------------------------------------------------------------
// External FFI — Erlang math NIFs
// ---------------------------------------------------------------------------

@external(erlang, "math", "log")
fn erlang_log(x: Float) -> Float

@external(erlang, "math", "sqrt")
fn erlang_sqrt(x: Float) -> Float

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Full mathematical analysis result for a guard grid history snapshot.
pub type MathAnalysis {
  MathAnalysis(
    /// Kolmogorov complexity estimate ∈ [0.0, 1.0]
    kolmogorov: Float,
    /// Fractal dimension estimate ∈ [1.0, 2.0]
    fractal_dim: Float,
    /// Hurst exponent estimate ∈ [0.0, 1.0]
    hurst: Float,
    /// Pairwise mutual information: (layerA, layerB, I(A;B))
    layer_correlations: List(#(String, String, Float)),
    /// Directed causal pairs: (source, target, TE(source→target))
    causal_pairs: List(#(String, String, Float)),
  )
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Natural log of 2 — used for converting nats to bits
const ln2: Float = 0.6931471805599453

/// Minimum list length required for meaningful R/S analysis
const min_rs_length: Int = 4

/// Layer labels used when building correlation/causal pair labels
const layer_labels: List(String) = [
  "L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7",
]

// ---------------------------------------------------------------------------
// 1. Kolmogorov complexity estimate
// ---------------------------------------------------------------------------

/// Kolmogorov complexity estimate — how compressible is the failure pattern?
///
/// Approximation: ratio of unique verdict patterns to total observations.
/// K → 0.0  perfectly compressible (e.g. all "PASSED")
/// K → 1.0  maximally complex / random
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pattern frequency map ↪ Float ratio</morphism>
///   <formal-proof>
///     <P> verdicts: List(String), possibly empty </P>
///     <C> kolmogorov_estimate(verdicts) </C>
///     <Q> 0.0 when |verdicts| == 0; unique/total otherwise, clamped [0,1] </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn kolmogorov_estimate(verdicts: List(String)) -> Float {
  let total = list.length(verdicts)
  case total {
    0 -> 0.0
    _ -> {
      let unique = count_unique(verdicts)
      let k = int.to_float(unique) /. int.to_float(total)
      float.clamp(k, min: 0.0, max: 1.0)
    }
  }
}

// ---------------------------------------------------------------------------
// 2. Shannon entropy helpers (used by MI and TE)
// ---------------------------------------------------------------------------

/// Shannon entropy H(X) in bits for a list of categorical observations.
/// H(X) = -Σ p_i × log₂(p_i)
/// Returns 0.0 for empty input or a single unique value.
pub fn shannon_entropy(observations: List(String)) -> Float {
  let total = list.length(observations)
  case total {
    0 -> 0.0
    _ -> {
      let counts = count_map(observations)
      let n_f = int.to_float(total)
      list.fold(counts, 0.0, fn(acc, pair) {
        let #(_, count) = pair
        case count {
          0 -> acc
          _ -> {
            let p = int.to_float(count) /. n_f
            acc -. { p *. safe_log2(p) }
          }
        }
      })
    }
  }
}

/// Joint Shannon entropy H(X,Y) treating each (x, y) pair as one symbol.
fn joint_entropy(xs: List(String), ys: List(String)) -> Float {
  let pairs = list.zip(xs, ys) |> list.map(fn(p) { p.0 <> "|" <> p.1 })
  shannon_entropy(pairs)
}

// ---------------------------------------------------------------------------
// 3. Mutual information I(X;Y)
// ---------------------------------------------------------------------------

/// Mutual information I(X;Y) = H(X) + H(Y) - H(X,Y)
///
/// Measures informational coupling between two layers' verdict histories.
///   I → 0.0  independent layers (failures do not correlate)
///   I > 0.0  coupled layers (failures tend to co-occur)
///
/// Lists of unequal length are truncated to the shorter.
/// Returns 0.0 for empty input.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">
///     Shannon formula I = H(X) + H(Y) - H(X,Y) ↪ Gleam Float
///   </morphism>
///   <formal-proof>
///     <P> layer_a_verdicts, layer_b_verdicts: List(String) </P>
///     <C> mutual_information(a, b) </C>
///     <Q> I(X;Y) >= 0 (clamped); 0.0 when either list is empty </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn mutual_information(
  layer_a_verdicts: List(String),
  layer_b_verdicts: List(String),
) -> Float {
  let len_a = list.length(layer_a_verdicts)
  let len_b = list.length(layer_b_verdicts)
  let min_len = int.min(len_a, len_b)
  case min_len {
    0 -> 0.0
    _ -> {
      let a = list.take(layer_a_verdicts, min_len)
      let b = list.take(layer_b_verdicts, min_len)
      let hx = shannon_entropy(a)
      let hy = shannon_entropy(b)
      let hxy = joint_entropy(a, b)
      float.max(0.0, hx +. hy -. hxy)
    }
  }
}

// ---------------------------------------------------------------------------
// 4. Transfer entropy TE(X→Y)
// ---------------------------------------------------------------------------

/// Transfer entropy TE(X→Y) = H(Yt | Yt-1) - H(Yt | Yt-1, Xt-1)
///
/// Directional: TE(A→B) ≠ TE(B→A) in general.
/// High TE(A→B) means A's past state predicts B's future transitions —
/// evidence of a causal influence from A to B.
///
/// Implementation (simplified, lag-1):
///   1. Build triples (Xt-1, Yt-1, Yt) from aligned histories
///   2. TE = H(Yt | Yt-1) - H(Yt | Yt-1, Xt-1)
///        = H(Yt, Yt-1) - H(Yt-1) - [ H(Xt-1, Yt-1, Yt) - H(Xt-1, Yt-1) ]
///
/// Returns 0.0 when histories are too short (< 2 elements after alignment).
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Lag-1 TE formula ↪ Gleam Float</morphism>
///   <formal-proof>
///     <P> source_history, target_history: List(String), len >= 2 </P>
///     <C> transfer_entropy(source, target) </C>
///     <Q> TE >= 0 (clamped); 0.0 when history too short </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn transfer_entropy(
  source_history: List(String),
  target_history: List(String),
) -> Float {
  let len_s = list.length(source_history)
  let len_t = list.length(target_history)
  let min_len = int.min(len_s, len_t)
  case min_len < 2 {
    True -> 0.0
    False -> {
      // Align to same length
      let s = list.take(source_history, min_len)
      let t = list.take(target_history, min_len)

      // Build lag-1 sequences (drop first element for "past", last for "future")
      let s_past = list.take(s, min_len - 1)
      let t_past = list.take(t, min_len - 1)
      let t_future = list.drop(t, 1)

      // H(Yt, Yt-1) — joint of target future and past
      let h_yt_yt1 = joint_entropy(t_future, t_past)
      // H(Yt-1)
      let h_yt1 = shannon_entropy(t_past)
      // H(Xt-1, Yt-1, Yt) — three-way joint
      let xyt_triples =
        list.zip(list.zip(s_past, t_past), t_future)
        |> list.map(fn(p) {
          let #(#(x, y_p), y_f) = p
          x <> "|" <> y_p <> "|" <> y_f
        })
      let h_xyt = shannon_entropy(xyt_triples)
      // H(Xt-1, Yt-1)
      let h_xt1_yt1 = joint_entropy(s_past, t_past)

      // TE = [H(Yt,Yt-1) - H(Yt-1)] - [H(Xt-1,Yt-1,Yt) - H(Xt-1,Yt-1)]
      let cond_y_given_y = h_yt_yt1 -. h_yt1
      let cond_y_given_xy = h_xyt -. h_xt1_yt1
      float.max(0.0, cond_y_given_y -. cond_y_given_xy)
    }
  }
}

// ---------------------------------------------------------------------------
// 5. Fractal dimension (box-counting)
// ---------------------------------------------------------------------------

/// Fractal dimension via box-counting on the 8-layer binary health grid.
///
/// The layer_states list represents one snapshot of the 8 fractal layers
/// as Bool (True = healthy, False = failing).  Box-counting is applied at
/// scales s = 1, 2, 4 to estimate the slope of log(N(s)) vs log(1/s).
///
/// D_f = -slope ≈ log(N(s1)/N(s2)) / log(s2/s1)
///
/// Clamped to [1.0, 2.0] since we are operating on a 1D grid embedded in 2D.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Box-counting ↪ Gleam Float</morphism>
///   <formal-proof>
///     <P> layer_states: List(Bool), len <= 8 </P>
///     <C> fractal_dimension(layer_states) </C>
///     <Q> D_f ∈ [1.0, 2.0]; 1.0 on empty or constant input </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn fractal_dimension(layer_states: List(Bool)) -> Float {
  let n = list.length(layer_states)
  case n < 2 {
    True -> 1.0
    False -> {
      // Count occupied boxes at scale 1 (each layer is its own box)
      let n_scale1 = list.count(layer_states, fn(b) { b == False })
      // Count occupied boxes at scale 2 (pair of adjacent layers)
      let n_scale2 = count_occupied_boxes(layer_states, 2)

      case n_scale1 == 0 || n_scale2 == 0 {
        // All healthy or all failing — dimension is 1 (uniform)
        True -> 1.0
        False -> {
          // D = log(N1/N2) / log(2)  (scale ratio = 2)
          let log_ratio =
            erlang_log(int.to_float(n_scale1) /. int.to_float(n_scale2))
          let d = log_ratio /. ln2
          float.clamp(d, min: 1.0, max: 2.0)
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 6. Hurst exponent (R/S analysis)
// ---------------------------------------------------------------------------

/// Hurst exponent via Rescaled Range (R/S) analysis on a health time series.
///
/// H = log(R/S) / log(n)  where:
///   R = range of cumulative deviations from mean
///   S = standard deviation of the series
///
/// H > 0.5  persistent (trending failures)
/// H = 0.5  random walk (Brownian motion, memoryless)
/// H < 0.5  anti-persistent (mean-reverting)
///
/// Returns 0.5 (random walk) when the series is too short or has zero variance.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">R/S algorithm ↪ Gleam Float</morphism>
///   <formal-proof>
///     <P> health_history: List(Float), values ∈ [0.0, 1.0] </P>
///     <C> hurst_exponent(health_history) </C>
///     <Q> H ∈ [0.0, 1.0]; 0.5 on degenerate input </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn hurst_exponent(health_history: List(Float)) -> Float {
  let n = list.length(health_history)
  case n < min_rs_length {
    True -> 0.5
    False -> {
      let mean = float_mean(health_history)
      // Cumulative deviations from mean
      let deviations = list.map(health_history, fn(x) { x -. mean })
      let cumulative = running_sum(deviations)
      // Range R = max(cumulative) - min(cumulative)
      let r_val = float_range(cumulative)
      // Standard deviation S
      let s_val = float_std_dev(health_history, mean)
      case s_val <. 1.0e-10 || r_val <. 1.0e-10 {
        // Constant series or zero range → random walk assumption
        True -> 0.5
        False -> {
          let rs = r_val /. s_val
          let h = erlang_log(rs) /. erlang_log(int.to_float(n))
          float.clamp(h, min: 0.0, max: 1.0)
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 7. Full analysis
// ---------------------------------------------------------------------------

/// Run ALL mathematical analyses on a guard grid history and return
/// a comprehensive MathAnalysis record.
///
/// grid_history: each inner list is one time-step snapshot of 8-layer verdicts.
///   grid_history[t] = ["PASSED","PASSED","FAILED",...] (8 elements, one per layer)
///
/// Returns MathAnalysis with:
///   - kolmogorov: estimate over the flattened verdict stream
///   - fractal_dim: computed from the most-recent snapshot
///   - hurst: computed from per-step health scores
///   - layer_correlations: all L0-L7 pairs, sorted by MI descending
///   - causal_pairs: all ordered L0-L7 pairs, sorted by TE descending
pub fn full_analysis(grid_history: List(List(String))) -> MathAnalysis {
  let flat_verdicts = list.flatten(grid_history)
  let k = kolmogorov_estimate(flat_verdicts)

  // Latest snapshot for fractal dimension
  let last_snap = case list.last(grid_history) {
    Ok(snap) -> snap
    Error(_) -> []
  }
  let bool_states = list.map(last_snap, fn(v) { v == "PASSED" })
  let fd = fractal_dimension(bool_states)

  // Health time series: fraction of "PASSED" per time step
  let health_series =
    list.map(grid_history, fn(snap) {
      let total = list.length(snap)
      case total {
        0 -> 1.0
        _ -> {
          let passed = list.count(snap, fn(v) { v == "PASSED" })
          int.to_float(passed) /. int.to_float(total)
        }
      }
    })
  let h = hurst_exponent(health_series)

  // Per-layer verdict histories (transpose grid_history)
  let layer_histories = extract_layer_histories(grid_history, 8)

  // Pairwise mutual information for all layer pairs
  let mi_pairs = compute_layer_mi(layer_histories)
  let causal = compute_causal_pairs(layer_histories)

  MathAnalysis(
    kolmogorov: k,
    fractal_dim: fd,
    hurst: h,
    layer_correlations: mi_pairs,
    causal_pairs: causal,
  )
}

// ---------------------------------------------------------------------------
// 8. Serialisation
// ---------------------------------------------------------------------------

/// Serialise a MathAnalysis to a compact JSON string.
pub fn to_json(analysis: MathAnalysis) -> String {
  let corr_json = json_float_tuple_array(analysis.layer_correlations)
  let causal_json = json_float_tuple_array(analysis.causal_pairs)
  "{"
  <> "\"kolmogorov\":"
  <> float.to_string(analysis.kolmogorov)
  <> ","
  <> "\"fractal_dim\":"
  <> float.to_string(analysis.fractal_dim)
  <> ","
  <> "\"hurst\":"
  <> float.to_string(analysis.hurst)
  <> ","
  <> "\"layer_correlations\":"
  <> corr_json
  <> ","
  <> "\"causal_pairs\":"
  <> causal_json
  <> "}"
}

/// Human-readable one-line summary of a MathAnalysis for TUI / logs.
pub fn summary(analysis: MathAnalysis) -> String {
  let k_str = float_to_2dp(analysis.kolmogorov)
  let fd_str = float_to_2dp(analysis.fractal_dim)
  let h_str = float_to_2dp(analysis.hurst)

  let h_label = case analysis.hurst >. 0.6 {
    True -> "persistent"
    False ->
      case analysis.hurst <. 0.4 {
        True -> "anti-persistent"
        False -> "random-walk"
      }
  }

  let k_label = case analysis.kolmogorov <. 0.25 {
    True -> "simple"
    False ->
      case analysis.kolmogorov >. 0.75 {
        True -> "complex"
        False -> "moderate"
      }
  }

  let top_corr = case analysis.layer_correlations {
    [#(a, b, mi), ..] ->
      " top-MI=" <> a <> "↔" <> b <> "(" <> float_to_2dp(mi) <> "bits)"
    [] -> ""
  }

  let top_causal = case analysis.causal_pairs {
    [#(src, tgt, te), ..] ->
      " top-TE=" <> src <> "→" <> tgt <> "(" <> float_to_2dp(te) <> "bits)"
    [] -> ""
  }

  "MathAnalysis["
  <> "K="
  <> k_str
  <> "("
  <> k_label
  <> ")"
  <> " Df="
  <> fd_str
  <> " H="
  <> h_str
  <> "("
  <> h_label
  <> ")"
  <> top_corr
  <> top_causal
  <> "]"
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Count unique elements in a list (O(n²) — acceptable for small verdict lists).
fn count_unique(items: List(String)) -> Int {
  list.fold(items, [], fn(acc, item) {
    case list.contains(acc, item) {
      True -> acc
      False -> [item, ..acc]
    }
  })
  |> list.length()
}

/// Build a frequency map as a list of (value, count) pairs.
fn count_map(items: List(String)) -> List(#(String, Int)) {
  list.fold(items, [], fn(acc, item) { inc_count(acc, item) })
}

fn inc_count(counts: List(#(String, Int)), key: String) -> List(#(String, Int)) {
  case list.find(counts, fn(p) { p.0 == key }) {
    Ok(_) ->
      list.map(counts, fn(p) {
        case p.0 == key {
          True -> #(p.0, p.1 + 1)
          False -> p
        }
      })
    Error(_) -> [#(key, 1), ..counts]
  }
}

/// log₂(x) = ln(x) / ln(2); returns 0.0 for x <= 0.
fn safe_log2(x: Float) -> Float {
  case x <=. 0.0 {
    True -> 0.0
    False -> erlang_log(x) /. ln2
  }
}

/// Count occupied boxes at a given scale (box width in number of elements).
/// A box is "occupied" if any element in it is False (failing).
fn count_occupied_boxes(states: List(Bool), box_size: Int) -> Int {
  count_boxes_in(states, box_size, 0)
}

fn count_boxes_in(states: List(Bool), box_size: Int, acc: Int) -> Int {
  case states {
    [] -> acc
    _ -> {
      let box = list.take(states, box_size)
      let rest = list.drop(states, box_size)
      let occupied = list.any(box, fn(b) { b == False })
      let new_acc = case occupied {
        True -> acc + 1
        False -> acc
      }
      count_boxes_in(rest, box_size, new_acc)
    }
  }
}

/// Arithmetic mean of a list of Floats; returns 0.0 for empty input.
fn float_mean(values: List(Float)) -> Float {
  let n = list.length(values)
  case n {
    0 -> 0.0
    _ -> list.fold(values, 0.0, fn(a, x) { a +. x }) /. int.to_float(n)
  }
}

/// Running cumulative sum of a list of Floats.
fn running_sum(values: List(Float)) -> List(Float) {
  do_running_sum(values, 0.0, [])
  |> list.reverse()
}

fn do_running_sum(
  values: List(Float),
  acc: Float,
  result: List(Float),
) -> List(Float) {
  case values {
    [] -> result
    [x, ..rest] -> do_running_sum(rest, acc +. x, [acc +. x, ..result])
  }
}

/// Range of a Float list: max - min.  Returns 0.0 for empty or singleton.
fn float_range(values: List(Float)) -> Float {
  case values {
    [] -> 0.0
    [_] -> 0.0
    _ -> {
      let max_v =
        list.fold(values, values |> list.first() |> unwrap_float(), float.max)
      let min_v =
        list.fold(values, values |> list.first() |> unwrap_float(), float.min)
      float.max(0.0, max_v -. min_v)
    }
  }
}

fn unwrap_float(r: Result(Float, Nil)) -> Float {
  case r {
    Ok(v) -> v
    Error(_) -> 0.0
  }
}

/// Population standard deviation of a Float list.
fn float_std_dev(values: List(Float), mean: Float) -> Float {
  let n = list.length(values)
  case n < 2 {
    True -> 0.0
    False -> {
      let variance =
        list.fold(values, 0.0, fn(acc, x) {
          let d = x -. mean
          acc +. d *. d
        })
        /. int.to_float(n)
      erlang_sqrt(float.max(0.0, variance))
    }
  }
}

/// Extract per-layer verdict history from a grid history.
/// Returns a list of `n_layers` lists, each being the time series for one layer.
fn extract_layer_histories(
  grid_history: List(List(String)),
  n_layers: Int,
) -> List(List(String)) {
  let indices = int_range(0, n_layers - 1)
  list.map(indices, fn(layer_idx) {
    list.filter_map(grid_history, fn(snap) {
      case list.drop(snap, layer_idx) {
        [v, ..] -> Ok(v)
        [] -> Error(Nil)
      }
    })
  })
}

/// Build a list of integers from `from` to `to` inclusive.
fn int_range(from: Int, to: Int) -> List(Int) {
  do_int_range(from, to, [])
  |> list.reverse()
}

fn do_int_range(from: Int, to: Int, acc: List(Int)) -> List(Int) {
  case from > to {
    True -> acc
    False -> do_int_range(from + 1, to, [from, ..acc])
  }
}

/// Compute pairwise MI for all layer combinations, sorted descending by MI.
fn compute_layer_mi(
  layer_histories: List(List(String)),
) -> List(#(String, String, Float)) {
  let indexed = list.zip(layer_labels, layer_histories)
  let pairs =
    list.flat_map(indexed, fn(a) {
      list.filter_map(indexed, fn(b) {
        let #(la, ha) = a
        let #(lb, hb) = b
        case la == lb {
          True -> Error(Nil)
          False -> {
            // Only emit (A,B) where A < B to avoid duplicates
            case string.compare(la, lb) {
              order.Lt -> {
                let mi = mutual_information(ha, hb)
                Ok(#(la, lb, mi))
              }
              _ -> Error(Nil)
            }
          }
        }
      })
    })
  list.sort(pairs, fn(p1, p2) {
    let #(_, _, mi1) = p1
    let #(_, _, mi2) = p2
    float.compare(mi2, mi1)
  })
}

/// Compute directed TE pairs for all ordered layer combinations,
/// sorted descending by TE.
fn compute_causal_pairs(
  layer_histories: List(List(String)),
) -> List(#(String, String, Float)) {
  let indexed = list.zip(layer_labels, layer_histories)
  let pairs =
    list.flat_map(indexed, fn(src) {
      list.filter_map(indexed, fn(tgt) {
        let #(ls, hs) = src
        let #(lt, ht) = tgt
        case ls == lt {
          True -> Error(Nil)
          False -> {
            let te = transfer_entropy(hs, ht)
            Ok(#(ls, lt, te))
          }
        }
      })
    })
  list.sort(pairs, fn(p1, p2) {
    let #(_, _, te1) = p1
    let #(_, _, te2) = p2
    float.compare(te2, te1)
  })
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

fn json_float_tuple_array(pairs: List(#(String, String, Float))) -> String {
  let inner =
    list.map(pairs, fn(p) {
      let #(a, b, v) = p
      "[\"" <> a <> "\",\"" <> b <> "\"," <> float.to_string(v) <> "]"
    })
    |> string.join(",")
  "[" <> inner <> "]"
}

/// Format a Float to 2 decimal places (truncation-based, no rounding library).
fn float_to_2dp(v: Float) -> String {
  let scaled = v *. 100.0
  let truncated = float.truncate(scaled)
  let int_part = truncated / 100
  let frac_part = int.absolute_value(truncated - int_part * 100)
  int.to_string(int_part) <> "." <> pad2(frac_part)
}

fn pad2(n: Int) -> String {
  case n < 10 {
    True -> "0" <> int.to_string(n)
    False -> int.to_string(n)
  }
}
