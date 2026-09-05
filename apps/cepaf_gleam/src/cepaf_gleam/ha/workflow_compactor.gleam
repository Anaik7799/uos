//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/workflow_compactor</module>
////     <fsharp-lineage>None — novel Gleam module for workflow event compaction (DUR-3)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Compaction of old workflow events into daily summaries.
////       Reduces storage and query latency for durable execution history
////       while preserving statistical signal (run counts, failure rates).
////
////       Compaction policy: events older than 7 days with total count > 100
////       are collapsed into per-day DailySummary records.  Individual events
////       within the compaction window are discarded after summarisation.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-GLM-UI-003, SC-TRUTH-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="surjective" loss="individual-event-detail">
////       List(WorkflowEvent) ↠ List(DailySummary).
////       Individual event payloads are discarded; only aggregate statistics
////       (run counts, failure counts, durations, unique activity names) are kept.
////       Mitigation: Raw events MUST be archived to audit store before compaction.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// WORKFLOW COMPACTOR — compact old events into daily summaries (DUR-3)
//// संग्रहण — Compaction preserves what matters, releases what does not (Gita 2.22)
////
//// Design:
////   Input:  List of raw event tuples (#(date, activity, status, duration_ms))
////   Output: List of DailySummary — one record per date
////
////   Compaction trigger: should_compact(count, days_old)
////     → True when days_old > 7 AND count > 100
////
////   Aggregation per date:
////     total_runs    = number of events on that date
////     completed     = events where status = "completed"
////     failed        = events where status = "failed"
////     total_duration = sum of all duration_ms
////     activities    = deduplicated list of activity names
////
//// STAMP: SC-HA-001, SC-GLM-UI-003, SC-TRUTH-001, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Compact when event count exceeds this threshold
const compaction_count_threshold: Int = 100

/// Compact only events older than this many days
const compaction_age_days: Int = 7

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Aggregated workflow execution statistics for a single calendar day.
pub type DailySummary {
  DailySummary(
    /// ISO date string YYYY-MM-DD identifying the day
    date: String,
    /// Total number of workflow run events on this day
    total_runs: Int,
    /// Number of runs that completed successfully
    completed: Int,
    /// Number of runs that ended in failure
    failed: Int,
    /// Sum of all individual run durations in milliseconds
    total_duration_ms: Int,
    /// Deduplicated list of activity names seen on this day
    activities: List(String),
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Compact a flat list of raw event tuples into per-day DailySummary records.
///
/// Input tuple layout: #(date, activity_name, status, duration_ms)
///   date          — ISO date string, e.g. "2026-04-14"
///   activity_name — name of the workflow activity
///   status        — "completed", "failed", or any other string
///   duration_ms   — execution duration in milliseconds
///
/// Returns one DailySummary per distinct date found in the input, sorted
/// lexicographically by date (ascending — oldest first).
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="surjective" loss="individual-event-detail">
///     List(#(String, String, String, Int)) ↠ List(DailySummary)
///   </morphism>
///   <formal-proof>
///     <P> Pre: events is a list of valid tuples (date non-empty) </P>
///     <C> compact_events(events) </C>
///     <Q> Post: |result| <= |unique_dates(events)|;
///              for each DailySummary s: s.total_runs = count(events where date=s.date);
///              s.completed + s.failed <= s.total_runs </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn compact_events(
  events: List(#(String, String, String, Int)),
) -> List(DailySummary) {
  // Group by date
  let dates =
    events
    |> list.map(fn(e) {
      let #(date, _, _, _) = e
      date
    })
    |> list.unique()
    |> list.sort(string.compare)

  list.map(dates, fn(date) {
    let day_events =
      list.filter(events, fn(e) {
        let #(d, _, _, _) = e
        d == date
      })

    let total_runs = list.length(day_events)

    let completed =
      list.length(
        list.filter(day_events, fn(e) {
          let #(_, _, status, _) = e
          status == "completed"
        }),
      )

    let failed =
      list.length(
        list.filter(day_events, fn(e) {
          let #(_, _, status, _) = e
          status == "failed"
        }),
      )

    let total_duration_ms =
      list.fold(day_events, 0, fn(acc, e) {
        let #(_, _, _, dur) = e
        acc + dur
      })

    let activities =
      day_events
      |> list.map(fn(e) {
        let #(_, activity, _, _) = e
        activity
      })
      |> list.unique()

    DailySummary(
      date: date,
      total_runs: total_runs,
      completed: completed,
      failed: failed,
      total_duration_ms: total_duration_ms,
      activities: activities,
    )
  })
}

/// Return True when compaction should be triggered.
///
/// Policy: compact when BOTH conditions hold:
///   1. event_count > compaction_count_threshold (100)
///   2. days_old    > compaction_age_days        (7)
///
/// Rationale: short-lived or small event sets carry enough detail that
/// compaction would destroy useful diagnostic information.
pub fn should_compact(event_count: Int, days_old: Int) -> Bool {
  event_count > compaction_count_threshold && days_old > compaction_age_days
}

/// Serialise a DailySummary to a compact JSON object string (SC-GLM-UI-003).
pub fn summary_to_json(s: DailySummary) -> String {
  let activities_json =
    s.activities
    |> list.map(fn(a) { "\"" <> a <> "\"" })
    |> string.join(",")

  "{"
  <> "\"date\":\""
  <> s.date
  <> "\","
  <> "\"total_runs\":"
  <> int.to_string(s.total_runs)
  <> ","
  <> "\"completed\":"
  <> int.to_string(s.completed)
  <> ","
  <> "\"failed\":"
  <> int.to_string(s.failed)
  <> ","
  <> "\"total_duration_ms\":"
  <> int.to_string(s.total_duration_ms)
  <> ","
  <> "\"activities\":["
  <> activities_json
  <> "]}"
}

/// Sum total_runs across all DailySummary records.
pub fn total_runs(summaries: List(DailySummary)) -> Int {
  list.fold(summaries, 0, fn(acc, s) { acc + s.total_runs })
}

/// Compute the overall success rate across all summaries.
///
/// Returns: completed / total_runs, or 0.0 when there are no runs.
pub fn overall_success_rate(summaries: List(DailySummary)) -> Float {
  let t = total_runs(summaries)
  case t == 0 {
    True -> 0.0
    False -> {
      let c = list.fold(summaries, 0, fn(acc, s) { acc + s.completed })
      int.to_float(c) /. int.to_float(t)
    }
  }
}

/// Return a one-line human-readable summary of compacted statistics.
pub fn summary(summaries: List(DailySummary)) -> String {
  let days = list.length(summaries)
  let runs = total_runs(summaries)
  let rate = overall_success_rate(summaries)
  let pct = float.round(rate *. 100.0)

  "WorkflowCompaction{"
  <> "days="
  <> int.to_string(days)
  <> ",total_runs="
  <> int.to_string(runs)
  <> ",success_rate="
  <> int.to_string(pct)
  <> "%}"
}
