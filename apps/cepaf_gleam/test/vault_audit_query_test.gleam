//// vault_audit_query_test — Pass-30 exhaustive coverage of audit log query
//// + histogram + anomaly detection.

import cepaf_gleam/vault_audit_query.{
  type AuditEntry, AuditEntry, AuditFilter, None, Some, count, histogram,
  match_all, most_recent, orphan_gets, query, total,
}
import gleeunit/should

fn sample_log() -> List(AuditEntry) {
  [
    AuditEntry(ts: 100, event: "unseal", name: "", version: 0, caller: "boot"),
    AuditEntry(
      ts: 110,
      event: "put",
      name: "anthropic_api_key",
      version: 1,
      caller: "nif",
    ),
    AuditEntry(
      ts: 120,
      event: "get",
      name: "anthropic_api_key",
      version: 1,
      caller: "nif",
    ),
    AuditEntry(
      ts: 130,
      event: "put",
      name: "telegram_token",
      version: 1,
      caller: "nif",
    ),
    AuditEntry(
      ts: 140,
      event: "get",
      name: "telegram_token",
      version: 1,
      caller: "nif",
    ),
    AuditEntry(
      ts: 150,
      event: "get",
      name: "anthropic_api_key",
      version: 1,
      caller: "nif",
    ),
    AuditEntry(
      ts: 160,
      event: "destroy",
      name: "telegram_token",
      version: 1,
      caller: "operator",
    ),
    AuditEntry(
      ts: 170,
      event: "get_failed_stale",
      name: "anthropic_api_key",
      version: 1,
      caller: "nif",
    ),
  ]
}

// =====================================================================
// query — match_all
// =====================================================================

pub fn match_all_returns_full_log_test() {
  query(sample_log(), match_all()) |> should.equal(sample_log())
}

pub fn match_all_on_empty_log_returns_empty_test() {
  query([], match_all()) |> should.equal([])
}

// =====================================================================
// query — by event
// =====================================================================

pub fn filter_by_event_put_test() {
  let f =
    AuditFilter(
      event: Some("put"),
      name: None,
      since_ts: None,
      until_ts: None,
      caller: None,
    )
  count(sample_log(), f) |> should.equal(2)
}

pub fn filter_by_event_get_test() {
  let f =
    AuditFilter(
      event: Some("get"),
      name: None,
      since_ts: None,
      until_ts: None,
      caller: None,
    )
  count(sample_log(), f) |> should.equal(3)
}

pub fn filter_by_event_no_match_test() {
  let f =
    AuditFilter(
      event: Some("nonexistent"),
      name: None,
      since_ts: None,
      until_ts: None,
      caller: None,
    )
  count(sample_log(), f) |> should.equal(0)
}

// =====================================================================
// query — by name
// =====================================================================

pub fn filter_by_name_returns_only_that_secret_test() {
  let f =
    AuditFilter(
      event: None,
      name: Some("telegram_token"),
      since_ts: None,
      until_ts: None,
      caller: None,
    )
  count(sample_log(), f) |> should.equal(3)
}

pub fn filter_by_name_unknown_returns_empty_test() {
  let f =
    AuditFilter(
      event: None,
      name: Some("ghost"),
      since_ts: None,
      until_ts: None,
      caller: None,
    )
  count(sample_log(), f) |> should.equal(0)
}

// =====================================================================
// query — by ts range
// =====================================================================

pub fn filter_since_ts_inclusive_test() {
  let f =
    AuditFilter(
      event: None,
      name: None,
      since_ts: Some(140),
      until_ts: None,
      caller: None,
    )
  // ts >= 140: 140, 150, 160, 170 → 4 entries
  count(sample_log(), f) |> should.equal(4)
}

pub fn filter_until_ts_inclusive_test() {
  let f =
    AuditFilter(
      event: None,
      name: None,
      since_ts: None,
      until_ts: Some(120),
      caller: None,
    )
  // ts <= 120: 100, 110, 120 → 3 entries
  count(sample_log(), f) |> should.equal(3)
}

pub fn filter_ts_window_test() {
  let f =
    AuditFilter(
      event: None,
      name: None,
      since_ts: Some(120),
      until_ts: Some(150),
      caller: None,
    )
  // 120, 130, 140, 150 → 4 entries
  count(sample_log(), f) |> should.equal(4)
}

// =====================================================================
// query — by caller
// =====================================================================

pub fn filter_by_caller_operator_test() {
  let f =
    AuditFilter(
      event: None,
      name: None,
      since_ts: None,
      until_ts: None,
      caller: Some("operator"),
    )
  count(sample_log(), f) |> should.equal(1)
}

pub fn filter_by_caller_boot_test() {
  let f =
    AuditFilter(
      event: None,
      name: None,
      since_ts: None,
      until_ts: None,
      caller: Some("boot"),
    )
  count(sample_log(), f) |> should.equal(1)
}

// =====================================================================
// query — composed filters
// =====================================================================

pub fn filter_event_and_name_combined_test() {
  let f =
    AuditFilter(
      event: Some("get"),
      name: Some("anthropic_api_key"),
      since_ts: None,
      until_ts: None,
      caller: None,
    )
  count(sample_log(), f) |> should.equal(2)
}

pub fn filter_event_and_window_combined_test() {
  let f =
    AuditFilter(
      event: Some("put"),
      name: None,
      since_ts: Some(120),
      until_ts: None,
      caller: None,
    )
  // puts after ts >= 120: only ts=130 → 1
  count(sample_log(), f) |> should.equal(1)
}

// =====================================================================
// histogram
// =====================================================================

pub fn histogram_counts_each_event_kind_test() {
  let h = histogram(sample_log())
  h.put_count |> should.equal(2)
  h.get_count |> should.equal(3)
  h.destroy_count |> should.equal(1)
  h.unseal_count |> should.equal(1)
  h.failed_get_count |> should.equal(1)
}

pub fn histogram_on_empty_log_is_zeros_test() {
  let h = histogram([])
  h.put_count |> should.equal(0)
  h.get_count |> should.equal(0)
  h.unseal_count |> should.equal(0)
  h.other_count |> should.equal(0)
}

pub fn histogram_unknown_events_in_other_count_test() {
  let entries = [
    AuditEntry(ts: 1, event: "weird_event", name: "k", version: 1, caller: "x"),
    AuditEntry(ts: 2, event: "another_one", name: "k", version: 1, caller: "x"),
  ]
  let h = histogram(entries)
  h.other_count |> should.equal(2)
}

// =====================================================================
// total + most_recent
// =====================================================================

pub fn total_returns_full_count_test() {
  total(sample_log()) |> should.equal(8)
}

pub fn most_recent_returns_n_in_descending_order_test() {
  let recent = most_recent(sample_log(), 3)
  case recent {
    [first, second, third] -> {
      first.ts |> should.equal(170)
      second.ts |> should.equal(160)
      third.ts |> should.equal(150)
    }
    _ -> panic as "expected 3 most-recent entries"
  }
}

pub fn most_recent_handles_n_larger_than_log_test() {
  let recent = most_recent(sample_log(), 100)
  case recent {
    entries -> {
      let n = list_length(entries)
      n |> should.equal(8)
    }
  }
}

// =====================================================================
// orphan_gets — anomaly detection
// =====================================================================

pub fn orphan_gets_returns_empty_for_clean_log_test() {
  orphan_gets(sample_log()) |> should.equal([])
}

pub fn orphan_gets_detects_get_without_put_test() {
  let entries = [
    AuditEntry(ts: 1, event: "get", name: "ghost", version: 1, caller: "nif"),
    AuditEntry(ts: 2, event: "put", name: "real", version: 1, caller: "nif"),
  ]
  let orphans = orphan_gets(entries)
  let n = list_length(orphans)
  n |> should.equal(1)
}

pub fn orphan_gets_does_not_flag_destroys_test() {
  let entries = [
    AuditEntry(
      ts: 1,
      event: "destroy",
      name: "deleted_key",
      version: 1,
      caller: "nif",
    ),
  ]
  // destroy without put isn't a "get"-orphan — caller must use other anomaly detectors
  orphan_gets(entries) |> should.equal([])
}

// =====================================================================
// Helpers
// =====================================================================

fn list_length(xs: List(a)) -> Int {
  do_length(xs, 0)
}

fn do_length(xs: List(a), acc: Int) -> Int {
  case xs {
    [] -> acc
    [_, ..tail] -> do_length(tail, acc + 1)
  }
}
