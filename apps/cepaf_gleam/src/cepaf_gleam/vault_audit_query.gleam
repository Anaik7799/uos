//// Vault audit query — pure-function filter/aggregation over audit log entries
//// returned by the Pass-20 `vault_audit_tail` NIF.
////
//// Slice F partial (Pass-30): the dashboard tile + Wisp REST surface need
//// filtered views over the append-only audit log:
////   - "show me all 'put' events for anthropic_api_key in the last hour"
////   - "count failed unseals across all secrets"
////   - "histogram of access events by hour"
////
//// All filtering happens client-side over the NIF tail result (cheap when
//// log is small; future passes may push filters into the NIF itself for
//// large logs). Pure functions, no I/O, exhaustively testable.

import gleam/list
import gleam/order

// =====================================================================
// Types — match the AuditEntry shape from rusty_vault_nif/src/lib.rs
// =====================================================================

/// One audit log entry. Mirrors `AuditEntry` Rust struct from Pass-20.
pub type AuditEntry {
  AuditEntry(ts: Int, event: String, name: String, version: Int, caller: String)
}

/// Filter criteria for `query/2`. Any None field means "match all".
pub type AuditFilter {
  AuditFilter(
    /// Match only events of this name (e.g. "put", "get", "destroy").
    event: Option(String),
    /// Match only entries for this secret name.
    name: Option(String),
    /// Match only entries with ts >= since (inclusive).
    since_ts: Option(Int),
    /// Match only entries with ts <= until (inclusive).
    until_ts: Option(Int),
    /// Match only entries from this caller (e.g. "nif" vs "operator-cli").
    caller: Option(String),
  )
}

pub type Option(a) {
  Some(value: a)
  None
}

/// Histogram of event counts. For the dashboard tile + RETE-UL freshness rules.
pub type EventHistogram {
  EventHistogram(
    put_count: Int,
    get_count: Int,
    destroy_count: Int,
    lease_renew_count: Int,
    unseal_count: Int,
    seal_count: Int,
    failed_get_count: Int,
    other_count: Int,
  )
}

// =====================================================================
// Public API
// =====================================================================

/// Empty filter — matches every entry.
pub fn match_all() -> AuditFilter {
  AuditFilter(
    event: None,
    name: None,
    since_ts: None,
    until_ts: None,
    caller: None,
  )
}

/// Apply a filter to the audit log; returns matching entries in original order.
pub fn query(
  entries: List(AuditEntry),
  filter: AuditFilter,
) -> List(AuditEntry) {
  list.filter(entries, fn(e) { matches(e, filter) })
}

/// Count entries matching the filter — convenience wrapper around `query`.
pub fn count(entries: List(AuditEntry), filter: AuditFilter) -> Int {
  list.length(query(entries, filter))
}

/// Aggregate event counts across the entire log (or a filtered subset if
/// caller pre-filtered).
pub fn histogram(entries: List(AuditEntry)) -> EventHistogram {
  list.fold(entries, empty_histogram(), fn(h, e) {
    case e.event {
      "put" -> EventHistogram(..h, put_count: h.put_count + 1)
      "get" -> EventHistogram(..h, get_count: h.get_count + 1)
      "destroy" -> EventHistogram(..h, destroy_count: h.destroy_count + 1)
      "lease_renew" ->
        EventHistogram(..h, lease_renew_count: h.lease_renew_count + 1)
      "unseal" -> EventHistogram(..h, unseal_count: h.unseal_count + 1)
      "seal" -> EventHistogram(..h, seal_count: h.seal_count + 1)
      "get_failed_stale" ->
        EventHistogram(..h, failed_get_count: h.failed_get_count + 1)
      _ -> EventHistogram(..h, other_count: h.other_count + 1)
    }
  })
}

/// Total entries matching the filter — alias for `count` with match_all defaults.
pub fn total(entries: List(AuditEntry)) -> Int {
  list.length(entries)
}

/// Returns the most recent N entries (by ts descending). Used by dashboard
/// "Recent Activity" panel.
pub fn most_recent(entries: List(AuditEntry), n: Int) -> List(AuditEntry) {
  let sorted =
    list.sort(entries, fn(a, b) {
      case a.ts > b.ts {
        True -> order.Lt
        False ->
          case a.ts < b.ts {
            True -> order.Gt
            False -> order.Eq
          }
      }
    })
  list.take(sorted, n)
}

/// Detect anomaly: SC-VAULT-009 mandates an envelope per call. If we see
/// a `get` event without a preceding `put` for the same name, flag it.
pub fn orphan_gets(entries: List(AuditEntry)) -> List(AuditEntry) {
  // Names that have at least one `put`
  let put_names =
    list.fold(entries, [], fn(acc, e) {
      case e.event {
        "put" -> [e.name, ..acc]
        _ -> acc
      }
    })
  list.filter(entries, fn(e) {
    case e.event {
      "get" -> !list.contains(put_names, e.name)
      _ -> False
    }
  })
}

// =====================================================================
// Internal
// =====================================================================

fn matches(entry: AuditEntry, filter: AuditFilter) -> Bool {
  matches_field(filter.event, entry.event)
  && matches_field(filter.name, entry.name)
  && matches_caller(filter.caller, entry.caller)
  && matches_since(filter.since_ts, entry.ts)
  && matches_until(filter.until_ts, entry.ts)
}

fn matches_field(needle: Option(String), value: String) -> Bool {
  case needle {
    None -> True
    Some(n) -> n == value
  }
}

fn matches_caller(needle: Option(String), value: String) -> Bool {
  matches_field(needle, value)
}

fn matches_since(needle: Option(Int), ts: Int) -> Bool {
  case needle {
    None -> True
    Some(s) -> ts >= s
  }
}

fn matches_until(needle: Option(Int), ts: Int) -> Bool {
  case needle {
    None -> True
    Some(u) -> ts <= u
  }
}

fn empty_histogram() -> EventHistogram {
  EventHistogram(
    put_count: 0,
    get_count: 0,
    destroy_count: 0,
    lease_renew_count: 0,
    unseal_count: 0,
    seal_count: 0,
    failed_get_count: 0,
    other_count: 0,
  )
}
