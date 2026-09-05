//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/config/constraint_sync</module>
////     <fsharp-lineage>Cepaf.Config.ConstraintSync.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <mesh-domain>Information Theory &amp; Constraint Analysis</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6</criticality>
////     <stamp-controls>SC-GLM-CORE-002</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string

// =============================================================================
// External FFI for logarithm
// =============================================================================

@external(erlang, "math", "log")
fn math_log(x: Float) -> Float

/// Natural log of 2 as a constant (precomputed for division).
fn ln2() -> Float {
  math_log(2.0)
}

/// Compute log base 2 of x using natural log.
fn log2(x: Float) -> Float {
  float.divide(math_log(x), ln2())
  |> result.unwrap(0.0)
}

// =============================================================================
// Functions (8)
// =============================================================================

/// Compute Shannon entropy H(X) = -sum(p * log2(p)) for a probability distribution.
/// Input: list of probabilities (should sum to ~1.0).
/// Returns 0.0 for empty lists. Skips zero/negative values.
pub fn shannon_entropy(probs: List(Float)) -> Float {
  case probs {
    [] -> 0.0
    _ ->
      probs
      |> list.filter(fn(p) {
        case float.compare(p, 0.0) {
          order.Gt -> True
          _ -> False
        }
      })
      |> list.fold(0.0, fn(acc, p) {
        float.add(acc, float.negate(float.multiply(p, log2(p))))
      })
  }
}

/// Compute Kullback-Leibler divergence DKL(P || Q) = sum(p * log2(p/q)).
/// Returns Error if lists have different lengths or Q contains zeros where P is nonzero.
pub fn kl_divergence(p: List(Float), q: List(Float)) -> Result(Float, String) {
  case list.length(p) == list.length(q) {
    False -> Error("Distributions must have equal length")
    True -> {
      let pairs = list.zip(p, q)
      let has_zero_q =
        list.any(pairs, fn(pair) {
          let #(pi, qi) = pair
          case float.compare(pi, 0.0) {
            order.Gt ->
              case float.compare(qi, 0.0) {
                order.Gt -> False
                _ -> True
              }
            _ -> False
          }
        })
      case has_zero_q {
        True -> Error("Q contains zero where P is nonzero")
        False -> {
          let total =
            list.fold(pairs, 0.0, fn(acc, pair) {
              let #(pi, qi) = pair
              case float.compare(pi, 0.0) {
                order.Gt -> {
                  let ratio =
                    float.divide(pi, qi)
                    |> result.unwrap(0.0)
                  float.add(acc, float.multiply(pi, log2(ratio)))
                }
                _ -> acc
              }
            })
          Ok(total)
        }
      }
    }
  }
}

/// Compute cross entropy H(P,Q) = -sum(p * log2(q)).
/// Returns Error if lists have different lengths or Q contains zeros where P is nonzero.
pub fn cross_entropy(p: List(Float), q: List(Float)) -> Result(Float, String) {
  case list.length(p) == list.length(q) {
    False -> Error("Distributions must have equal length")
    True -> {
      let pairs = list.zip(p, q)
      let has_zero_q =
        list.any(pairs, fn(pair) {
          let #(pi, qi) = pair
          case float.compare(pi, 0.0) {
            order.Gt ->
              case float.compare(qi, 0.0) {
                order.Gt -> False
                _ -> True
              }
            _ -> False
          }
        })
      case has_zero_q {
        True -> Error("Q contains zero where P is nonzero")
        False -> {
          let total =
            list.fold(pairs, 0.0, fn(acc, pair) {
              let #(pi, qi) = pair
              case float.compare(pi, 0.0) {
                order.Gt ->
                  float.add(acc, float.negate(float.multiply(pi, log2(qi))))
                _ -> acc
              }
            })
          Ok(total)
        }
      }
    }
  }
}

/// Classify a constraint ID string into priority category.
/// Expects format like "SC-MESH-001" or "AOR-GLM-002".
pub fn classify_priority(id: String) -> String {
  let upper = string.uppercase(id)
  case string.starts_with(upper, "SC-") {
    True -> "STAMP_CONTROL"
    False ->
      case string.starts_with(upper, "AOR-") {
        True -> "AGENT_OPERATING_RULE"
        False ->
          case string.starts_with(upper, "IEC-") {
            True -> "IEC_STANDARD"
            False ->
              case string.starts_with(upper, "DO-") {
                True -> "DO_STANDARD"
                False -> "UNKNOWN"
              }
          }
      }
  }
}

/// Extract the family prefix from a constraint ID.
/// "SC-MESH-001" -> "SC-MESH", "AOR-GLM-002" -> "AOR-GLM".
pub fn extract_family(id: String) -> String {
  let parts = string.split(id, on: "-")
  case parts {
    [a, b, ..] -> a <> "-" <> b
    [a] -> a
    [] -> ""
  }
}

/// Extract the numeric suffix from a constraint ID.
/// "SC-MESH-001" -> Ok(1), "invalid" -> Error(...).
pub fn extract_id_number(id: String) -> Result(Int, String) {
  let parts = string.split(id, on: "-")
  case list.last(parts) {
    Ok(num_str) ->
      case int.parse(num_str) {
        Ok(n) -> Ok(n)
        Error(_) -> Error("No numeric suffix in: " <> id)
      }
    Error(_) -> Error("Empty constraint ID")
  }
}

/// Compute Risk Priority Number (RPN) = Severity * Occurrence * Detection.
/// Used in FMEA analysis. All inputs should be 1-10.
pub fn compute_criticality(
  severity: Int,
  occurrence: Int,
  detection: Int,
) -> Int {
  severity * occurrence * detection
}

/// Assess overall health based on 4 metrics (0-100 each).
/// Returns a string classification.
pub fn assess_health(
  availability: Int,
  latency: Int,
  error_rate: Int,
  throughput: Int,
) -> String {
  let score = { availability + latency + error_rate + throughput } / 4
  case score >= 90 {
    True -> "HEALTHY"
    False ->
      case score >= 70 {
        True -> "DEGRADED"
        False ->
          case score >= 50 {
            True -> "WARNING"
            False -> "CRITICAL"
          }
      }
  }
}
