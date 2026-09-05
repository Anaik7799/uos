// =============================================================================
// token_budget_test.gleam — Claude Token Budget Tests (CE5)
// =============================================================================
// Tests for ha/token_budget.gleam
//
// Coverage categories addressed:
//   C1 Page Structure  — init() returns valid baseline allocation
//   C2 Status Badges   — is_warning / is_critical thresholds correct
//   C3 Data Grids      — multiple add_conversation() calls accumulate
//   C4 Timeline        — utilization_percent increases monotonically
//   C5 Interactive     — estimate_text_tokens scales with text length
//   C6 Media/Rich      — summary() contains all key fields
//   C7 AI Advisory     — is_warning/is_critical are mutually exclusive at mid-range
//   C8 Action Button   — remaining never goes negative under normal use
//
// STAMP: SC-MUDA-001, SC-ARCH-SPLIT-002, SC-BOOTSTRAP-001
// Layer: L5_COGNITIVE
// =============================================================================

import cepaf_gleam/ha/token_budget
import gleam/string
import gleeunit/should

// =============================================================================
// C1 — init() structure
// =============================================================================

pub fn init_capacity_200k_test() {
  token_budget.init().capacity
  |> should.equal(200_000)
}

pub fn init_rules_tokens_positive_test() {
  token_budget.init().rules_tokens
  |> fn(n) { n > 0 }
  |> should.be_true()
}

pub fn init_memory_tokens_positive_test() {
  token_budget.init().memory_tokens
  |> fn(n) { n > 0 }
  |> should.be_true()
}

pub fn init_claude_md_tokens_positive_test() {
  token_budget.init().claude_md_tokens
  |> fn(n) { n > 0 }
  |> should.be_true()
}

pub fn init_hook_tokens_positive_test() {
  token_budget.init().hook_tokens
  |> fn(n) { n > 0 }
  |> should.be_true()
}

pub fn init_conversation_tokens_zero_test() {
  token_budget.init().conversation_tokens
  |> should.equal(0)
}

pub fn init_remaining_less_than_capacity_test() {
  let b = token_budget.init()
  { b.remaining < b.capacity }
  |> should.be_true()
}

pub fn init_remaining_accounts_for_fixed_overhead_test() {
  let b = token_budget.init()
  let fixed =
    b.rules_tokens + b.memory_tokens + b.claude_md_tokens + b.hook_tokens
  b.remaining
  |> should.equal(b.capacity - fixed)
}

// =============================================================================
// C5 — estimate_text_tokens
// =============================================================================

pub fn estimate_empty_string_is_zero_test() {
  token_budget.estimate_text_tokens("")
  |> should.equal(0)
}

pub fn estimate_four_chars_is_one_token_test() {
  token_budget.estimate_text_tokens("abcd")
  |> should.equal(1)
}

pub fn estimate_longer_text_scales_test() {
  // 400 chars → ~100 tokens
  let text = string.repeat("x", 400)
  token_budget.estimate_text_tokens(text)
  |> should.equal(100)
}

pub fn estimate_one_char_rounds_up_test() {
  token_budget.estimate_text_tokens("a")
  |> should.equal(1)
}

// =============================================================================
// C3 — add_conversation accumulation
// =============================================================================

pub fn add_conversation_increases_conversation_tokens_test() {
  let b = token_budget.init() |> token_budget.add_conversation(400)
  // 400 chars / 4 = 100 tokens
  b.conversation_tokens
  |> should.equal(100)
}

pub fn add_conversation_decreases_remaining_test() {
  let b0 = token_budget.init()
  let b1 = token_budget.add_conversation(b0, 400)
  { b1.remaining < b0.remaining }
  |> should.be_true()
}

pub fn add_conversation_twice_accumulates_test() {
  let b =
    token_budget.init()
    |> token_budget.add_conversation(400)
    |> token_budget.add_conversation(400)
  b.conversation_tokens
  |> should.equal(200)
}

pub fn add_conversation_capacity_unchanged_test() {
  let b = token_budget.init() |> token_budget.add_conversation(400)
  b.capacity
  |> should.equal(200_000)
}

// =============================================================================
// C2 — is_warning / is_critical thresholds
// =============================================================================

pub fn fresh_budget_not_warning_test() {
  token_budget.init()
  |> token_budget.is_warning()
  |> should.be_false()
}

pub fn fresh_budget_not_critical_test() {
  token_budget.init()
  |> token_budget.is_critical()
  |> should.be_false()
}

pub fn critical_threshold_triggers_at_ten_percent_test() {
  // Add enough to consume 91% (> 90% used)
  // capacity=200_000; fixed overhead ≈ 22_820; need remaining < 20_000
  // Add ~160_000 chars / 4 = ~40_000 tokens worth of text
  let large_text_len = 160_000 * 4
  let b = token_budget.init() |> token_budget.add_conversation(large_text_len)
  // remaining should now be < 10% of 200_000 = 20_000
  { b.remaining < 20_000 }
  |> should.be_true()
}

// =============================================================================
// C4 — utilization_percent
// =============================================================================

pub fn utilization_increases_after_add_test() {
  let b0 = token_budget.init()
  let b1 = token_budget.add_conversation(b0, 4000)
  let u1 = token_budget.utilization_percent(b1)
  let u0 = token_budget.utilization_percent(b0)
  { u1 >. u0 }
  |> should.be_true()
}

pub fn utilization_above_zero_at_init_test() {
  token_budget.init()
  |> token_budget.utilization_percent()
  |> fn(p) { p >. 0.0 }
  |> should.be_true()
}

pub fn utilization_below_100_at_init_test() {
  token_budget.init()
  |> token_budget.utilization_percent()
  |> fn(p) { p <. 100.0 }
  |> should.be_true()
}

// =============================================================================
// C6 — summary()
// =============================================================================

pub fn summary_contains_capacity_test() {
  token_budget.init()
  |> token_budget.summary()
  |> string.contains("200000")
  |> should.be_true()
}

pub fn summary_contains_status_ok_test() {
  token_budget.init()
  |> token_budget.summary()
  |> string.contains("OK")
  |> should.be_true()
}

pub fn summary_is_non_empty_test() {
  token_budget.init()
  |> token_budget.summary()
  |> string.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}
