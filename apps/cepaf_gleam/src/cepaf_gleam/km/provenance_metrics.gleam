//// KM provenance metrics — Gleam control over the Mojo kernel (SC-PROVENANCE-001).
////
//// Gleam owns the control decision; the Mojo kernel owns the arithmetic. The
//// boundary is deliberate: policy thresholds and verdicts live here in typed
//// Gleam, numeric reduction lives behind the C ABI in `uos_km_nif`.
////
//// Every entry point is fail-closed. When the NIF is absent the result is
//// `Error(KernelUnavailable)` and no verdict is produced — an uncomputed
//// metric is never reported as a passing number.

import gleam/float
import gleam/list

/// Why a metric could not be produced.
pub type MetricError {
  /// The Mojo kernel is not loaded behind the NIF.
  KernelUnavailable
  /// The kernel rejected the arguments (out of range, ragged, empty).
  KernelRejected(reason: String)
  /// The caller supplied inconsistent inputs before the kernel was reached.
  InvalidInput(reason: String)
}

/// One surface that must carry the provenance marking.
/// `observed` and `nominal` are coverage ratios in [0.0, 1.0].
pub type Surface {
  Surface(label: String, observed: Float, nominal: Float)
}

/// The verdict for one observation of the corpus.
pub type Verdict {
  /// Every index is complete and every quarantine-derived record is marked.
  Pass(conformance: Float, entropy_bits: Float, drift: Float)
  /// At least one threshold is unmet; `reasons` names each one.
  Hold(
    conformance: Float,
    entropy_bits: Float,
    drift: Float,
    reasons: List(String),
  )
}

/// CHK-09-MATH Shannon entropy floor, in bits.
pub const entropy_floor: Float = 2.5

/// Minimum acceptable weighted conformance across checklist dimensions.
pub const conformance_floor: Float = 1.0

/// Maximum acceptable Euclidean drift from the fully-marked centroid.
pub const drift_ceiling: Float = 0.0

@external(erlang, "uos_km_nif", "loaded")
fn nif_loaded() -> Bool

@external(erlang, "cepaf_km_ffi", "conformance_score")
fn ffi_conformance(
  features: List(Float),
  weights: List(Float),
) -> Result(Float, String)

@external(erlang, "cepaf_km_ffi", "shannon_entropy_bits")
fn ffi_entropy(counts: List(Float)) -> Result(Float, String)

@external(erlang, "cepaf_km_ffi", "drift_distance")
fn ffi_drift(
  observed: List(Float),
  nominal: List(Float),
) -> Result(Float, String)

@external(erlang, "cepaf_km_ffi", "fmea_band")
fn ffi_fmea(
  severity: Int,
  occurrence: Int,
  detection: Int,
) -> Result(Int, String)

fn guard() -> Result(Nil, MetricError) {
  case nif_loaded() {
    True -> Ok(Nil)
    False -> Error(KernelUnavailable)
  }
}

fn lift(r: Result(a, String)) -> Result(a, MetricError) {
  case r {
    Ok(v) -> Ok(v)
    Error(reason) -> Error(KernelRejected(reason))
  }
}

/// Weighted conformance of an artifact's checklist indicator vector.
pub fn conformance(
  features: List(Float),
  weights: List(Float),
) -> Result(Float, MetricError) {
  case guard() {
    Error(e) -> Error(e)
    Ok(_) ->
      case list.length(features) == list.length(weights) {
        False -> Error(InvalidInput("features and weights differ in length"))
        True -> lift(ffi_conformance(features, weights))
      }
  }
}

/// Shannon entropy, in bits, of a non-negative count distribution.
pub fn entropy_bits(counts: List(Float)) -> Result(Float, MetricError) {
  case guard() {
    Error(e) -> Error(e)
    Ok(_) -> lift(ffi_entropy(counts))
  }
}

/// Euclidean distance from the fully-marked nominal centroid.
pub fn drift(surfaces: List(Surface)) -> Result(Float, MetricError) {
  case guard() {
    Error(e) -> Error(e)
    Ok(_) ->
      case surfaces {
        [] -> Error(InvalidInput("no surfaces supplied"))
        _ ->
          lift(ffi_drift(
            list.map(surfaces, fn(s) { s.observed }),
            list.map(surfaces, fn(s) { s.nominal }),
          ))
      }
  }
}

/// FMEA band 1..5 from severity, occurrence and detection, each 1..5.
pub fn fmea_band(
  severity: Int,
  occurrence: Int,
  detection: Int,
) -> Result(Int, MetricError) {
  case guard() {
    Error(e) -> Error(e)
    Ok(_) -> lift(ffi_fmea(severity, occurrence, detection))
  }
}

/// Combines the three measures into one verdict. Any kernel failure propagates:
/// there is no partial verdict and no default-pass.
pub fn evaluate(
  features: List(Float),
  weights: List(Float),
  layer_counts: List(Float),
  surfaces: List(Surface),
) -> Result(Verdict, MetricError) {
  case conformance(features, weights) {
    Error(e) -> Error(e)
    Ok(c) ->
      case entropy_bits(layer_counts) {
        Error(e) -> Error(e)
        Ok(h) ->
          case drift(surfaces) {
            Error(e) -> Error(e)
            Ok(d) -> Ok(verdict_of(c, h, d))
          }
      }
  }
}

fn verdict_of(c: Float, h: Float, d: Float) -> Verdict {
  let reasons =
    []
    |> prepend_if(c <. conformance_floor, "conformance below floor")
    |> prepend_if(h <. entropy_floor, "layer entropy below CHK-09-MATH floor")
    |> prepend_if(d >. drift_ceiling, "surface drift above ceiling")

  case reasons {
    [] -> Pass(c, h, d)
    _ -> Hold(c, h, d, list.reverse(reasons))
  }
}

fn prepend_if(acc: List(String), cond: Bool, msg: String) -> List(String) {
  case cond {
    True -> [msg, ..acc]
    False -> acc
  }
}

/// Formats a float for telemetry without locale dependence.
pub fn show(value: Float) -> String {
  float.to_string(value)
}
