//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/hook_latency</module>
////     <fsharp-lineage>None — novel OODA hook timing tracker (SA3)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////     <mesh-domain>Claude hook execution latency monitoring and alerting</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-MUDA-001, SC-ARCH-SPLIT-002, SC-OODA-ACCEL-003</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Hook start/end timestamps ↪ LatencyTracker with rolling statistics.
////       Exposes slowest hook and average latency for OODA budget verification.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// CLAUDE HOOK EXECUTION LATENCY TRACKER — OODA budget verification (SA3)
//// क्लॉड हुक निष्पादन विलम्बता अनुवर्तक — ऊडा बजट सत्यापन
////
//// Each Claude hook (SessionStart, UserPromptSubmit, PostToolUse, Stop) has a
//// latency budget within the overall OODA cycle target of < 100 ms (SC-BIO-001).
////
//// This module records per-hook timings and surfaces:
////   • average_ms  — mean latency across all recorded hooks
////   • slowest     — the single slowest hook (for Jidoka analysis)
////   • summary     — one-line status for TUI / log output
////
//// Mathematical model:
////   μ(latency) = Σ duration_ms(h) / |H|
////   P(timeout) = |{h ∈ H : h.timed_out}| / |H|
////   OODA compliant iff μ < 100 ms ∧ max(duration_ms) < 200 ms
////
//// STAMP: SC-MUDA-001, SC-ARCH-SPLIT-002, SC-OODA-ACCEL-003
////
//// कालः कलयतामहं — I am Time among reckoners (Gita 10.30)
//// Measure hook time. Respect the OODA budget.

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Timing record for a single hook execution.
pub type HookTiming {
  HookTiming(
    /// Name of the hook, e.g. "SessionStart", "UserPromptSubmit", "PostToolUse".
    hook_name: String,
    /// Unix-epoch millisecond timestamp when the hook began executing.
    start_ms: Int,
    /// Unix-epoch millisecond timestamp when the hook finished executing.
    end_ms: Int,
    /// Wall-clock duration: `end_ms - start_ms`.
    duration_ms: Int,
    /// True if the hook exceeded its budget and was forcibly terminated.
    timed_out: Bool,
  )
}

/// Accumulated timing statistics across all recorded hooks in a session.
pub type LatencyTracker {
  LatencyTracker(
    /// Ordered list of all recorded `HookTiming` values (newest last).
    timings: List(HookTiming),
    /// Total number of hooks recorded.
    total_hooks: Int,
    /// Sum of all `duration_ms` values for O(1) average computation.
    total_duration_ms: Int,
  )
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// OODA budget per hook: 100 ms (SC-BIO-001).
pub const budget_ms: Int = 100

/// Hard timeout per hook: 200 ms (exceeding this sets `timed_out = True`).
pub const timeout_ms: Int = 200

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Empty bootstrap ↪ zero-state LatencyTracker</morphism>
///   <formal-proof>
///     <P> Pre-condition: None. </P>
///     <C> Return LatencyTracker with empty timings list, counters at zero. </C>
///     <Q> Post-condition: total_hooks == 0, total_duration_ms == 0. </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// Create a new, empty `LatencyTracker`.
pub fn init() -> LatencyTracker {
  LatencyTracker(timings: [], total_hooks: 0, total_duration_ms: 0)
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">HookTiming ↪ updated LatencyTracker</morphism>
///   <formal-proof>
///     <P> Pre-condition: timing.duration_ms >= 0. </P>
///     <C> Append timing; increment total_hooks; accumulate total_duration_ms. </C>
///     <Q> Post-condition: total_hooks == prev + 1; total_duration_ms == prev + timing.duration_ms. </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// Record a completed hook timing into the tracker.
///
/// Appends `timing` to the end of `timings` so that `list.last` returns the
/// most-recently-recorded entry.
pub fn record(tracker: LatencyTracker, timing: HookTiming) -> LatencyTracker {
  LatencyTracker(
    timings: list.append(tracker.timings, [timing]),
    total_hooks: tracker.total_hooks + 1,
    total_duration_ms: tracker.total_duration_ms + timing.duration_ms,
  )
}

/// Return the mean hook duration in milliseconds.
///
/// Returns `0.0` if no hooks have been recorded yet.
pub fn average_ms(tracker: LatencyTracker) -> Float {
  case tracker.total_hooks {
    0 -> 0.0
    n -> int.to_float(tracker.total_duration_ms) /. int.to_float(n)
  }
}

/// Return the `HookTiming` with the largest `duration_ms`, or `Error(Nil)` if
/// no hooks have been recorded.
pub fn slowest(tracker: LatencyTracker) -> Result(HookTiming, Nil) {
  case tracker.timings {
    [] -> Error(Nil)
    [first, ..rest] ->
      Ok(
        list.fold(rest, first, fn(acc, t) {
          case t.duration_ms > acc.duration_ms {
            True -> t
            False -> acc
          }
        }),
      )
  }
}

/// Return the number of hooks that exceeded the `timeout_ms` hard limit.
pub fn timeout_count(tracker: LatencyTracker) -> Int {
  list.fold(tracker.timings, 0, fn(acc, t) {
    case t.timed_out {
      True -> acc + 1
      False -> acc
    }
  })
}

/// Return `True` if the mean hook latency is within the OODA budget.
pub fn is_within_budget(tracker: LatencyTracker) -> Bool {
  average_ms(tracker) <. int.to_float(budget_ms)
}

/// Return a human-readable one-line summary of hook latency statistics.
pub fn summary(tracker: LatencyTracker) -> String {
  let avg = float.round(average_ms(tracker))
  let timeouts = timeout_count(tracker)
  let status = case is_within_budget(tracker) {
    True -> "WITHIN_BUDGET"
    False -> "OVER_BUDGET"
  }
  let slowest_info = case slowest(tracker) {
    Ok(t) -> t.hook_name <> "=" <> int.to_string(t.duration_ms) <> "ms"
    Error(_) -> "none"
  }
  string.join(
    [
      "hooks=" <> int.to_string(tracker.total_hooks),
      "avg=" <> int.to_string(avg) <> "ms",
      "slowest=" <> slowest_info,
      "timeouts=" <> int.to_string(timeouts),
      "status=" <> status,
    ],
    " ",
  )
}

/// Convenience constructor: build a `HookTiming` from a name, start, and end.
///
/// `timed_out` is set automatically when `duration_ms >= timeout_ms`.
pub fn make_timing(hook_name: String, start_ms: Int, end_ms: Int) -> HookTiming {
  let duration = end_ms - start_ms
  HookTiming(
    hook_name: hook_name,
    start_ms: start_ms,
    end_ms: end_ms,
    duration_ms: duration,
    timed_out: duration >= timeout_ms,
  )
}
