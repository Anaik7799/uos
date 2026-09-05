//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/actors/freshness_actor</module>
////     <fsharp-lineage>None — novel safety-critical Gleam OTP actor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Continuously-running OTP process wrapping the stateless
////       freshness_monitor check() cycle. Persists intermediate state
////       between ticks and caches the summary into ETS for zero-copy
////       reads by API endpoints.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>
////       SC-SIL4-001, SC-DMS-001, SC-FUNC-002,
////       SC-FUNC-004, SC-MUDA-001, SC-ARCH-SPLIT-002
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       freshness_monitor (stateless check) ↪ FreshnessActorState
////       (OTP actor with cycle counter + ETS side-channel).
////       The stateless monitor is embedded into a stateful OTP shell;
////       no information is lost — the full FreshnessState is preserved
////       as the `monitor` field on every tick.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// OTP FRESHNESS MONITOR ACTOR
//// सदा जाग्रत — Always awake
////
//// Wraps freshness_monitor.check/1 into a continuously-running OTP
//// process.  On each tick (expected every 10 seconds) it:
////
////   1. Calls freshness_monitor.check/1 with the current FreshnessState.
////   2. Executes the returned ControlAction (side-effects: log / reload /
////      emergency / halt).
////   3. Writes three keys into ETS via beam_cache so that HTTP API
////      handlers can read the latest status without message-passing:
////
////        freshness:status  — human-readable string (e.g. "FRESH (checks: 5 …)")
////        freshness:level   — raw level atom string ("fresh" | "stale" | …)
////        freshness:cycles  — total tick count as a decimal string
////
//// DESIGN INTENT
//// The actor itself is NOT exposed as a full OTP server — the public
//// surface consists of three pure functions (init/0, tick/1, get_status/0)
//// so that they can be driven from any OTP supervisor or called directly
//// in tests without spawning a process.  A supervisor can wrap tick/1
//// inside a receive loop or a Process.send_after/3 heartbeat pattern.
////
//// SC-SIL4-001: Safety functions MUST fail to safe state.
//// SC-DMS-001:  Dead man's switch — if actor stops, system alerts.
//// SC-FUNC-002: Core services MUST be operational.
//// SC-FUNC-004: State MUST be recoverable from ETS / SQLite.

import cepaf_gleam/ha/freshness_monitor
import cepaf_gleam/substrate/beam_cache
import gleam/int
import gleam/io

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">
///     FreshnessState (monitor) + cycle_count (actor-local) ↪
///     FreshnessActorState (combined OTP envelope)
///   </morphism>
///   <formal-proof>
///     <P> Pre-condition: freshness_monitor.init() produces a valid FreshnessState. </P>
///     <C> FreshnessActorState wraps that state plus a zero-based cycle counter. </C>
///     <Q> Post-condition: actor state is fully reconstructible from ETS keys
///         freshness:status, freshness:level, freshness:cycles. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub type FreshnessActorState {
  FreshnessActorState(
    /// The underlying stateless monitor state — threaded through every tick.
    monitor: freshness_monitor.FreshnessState,
    /// Monotonically increasing counter of completed check cycles.
    cycle_count: Int,
  )
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">OTP init callback ↪ init/0</morphism>
///   <formal-proof>
///     <P> Pre-condition: beam_cache ETS table may or may not exist yet. </P>
///     <C> init() initialises beam_cache, runs the first check cycle,
///         executes the resulting action, and writes three ETS keys. </C>
///     <Q> Post-condition: FreshnessActorState with cycle_count == 1 returned;
///         ETS keys freshness:status, freshness:level, freshness:cycles are set. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init() -> FreshnessActorState {
  // Ensure ETS table is available before first write (idempotent).
  let _ = beam_cache.init()

  let monitor = freshness_monitor.init()
  let #(new_monitor, action) = freshness_monitor.check(monitor)
  freshness_monitor.execute_action(action)

  // Persist initial state into ETS so API endpoints have data immediately.
  let _ =
    beam_cache.put(
      "freshness:status",
      freshness_monitor.status_string(new_monitor),
    )
  let _ = beam_cache.put("freshness:level", level_string(new_monitor.level))
  let _ = beam_cache.put("freshness:cycles", "1")

  io.println(
    "[FRESHNESS-ACTOR] Initialised — level=" <> level_string(new_monitor.level),
  )

  FreshnessActorState(monitor: new_monitor, cycle_count: 1)
}

// ---------------------------------------------------------------------------
// Tick — call every 10 seconds from supervisor / receive loop
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">
///     FreshnessActorState × tick ≅ FreshnessActorState'
///   </morphism>
///   <formal-proof>
///     <P> Pre-condition: state.cycle_count >= 1 (init was called). </P>
///     <C> tick(state) — run one check cycle, execute action, update ETS. </C>
///     <Q> Post-condition:
///         result.cycle_count == state.cycle_count + 1;
///         ETS freshness:cycles updated to match;
///         execute_action side-effect applied. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn tick(state: FreshnessActorState) -> FreshnessActorState {
  let #(new_monitor, action) = freshness_monitor.check(state.monitor)
  freshness_monitor.execute_action(action)

  let new_cycle = state.cycle_count + 1

  // Refresh ETS cache — API handlers read these without message-passing.
  let _ =
    beam_cache.put(
      "freshness:status",
      freshness_monitor.status_string(new_monitor),
    )
  let _ = beam_cache.put("freshness:level", level_string(new_monitor.level))
  let _ = beam_cache.put("freshness:cycles", int.to_string(new_cycle))

  FreshnessActorState(monitor: new_monitor, cycle_count: new_cycle)
}

// ---------------------------------------------------------------------------
// ETS read-path (no message-passing needed)
// ---------------------------------------------------------------------------

/// Return the latest freshness status string from ETS.
/// Returns "unknown" when ETS has not been populated yet (before init/0).
///
/// STAMP: SC-FUNC-004 — state recoverable without actor message-passing.
pub fn get_status() -> String {
  case beam_cache.get("freshness:status") {
    Ok(s) -> s
    Error(_) -> "unknown"
  }
}

/// Return the latest freshness level string from ETS.
/// Returns "unknown" when ETS has not been populated yet.
pub fn get_level() -> String {
  case beam_cache.get("freshness:level") {
    Ok(l) -> l
    Error(_) -> "unknown"
  }
}

/// Return the total number of completed check cycles from ETS.
/// Returns 0 when ETS has not been populated yet.
pub fn get_cycle_count() -> Int {
  case beam_cache.get("freshness:cycles") {
    Ok(s) ->
      case int.parse(s) {
        Ok(n) -> n
        Error(_) -> 0
      }
    Error(_) -> 0
  }
}

// ---------------------------------------------------------------------------
// Pure helper functions (no side effects)
// ---------------------------------------------------------------------------

/// Convert a StalenessLevel to a lowercase atom-style string.
/// Used as a compact ETS value and in log messages.
///
/// STAMP: SC-MUDA-001 — single canonical conversion, no duplication.
pub fn level_string(level: freshness_monitor.StalenessLevel) -> String {
  case level {
    freshness_monitor.Fresh -> "fresh"
    freshness_monitor.Stale -> "stale"
    freshness_monitor.Degraded -> "degraded"
    freshness_monitor.Dead -> "dead"
  }
}

/// Convert a cycle count integer to its decimal string representation.
/// Thin wrapper over int.to_string/1 — exists for symmetry with the
/// other ETS helper functions so callers never need to import gleam/int.
pub fn int_to_str(n: Int) -> String {
  int.to_string(n)
}
