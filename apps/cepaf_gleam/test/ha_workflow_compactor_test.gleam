/// Workflow Compactor Tests — compact old workflow events into daily summaries
/// संग्रहण — Compaction preserves what matters, releases what does not (Gita 2.22)
///
/// 15 tests covering:
///   - compact_events: empty input, single event, multi-day grouping,
///                     completed/failed counts, duration sum, activity dedup,
///                     date-sorted order
///   - should_compact: below threshold, exactly at threshold, above threshold,
///                     young events not compacted, count-only not compacted
///   - summary_to_json: structure, key presence, array fields
///   - total_runs: empty, single, multi
///   - overall_success_rate: all success, all failed, mixed, empty
///   - summary: non-empty, contains key fields
///
/// Layer: L4_SYSTEM
/// STAMP: SC-HA-001, SC-GLM-UI-003, SC-TRUTH-001
import cepaf_gleam/ha/workflow_compactor.{
  DailySummary, compact_events, overall_success_rate, should_compact, summary,
  summary_to_json, total_runs,
}
import gleam/list
import gleam/string
import gleeunit/should

// ═══════════════════════════════════════════════════════════════
// compact_events — core aggregation
// ═══════════════════════════════════════════════════════════════

pub fn compact_events_empty_returns_empty_test() {
  compact_events([]) |> should.equal([])
}

pub fn compact_events_single_event_one_summary_test() {
  let events = [#("2026-04-01", "send_email", "completed", 120)]
  let result = compact_events(events)
  list.length(result) |> should.equal(1)
}

pub fn compact_events_single_total_runs_is_one_test() {
  let events = [#("2026-04-01", "send_email", "completed", 120)]
  let result = compact_events(events)
  let first = list.first(result)
  case first {
    Ok(s) -> s.total_runs |> should.equal(1)
    Error(_) -> should.fail()
  }
}

pub fn compact_events_two_days_two_summaries_test() {
  let events = [
    #("2026-04-01", "process", "completed", 100),
    #("2026-04-02", "send_email", "failed", 200),
  ]
  compact_events(events) |> list.length() |> should.equal(2)
}

pub fn compact_events_completed_count_correct_test() {
  let events = [
    #("2026-04-01", "process", "completed", 100),
    #("2026-04-01", "notify", "completed", 50),
    #("2026-04-01", "validate", "failed", 30),
  ]
  let result = compact_events(events)
  case list.first(result) {
    Ok(s) -> s.completed |> should.equal(2)
    Error(_) -> should.fail()
  }
}

pub fn compact_events_failed_count_correct_test() {
  let events = [
    #("2026-04-01", "process", "completed", 100),
    #("2026-04-01", "notify", "failed", 50),
    #("2026-04-01", "validate", "failed", 30),
  ]
  let result = compact_events(events)
  case list.first(result) {
    Ok(s) -> s.failed |> should.equal(2)
    Error(_) -> should.fail()
  }
}

pub fn compact_events_duration_sum_correct_test() {
  let events = [
    #("2026-04-01", "step_a", "completed", 100),
    #("2026-04-01", "step_b", "completed", 250),
    #("2026-04-01", "step_c", "failed", 75),
  ]
  let result = compact_events(events)
  case list.first(result) {
    Ok(s) -> s.total_duration_ms |> should.equal(425)
    Error(_) -> should.fail()
  }
}

pub fn compact_events_activities_deduplicated_test() {
  let events = [
    #("2026-04-01", "send_email", "completed", 100),
    #("2026-04-01", "send_email", "completed", 110),
    #("2026-04-01", "process", "completed", 50),
  ]
  let result = compact_events(events)
  case list.first(result) {
    Ok(s) -> list.length(s.activities) |> should.equal(2)
    Error(_) -> should.fail()
  }
}

pub fn compact_events_sorted_by_date_test() {
  // Insert in reverse chronological order — output should be ascending
  let events = [
    #("2026-04-03", "c", "completed", 10),
    #("2026-04-01", "a", "completed", 10),
    #("2026-04-02", "b", "completed", 10),
  ]
  let result = compact_events(events)
  let dates = list.map(result, fn(s) { s.date })
  dates |> should.equal(["2026-04-01", "2026-04-02", "2026-04-03"])
}

// ═══════════════════════════════════════════════════════════════
// should_compact
// ═══════════════════════════════════════════════════════════════

pub fn should_compact_above_both_thresholds_test() {
  should_compact(101, 8) |> should.be_true()
}

pub fn should_compact_count_below_threshold_test() {
  // count=50 (below 100), days=10 — should NOT compact
  should_compact(50, 10) |> should.be_false()
}

pub fn should_compact_days_below_threshold_test() {
  // count=200 (above 100), days=3 (below 7) — should NOT compact
  should_compact(200, 3) |> should.be_false()
}

pub fn should_compact_exactly_at_count_threshold_test() {
  // count=100 is NOT > 100 → should NOT compact
  should_compact(100, 8) |> should.be_false()
}

pub fn should_compact_exactly_at_days_threshold_test() {
  // days=7 is NOT > 7 → should NOT compact
  should_compact(101, 7) |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════
// summary_to_json — structure verification
// ═══════════════════════════════════════════════════════════════

pub fn summary_to_json_contains_date_key_test() {
  let s =
    DailySummary(
      date: "2026-04-01",
      total_runs: 5,
      completed: 4,
      failed: 1,
      total_duration_ms: 500,
      activities: ["a", "b"],
    )
  summary_to_json(s) |> string.contains("\"date\"") |> should.be_true()
}

pub fn summary_to_json_contains_total_runs_key_test() {
  let s =
    DailySummary(
      date: "2026-04-01",
      total_runs: 5,
      completed: 4,
      failed: 1,
      total_duration_ms: 500,
      activities: ["a"],
    )
  summary_to_json(s) |> string.contains("\"total_runs\"") |> should.be_true()
}

pub fn summary_to_json_contains_activities_array_test() {
  let s =
    DailySummary(
      date: "2026-04-01",
      total_runs: 2,
      completed: 2,
      failed: 0,
      total_duration_ms: 200,
      activities: ["process", "notify"],
    )
  let j = summary_to_json(s)
  string.contains(j, "\"activities\"") |> should.be_true()
}

pub fn summary_to_json_is_object_test() {
  let s =
    DailySummary(
      date: "2026-04-01",
      total_runs: 1,
      completed: 1,
      failed: 0,
      total_duration_ms: 100,
      activities: [],
    )
  let j = summary_to_json(s)
  let ok = string.starts_with(j, "{") && string.ends_with(j, "}")
  ok |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// total_runs
// ═══════════════════════════════════════════════════════════════

pub fn total_runs_empty_is_zero_test() {
  total_runs([]) |> should.equal(0)
}

pub fn total_runs_single_summary_test() {
  let summaries = [
    DailySummary(
      date: "2026-04-01",
      total_runs: 7,
      completed: 6,
      failed: 1,
      total_duration_ms: 700,
      activities: [],
    ),
  ]
  total_runs(summaries) |> should.equal(7)
}

pub fn total_runs_multi_summary_sums_correctly_test() {
  let summaries = [
    DailySummary(
      date: "2026-04-01",
      total_runs: 5,
      completed: 5,
      failed: 0,
      total_duration_ms: 500,
      activities: [],
    ),
    DailySummary(
      date: "2026-04-02",
      total_runs: 3,
      completed: 2,
      failed: 1,
      total_duration_ms: 300,
      activities: [],
    ),
  ]
  total_runs(summaries) |> should.equal(8)
}

// ═══════════════════════════════════════════════════════════════
// overall_success_rate
// ═══════════════════════════════════════════════════════════════

pub fn overall_success_rate_empty_is_zero_test() {
  overall_success_rate([]) |> should.equal(0.0)
}

pub fn overall_success_rate_all_completed_test() {
  let summaries = [
    DailySummary(
      date: "2026-04-01",
      total_runs: 4,
      completed: 4,
      failed: 0,
      total_duration_ms: 400,
      activities: [],
    ),
  ]
  overall_success_rate(summaries) |> should.equal(1.0)
}

pub fn overall_success_rate_all_failed_test() {
  let summaries = [
    DailySummary(
      date: "2026-04-01",
      total_runs: 3,
      completed: 0,
      failed: 3,
      total_duration_ms: 300,
      activities: [],
    ),
  ]
  overall_success_rate(summaries) |> should.equal(0.0)
}

pub fn overall_success_rate_mixed_test() {
  // 3 completed out of 4 total → 0.75
  let summaries = [
    DailySummary(
      date: "2026-04-01",
      total_runs: 4,
      completed: 3,
      failed: 1,
      total_duration_ms: 400,
      activities: [],
    ),
  ]
  let rate = overall_success_rate(summaries)
  // rate = 0.75; check within tolerance
  let ok = rate >. 0.74 && rate <. 0.76
  ok |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// summary — human-readable string
// ═══════════════════════════════════════════════════════════════

pub fn summary_nonempty_test() {
  let s = summary([])
  { string.length(s) > 0 } |> should.be_true()
}

pub fn summary_contains_days_field_test() {
  let s = summary([])
  string.contains(s, "days=") |> should.be_true()
}

pub fn summary_contains_total_runs_field_test() {
  let s = summary([])
  string.contains(s, "total_runs=") |> should.be_true()
}

pub fn summary_contains_success_rate_field_test() {
  let s = summary([])
  string.contains(s, "success_rate=") |> should.be_true()
}
