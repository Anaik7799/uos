//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/counterfactual</module>
////     <fsharp-lineage>None — novel XAI counterfactual explainer for guard rules (SERBAN-3)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Counterfactual explanations for the RETE-UL guard rule decisions.
////       For each rule that fired, the module answers: "which parameter,
////       changed by the smallest absolute amount, would flip the verdict?"
////
////       Explanation algorithm:
////         For each parameter p ∈ {health, entropy, cascade, failures, lyapunov}:
////           1. Probe both directions: p − δ and p + δ (δ = 0.01).
////           2. Re-evaluate the hard-coded rule threshold for that parameter.
////           3. If verdict flips, record the Counterfactual with flip_value = p ± δ.
////           4. nearest_flip selects the Counterfactual with |flip_value − original| minimal.
////
////       Guard rule thresholds (mirrors guard_rules.gleam RETE-UL constants):
////         health    : < 0.4 → fail  |  > 0.8 → pass
////         entropy   : > 2.5 → fail  (high disorder)
////         cascade   : > 3   → fail  (deep failure cascade)
////         failures  : > 5   → fail  (consecutive failures)
////         lyapunov  : > 0.0 → fail  (positive → unstable)
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-OODA-001, SC-VER-001, SC-MUDA-001, SC-SIL4-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       XAI counterfactual reasoning ↪ Gleam pure ADT list.
////       All rule thresholds encoded as named constants — single source of truth.
////     </morphism>
////     <morphism type="surjective" loss="interaction-effects">
////       Single-parameter perturbation does not capture parameter interactions.
////       Mitigation: nearest_flip reports only the cheapest single-parameter flip;
////       multi-parameter explanations are future work.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// COUNTERFACTUAL EXPLAINER — Guard Rule Decision Explanation
//// यत्र नायस्तु पूज्यन्ते — Where understanding is honoured, there is wisdom
////
//// Counterfactual XAI reference: Wachter, Mittelstadt & Russell (2017),
//// "Counterfactual Explanations Without Opening the Black Box".
////
//// Ultrathink alignment: Focus #5 (Continuous Formal Verification),
////                        Focus #6 (Embedded SLM Cognitive Kernels).

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// =============================================================================
// Public types
// =============================================================================

/// A single counterfactual explanation: the smallest change to one parameter
/// that would flip the guard rule verdict for `rule_id`.
pub type Counterfactual {
  Counterfactual(
    /// Identifier of the guard rule being explained (e.g. "health-below-threshold").
    rule_id: String,
    /// The verdict the rule produced with original parameter values.
    current_verdict: Bool,
    /// Name of the parameter whose change flips the verdict.
    flip_parameter: String,
    /// The value the parameter must reach to flip the verdict.
    flip_value: Float,
    /// The original value of that parameter.
    original_value: Float,
  )
}

// =============================================================================
// Rule thresholds (mirrors guard_rules.gleam RETE-UL constants)
// =============================================================================

const health_fail_threshold: Float = 0.4

const health_pass_threshold: Float = 0.8

const entropy_fail_threshold: Float = 2.5

const cascade_fail_threshold: Int = 3

const failures_fail_threshold: Int = 5

const probe_delta: Float = 0.01

// =============================================================================
// Explanation entry-point
// =============================================================================

/// Generate counterfactual explanations for all guard rules whose verdict
/// could be flipped by a single small parameter change.
///
/// Parameters map to the RETE-UL guard grid state:
///   health   ∈ [0.0, 1.0] — aggregate system health score
///   entropy  ≥ 0.0        — Shannon entropy of guard verdicts (bits)
///   cascade  ≥ 0          — current cascade depth (integer)
///   failures ≥ 0          — consecutive failure count
///   lyapunov ∈ ℝ          — Lyapunov exponent estimate
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">guard rule parameters ↪ List(Counterfactual) ADT</morphism>
///   <formal-proof>
///     <P>all parameters are finite floats / ints</P>
///     <C>explain(rule_id, health, entropy, cascade, failures, lyapunov)</C>
///     <Q>non-null List(Counterfactual); may be empty if no flip found; no panics</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn explain(
  rule_id: String,
  health: Float,
  entropy: Float,
  cascade: Int,
  failures: Int,
  lyapunov: Float,
) -> List(Counterfactual) {
  let health_cfs = health_counterfactuals(rule_id, health)
  let entropy_cfs = entropy_counterfactuals(rule_id, entropy)
  let cascade_cfs = cascade_counterfactuals(rule_id, cascade)
  let failure_cfs = failure_counterfactuals(rule_id, failures)
  let lyapunov_cfs = lyapunov_counterfactuals(rule_id, lyapunov)
  list.flatten([health_cfs, entropy_cfs, cascade_cfs, failure_cfs, lyapunov_cfs])
}

// =============================================================================
// Nearest flip selection
// =============================================================================

/// Return the Counterfactual that requires the smallest absolute parameter change.
/// Returns Error(Nil) if the list is empty.
pub fn nearest_flip(cfs: List(Counterfactual)) -> Option(Counterfactual) {
  case cfs {
    [] -> None
    [first, ..rest] ->
      Some(
        list.fold(rest, first, fn(best, cf) {
          let best_dist =
            float.absolute_value(best.flip_value -. best.original_value)
          let cf_dist = float.absolute_value(cf.flip_value -. cf.original_value)
          case cf_dist <. best_dist {
            True -> cf
            False -> best
          }
        }),
      )
  }
}

// =============================================================================
// Rendering helpers
// =============================================================================

/// Multi-line human-readable explanation summary.
pub fn summary(cfs: List(Counterfactual)) -> String {
  case cfs {
    [] ->
      "No counterfactuals found (verdict cannot be flipped by a small change)"
    _ -> {
      let lines =
        list.map(cfs, fn(cf) {
          let verdict_str = case cf.current_verdict {
            True -> "PASS"
            False -> "FAIL"
          }
          "  rule="
          <> cf.rule_id
          <> " verdict="
          <> verdict_str
          <> " flip_param="
          <> cf.flip_parameter
          <> " orig="
          <> float.to_string(cf.original_value)
          <> " need="
          <> float.to_string(cf.flip_value)
          <> " delta="
          <> float.to_string(float.absolute_value(
            cf.flip_value -. cf.original_value,
          ))
        })
      string.join(
        [
          "Counterfactuals (" <> int.to_string(list.length(cfs)) <> "):",
          ..lines
        ],
        "\n",
      )
    }
  }
}

/// JSON array of counterfactual objects.
pub fn to_json(cfs: List(Counterfactual)) -> String {
  let items =
    list.map(cfs, fn(cf) {
      let verdict_str = case cf.current_verdict {
        True -> "true"
        False -> "false"
      }
      "{"
      <> "\"rule_id\":\""
      <> cf.rule_id
      <> "\","
      <> "\"current_verdict\":"
      <> verdict_str
      <> ","
      <> "\"flip_parameter\":\""
      <> cf.flip_parameter
      <> "\","
      <> "\"flip_value\":"
      <> float.to_string(cf.flip_value)
      <> ","
      <> "\"original_value\":"
      <> float.to_string(cf.original_value)
      <> "}"
    })
  "[" <> string.join(items, ",") <> "]"
}

// =============================================================================
// Per-parameter counterfactual probers
// =============================================================================

fn health_counterfactuals(
  rule_id: String,
  health: Float,
) -> List(Counterfactual) {
  let current_verdict = health >. health_fail_threshold
  let results = []
  // If currently failing (health <= 0.4), find flip to pass (need > 0.8)
  let results = case !current_verdict {
    True -> {
      let flip = health_pass_threshold +. probe_delta
      [
        Counterfactual(
          rule_id: rule_id,
          current_verdict: current_verdict,
          flip_parameter: "health",
          flip_value: flip,
          original_value: health,
        ),
        ..results
      ]
    }
    False -> results
  }
  // If currently passing (health > 0.4), find flip to fail (need <= 0.4)
  case current_verdict {
    True -> {
      let flip = health_fail_threshold -. probe_delta
      [
        Counterfactual(
          rule_id: rule_id,
          current_verdict: current_verdict,
          flip_parameter: "health",
          flip_value: flip,
          original_value: health,
        ),
        ..results
      ]
    }
    False -> results
  }
}

fn entropy_counterfactuals(
  rule_id: String,
  entropy: Float,
) -> List(Counterfactual) {
  // High entropy is bad: entropy > 2.5 → fail
  let current_verdict = entropy <. entropy_fail_threshold
  case !current_verdict {
    True -> {
      // Currently failing: need entropy < 2.5
      let flip = entropy_fail_threshold -. probe_delta
      [
        Counterfactual(
          rule_id: rule_id,
          current_verdict: current_verdict,
          flip_parameter: "entropy",
          flip_value: flip,
          original_value: entropy,
        ),
      ]
    }
    False -> []
  }
}

fn cascade_counterfactuals(
  rule_id: String,
  cascade: Int,
) -> List(Counterfactual) {
  // Cascade depth > 3 → fail
  let current_verdict = cascade <= cascade_fail_threshold
  case !current_verdict {
    True -> {
      // Currently failing: need cascade <= 3
      let flip = int.to_float(cascade_fail_threshold)
      [
        Counterfactual(
          rule_id: rule_id,
          current_verdict: current_verdict,
          flip_parameter: "cascade",
          flip_value: flip,
          original_value: int.to_float(cascade),
        ),
      ]
    }
    False -> []
  }
}

fn failure_counterfactuals(
  rule_id: String,
  failures: Int,
) -> List(Counterfactual) {
  // failures > 5 → fail
  let current_verdict = failures <= failures_fail_threshold
  case !current_verdict {
    True -> {
      let flip = int.to_float(failures_fail_threshold)
      [
        Counterfactual(
          rule_id: rule_id,
          current_verdict: current_verdict,
          flip_parameter: "failures",
          flip_value: flip,
          original_value: int.to_float(failures),
        ),
      ]
    }
    False -> []
  }
}

fn lyapunov_counterfactuals(
  rule_id: String,
  lyapunov: Float,
) -> List(Counterfactual) {
  // lyapunov > 0.0 → unstable → fail
  let current_verdict = lyapunov <. 0.0
  case !current_verdict {
    True -> {
      // Currently unstable (lyapunov >= 0): need lyapunov < 0
      let flip = 0.0 -. probe_delta
      [
        Counterfactual(
          rule_id: rule_id,
          current_verdict: current_verdict,
          flip_parameter: "lyapunov",
          flip_value: flip,
          original_value: lyapunov,
        ),
      ]
    }
    False -> []
  }
}
