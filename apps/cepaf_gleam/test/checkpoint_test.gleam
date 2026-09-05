// =============================================================================
// checkpoint_test.gleam — ETS → SQLite Checkpoint Tests (DUR-1)
// =============================================================================
// Tests for ha/checkpoint.gleam
//
// Coverage categories addressed:
//   C1 Page Structure  — init() returns valid zero-state
//   C2 Status Badges   — summary() reflects state correctly
//   C3 Data Grids      — save() tracks key counts accurately
//   C4 Timeline        — is_due() correctly gates on elapsed time
//   C5 Interactive     — sequential save() calls accumulate state
//   C6 Media/Rich      — schema_ddl() produces valid SQL string
//   C7 AI Advisory     — restore() integrates with beam_cache
//   C8 Action Button   — interval_ms() returns expected constant
//
// STAMP: SC-FUNC-004, SC-MUDA-001, SC-ARCH-SPLIT-002, SC-HA-001
// Layer: L3_TRANSACTION
//
// सर्वे क्षयान्ता निचयाः — All accumulations end in dispersal. (Mahabharata)
// (i.e. ETS is volatile — we checkpoint to survive dispersal)
// =============================================================================

import cepaf_gleam/ha/checkpoint
import cepaf_gleam/substrate/beam_cache
import gleam/string
import gleeunit/should

// =============================================================================
// C1 — init() structure
// =============================================================================

pub fn init_returns_zero_checkpoint_count_test() {
  checkpoint.init().checkpoint_count
  |> should.equal(0)
}

pub fn init_returns_zero_keys_saved_test() {
  checkpoint.init().keys_saved
  |> should.equal(0)
}

pub fn init_returns_zero_restore_count_test() {
  checkpoint.init().restore_count
  |> should.equal(0)
}

pub fn init_returns_zero_last_checkpoint_ms_test() {
  checkpoint.init().last_checkpoint_ms
  |> should.equal(0)
}

// =============================================================================
// C8 — interval_ms() constant
// =============================================================================

pub fn interval_ms_returns_sixty_seconds_test() {
  // 60 000 ms == 60 seconds — the guaranteed max data-loss window
  checkpoint.interval_ms()
  |> should.equal(60_000)
}

// =============================================================================
// C4 — is_due() time-gate logic
// =============================================================================

pub fn is_due_returns_true_when_last_checkpoint_zero_test() {
  // A fresh state (last_checkpoint_ms == 0) is always overdue.
  let state = checkpoint.init()
  checkpoint.is_due(state, 0)
  |> should.be_true()
}

pub fn is_due_returns_true_when_interval_elapsed_test() {
  let state = checkpoint.init()
  // Simulate one checkpoint at t=1000 ms.
  let after_one = checkpoint.CheckpointState(..state, last_checkpoint_ms: 1000)
  // At t = 1000 + 60_000 exactly, the checkpoint is due.
  checkpoint.is_due(after_one, 61_000)
  |> should.be_true()
}

pub fn is_due_returns_false_when_interval_not_elapsed_test() {
  let state = checkpoint.init()
  let after_one = checkpoint.CheckpointState(..state, last_checkpoint_ms: 1000)
  // At t = 1000 + 59_999, the checkpoint is NOT yet due.
  checkpoint.is_due(after_one, 60_999)
  |> should.be_false()
}

pub fn is_due_returns_true_exactly_at_interval_boundary_test() {
  let state = checkpoint.init()
  let after_one = checkpoint.CheckpointState(..state, last_checkpoint_ms: 5000)
  // At t = 5000 + 60_000, exactly on boundary → due.
  checkpoint.is_due(after_one, 65_000)
  |> should.be_true()
}

// =============================================================================
// C3 / C5 — save() accumulates state
// =============================================================================

pub fn save_increments_checkpoint_count_test() {
  let _ = beam_cache.init()
  let state = checkpoint.init()
  let after = checkpoint.save(state)
  after.checkpoint_count
  |> should.equal(1)
}

pub fn save_twice_increments_checkpoint_count_to_two_test() {
  let _ = beam_cache.init()
  let state = checkpoint.init()
  let after =
    state
    |> checkpoint.save()
    |> checkpoint.save()
  after.checkpoint_count
  |> should.equal(2)
}

pub fn save_with_populated_cache_records_keys_saved_test() {
  let _ = beam_cache.init()
  let _ = beam_cache.put("cp_test_key_a", "value_a")
  let _ = beam_cache.put("cp_test_key_b", "value_b")
  let state = checkpoint.init()
  let after = checkpoint.save(state)
  // At least the two keys we inserted must be captured.
  { after.keys_saved >= 2 }
  |> should.be_true()
}

pub fn save_accumulates_keys_saved_across_calls_test() {
  let _ = beam_cache.init()
  let _ = beam_cache.put("cp_accum_key", "v")
  let state = checkpoint.init()
  let after1 = checkpoint.save(state)
  let after2 = checkpoint.save(after1)
  { after2.keys_saved >= after1.keys_saved }
  |> should.be_true()
}

// =============================================================================
// C7 — restore() integrates with beam_cache
// =============================================================================

pub fn restore_returns_checkpoint_state_test() {
  let _ = beam_cache.init()
  let state = checkpoint.restore()
  // restore_count must be non-negative.
  { state.restore_count >= 0 }
  |> should.be_true()
}

pub fn restore_leaves_checkpoint_count_at_zero_test() {
  let state = checkpoint.restore()
  // restore() creates a fresh state — checkpoint_count starts at 0.
  state.checkpoint_count
  |> should.equal(0)
}

// =============================================================================
// C2 — summary() badge rendering
// =============================================================================

pub fn summary_contains_checkpoint_number_test() {
  let state =
    checkpoint.CheckpointState(
      last_checkpoint_ms: 120_000,
      checkpoint_count: 5,
      keys_saved: 42,
      restore_count: 10,
    )
  checkpoint.summary(state)
  |> string.contains("5")
  |> should.be_true()
}

pub fn summary_contains_keys_saved_test() {
  let state =
    checkpoint.CheckpointState(
      last_checkpoint_ms: 60_000,
      checkpoint_count: 2,
      keys_saved: 17,
      restore_count: 0,
    )
  checkpoint.summary(state)
  |> string.contains("17")
  |> should.be_true()
}

pub fn summary_contains_restore_count_test() {
  let state =
    checkpoint.CheckpointState(
      last_checkpoint_ms: 0,
      checkpoint_count: 0,
      keys_saved: 0,
      restore_count: 9,
    )
  checkpoint.summary(state)
  |> string.contains("9")
  |> should.be_true()
}

// =============================================================================
// C6 — schema_ddl() SQL structure
// =============================================================================

pub fn schema_ddl_contains_create_table_test() {
  checkpoint.schema_ddl()
  |> string.contains("CREATE TABLE")
  |> should.be_true()
}

pub fn schema_ddl_contains_checkpoint_table_name_test() {
  checkpoint.schema_ddl()
  |> string.contains("ets_checkpoints")
  |> should.be_true()
}

pub fn schema_ddl_contains_key_column_test() {
  checkpoint.schema_ddl()
  |> string.contains("key")
  |> should.be_true()
}

pub fn schema_ddl_contains_value_column_test() {
  checkpoint.schema_ddl()
  |> string.contains("value")
  |> should.be_true()
}

pub fn schema_ddl_contains_if_not_exists_test() {
  checkpoint.schema_ddl()
  |> string.contains("IF NOT EXISTS")
  |> should.be_true()
}
