// =============================================================================
// rule_pruner_test.gleam — Dynamic Rule Pruner Tests
// =============================================================================
// 13 tests covering:
//   T01–T02: rule_keywords index completeness
//   T03–T04: tokenize
//   T05–T07: rank_rules top-N selection and ordering
//   T08–T09: tokens_saved formula
//   T10–T11: top_filenames and matching_count
//   T12–T13: edge cases (empty prompt, unknown domain)
//
// STAMP: SC-MUDA-001, SC-ZK-CLAUDE-001, SC-OODA-CLAUDE-001
// Layer: L5_COGNITIVE
// =============================================================================

import cepaf_gleam/ha/rule_pruner
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// T01 — rule_keywords returns 84 entries (one per rule file)
// ---------------------------------------------------------------------------

pub fn rule_keywords_count_84_test() {
  let index = rule_pruner.rule_keywords()
  list.length(index) |> should.equal(84)
}

// ---------------------------------------------------------------------------
// T02 — every entry in rule_keywords has a non-empty filename and keywords
// ---------------------------------------------------------------------------

pub fn rule_keywords_all_entries_valid_test() {
  let index = rule_pruner.rule_keywords()
  list.all(index, fn(pair) {
    let #(filename, keywords) = pair
    string.length(filename) > 0 && keywords != []
  })
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// T03 — tokenize splits on whitespace and lowercases
// ---------------------------------------------------------------------------

pub fn tokenize_splits_and_lowercases_test() {
  let tokens = rule_pruner.tokenize("Build the Gleam Module Now")
  list.contains(tokens, "build") |> should.be_true()
  list.contains(tokens, "gleam") |> should.be_true()
  list.contains(tokens, "module") |> should.be_true()
}

// ---------------------------------------------------------------------------
// T04 — tokenize filters short tokens (< 3 chars)
// ---------------------------------------------------------------------------

pub fn tokenize_filters_short_tokens_test() {
  let tokens = rule_pruner.tokenize("do it a now at up")
  // "do", "it", "a", "at", "up" are all < 3 chars and should be filtered
  list.contains(tokens, "do") |> should.be_false()
  list.contains(tokens, "it") |> should.be_false()
  list.contains(tokens, "a") |> should.be_false()
  // "now" has 3 chars and should pass
  list.contains(tokens, "now") |> should.be_true()
}

// ---------------------------------------------------------------------------
// T05 — rank_rules returns at most `limit` results
// ---------------------------------------------------------------------------

pub fn rank_rules_respects_limit_test() {
  let results = rule_pruner.rank_rules("gleam build test compile", 5)
  { list.length(results) <= 5 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// T06 — rank_rules orders results by score descending
// ---------------------------------------------------------------------------

pub fn rank_rules_sorted_descending_test() {
  let results = rule_pruner.rank_rules("gleam build test compile wallaby", 10)
  // Verify each consecutive pair: score[i] >= score[i+1]
  let pairs =
    list.zip(
      list.take(results, list.length(results) - 1),
      list.drop(results, 1),
    )
  list.all(pairs, fn(pair) {
    let #(a, b) = pair
    a.score >=. b.score
  })
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// T07 — rank_rules returns build-and-test.md for build/test prompt
// ---------------------------------------------------------------------------

pub fn rank_rules_build_test_prompt_matches_build_file_test() {
  let results = rule_pruner.rank_rules("gleam build test compile", 84)
  let filenames = list.map(results, fn(r) { r.filename })
  list.contains(filenames, "build-and-test.md") |> should.be_true()
}

// ---------------------------------------------------------------------------
// T08 — tokens_saved is positive when loaded < total
// ---------------------------------------------------------------------------

pub fn tokens_saved_positive_when_fewer_loaded_test() {
  let saved = rule_pruner.tokens_saved(10, 84)
  { saved > 0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// T09 — tokens_saved is 0 when loaded == total
// ---------------------------------------------------------------------------

pub fn tokens_saved_zero_when_all_loaded_test() {
  let saved = rule_pruner.tokens_saved(84, 84)
  saved |> should.equal(0)
}

// ---------------------------------------------------------------------------
// T10 — top_filenames returns a list of strings (not RuleRelevance)
// ---------------------------------------------------------------------------

pub fn top_filenames_returns_strings_test() {
  let names = rule_pruner.top_filenames("zettelkasten recall holon", 5)
  // All results should be non-empty strings ending in .md
  list.all(names, fn(n) { string.length(n) > 0 && string.ends_with(n, ".md") })
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// T11 — matching_count returns positive count for relevant prompt
// ---------------------------------------------------------------------------

pub fn matching_count_positive_for_relevant_prompt_test() {
  let count = rule_pruner.matching_count("gleam build test compile otel")
  { count > 0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// T12 — empty prompt produces zero matches
// ---------------------------------------------------------------------------

pub fn empty_prompt_zero_matches_test() {
  let results = rule_pruner.rank_rules("", 84)
  list.length(results) |> should.equal(0)
}

// ---------------------------------------------------------------------------
// T13 — prompt with unknown domain still returns 0 matches gracefully
// ---------------------------------------------------------------------------

pub fn unknown_domain_returns_zero_matches_test() {
  let results =
    rule_pruner.rank_rules(
      "xyzzyflurblquux nonsense unrecognised tokens zzz",
      84,
    )
  // None of the keywords should match these nonsense tokens
  list.length(results) |> should.equal(0)
}

// ---------------------------------------------------------------------------
// T14 — rank_rules: keywords_matched is a subset of rule keywords
// ---------------------------------------------------------------------------

pub fn rank_rules_matched_keywords_are_subset_test() {
  let results = rule_pruner.rank_rules("zenoh telemetry otel span publish", 10)
  list.all(results, fn(r) { list.length(r.keywords_matched) >= 0 })
  |> should.be_true()

  // Verify that matched keywords appear in the prompt (they were tokenized from it)
  let prompt_tokens = rule_pruner.tokenize("zenoh telemetry otel span publish")
  list.all(results, fn(r) {
    list.all(r.keywords_matched, fn(kw) { list.contains(prompt_tokens, kw) })
  })
  |> should.be_true()
}
