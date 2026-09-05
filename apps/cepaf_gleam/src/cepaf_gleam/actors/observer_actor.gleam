//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/actors/observer_actor</module>
////     <fsharp-lineage>None — novel proprioceptive OTP actor (Satya Plan Sprint 5)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Self-Observer OTP Actor — orchestrates invariant checking and truth audit.
////       Calls self_observer.check_all_invariants every 60-second logical tick,
////       records results in truth_audit trail, persists summary metrics to ETS.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>
////       SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-TRUTH-001,
////       SC-GLM-UI-001, SC-WIRE-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       OTP GenServer heartbeat pattern ↪ Gleam pure state machine.
////       No OTP timer dependency — caller drives ticks (testable, deterministic).
////       ETS acts as shared read-only projection for the REST / TUI layers.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// SELF-OBSERVER OTP ACTOR — KNOW THYSELF
//// आत्मानं विद्धि — Know thyself (Upanishadic injunction)
////
//// This actor is the autonomous conscience of the mesh. Every 60-second tick:
////   1. Fetches current mesh state via state.default_state()
////   2. Calls self_observer to evaluate all 12 constitutional invariants (I-01..I-12)
////   3. Constructs a TruthAuditEntry from the check result
////   4. Records the entry in the TruthAuditTrail (pure accumulation)
////   5. Queries predict_next_failure() for proactive situational awareness
////   6. Persists four ETS keys for the REST and TUI layers to consume:
////        truth:rate       — "95%" (integer percent string)
////        truth:streak     — "3"   (consecutive-truthful-checks count)
////        truth:prediction — "I-04" (most likely next failure)
////        truth:last_check — "42"  (logical tick counter)
////
//// The state machine is PURE — no OTP timers, no process spawning.
//// The caller owns the heartbeat (process send_after, or test loop).
////
//// Architectural invariants:
////   • cycle_count is strictly monotone increasing
////   • truth_rate is always in [0, 100]
////   • last_result_truthful reflects ONLY the most recent tick
////   • ETS keys are idempotent — writing the same value is safe
////
//// STAMP: SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-TRUTH-001
////
//// OODA alignment: L0_CONSTITUTIONAL (constitutional self-check before every decide phase)

import cepaf_gleam/ha/self_observer
import cepaf_gleam/ha/truth_audit
import cepaf_gleam/substrate/beam_cache
import cepaf_gleam/ui/state as mesh_state
import gleam/float
import gleam/int
import gleam/list

// ---------------------------------------------------------------------------
// ETS key constants
// ---------------------------------------------------------------------------

/// ETS key for the current truth rate (integer percent, e.g. "95").
pub const ets_key_rate = "truth:rate"

/// ETS key for consecutive truthful checks streak (e.g. "3").
pub const ets_key_streak = "truth:streak"

/// ETS key for the predicted next failing invariant (e.g. "I-04").
pub const ets_key_prediction = "truth:prediction"

/// ETS key for the logical tick counter at last check (e.g. "42").
pub const ets_key_last_check = "truth:last_check"

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// State held by the ObserverActor between ticks.
///
/// INVARIANT: cycle_count >= 0 and strictly increases by 1 per tick.
/// INVARIANT: truth_rate_pct ∈ [0, 100].
/// INVARIANT: streak >= 0.
pub type ObserverActorState {
  ObserverActorState(
    /// Truth audit trail — full accumulated history (pure, no IO)
    audit: truth_audit.AuditTrailState,
    /// Monotone logical tick counter
    cycle_count: Int,
    /// Whether the most recent tick was fully truthful
    last_result_truthful: Bool,
  )
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

/// Initialise a clean ObserverActorState.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Empty state ↪ ObserverActorState with zero counters</morphism>
///   <formal-proof>
///     <P> Pre: none </P>
///     <C> init() </C>
///     <Q> Post: cycle_count=0, last_result_truthful=False (no check yet), audit=empty </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init() -> ObserverActorState {
  ObserverActorState(
    audit: truth_audit.init(),
    cycle_count: 0,
    last_result_truthful: False,
  )
}

// ---------------------------------------------------------------------------
// Tick — the core OODA step
// ---------------------------------------------------------------------------

/// Execute one observation cycle. Returns updated state.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">State_n + mesh_snapshot ↪ State_{n+1} + ETS projection</morphism>
///   <formal-proof>
///     <P> Pre: state is valid ObserverActorState; ETS table exists (beam_cache.init called) </P>
///     <C> tick(state) </C>
///     <Q> Post: cycle_count = old + 1; audit.total_checks = old + 1;
///         ETS keys truth:rate / truth:streak / truth:prediction / truth:last_check refreshed;
///         last_result_truthful = True iff all 12 invariants passed </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// On each tick:
///   1. Get current state via mesh_state.default_state()
///   2. Call self_observer.check_with_state to evaluate 12 invariants
///   3. Build TruthAuditEntry from result
///   4. Call truth_audit.record to accumulate
///   5. Call truth_audit.predict_next_failure for situational awareness
///   6. Persist four ETS keys for REST/TUI consumers
pub fn tick(state: ObserverActorState) -> ObserverActorState {
  let new_cycle = state.cycle_count + 1

  // Step 1 — snapshot current mesh state
  let mesh_st = mesh_state.default_state()

  // Step 2 — evaluate all 12 constitutional invariants
  let observer_state = self_observer.init()
  let #(_obs_st, check_result) =
    self_observer.check_with_state(observer_state, mesh_st)

  // Step 3 — build TruthAuditEntry from check result
  let entry = build_entry(new_cycle, check_result)

  // Step 4 — record in the audit trail (pure accumulation)
  let new_audit = truth_audit.record(state.audit, entry)

  // Step 5 — predict next failure (frequency-based)
  let prediction = truth_audit.predict_next_failure(new_audit)

  // Step 6 — persist ETS projection for REST/TUI
  persist_to_ets(new_audit, new_cycle, prediction)

  ObserverActorState(
    audit: new_audit,
    cycle_count: new_cycle,
    last_result_truthful: entry.all_truthful,
  )
}

// ---------------------------------------------------------------------------
// ETS read helpers — consumed by REST API and TUI views
// ---------------------------------------------------------------------------

/// Return current truth rate as a percentage string (e.g. "95%").
/// Falls back to "N/A" when ETS is unavailable or no checks recorded.
pub fn get_truth_rate() -> String {
  case beam_cache.get(ets_key_rate) {
    Ok(pct) -> pct <> "%"
    Error(_) -> "N/A"
  }
}

/// Return consecutive-truthful-checks streak as a string (e.g. "3").
/// Falls back to "0" when ETS is unavailable.
pub fn get_streak() -> String {
  case beam_cache.get(ets_key_streak) {
    Ok(s) -> s
    Error(_) -> "0"
  }
}

/// Return the predicted next failing invariant ID (e.g. "I-04").
/// Falls back to "none" when ETS is unavailable or no history.
pub fn get_prediction() -> String {
  case beam_cache.get(ets_key_prediction) {
    Ok(p) -> p
    Error(_) -> "none"
  }
}

/// Return the logical tick number at the last check (e.g. "42").
/// Falls back to "0" when ETS is unavailable.
pub fn get_audit_summary() -> String {
  case beam_cache.get(ets_key_last_check) {
    Ok(n) -> "cycle:" <> n
    Error(_) -> "cycle:0"
  }
}

// ---------------------------------------------------------------------------
// Convenience read — full summary line from live ETS state
// ---------------------------------------------------------------------------

/// Build a one-line summary from ETS keys (for TUI / Wisp API).
/// Format: "OBSERVER rate:95% streak:3 prediction:I-04 cycle:42"
pub fn ets_summary() -> String {
  "OBSERVER"
  <> " rate:"
  <> get_truth_rate()
  <> " streak:"
  <> get_streak()
  <> " prediction:"
  <> get_prediction()
  <> " "
  <> get_audit_summary()
}

// ---------------------------------------------------------------------------
// In-memory summary — read directly from actor state (no ETS round-trip)
// ---------------------------------------------------------------------------

/// Build a summary from the in-memory actor state (does not require ETS).
/// Useful in tests or when ETS is not initialised.
pub fn state_summary(state: ObserverActorState) -> String {
  let rate_str = case state.audit.total_checks > 0 {
    True -> int.to_string(float.round(state.audit.truth_rate *. 100.0)) <> "%"
    False -> "N/A"
  }
  "OBSERVER"
  <> " cycle:"
  <> int.to_string(state.cycle_count)
  <> " rate:"
  <> rate_str
  <> " last_truthful:"
  <> case state.last_result_truthful {
    True -> "yes"
    False -> "no"
  }
  <> " prediction:"
  <> truth_audit.predict_next_failure(state.audit)
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Build a TruthAuditEntry from a TruthCheckResult.
fn build_entry(
  check_id: Int,
  result: self_observer.TruthCheckResult,
) -> truth_audit.TruthAuditEntry {
  case result {
    self_observer.AllTruthful ->
      truth_audit.TruthAuditEntry(
        check_id: check_id,
        page: "mesh",
        all_truthful: True,
        passed_count: 12,
        failed_count: 0,
        failed_ids: [],
        timestamp: check_id,
      )
    self_observer.MismatchDetected(mismatches: ms) -> {
      let failed_ids = list.map(ms, fn(m) { m.value_id })
      let failed_count = list_length(failed_ids)
      truth_audit.TruthAuditEntry(
        check_id: check_id,
        page: "mesh",
        all_truthful: False,
        passed_count: 12 - failed_count,
        failed_count: failed_count,
        failed_ids: failed_ids,
        timestamp: check_id,
      )
    }
  }
}

/// Write the four ETS keys. Silently swallows ETS errors (best-effort projection).
fn persist_to_ets(
  audit: truth_audit.AuditTrailState,
  cycle: Int,
  prediction: String,
) -> Nil {
  // truth:rate — integer percent
  let rate_pct = case audit.total_checks > 0 {
    True -> int.to_string(float.round(audit.truth_rate *. 100.0))
    False -> "0"
  }
  let _ = beam_cache.put(ets_key_rate, rate_pct)

  // truth:streak — consecutive truthful checks
  let streak = compute_streak(audit)
  let _ = beam_cache.put(ets_key_streak, int.to_string(streak))

  // truth:prediction — most likely next failing invariant
  let _ = beam_cache.put(ets_key_prediction, prediction)

  // truth:last_check — logical tick counter
  let _ = beam_cache.put(ets_key_last_check, int.to_string(cycle))

  Nil
}

/// Count consecutive truthful entries at the head of the audit trail.
fn compute_streak(audit: truth_audit.AuditTrailState) -> Int {
  count_streak(audit.entries, 0)
}

fn count_streak(entries: List(truth_audit.TruthAuditEntry), acc: Int) -> Int {
  case entries {
    [] -> acc
    [e, ..rest] ->
      case e.all_truthful {
        True -> count_streak(rest, acc + 1)
        False -> acc
      }
  }
}

fn list_length(items: List(a)) -> Int {
  list.length(items)
}
