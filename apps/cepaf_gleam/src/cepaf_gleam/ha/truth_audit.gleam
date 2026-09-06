//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/truth_audit</module>
////     <fsharp-lineage>None — novel cognitive learning actor (Satya Plan Sprint 4)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Truth audit trail — records every truth check, learns failure patterns,
////       predicts next failure via frequency analysis of historical violations.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-TRUTH-001, SC-GLM-UI-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Cognitive learning pattern ↪ Gleam pure functions.
////       Historical truth-check records accumulate in AuditTrailState.
////       Frequency analysis of failed invariant IDs drives next-failure prediction.
////       Zero side-effects — state in / state out; caller owns persistence.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// TRUTH AUDIT TRAIL — CONTINUOUS SELF-KNOWLEDGE
//// मत्तः स्मृतिर्ज्ञानमपोहनं च
//// From Me come memory, knowledge, and their removal (Gita 15.15)
////
//// The system records every truth-check result to build institutional memory.
//// Over time it learns WHICH invariants fail most frequently and PREDICTS
//// the next likely failure — enabling proactive operator intervention.
////
//// Design principles:
////   1. PURE — no IO, no side effects; all state passed by value
////   2. IMMUTABLE — entries prepended (most-recent-first), never mutated
////   3. PREDICTIVE — most_failing / predict_next_failure via count ranking
////   4. BOUNDED — recent() trims the view; full history stays in entries
////   5. OBSERVABLE — to_json / summary give structured + human-readable output
////
//// The caller (an OTP actor) calls record() after each self_observer check,
//// stores the returned AuditTrailState, and queries predict_next_failure()
//// before each OODA decide phase to sharpen the system's situational awareness.
////
//// STAMP: SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-TRUTH-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A single truth audit entry — one snapshot of a page's invariant check.
pub type TruthAuditEntry {
  TruthAuditEntry(
    /// Sequential check number (1-based, monotonically increasing)
    check_id: Int,
    /// Page that was checked (e.g. "planning", "cockpit")
    page: String,
    /// Whether every invariant passed in this check
    all_truthful: Bool,
    /// Number of invariants that passed
    passed_count: Int,
    /// Number of invariants that failed
    failed_count: Int,
    /// Stable IDs of invariants that failed, e.g. ["I-01", "I-04"]
    failed_ids: List(String),
    /// Sequential counter used as timestamp (not wall-clock)
    timestamp: Int,
  )
}

/// Audit trail state — the full accumulated history plus derived statistics.
/// Statistics are kept incrementally so queries are O(1).
pub type AuditTrailState {
  AuditTrailState(
    /// All entries, most-recent first
    entries: List(TruthAuditEntry),
    /// Total truth checks recorded
    total_checks: Int,
    /// Checks where all invariants passed
    truthful_checks: Int,
    /// Checks where at least one invariant failed
    lying_checks: Int,
    /// truth_rate = truthful_checks / total_checks (0.0 when total = 0)
    truth_rate: Float,
    /// The invariant ID with the highest cumulative failure count
    most_failing_invariant: String,
    /// (invariant_id, failure_count) sorted by count descending
    failure_counts: List(#(String, Int)),
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise an empty audit trail with all-zero statistics.
pub fn init() -> AuditTrailState {
  AuditTrailState(
    entries: [],
    total_checks: 0,
    truthful_checks: 0,
    lying_checks: 0,
    truth_rate: 0.0,
    most_failing_invariant: "none",
    failure_counts: [],
  )
}

/// Record one truth-check result.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Record accumulator ↪ updated AuditTrailState</morphism>
///   <formal-proof>
///     <P> Pre: state is a valid AuditTrailState; entry has consistent passed/failed counts </P>
///     <C> record(state, entry) </C>
///     <Q> Post: total_checks incremented; truth_rate recomputed; failure_counts updated;
///         entries prepended (most-recent-first); most_failing_invariant reflects argmax </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn record(
  state: AuditTrailState,
  entry: TruthAuditEntry,
) -> AuditTrailState {
  let new_total = state.total_checks + 1
  let new_truthful = case entry.all_truthful {
    True -> state.truthful_checks + 1
    False -> state.truthful_checks
  }
  let new_lying = case entry.all_truthful {
    True -> state.lying_checks
    False -> state.lying_checks + 1
  }
  let new_rate = compute_rate(new_truthful, new_total)
  let new_counts = update_failure_counts(state.failure_counts, entry.failed_ids)
  let new_most = most_failing_from(new_counts)

  AuditTrailState(
    entries: [entry, ..state.entries],
    total_checks: new_total,
    truthful_checks: new_truthful,
    lying_checks: new_lying,
    truth_rate: new_rate,
    most_failing_invariant: new_most,
    failure_counts: new_counts,
  )
}

/// Current truth rate as a float in [0.0, 1.0].
/// Returns 0.0 when no checks have been recorded yet.
pub fn truth_rate(state: AuditTrailState) -> Float {
  state.truth_rate
}

/// The invariant ID with the most cumulative failures.
/// Returns "none" when no failures have been recorded.
pub fn most_failing(state: AuditTrailState) -> String {
  state.most_failing_invariant
}

/// Predict which invariant is most likely to fail next.
///
/// Strategy: argmax over failure_counts (frequency-based prediction).
/// Ties broken by the order entries appear in failure_counts (most recently
/// updated first, because update_failure_counts prepends new IDs).
///
/// Returns "none" when there is no failure history.
pub fn predict_next_failure(state: AuditTrailState) -> String {
  // Identical to most_failing — frequency is the best predictor with
  // the data available. A future sprint may weight recency.
  state.most_failing_invariant
}

/// Return the cumulative failure count for a specific invariant ID.
/// Returns 0 when the invariant has never failed.
pub fn failure_count_for(state: AuditTrailState, invariant_id: String) -> Int {
  find_count(state.failure_counts, invariant_id)
}

/// Return the last `count` entries (most recent first).
/// If `count` exceeds the number of entries, all entries are returned.
/// If `count` <= 0, an empty list is returned.
pub fn recent(state: AuditTrailState, count: Int) -> List(TruthAuditEntry) {
  case count <= 0 {
    True -> []
    False -> take(state.entries, count)
  }
}

/// Return True iff the last `n` checks were ALL truthful.
///
/// Edge cases:
///   n <= 0  → True  (vacuously true)
///   fewer than n entries exist → False (insufficient history)
pub fn truthful_streak(state: AuditTrailState, n: Int) -> Bool {
  case n <= 0 {
    True -> True
    False -> {
      let window = take(state.entries, n)
      // If we don't have n entries yet, the streak is not established
      case list_length(window) < n {
        True -> False
        False -> list.all(window, fn(e) { e.all_truthful })
      }
    }
  }
}

/// Serialise the audit trail state to a JSON string.
///
/// Produces a compact JSON object suitable for the Wisp API endpoint.
/// Float formatting keeps at most two decimal places.
pub fn to_json(state: AuditTrailState) -> String {
  let rate_str = float_to_fixed2(state.truth_rate)
  let counts_json = failure_counts_to_json(state.failure_counts)
  let entries_json = entries_to_json(recent(state, 10))

  "{"
  <> "\"total_checks\":"
  <> int.to_string(state.total_checks)
  <> ","
  <> "\"truthful_checks\":"
  <> int.to_string(state.truthful_checks)
  <> ","
  <> "\"lying_checks\":"
  <> int.to_string(state.lying_checks)
  <> ","
  <> "\"truth_rate\":"
  <> rate_str
  <> ","
  <> "\"most_failing_invariant\":\""
  <> state.most_failing_invariant
  <> "\","
  <> "\"failure_counts\":"
  <> counts_json
  <> ","
  <> "\"recent_entries\":"
  <> entries_json
  <> "}"
}

/// One-line summary for logging, e.g.:
///   TRUTH-AUDIT (checks:10, truthful:8, lying:2, rate:80%, most_failing:I-04)
pub fn summary(state: AuditTrailState) -> String {
  let rate_pct = case state.total_checks > 0 {
    True ->
      int.to_string(
        float_to_int_rounded(float_mul(state.truth_rate, int_to_float(100))),
      )
      <> "%"
    False -> "N/A"
  }
  "TRUTH-AUDIT"
  <> " (checks:"
  <> int.to_string(state.total_checks)
  <> ", truthful:"
  <> int.to_string(state.truthful_checks)
  <> ", lying:"
  <> int.to_string(state.lying_checks)
  <> ", rate:"
  <> rate_pct
  <> ", most_failing:"
  <> state.most_failing_invariant
  <> ")"
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Compute truth rate as Float, guarding against division by zero.
fn compute_rate(truthful: Int, total: Int) -> Float {
  case total == 0 {
    True -> 0.0
    False -> float_div(int_to_float(truthful), int_to_float(total))
  }
}

/// Increment failure counts for each ID in `failed_ids`.
/// New IDs are appended; existing IDs have their count bumped.
/// The list is re-sorted descending by count after each update.
fn update_failure_counts(
  counts: List(#(String, Int)),
  failed_ids: List(String),
) -> List(#(String, Int)) {
  let updated = list.fold(failed_ids, counts, increment_count)
  sort_desc(updated)
}

/// Increment the count for `id` in `counts`, adding it at count=1 if absent.
fn increment_count(
  counts: List(#(String, Int)),
  id: String,
) -> List(#(String, Int)) {
  case find_and_bump(counts, id, []) {
    #(True, new_counts) -> new_counts
    #(False, _) -> [#(id, 1), ..counts]
  }
}

/// Walk the list once and bump the matching entry.
/// Returns #(True, new_list) if found, #(False, original) if not.
fn find_and_bump(
  items: List(#(String, Int)),
  target: String,
  acc: List(#(String, Int)),
) -> #(Bool, List(#(String, Int))) {
  case items {
    [] -> #(False, acc)
    [#(id, cnt), ..rest] ->
      case id == target {
        True -> #(
          True,
          list_concat(list_reverse(acc), [#(id, cnt + 1), ..rest]),
        )
        False -> find_and_bump(rest, target, [#(id, cnt), ..acc])
      }
  }
}

/// Return the ID with the highest count, or "none" if the list is empty.
fn most_failing_from(counts: List(#(String, Int))) -> String {
  case counts {
    [] -> "none"
    [#(id, _), ..] -> id
  }
}

/// Find the count for `id` in the list; return 0 if absent.
fn find_count(counts: List(#(String, Int)), id: String) -> Int {
  case counts {
    [] -> 0
    [#(k, v), ..rest] ->
      case k == id {
        True -> v
        False -> find_count(rest, id)
      }
  }
}

/// Take at most `n` items from the front of a list.
fn take(items: List(a), n: Int) -> List(a) {
  do_take(items, n, [])
}

fn do_take(items: List(a), remaining: Int, acc: List(a)) -> List(a) {
  case remaining <= 0 || items == [] {
    True -> list_reverse(acc)
    False ->
      case items {
        [] -> list_reverse(acc)
        [h, ..t] -> do_take(t, remaining - 1, [h, ..acc])
      }
  }
}

/// Stable sort descending by the Int component of each pair.
fn sort_desc(items: List(#(String, Int))) -> List(#(String, Int)) {
  list.sort(items, fn(a, b) { int.compare(b.1, a.1) })
}

fn list_concat(a: List(a), b: List(a)) -> List(a) {
  case a {
    [] -> b
    [h, ..t] -> [h, ..list_concat(t, b)]
  }
}

fn list_reverse(items: List(a)) -> List(a) {
  list.reverse(items)
}

fn list_length(items: List(a)) -> Int {
  list.length(items)
}

/// Serialise failure_counts to a JSON array.
fn failure_counts_to_json(counts: List(#(String, Int))) -> String {
  let pairs =
    list.map(counts, fn(pair) {
      "{\"id\":\"" <> pair.0 <> "\",\"count\":" <> int.to_string(pair.1) <> "}"
    })
  "[" <> string.join(pairs, ",") <> "]"
}

/// Serialise a list of TruthAuditEntry to a JSON array.
fn entries_to_json(entries: List(TruthAuditEntry)) -> String {
  let items = list.map(entries, entry_to_json)
  "[" <> string.join(items, ",") <> "]"
}

fn entry_to_json(e: TruthAuditEntry) -> String {
  let ids_str =
    "["
    <> string.join(list.map(e.failed_ids, fn(id) { "\"" <> id <> "\"" }), ",")
    <> "]"
  "{"
  <> "\"check_id\":"
  <> int.to_string(e.check_id)
  <> ","
  <> "\"page\":\""
  <> e.page
  <> "\","
  <> "\"all_truthful\":"
  <> case e.all_truthful {
    True -> "true"
    False -> "false"
  }
  <> ","
  <> "\"passed_count\":"
  <> int.to_string(e.passed_count)
  <> ","
  <> "\"failed_count\":"
  <> int.to_string(e.failed_count)
  <> ","
  <> "\"failed_ids\":"
  <> ids_str
  <> ","
  <> "\"timestamp\":"
  <> int.to_string(e.timestamp)
  <> "}"
}

// ---------------------------------------------------------------------------
// Float arithmetic helpers (Gleam Float is f64; avoid stdlib float/format)
// ---------------------------------------------------------------------------

fn int_to_float(n: Int) -> Float {
  int.to_float(n)
}

fn float_div(a: Float, b: Float) -> Float {
  case b == 0.0 {
    True -> 0.0
    False -> a /. b
  }
}

fn float_mul(a: Float, b: Float) -> Float {
  a *. b
}

fn float_to_int_rounded(f: Float) -> Int {
  float.round(f)
}

/// Format a float to two decimal places without the gleam/float formatter.
/// E.g. 0.8333 → "0.83"
fn float_to_fixed2(f: Float) -> String {
  let whole = float_to_int_rounded(float.floor(f))
  let frac_raw =
    float_to_int_rounded(float_mul(f -. int_to_float(whole), 100.0))
  // Guard: frac_raw may be negative for negative floats; clamp to 0
  let frac = case frac_raw < 0 {
    True -> 0
    False -> frac_raw
  }
  let frac_str = case frac < 10 {
    True -> "0" <> int.to_string(frac)
    False -> int.to_string(frac)
  }
  int.to_string(whole) <> "." <> frac_str
}
