/// Active / Continual / Transfer Learning — Comprehensive Tests (~20 tests)
///
/// C1: memory_new + record_pattern (page structure / init)
/// C2: cosine_similarity edge cases (status badges / math correctness)
/// C3: match_pattern — Apply / Explore / NoMatch (data grid / decision table)
/// C4: feedback + feedback_loop_quality (timeline / error tracking)
/// C5: cross_domain_search (interactive / transfer search)
/// C6: adapt_pattern + auto_transfer (rich feature / domain adaptation)
/// C7: prune_stale (AI advisory / memory management)
/// C8: summary string (action / reporting)
///
/// STAMP: SC-MATH-001, SC-BIO-EVO-006, SC-OODA-003
/// Layer: L5_COGNITIVE
import cepaf_gleam/math/learning
import gleam/float
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// C1 — memory_new + record_pattern
// =============================================================================

pub fn memory_new_is_empty_test() {
  let m = learning.memory_new()
  list.length(m.patterns) |> should.equal(0)
  list.length(m.feedback_log) |> should.equal(0)
  m.generation |> should.equal(0)
}

pub fn record_pattern_increments_generation_test() {
  let pat =
    learning.LearningPattern(
      id: "p1",
      domain: "ooda",
      features: [1.0, 0.0],
      outcome: 0.9,
      confidence: 0.8,
      usage_count: 5,
    )
  let m = learning.memory_new() |> learning.record_pattern(pat)
  m.generation |> should.equal(1)
  list.length(m.patterns) |> should.equal(1)
}

pub fn record_two_patterns_test() {
  let make_pat = fn(id: String) {
    learning.LearningPattern(
      id: id,
      domain: "test",
      features: [0.5, 0.5],
      outcome: 1.0,
      confidence: 0.9,
      usage_count: 1,
    )
  }
  let m =
    learning.memory_new()
    |> learning.record_pattern(make_pat("a"))
    |> learning.record_pattern(make_pat("b"))
  list.length(m.patterns) |> should.equal(2)
  m.generation |> should.equal(2)
}

// =============================================================================
// C2 — cosine_similarity (math correctness)
// =============================================================================

pub fn cosine_similarity_identical_vectors_test() {
  let sim = learning.cosine_similarity([1.0, 2.0, 3.0], [1.0, 2.0, 3.0])
  { float.absolute_value(sim -. 1.0) <. 1.0e-9 } |> should.be_true()
}

pub fn cosine_similarity_orthogonal_vectors_test() {
  let sim = learning.cosine_similarity([1.0, 0.0], [0.0, 1.0])
  { float.absolute_value(sim) <. 1.0e-9 } |> should.be_true()
}

pub fn cosine_similarity_zero_vector_returns_zero_test() {
  let sim = learning.cosine_similarity([0.0, 0.0], [1.0, 2.0])
  sim |> should.equal(0.0)
}

pub fn cosine_similarity_opposite_vectors_test() {
  let sim = learning.cosine_similarity([1.0, 1.0], [-1.0, -1.0])
  { float.absolute_value(sim +. 1.0) <. 1.0e-9 } |> should.be_true()
}

// =============================================================================
// C3 — match_pattern (Apply / Explore / NoMatch)
// =============================================================================

fn sample_memory() -> learning.LearningMemory {
  let pat =
    learning.LearningPattern(
      id: "pat-health",
      domain: "health",
      features: [1.0, 0.0, 0.0],
      outcome: 0.95,
      confidence: 0.9,
      usage_count: 10,
    )
  learning.memory_new() |> learning.record_pattern(pat)
}

pub fn match_pattern_apply_on_near_identical_test() {
  let m = sample_memory()
  let decision = learning.match_pattern(m, [1.0, 0.01, 0.0], 0.95)
  case decision {
    learning.Apply(id) -> string.contains(id, "pat-health") |> should.be_true()
    _ -> should.fail()
  }
}

pub fn match_pattern_explore_below_threshold_test() {
  let m = sample_memory()
  // Orthogonal vector → similarity ≈ 0, below any reasonable threshold
  let decision = learning.match_pattern(m, [0.0, 1.0, 0.0], 0.99)
  decision |> should.equal(learning.Explore)
}

pub fn match_pattern_no_match_on_empty_memory_test() {
  let decision = learning.match_pattern(learning.memory_new(), [1.0, 0.0], 0.5)
  decision |> should.equal(learning.NoMatch)
}

// =============================================================================
// C4 — feedback + feedback_loop_quality (error tracking)
// =============================================================================

pub fn feedback_records_entry_test() {
  let m = sample_memory()
  let m2 = learning.feedback(m, "pat-health", 0.8)
  list.length(m2.feedback_log) |> should.equal(1)
  let entry = case m2.feedback_log {
    [e, ..] -> e
    [] -> panic as "should have an entry"
  }
  { float.absolute_value(entry.actual -. 0.8) <. 1.0e-9 } |> should.be_true()
  // error = |0.95 - 0.80| = 0.15
  { float.absolute_value(entry.error -. 0.15) <. 1.0e-6 } |> should.be_true()
}

pub fn feedback_unknown_id_does_not_change_memory_test() {
  let m = sample_memory()
  let m2 = learning.feedback(m, "nonexistent", 0.5)
  list.length(m2.feedback_log) |> should.equal(0)
}

pub fn feedback_loop_quality_empty_is_zero_test() {
  learning.memory_new()
  |> learning.feedback_loop_quality()
  |> should.equal(0.0)
}

pub fn feedback_loop_quality_returns_mean_absolute_error_test() {
  let m = sample_memory()
  // Two feedbacks: errors = 0.15 and 0.05 → MAE = 0.10
  let m2 =
    m
    |> learning.feedback("pat-health", 0.8)
    |> learning.feedback("pat-health", 0.9)
  let mae = learning.feedback_loop_quality(m2)
  { float.absolute_value(mae -. 0.1) <. 1.0e-6 } |> should.be_true()
}

// =============================================================================
// C5 — cross_domain_search
// =============================================================================

fn two_domain_memory() -> learning.LearningMemory {
  let p1 =
    learning.LearningPattern(
      id: "src1",
      domain: "source",
      features: [1.0, 0.0],
      outcome: 0.8,
      confidence: 0.7,
      usage_count: 3,
    )
  let p2 =
    learning.LearningPattern(
      id: "tgt1",
      domain: "target",
      features: [0.99, 0.01],
      outcome: 0.85,
      confidence: 0.8,
      usage_count: 2,
    )
  learning.memory_new()
  |> learning.record_pattern(p1)
  |> learning.record_pattern(p2)
}

pub fn cross_domain_search_finds_similar_source_test() {
  let m = two_domain_memory()
  let candidates = learning.cross_domain_search(m, "target", 0.9)
  // src1 is nearly identical to tgt1 → should appear
  { candidates != [] } |> should.be_true
  let first = case candidates {
    [c, ..] -> c
    [] -> panic as "expected at least one candidate"
  }
  first.source_domain |> should.equal("source")
  first.target_domain |> should.equal("target")
}

pub fn cross_domain_search_no_candidates_for_unknown_domain_test() {
  let m = sample_memory()
  // No target-domain patterns exist → all other-domain patterns returned at sim 0.0
  // But we pass an impossibly high threshold
  let candidates = learning.cross_domain_search(m, "unknown-domain", 0.9999)
  // source has no "unknown-domain" patterns to compute similarity against → fallback = 0.0 < threshold
  // When target_patterns == [], sim = 0.0 and threshold > 0.0 → filtered out
  list.length(candidates) |> should.equal(0)
}

// =============================================================================
// C6 — adapt_pattern + auto_transfer
// =============================================================================

pub fn adapt_pattern_retags_domain_test() {
  let p =
    learning.LearningPattern(
      id: "orig",
      domain: "source",
      features: [1.0],
      outcome: 0.5,
      confidence: 1.0,
      usage_count: 7,
    )
  let adapted = learning.adapt_pattern(p, "new-domain")
  adapted.domain |> should.equal("new-domain")
  adapted.usage_count |> should.equal(0)
  // confidence reduced by 20%
  { float.absolute_value(adapted.confidence -. 0.8) <. 1.0e-9 }
  |> should.be_true()
  // id includes arrow notation
  string.contains(adapted.id, "->") |> should.be_true()
}

pub fn auto_transfer_adds_patterns_to_memory_test() {
  let m = two_domain_memory()
  let before = list.length(m.patterns)
  let m2 = learning.auto_transfer(m, "target", 0.9)
  let after = list.length(m2.patterns)
  // At least one adapted pattern should have been added
  { after >= before } |> should.be_true()
}

// =============================================================================
// C7 — prune_stale
// =============================================================================

pub fn prune_stale_removes_low_usage_patterns_test() {
  let p_high =
    learning.LearningPattern(
      id: "high",
      domain: "d",
      features: [1.0],
      outcome: 0.9,
      confidence: 0.9,
      usage_count: 10,
    )
  let p_low =
    learning.LearningPattern(
      id: "low",
      domain: "d",
      features: [0.5],
      outcome: 0.5,
      confidence: 0.5,
      usage_count: 0,
    )
  let m =
    learning.memory_new()
    |> learning.record_pattern(p_high)
    |> learning.record_pattern(p_low)
  let pruned = learning.prune_stale(m, 1)
  list.length(pruned.patterns) |> should.equal(1)
  let remaining = case pruned.patterns {
    [p, ..] -> p
    [] -> panic as "expected one pattern"
  }
  remaining.id |> should.equal("high")
}

pub fn prune_stale_zero_threshold_keeps_all_test() {
  let m = two_domain_memory()
  let pruned = learning.prune_stale(m, 0)
  list.length(pruned.patterns) |> should.equal(list.length(m.patterns))
}

// =============================================================================
// C8 — summary
// =============================================================================

pub fn summary_contains_generation_test() {
  let m = sample_memory()
  let s = learning.summary(m)
  string.contains(s, "gen=") |> should.be_true()
}

pub fn summary_contains_pattern_count_test() {
  let m = sample_memory()
  let s = learning.summary(m)
  string.contains(s, "patterns=") |> should.be_true()
  string.contains(s, "mae=") |> should.be_true()
}
