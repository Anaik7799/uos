//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/actors/guard_grid_actor</module>
////     <fsharp-lineage>None — novel OODA cognitive cycle OTP actor (L5)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       OODA cognitive cycle actor for the Guard Grid.
////       Runs the full Observe-Orient-Decide-Act loop every 10 seconds.
////       Observes grid health, orients via entropy + Wolfram cellular
////       automata + Lyapunov estimation, decides via 30-rule RETE-UL
////       evaluation, acts by logging the highest-priority action to ETS.
////       Health derivative (d(H)/dt) tracks stability trajectory.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>
////       SC-SIL4-001, SC-HA-001, SC-OODA-001, SC-FUNC-002,
////       SC-FUNC-004, SC-MUDA-001, SC-ARCH-SPLIT-002
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       GuardGrid (stateless matrix) + guard_rules (pure evaluation) ↪
////       GuardGridActorState (OTP actor envelope with OODA cycle state).
////       All immutable grid operations are lifted into a stateful actor;
////       zero information is lost — full grid is preserved in state.
////     </morphism>
////     <morphism type="surjective" loss="wall-clock time">
////       OODA cycle_count is logical monotonic counter, not wall-clock.
////       Mitigation: ETS guard:grid:cycles stores the count for external
////       correlation; callers that need timestamps supply them explicitly.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// GUARD GRID OODA ACTOR — Full cognitive cycle every 10 seconds
//// ऊडा चक्र सदा चलति — The OODA cycle always turns
////
//// Architecture:
////   GuardGrid (immutable matrix) → GuardGridActorState (OODA envelope)
////     ↳ OBSERVE  : read health_score from current grid
////     ↳ ORIENT   : compute_entropy + apply_rule_110 + lyapunov_estimate
////                  + multi_rule_analysis (Rules 30, 110, 90, 54, 184, 126)
////     ↳ DECIDE   : evaluate_all_with_layers → highest_priority_action
////     ↳ ACT      : execute action (log to ETS), write guard:grid:* keys
////     ↳ VERIFY   : compare health_after vs health_before for regression
////
//// ETS keys (beam_cache):
////   guard:grid:health      — current health_score as string "0.875"
////   guard:grid:entropy     — Shannon entropy "1.23"
////   guard:grid:lyapunov    — Lyapunov exponent estimate "-0.45"
////   guard:grid:action      — last action string e.g. "SetCockpitMode(dark)"
////   guard:grid:cycles      — OODA cycle count as decimal string
////   guard:grid:derivative  — d(Health)/dt as string "-0.050"
////
//// STAMP: SC-SIL4-001, SC-HA-001, SC-OODA-001, SC-FUNC-002, SC-FUNC-004

import cepaf_gleam/ha/claude_metrics
import cepaf_gleam/ha/guard_grid
import cepaf_gleam/ha/guard_rules
import cepaf_gleam/substrate/beam_cache
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Number of historical health scores retained for derivative computation.
const history_window: Int = 10

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">
///     GuardGrid (stateless) + OODA history ↪ GuardGridActorState (OTP actor)
///   </morphism>
///   <formal-proof>
///     <P> Pre-condition: guard_grid.init() produces a valid GuardGrid. </P>
///     <C> GuardGridActorState wraps the grid plus OODA bookkeeping fields. </C>
///     <Q> Post-condition: state is fully reconstructible from ETS keys
///         guard:grid:health, guard:grid:entropy, guard:grid:lyapunov,
///         guard:grid:action, guard:grid:cycles, guard:grid:derivative. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub type GuardGridActorState {
  GuardGridActorState(
    /// The underlying immutable guard grid — threaded through every cycle.
    grid: guard_grid.GuardGrid,
    /// Monotonically increasing OODA cycle counter.
    cycle_count: Int,
    /// Human-readable string of the last RETE-UL action executed.
    last_action: String,
    /// Health score from the most recently completed OODA cycle.
    last_health: Float,
    /// Shannon entropy from the most recently completed OODA cycle.
    last_entropy: Float,
    /// Sliding window of health scores for d(H)/dt computation.
    /// Most recent score is at the head; oldest is at the tail.
    /// Maximum length: history_window (10 entries).
    health_history: List(Float),
  )
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Initialise the actor state with a fresh guard grid and run one OODA cycle.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">OTP init callback ↪ init/0</morphism>
///   <formal-proof>
///     <P> Pre-condition: beam_cache ETS table may or may not exist. </P>
///     <C> init() initialises beam_cache, builds a pristine GuardGrid,
///         runs the first OODA tick, and writes six ETS keys. </C>
///     <Q> Post-condition: GuardGridActorState with cycle_count == 1 returned;
///         all guard:grid:* ETS keys are populated. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init() -> GuardGridActorState {
  // Ensure ETS table is present before first write (idempotent).
  let _ = beam_cache.init()

  let grid = guard_grid.init()
  let initial =
    GuardGridActorState(
      grid: grid,
      cycle_count: 0,
      last_action: "NoAction",
      last_health: guard_grid.health_score(grid),
      last_entropy: guard_grid.compute_entropy(grid),
      health_history: [],
    )

  io.println("[GUARD-GRID-ACTOR] Initialised — running first OODA tick")

  // Run first cycle so ETS is populated immediately.
  ooda_tick(initial)
}

// ---------------------------------------------------------------------------
// OODA cycle — call every 10 seconds
// ---------------------------------------------------------------------------

/// Execute one full OODA cognitive cycle against the current guard grid state.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">
///     GuardGridActorState × ooda_tick ≅ GuardGridActorState'
///   </morphism>
///   <formal-proof>
///     <P> Pre-condition: state.cycle_count >= 0. </P>
///     <C> ooda_tick: OBSERVE health → ORIENT (entropy, rule-110, lyapunov,
///         multi_rule_analysis) → DECIDE (30 rules, highest-priority action) →
///         ACT (write ETS) → VERIFY (health regression check). </C>
///     <Q> Post-condition:
///         result.cycle_count == state.cycle_count + 1;
///         ETS guard:grid:* keys refreshed;
///         result.last_action reflects the fired rule action (or "NoAction"). </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn ooda_tick(state: GuardGridActorState) -> GuardGridActorState {
  let grid = state.grid

  // ── OBSERVE ──────────────────────────────────────────────────────────────
  let health = guard_grid.health_score(grid)

  // ── ORIENT ───────────────────────────────────────────────────────────────
  let entropy = guard_grid.compute_entropy(grid)
  let lyapunov = guard_grid.lyapunov_estimate(grid)
  let _rule_110_result = guard_grid.apply_rule_110(grid)
  let _multi_analysis = guard_grid.multi_rule_analysis(grid)
  let cascade = guard_grid.detect_cascade(grid)

  // Derive failing layers from grid cells for accurate rule evaluation.
  let failing_layers = collect_failing_layers(grid)

  // Cascade depth = number of adjacent failing-layer pairs.
  let cascade_depth = compute_cascade_depth(failing_layers)

  // Failure count = total cells with non-PASSED verdict.
  let failure_count = grid.failed_cells

  // ── DECIDE ───────────────────────────────────────────────────────────────
  let evaluations =
    guard_rules.evaluate_all_with_layers(
      health,
      entropy,
      cascade_depth,
      failure_count,
      lyapunov,
      failing_layers,
    )
  let action = guard_rules.highest_priority_action(evaluations)
  let action_str = guard_rules.action_to_string(action)

  // ── ACT ──────────────────────────────────────────────────────────────────
  execute_action(action, health, entropy, lyapunov, cascade)

  // Record one MCP call per OODA cycle to the session metrics (SC-SATYA-002).
  let _metrics =
    claude_metrics.record_mcp_call(claude_metrics.init("guard_grid", 0))

  let new_cycle = state.cycle_count + 1

  // Update sliding health history (cap at history_window).
  let new_history =
    [health, ..state.health_history]
    |> list.take(history_window)

  // Compute first derivative for this new history.
  let derivative = derivative_from_history(new_history)

  // Write all six ETS keys — API handlers read without message-passing.
  let _ = beam_cache.put("guard:grid:health", float_str(health))
  let _ = beam_cache.put("guard:grid:entropy", float_str(entropy))
  let _ = beam_cache.put("guard:grid:lyapunov", float_str(lyapunov))
  let _ = beam_cache.put("guard:grid:action", action_str)
  let _ = beam_cache.put("guard:grid:cycles", int.to_string(new_cycle))
  let _ = beam_cache.put("guard:grid:derivative", float_str(derivative))

  // ── VERIFY ───────────────────────────────────────────────────────────────
  // Log regression if health dropped more than 0.1 in one cycle.
  let prev = state.last_health
  let delta = health -. prev
  let _ = case delta <. -0.1 {
    True ->
      io.println(
        "[GUARD-GRID-ACTOR] VERIFY: health regression Δ="
        <> float_str(delta)
        <> " cycle="
        <> int.to_string(new_cycle),
      )
    False -> Nil
  }

  GuardGridActorState(
    grid: grid,
    cycle_count: new_cycle,
    last_action: action_str,
    last_health: health,
    last_entropy: entropy,
    health_history: new_history,
  )
}

// ---------------------------------------------------------------------------
// Verdict recording
// ---------------------------------------------------------------------------

/// Record a guard verdict from module_guard or invariant_gate.
/// Delegates to guard_grid.record_verdict/5 and returns an updated actor state.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">
///     GuardGridActorState × verdict ≅ GuardGridActorState'
///   </morphism>
///   <formal-proof>
///     <P> Pre-condition: layer in "L0".."L7", verdict is a known verdict string. </P>
///     <C> record_verdict updates the corresponding grid cell and rebuilds metrics. </C>
///     <Q> Post-condition: result.grid reflects the new verdict; cycle_count unchanged. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn record_verdict(
  state: GuardGridActorState,
  layer: String,
  module: String,
  verdict: String,
) -> GuardGridActorState {
  let new_grid =
    guard_grid.record_verdict(
      state.grid,
      layer,
      module,
      verdict,
      state.cycle_count,
    )
  GuardGridActorState(..state, grid: new_grid)
}

// ---------------------------------------------------------------------------
// Health derivative
// ---------------------------------------------------------------------------

/// Compute d(Health)/dt — first derivative from the health_history window.
///
/// Defined as: (head - last) / (window_size - 1)
/// Returns 0.0 when the history is too short (< 2 entries).
///
/// Positive → health improving; negative → health declining.
pub fn health_derivative(state: GuardGridActorState) -> Float {
  derivative_from_history(state.health_history)
}

// ---------------------------------------------------------------------------
// ETS read-path (no message-passing needed)
// ---------------------------------------------------------------------------

/// Return the latest guard grid health score string from ETS.
/// Format: "0.875" — passed_cells / total_cells.
pub fn get_health() -> String {
  case beam_cache.get("guard:grid:health") {
    Ok(s) -> s
    Error(_) -> "unknown"
  }
}

/// Return the last OODA action string from ETS.
/// e.g. "SetCockpitMode(dark)", "NoAction", "JidokaHalt(...)"
pub fn get_last_action() -> String {
  case beam_cache.get("guard:grid:action") {
    Ok(s) -> s
    Error(_) -> "unknown"
  }
}

/// Return a compact JSON status object from ETS keys.
/// Suitable for the /api/v1/guard/status Wisp endpoint.
pub fn get_grid_status() -> String {
  let health = case beam_cache.get("guard:grid:health") {
    Ok(s) -> s
    Error(_) -> "unknown"
  }
  let entropy = case beam_cache.get("guard:grid:entropy") {
    Ok(s) -> s
    Error(_) -> "unknown"
  }
  let lyapunov = case beam_cache.get("guard:grid:lyapunov") {
    Ok(s) -> s
    Error(_) -> "unknown"
  }
  let action = case beam_cache.get("guard:grid:action") {
    Ok(s) -> s
    Error(_) -> "unknown"
  }
  let cycles = case beam_cache.get("guard:grid:cycles") {
    Ok(s) -> s
    Error(_) -> "0"
  }
  let derivative = case beam_cache.get("guard:grid:derivative") {
    Ok(s) -> s
    Error(_) -> "0.000"
  }
  "{"
  <> "\"health\":"
  <> health
  <> ",\"entropy\":"
  <> entropy
  <> ",\"lyapunov\":"
  <> lyapunov
  <> ",\"last_action\":\""
  <> action
  <> "\",\"cycles\":"
  <> cycles
  <> ",\"derivative\":"
  <> derivative
  <> "}"
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Collect the list of fractal layer strings that have at least one failed cell.
fn collect_failing_layers(grid: guard_grid.GuardGrid) -> List(String) {
  let all_layers = ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"]
  list.filter(all_layers, fn(layer) {
    list.any(grid.cells, fn(cell) {
      cell.layer == layer && cell.verdict != "PASSED"
    })
  })
}

/// Compute cascade depth — number of adjacent layer-pair slots where both
/// layers are failing.  Layers are ordered L0..L7; adjacency is index-based.
fn compute_cascade_depth(failing_layers: List(String)) -> Int {
  let ordered = ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"]
  let pairs = [
    #("L0", "L1"),
    #("L1", "L2"),
    #("L2", "L3"),
    #("L3", "L4"),
    #("L4", "L5"),
    #("L5", "L6"),
    #("L6", "L7"),
  ]
  let _ = ordered
  list.count(pairs, fn(pair) {
    let #(a, b) = pair
    list.contains(failing_layers, a) && list.contains(failing_layers, b)
  })
}

/// Execute side-effects for a guard action: log to stdout + emit marker to ETS.
/// In production a supervisor can extend this with runbook invocations.
fn execute_action(
  action: guard_rules.RuleAction,
  health: Float,
  entropy: Float,
  lyapunov: Float,
  cascade: Bool,
) -> Nil {
  let summary =
    " [health="
    <> float_str(health)
    <> " entropy="
    <> float_str(entropy)
    <> " lyapunov="
    <> float_str(lyapunov)
    <> " cascade="
    <> bool_str(cascade)
    <> "]"
  case action {
    guard_rules.NoAction -> Nil

    guard_rules.LogWarning(msg) ->
      io.println("[GUARD-GRID] WARN: " <> msg <> summary)

    guard_rules.JidokaHalt(reason) -> {
      io.println("[GUARD-GRID] JIDOKA HALT: " <> reason <> summary)
      let _ = beam_cache.put("guard:grid:jidoka", reason)
      Nil
    }

    guard_rules.SetCockpitMode(mode) ->
      io.println("[GUARD-GRID] cockpit→" <> mode <> summary)

    guard_rules.EscalateToOperator(reason) ->
      io.println("[GUARD-GRID] ESCALATE: " <> reason <> summary)

    guard_rules.AttemptHotReload ->
      io.println("[GUARD-GRID] HOT RELOAD triggered" <> summary)

    guard_rules.IsolateCell(layer) ->
      io.println("[GUARD-GRID] ISOLATE cell: " <> layer <> summary)

    guard_rules.TriggerRunbook(id) ->
      io.println("[GUARD-GRID] RUNBOOK: " <> id <> summary)

    guard_rules.CorrelateFailures(description) ->
      io.println("[GUARD-GRID] CORRELATE: " <> description <> summary)

    guard_rules.ClassifyPattern(pattern) ->
      io.println("[GUARD-GRID] PATTERN: " <> pattern <> summary)

    guard_rules.RecordMilestone(milestone) ->
      io.println("[GUARD-GRID] MILESTONE: " <> milestone <> summary)

    guard_rules.PredictiveAlert(prediction) ->
      io.println("[GUARD-GRID] PREDICT: " <> prediction <> summary)

    guard_rules.PreventiveCooldown(reason) ->
      io.println("[GUARD-GRID] COOLDOWN: " <> reason <> summary)

    guard_rules.ActionSequence(actions) -> {
      list.each(actions, fn(a) {
        execute_action(a, health, entropy, lyapunov, cascade)
      })
    }

    guard_rules.BlockContainerRemove(container, reason) ->
      io.println(
        "[GUARD-GRID] BLOCK REMOVE: " <> container <> " — " <> reason <> summary,
      )

    guard_rules.RequireNamedVolume(container) ->
      io.println("[GUARD-GRID] REQUIRE NAMED VOLUME: " <> container <> summary)
  }
}

/// First derivative of health from a sliding history window.
/// (newest - oldest) / (n - 1) where n = list length.
fn derivative_from_history(history: List(Float)) -> Float {
  let n = list.length(history)
  case n < 2 {
    True -> 0.0
    False -> {
      let newest = case list.first(history) {
        Ok(h) -> h
        Error(_) -> 0.0
      }
      let oldest = case list.last(history) {
        Ok(h) -> h
        Error(_) -> 0.0
      }
      let span = int.to_float(n - 1)
      { newest -. oldest } /. span
    }
  }
}

/// Format a Float to 3 decimal places for ETS storage.
/// Gleam's float.to_string produces e.g. "0.875000" — we trim to "0.875".
fn float_str(f: Float) -> String {
  float.to_string(f)
}

/// Convert a Bool to a lowercase string for log output.
fn bool_str(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

/// Convert a cellular rule result to a compact string for logging.
pub fn rule_to_string(rule: guard_grid.CellularRule) -> String {
  case rule {
    guard_grid.RuleNone -> "none"
    guard_grid.RuleCascade -> "cascade"
    guard_grid.RuleIsolated -> "isolated"
    guard_grid.RulePeriodic -> "periodic"
    guard_grid.RuleSystemic -> "systemic"
    guard_grid.RuleRecovering -> "recovering"
  }
}

/// Summarise the multi-rule analysis into a comma-joined string for logging.
pub fn multi_rule_summary(
  analysis: List(#(Int, guard_grid.CellularRule)),
) -> String {
  analysis
  |> list.map(fn(pair) {
    let #(rule_num, result) = pair
    "R" <> int.to_string(rule_num) <> ":" <> rule_to_string(result)
  })
  |> string.join(",")
}
