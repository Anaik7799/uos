// =============================================================================
// context_manager_test.gleam — Hierarchical Context Manager Tests
// =============================================================================
// 15 tests covering:
//   T01–T03: init / tier constants
//   T04–T06: estimate_tokens
//   T07–T09: add_entry tier placement and overflow
//   T10–T11: evict_l1
//   T12–T13: promote_to_l1
//   T14:     l1_remaining
//   T15–T16: summary and to_json
//
// STAMP: SC-ZK-IMP-001, SC-SATYA-002, SC-OODA-CLAUDE-001
// Layer: L5_COGNITIVE
// =============================================================================

import cepaf_gleam/ha/context_manager
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn make_entry(
  id: String,
  tier: context_manager.ContextTier,
  relevance: Float,
  tokens: Int,
) -> context_manager.ContextEntry {
  context_manager.ContextEntry(
    holon_id: id,
    title: "Test holon " <> id,
    content: "content for " <> id,
    tier: tier,
    relevance_score: relevance,
    token_estimate: tokens,
    last_accessed_ms: 0,
  )
}

// ---------------------------------------------------------------------------
// T01 — init returns correct L1 capacity
// ---------------------------------------------------------------------------

pub fn init_l1_capacity_test() {
  let budget = context_manager.init()
  budget.l1_capacity
  |> should.equal(200_000)
}

// ---------------------------------------------------------------------------
// T02 — init returns correct L2 capacity
// ---------------------------------------------------------------------------

pub fn init_l2_capacity_test() {
  let budget = context_manager.init()
  budget.l2_capacity
  |> should.equal(1_000_000)
}

// ---------------------------------------------------------------------------
// T03 — init returns zero usage and empty entries
// ---------------------------------------------------------------------------

pub fn init_zero_usage_test() {
  let budget = context_manager.init()
  budget.l1_used |> should.equal(0)
  budget.l2_used |> should.equal(0)
  budget.l3_total |> should.equal(0)
  budget.entries |> should.equal([])
}

// ---------------------------------------------------------------------------
// T04 — estimate_tokens: empty string returns 0
// ---------------------------------------------------------------------------

pub fn estimate_tokens_empty_test() {
  context_manager.estimate_tokens("")
  |> should.equal(0)
}

// ---------------------------------------------------------------------------
// T05 — estimate_tokens: ~4 chars per token
// ---------------------------------------------------------------------------

pub fn estimate_tokens_approx_test() {
  // 40 chars → ~10 tokens
  let text = "1234567890123456789012345678901234567890"
  let tokens = context_manager.estimate_tokens(text)
  // Should be exactly 10 (40 / 4)
  tokens |> should.equal(10)
}

// ---------------------------------------------------------------------------
// T06 — estimate_tokens: short string returns at least 1
// ---------------------------------------------------------------------------

pub fn estimate_tokens_minimum_one_test() {
  // 3 chars < 4, but should return 1 (not 0)
  let tokens = context_manager.estimate_tokens("abc")
  { tokens >= 1 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// T07 — add_entry L1: increments l1_used
// ---------------------------------------------------------------------------

pub fn add_entry_l1_increments_used_test() {
  let budget = context_manager.init()
  let entry = make_entry("zk-001", context_manager.L1Active, 0.9, 100)
  let updated = context_manager.add_entry(budget, entry)
  updated.l1_used |> should.equal(100)
}

// ---------------------------------------------------------------------------
// T08 — add_entry L2: increments l2_used, not l1_used
// ---------------------------------------------------------------------------

pub fn add_entry_l2_increments_l2_used_test() {
  let budget = context_manager.init()
  let entry = make_entry("zk-002", context_manager.L2Cached, 0.5, 500)
  let updated = context_manager.add_entry(budget, entry)
  updated.l2_used |> should.equal(500)
  updated.l1_used |> should.equal(0)
}

// ---------------------------------------------------------------------------
// T09 — add_entry L1 overflow: entry downgraded to L2
// ---------------------------------------------------------------------------

pub fn add_entry_l1_overflow_demotes_to_l2_test() {
  let budget = context_manager.init()
  // Fill L1 to capacity exactly
  let big_entry = make_entry("zk-big", context_manager.L1Active, 0.8, 200_000)
  let full_budget = context_manager.add_entry(budget, big_entry)
  full_budget.l1_used |> should.equal(200_000)

  // Now add another L1 entry — it must overflow to L2
  let overflow_entry =
    make_entry("zk-overflow", context_manager.L1Active, 0.7, 1000)
  let result = context_manager.add_entry(full_budget, overflow_entry)

  // l1_used unchanged, l2_used increased
  result.l1_used |> should.equal(200_000)
  result.l2_used |> should.equal(1000)
}

// ---------------------------------------------------------------------------
// T10 — evict_l1: removes lowest-relevance entries first
// ---------------------------------------------------------------------------

pub fn evict_l1_removes_lowest_relevance_test() {
  let budget = context_manager.init()

  // Add three L1 entries with distinct relevance scores
  let e_high = make_entry("zk-high", context_manager.L1Active, 0.9, 1000)
  let e_mid = make_entry("zk-mid", context_manager.L1Active, 0.5, 1000)
  let e_low = make_entry("zk-low", context_manager.L1Active, 0.1, 1000)

  let b1 = context_manager.add_entry(budget, e_high)
  let b2 = context_manager.add_entry(b1, e_mid)
  let b3 = context_manager.add_entry(b2, e_low)
  b3.l1_used |> should.equal(3000)

  // Evict 1000 tokens — should remove the lowest-relevance entry
  let evicted = context_manager.evict_l1(b3, 1000)

  // l1_used should decrease
  { evicted.l1_used < b3.l1_used } |> should.be_true()

  // The lowest-relevance entry should no longer be in L1
  let l1_ids =
    context_manager.l1_entries(evicted)
    |> list.map(fn(e) { e.holon_id })
  list.contains(l1_ids, "zk-low") |> should.be_false()
}

// ---------------------------------------------------------------------------
// T11 — evict_l1: evicted entries appear in L2
// ---------------------------------------------------------------------------

pub fn evict_l1_demotes_to_l2_test() {
  let budget = context_manager.init()
  let e = make_entry("zk-demote", context_manager.L1Active, 0.2, 500)
  let b = context_manager.add_entry(budget, e)
  let after = context_manager.evict_l1(b, 500)

  // Find the entry in L2
  let l2_entry =
    list.find(after.entries, fn(x) {
      x.holon_id == "zk-demote" && x.tier == context_manager.L2Cached
    })
  l2_entry |> should.be_ok()
}

// ---------------------------------------------------------------------------
// T12 — promote_to_l1: moves an L2 entry into L1
// ---------------------------------------------------------------------------

pub fn promote_to_l1_moves_entry_test() {
  let budget = context_manager.init()
  let entry = make_entry("zk-promo", context_manager.L2Cached, 0.8, 200)
  let b = context_manager.add_entry(budget, entry)
  b.l2_used |> should.equal(200)

  let promoted = context_manager.promote_to_l1(b, "zk-promo")
  promoted.l1_used |> should.equal(200)
  // l2_used should decrease to 0
  promoted.l2_used |> should.equal(0)

  // Entry should appear in l1_entries
  let ids =
    context_manager.l1_entries(promoted)
    |> list.map(fn(e) { e.holon_id })
  list.contains(ids, "zk-promo") |> should.be_true()
}

// ---------------------------------------------------------------------------
// T13 — promote_to_l1: unknown id returns budget unchanged
// ---------------------------------------------------------------------------

pub fn promote_unknown_id_returns_unchanged_test() {
  let budget = context_manager.init()
  let result = context_manager.promote_to_l1(budget, "zk-nonexistent")
  result.l1_used |> should.equal(0)
  result.entries |> should.equal([])
}

// ---------------------------------------------------------------------------
// T14 — l1_remaining decreases as L1 entries are added
// ---------------------------------------------------------------------------

pub fn l1_remaining_decreases_with_entries_test() {
  let budget = context_manager.init()
  let initial_remaining = context_manager.l1_remaining(budget)
  initial_remaining |> should.equal(200_000)

  let entry = make_entry("zk-rem", context_manager.L1Active, 0.6, 5000)
  let updated = context_manager.add_entry(budget, entry)
  let after_remaining = context_manager.l1_remaining(updated)
  after_remaining |> should.equal(195_000)
}

// ---------------------------------------------------------------------------
// T15 — summary is non-empty and contains tier info
// ---------------------------------------------------------------------------

pub fn summary_is_non_empty_test() {
  let budget = context_manager.init()
  let s = context_manager.summary(budget)
  { string.length(s) > 0 } |> should.be_true()
  string.contains(s, "L1=") |> should.be_true()
  string.contains(s, "L2=") |> should.be_true()
}

// ---------------------------------------------------------------------------
// T16 — to_json produces valid-looking JSON with expected fields
// ---------------------------------------------------------------------------

pub fn to_json_contains_expected_fields_test() {
  let budget = context_manager.init()
  let entry = make_entry("zk-json", context_manager.L1Active, 1.0, 100)
  let b = context_manager.add_entry(budget, entry)
  let j = context_manager.to_json(b)

  string.contains(j, "\"l1_capacity\"") |> should.be_true()
  string.contains(j, "\"l2_capacity\"") |> should.be_true()
  string.contains(j, "\"entries\"") |> should.be_true()
  string.contains(j, "zk-json") |> should.be_true()
}
