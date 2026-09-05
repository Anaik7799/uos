//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/zettelkasten/entropy</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-IKE-002, SC-SMRITI-140</stamp-controls></compliance>
//// </c3i-module>
////
//// Entropy decay and forgetting curve for knowledge management.
//// Healthy knowledge systems must forget — stale knowledge fades, fresh shines.
//// STAMP: SC-IKE-002 (entropy gating), SC-SMRITI-140 (evolution events recorded)

import cepaf_gleam/zettelkasten/types.{
  type DecayRate, type Holon, Fast, Holon, Medium, Slow,
}
import gleam/float
import gleam/option

/// Daily entropy increment per decay rate.
pub fn daily_entropy_increment(rate: DecayRate) -> Float {
  case rate {
    Slow -> 0.003
    Medium -> 0.01
    Fast -> 0.03
  }
}

/// Compute new entropy after N days without verification.
/// Clamped to [0.0, 1.0].
pub fn entropy_after_days(current: Float, rate: DecayRate, days: Int) -> Float {
  let increment = daily_entropy_increment(rate)
  let new = current +. increment *. int_to_float(days)
  float.min(1.0, float.max(0.0, new))
}

/// Is this holon "rotting"? (entropy > 0.7)
pub fn is_rotting(holon: Holon) -> Bool {
  holon.entropy >. 0.7
}

/// Is this holon "fresh"? (entropy < 0.3)
pub fn is_fresh(holon: Holon) -> Bool {
  holon.entropy <. 0.3
}

/// Is this holon too stale for RAG? (entropy > 0.9)
pub fn is_excluded_from_rag(holon: Holon) -> Bool {
  holon.entropy >. 0.9
}

/// Reset entropy to 0.0 (operator verified this zettel is still accurate).
pub fn verify(holon: Holon, verified_at: String) -> Holon {
  Holon(
    ..holon,
    entropy: 0.0,
    verified_at: option.Some(verified_at),
    updated_at: verified_at,
  )
}

/// Apply daily decay to a holon.
pub fn apply_daily_decay(holon: Holon) -> Holon {
  let new_entropy = entropy_after_days(holon.entropy, holon.decay_rate, 1)
  Holon(..holon, entropy: new_entropy)
}

/// Entropy category label.
pub fn entropy_label(entropy: Float) -> String {
  case entropy <. 0.3 {
    True -> "fresh"
    False ->
      case entropy <. 0.7 {
        True -> "aging"
        False ->
          case entropy <. 0.9 {
            True -> "rotting"
            False -> "excluded"
          }
      }
  }
}

/// Days until a holon reaches a given entropy threshold.
pub fn days_until_entropy(current: Float, rate: DecayRate, target: Float) -> Int {
  case current >=. target {
    True -> 0
    False -> {
      let increment = daily_entropy_increment(rate)
      case increment >. 0.0 {
        True -> {
          let delta = target -. current
          float_to_int_ceil(delta /. increment)
        }
        False -> 999_999
      }
    }
  }
}

/// Days until rotting (entropy > 0.7).
pub fn days_until_rotting(holon: Holon) -> Int {
  days_until_entropy(holon.entropy, holon.decay_rate, 0.7)
}

/// Days until RAG exclusion (entropy > 0.9).
pub fn days_until_excluded(holon: Holon) -> Int {
  days_until_entropy(holon.entropy, holon.decay_rate, 0.9)
}

// Helpers
fn int_to_float(n: Int) -> Float {
  case n {
    0 -> 0.0
    1 -> 1.0
    _ -> {
      let half = int_to_float(n / 2)
      let remainder = case n % 2 {
        0 -> 0.0
        _ -> 1.0
      }
      half +. half +. remainder
    }
  }
}

fn float_to_int_ceil(f: Float) -> Int {
  let truncated = float.truncate(f)
  let remainder = f -. int_to_float(truncated)
  case remainder >. 0.0 {
    True -> truncated + 1
    False -> truncated
  }
}
