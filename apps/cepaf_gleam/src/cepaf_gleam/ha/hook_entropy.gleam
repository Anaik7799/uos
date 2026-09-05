//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/hook_entropy</module>
////     <fsharp-lineage>None — novel Shannon entropy alarm for hook subsystem</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////     <mesh-domain>Bootstrap hook subsystem Shannon entropy alarm</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-BOOTSTRAP-005, SC-FRAC-RRF-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Hook outcome stream ↪ Shannon H computation.
////       Pure function, no I/O, no side effects.
////       RETE-UL rule C-2 EntropyAlarm checks entropy_alarm_high/2.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// SHANNON ENTROPY ALARM — Bootstrap hook subsystem (Stream C, rule C-2)
//// शैनन एन्ट्रॉपी अलार्म — बूटस्ट्रैप हुक उपतन्त्र
////
//// Computes H = -Σ p_i * log2(p_i) over a sliding window of HookOutcome
//// values. The RETE-UL rule C-2 EntropyAlarm fires when entropy_high == true,
//// which occurs when H > threshold_bits (default 0.5 bits).
////
//// Mathematical model:
////   H(outcomes) = -Σ_{o ∈ distinct(outcomes)} p(o) * log2(p(o))
////   where p(o) = count(o) / |outcomes|
////
////   H = 0      → all outcomes identical (all-success or all-failure) — calm
////   H ≈ log2(k) → uniform across k distinct outcomes — maximum entropy, alarm
////
////   Default threshold: 0.5 bits (triggers on any non-trivial mixing)
////
//// STAMP: SC-BOOTSTRAP-005, SC-FRAC-RRF-001, SC-MUDA-001
////
//// ज्ञानेन तु तदज्ञानं येषां नाशितमात्मनः — By knowledge, ignorance is destroyed (Gita 5.16)
//// Entropy measures the system's ignorance about its own hook behaviour.

import gleam/float
import gleam/int
import gleam/list
import gleam/result

// =============================================================================
// Erlang log FFI (reuses pattern from testing/coverage_math.gleam)
// =============================================================================

@external(erlang, "math", "log")
fn math_log(x: Float) -> Float

fn ln2() -> Float {
  math_log(2.0)
}

fn log2(x: Float) -> Float {
  float.divide(math_log(x), ln2())
  |> result.unwrap(0.0)
}

// =============================================================================
// Public types
// =============================================================================

/// Outcome of a single hook execution.
/// Maps to the RETE-UL C-2 EntropyAlarm fact context.
pub type HookOutcome {
  /// Hook completed within budget with all checks passing.
  Success
  /// Hook ran but returned stale/degraded data (ZK result was stale).
  DegradedStale
  /// sa-plan-daemon or knowledge-search binary was unreachable.
  DaemonDown
  /// ZK lock file was stale; lock could not be acquired.
  LockStale
  /// Hook exceeded its OODA time budget (>200 ms).
  Timeout
  /// Any other hook failure not covered above.
  OtherFailure
}

// =============================================================================
// Internal helpers
// =============================================================================

/// Convert a HookOutcome to a stable integer tag for grouping.
/// We use ints rather than strings to avoid heap allocation in hot paths.
fn outcome_tag(o: HookOutcome) -> Int {
  case o {
    Success -> 0
    DegradedStale -> 1
    DaemonDown -> 2
    LockStale -> 3
    Timeout -> 4
    OtherFailure -> 5
  }
}

/// Count occurrences of each distinct outcome in the window.
/// Returns a list of (count, total) pairs — one per distinct tag.
fn outcome_counts(outcomes: List(HookOutcome)) -> List(#(Int, Int)) {
  let total = list.length(outcomes)
  case total {
    0 -> []
    _ -> {
      let tags = list.map(outcomes, outcome_tag)
      // For each of the 6 possible tags, count occurrences.
      let possible = [0, 1, 2, 3, 4, 5]
      list.filter_map(possible, fn(tag) {
        let count = list.count(tags, fn(t) { t == tag })
        case count {
          0 -> Error(Nil)
          c -> Ok(#(c, total))
        }
      })
    }
  }
}

// =============================================================================
// Public API
// =============================================================================

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pure function — no I/O</morphism>
///   <formal-proof>
///     <P> Pre: outcomes is a finite list (may be empty) </P>
///     <C> shannon_entropy_bits(outcomes) </C>
///     <Q> Post: result ∈ [0.0, log2(6)] ≈ [0.0, 2.585], never NaN, never panics </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// Compute Shannon entropy H (in bits) over a window of hook outcomes.
///
///   H = 0.0   when all outcomes are identical (or window is empty)
///   H ≈ 2.32  when outcomes are uniformly distributed across 5 values
///   H ≈ 2.58  theoretical max across all 6 outcome types
///
/// STAMP: SC-BOOTSTRAP-005, SC-FRAC-RRF-001
pub fn shannon_entropy_bits(outcomes: List(HookOutcome)) -> Float {
  let counts = outcome_counts(outcomes)
  case counts {
    [] -> 0.0
    _ ->
      list.fold(counts, 0.0, fn(acc, pair) {
        let #(count, total) = pair
        let p =
          float.divide(int.to_float(count), int.to_float(total))
          |> result.unwrap(0.0)
        case p <=. 0.0 {
          True -> acc
          False -> {
            let term = p *. log2(p)
            acc -. term
          }
        }
      })
  }
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pure function — delegates to shannon_entropy_bits</morphism>
///   <formal-proof>
///     <P> Pre: threshold_bits >= 0.0 </P>
///     <C> entropy_alarm_high(outcomes, threshold_bits) </C>
///     <Q> Post: True iff H(outcomes) > threshold_bits. RETE-UL C-2 reads this. </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// Returns True when H(outcomes) > threshold_bits, triggering RETE-UL rule C-2.
///
/// Default threshold recommended: 0.5 bits (any non-trivial mixing).
/// Use 1.0 bits for a more permissive alarm.
///
/// STAMP: SC-BOOTSTRAP-005
pub fn entropy_alarm_high(
  outcomes: List(HookOutcome),
  threshold_bits: Float,
) -> Bool {
  shannon_entropy_bits(outcomes) >. threshold_bits
}
