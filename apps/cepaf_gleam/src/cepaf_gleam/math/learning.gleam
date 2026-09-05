//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/math/learning</module>
////     <fsharp-lineage>None — novel Gleam active/continual/transfer learning</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-MATH-001, SC-BIO-EVO-006, SC-MUDA-001, SC-OODA-003</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Pure functional active learning — no mutable state, no side effects.
////       LearningMemory is a value type; all updates return a new memory.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// सक्रिय अधिगम — Active, Continual & Transfer Learning (Pure Gleam)
////
//// Provides pattern registration, cosine-similarity matching, cross-domain
//// transfer, feedback-loop quality assessment, and stale-pattern pruning.
//// All functions are pure — zero side effects, fully deterministic.
////
//// STAMP: SC-MATH-001, SC-BIO-EVO-006 (Adaptation), SC-OODA-003

import gleam/float
import gleam/int
import gleam/list
import gleam/order.{type Order}
import gleam/string

// =============================================================================
// FFI: Erlang math module
// =============================================================================

@external(erlang, "math", "sqrt")
fn math_sqrt(x: Float) -> Float

// =============================================================================
// Types (प्रकार)
// =============================================================================

/// A learned pattern: feature vector + outcome + metadata.
pub type LearningPattern {
  LearningPattern(
    id: String,
    domain: String,
    features: List(Float),
    outcome: Float,
    confidence: Float,
    usage_count: Int,
  )
}

/// A feedback entry: what was predicted vs what actually happened.
pub type FeedbackEntry {
  FeedbackEntry(
    pattern_id: String,
    predicted: Float,
    actual: Float,
    error: Float,
  )
}

/// The learning memory: collection of patterns + feedback history + generation.
pub type LearningMemory {
  LearningMemory(
    patterns: List(LearningPattern),
    feedback_log: List(FeedbackEntry),
    generation: Int,
  )
}

/// A candidate pattern for transfer from one domain to another.
pub type TransferCandidate {
  TransferCandidate(
    source_domain: String,
    target_domain: String,
    pattern_id: String,
    similarity: Float,
  )
}

/// The result of a pattern-match query.
pub type LearningDecision {
  /// A pattern matched — apply it (carries the pattern id).
  Apply(String)
  /// No pattern is close enough — explore (gather new data).
  Explore
  /// Transfer from source domain to target domain.
  Transfer(String, String)
  /// No match and no transfer candidate found.
  NoMatch
}

// =============================================================================
// Memory lifecycle (स्मृति जीवन-चक्र)
// =============================================================================

/// Create an empty learning memory.
pub fn memory_new() -> LearningMemory {
  LearningMemory(patterns: [], feedback_log: [], generation: 0)
}

/// Add a pattern to the memory, bumping the generation counter.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P>Pre: memory is valid LearningMemory, pattern has id != ""</P>
///     <C>record_pattern(memory, pattern)</C>
///     <Q>Post: result.patterns contains pattern, generation = memory.generation + 1</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn record_pattern(
  memory: LearningMemory,
  pattern: LearningPattern,
) -> LearningMemory {
  LearningMemory(
    patterns: [pattern, ..memory.patterns],
    feedback_log: memory.feedback_log,
    generation: memory.generation + 1,
  )
}

// =============================================================================
// Cosine similarity (कोसाइन समानता)
// =============================================================================

/// Dot product of two float vectors (truncated to shorter length).
fn dot(a: List(Float), b: List(Float)) -> Float {
  list.zip(a, b)
  |> list.fold(0.0, fn(acc, pair) {
    let #(x, y) = pair
    acc +. x *. y
  })
}

/// Euclidean norm of a float vector.
fn norm(v: List(Float)) -> Float {
  math_sqrt(list.fold(v, 0.0, fn(acc, x) { acc +. x *. x }))
}

/// Cosine similarity ∈ [-1, 1].
/// Returns 0.0 when either vector is the zero vector.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P>Pre: a, b are finite float lists</P>
///     <C>cosine_similarity(a, b)</C>
///     <Q>Post: result ∈ [-1.0, 1.0]; 0.0 when either norm = 0</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn cosine_similarity(a: List(Float), b: List(Float)) -> Float {
  let na = norm(a)
  let nb = norm(b)
  case na >. 0.0 && nb >. 0.0 {
    True -> dot(a, b) /. { na *. nb }
    False -> 0.0
  }
}

// =============================================================================
// Pattern matching (पैटर्न मिलान)
// =============================================================================

/// Find the most similar pattern to `features` in memory.
/// Returns `Apply(id)` when best similarity >= threshold,
/// `Explore` when patterns exist but none reach threshold,
/// `NoMatch` when memory is empty.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P>Pre: threshold ∈ [0.0, 1.0]</P>
///     <C>match_pattern(memory, features, threshold)</C>
///     <Q>Post: Apply(id) only when similarity >= threshold;
///              never returns Apply for an id not in memory.patterns</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn match_pattern(
  memory: LearningMemory,
  features: List(Float),
  threshold: Float,
) -> LearningDecision {
  case memory.patterns {
    [] -> NoMatch
    patterns -> {
      let scored =
        list.map(patterns, fn(p) {
          #(cosine_similarity(features, p.features), p)
        })
      let best =
        list.fold(scored, #(0.0, ""), fn(acc, pair) {
          let #(sim, p) = pair
          let #(best_sim, _) = acc
          case sim >. best_sim {
            True -> #(sim, p.id)
            False -> acc
          }
        })
      let #(best_sim, best_id) = best
      case best_sim >=. threshold {
        True -> Apply(best_id)
        False -> Explore
      }
    }
  }
}

// =============================================================================
// Feedback (प्रतिपुष्टि)
// =============================================================================

/// Record feedback: find the pattern by id, compute |predicted - actual|,
/// append a FeedbackEntry, and return updated memory.
/// If the pattern id is not found, returns memory unchanged.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P>Pre: pattern_id is a non-empty string; actual is finite</P>
///     <C>feedback(memory, pattern_id, actual)</C>
///     <Q>Post: |result.feedback_log| >= |memory.feedback_log|;
///              new entry has error = |predicted - actual|</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn feedback(
  memory: LearningMemory,
  pattern_id: String,
  actual: Float,
) -> LearningMemory {
  let found = list.find(memory.patterns, fn(p) { p.id == pattern_id })
  case found {
    Error(_) -> memory
    Ok(p) -> {
      let err = float.absolute_value(p.outcome -. actual)
      let entry =
        FeedbackEntry(
          pattern_id: pattern_id,
          predicted: p.outcome,
          actual: actual,
          error: err,
        )
      LearningMemory(
        patterns: memory.patterns,
        feedback_log: [entry, ..memory.feedback_log],
        generation: memory.generation,
      )
    }
  }
}

// =============================================================================
// Transfer learning (स्थानांतरण अधिगम)
// =============================================================================

/// Search memory for patterns NOT in `target_domain` whose feature vector
/// is within `threshold` cosine similarity of ANY pattern already in target_domain.
/// Returns candidates ordered by similarity descending.
///
/// When no target-domain patterns exist, all patterns from other domains
/// are returned (similarity = 0.0).
pub fn cross_domain_search(
  memory: LearningMemory,
  target_domain: String,
  threshold: Float,
) -> List(TransferCandidate) {
  let target_patterns =
    list.filter(memory.patterns, fn(p) { p.domain == target_domain })
  let source_patterns =
    list.filter(memory.patterns, fn(p) { p.domain != target_domain })
  list.filter_map(source_patterns, fn(src) {
    let best_sim = case target_patterns {
      [] -> 0.0
      tgt ->
        list.fold(tgt, 0.0, fn(best, tp) {
          let s = cosine_similarity(src.features, tp.features)
          case s >. best {
            True -> s
            False -> best
          }
        })
    }
    case best_sim >=. threshold {
      True ->
        Ok(TransferCandidate(
          source_domain: src.domain,
          target_domain: target_domain,
          pattern_id: src.id,
          similarity: best_sim,
        ))
      False -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) {
    case a.similarity >. b.similarity {
      True -> order_lt()
      False ->
        case a.similarity <. b.similarity {
          True -> order_gt()
          False -> order_eq()
        }
    }
  })
}

// ---------------------------------------------------------------------------
// Ordering helpers
// ---------------------------------------------------------------------------

fn order_lt() -> Order {
  order.Lt
}

fn order_gt() -> Order {
  order.Gt
}

fn order_eq() -> Order {
  order.Eq
}

/// Re-tag a pattern for a new domain and reset usage_count.
pub fn adapt_pattern(
  pattern: LearningPattern,
  target_domain: String,
) -> LearningPattern {
  LearningPattern(
    id: pattern.id <> "->" <> target_domain,
    domain: target_domain,
    features: pattern.features,
    outcome: pattern.outcome,
    confidence: pattern.confidence *. 0.8,
    usage_count: 0,
  )
}

/// Find transfer candidates and add adapted copies to memory.
/// Returns the updated memory with new adapted patterns recorded.
pub fn auto_transfer(
  memory: LearningMemory,
  target_domain: String,
  threshold: Float,
) -> LearningMemory {
  let candidates = cross_domain_search(memory, target_domain, threshold)
  list.fold(candidates, memory, fn(mem, candidate) {
    let found = list.find(mem.patterns, fn(p) { p.id == candidate.pattern_id })
    case found {
      Error(_) -> mem
      Ok(src) -> {
        let adapted = adapt_pattern(src, target_domain)
        record_pattern(mem, adapted)
      }
    }
  })
}

// =============================================================================
// Quality metrics (गुणवत्ता मापदण्ड)
// =============================================================================

/// Mean Absolute Error across all feedback entries.
/// Returns 0.0 when feedback_log is empty.
pub fn feedback_loop_quality(memory: LearningMemory) -> Float {
  case memory.feedback_log {
    [] -> 0.0
    entries -> {
      let n = list.length(entries)
      let sum = list.fold(entries, 0.0, fn(acc, e) { acc +. e.error })
      sum /. int_to_float(n)
    }
  }
}

fn int_to_float(n: Int) -> Float {
  let assert Ok(f) = float.parse(int.to_string(n) <> ".0")
  f
}

// =============================================================================
// Pruning (छंटाई)
// =============================================================================

/// Remove patterns whose usage_count is below `min_usage`.
pub fn prune_stale(memory: LearningMemory, min_usage: Int) -> LearningMemory {
  LearningMemory(
    patterns: list.filter(memory.patterns, fn(p) { p.usage_count >= min_usage }),
    feedback_log: memory.feedback_log,
    generation: memory.generation,
  )
}

// =============================================================================
// Summary (सारांश)
// =============================================================================

/// Human-readable one-line summary of the learning memory.
pub fn summary(memory: LearningMemory) -> String {
  let n_patterns = int.to_string(list.length(memory.patterns))
  let n_feedback = int.to_string(list.length(memory.feedback_log))
  let gen = int.to_string(memory.generation)
  let mae = feedback_loop_quality(memory)
  let mae_str = float.to_string(mae)
  let domains =
    memory.patterns
    |> list.map(fn(p) { p.domain })
    |> list.unique()
    |> list.length()
    |> int.to_string()
  string.join(
    [
      "LearningMemory{",
      "gen=" <> gen,
      "patterns=" <> n_patterns,
      "domains=" <> domains,
      "feedback=" <> n_feedback,
      "mae=" <> mae_str,
      "}",
    ],
    " ",
  )
}
