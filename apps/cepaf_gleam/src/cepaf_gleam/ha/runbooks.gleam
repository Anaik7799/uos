//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/runbooks</module>
////     <fsharp-lineage>None — novel self-healing runbook library (F03)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Automated Runbook Library (F03).
////       Pre-defined, ordered recovery action sequences for each known
////       failure mode in the SIL-6 Biomorphic Mesh. Each runbook encodes
////       operator tribal knowledge as executable intent: trigger → steps → rollback.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-SIL4-001, SC-FUNC-003, SC-MUDA-001, SC-GLM-UI-003</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Operator runbook binder (HTML/PDF) ↪ Gleam ADT with ordered steps.
////       No external I/O in this module — pure catalog + lookup functions.
////       Callers own execution context; this module owns only the intent.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// AUTOMATED RUNBOOK LIBRARY — SELF-HEALING RECOVERY ACTIONS
//// स्वधर्मे निधनं श्रेयः — Better to fail in one's own dharma (Gita 3.35)
////
//// Each Runbook encodes a complete recovery procedure triggered by a specific
//// failure signal. The library ships 10 runbooks covering the most common
//// SIL-6 mesh failure modes:
////
////   RB-001 — NIF Pipeline Recovery        (NIF load failure / crash)
////   RB-002 — Zenoh Session Recovery       (mesh connectivity loss)
////   RB-003 — Cache Corruption Recovery    (stale / invalid cached data)
////   RB-004 — Process Crash Recovery       (unexpected process exit)
////   RB-005 — Circuit Breaker Reset        (open circuit unblocking)
////   RB-006 — SLO Budget Recovery          (error budget exhaustion)
////   RB-007 — Invariant Violation Recovery (structural state corruption)
////   RB-008 — Health Check Failure         (component liveness probe failure)
////   RB-009 — Staleness Recovery           (data freshness threshold breach)
////   RB-010 — Jidoka Emergency Halt        (operator-mandated full stop)
////
//// STAMP: SC-HA-001, SC-SIL4-001, SC-FUNC-003

import gleam/int
import gleam/json
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A complete self-healing runbook: trigger, ordered steps, metadata.
pub type Runbook {
  Runbook(
    /// Stable short identifier, e.g. "RB-001"
    id: String,
    /// Human-readable title, e.g. "NIF Pipeline Recovery"
    name: String,
    /// The signal that activates this runbook
    trigger: RunbookTrigger,
    /// Ordered recovery steps (lowest order first)
    steps: List(RunbookStep),
    /// Fractal layer classification, e.g. "L4_SYSTEM"
    layer: String,
    /// Priority classification: "P0" | "P1" | "P2" | "P3"
    severity: String,
    /// Upper bound on total execution time (sum of step timeouts)
    estimated_duration_ms: Int,
  )
}

/// The signal type that triggers a runbook.
pub type RunbookTrigger {
  /// A structural invariant was violated (e.g. "I-01")
  InvariantViolation(invariant_id: String)
  /// Data freshness exceeded the given threshold
  StalenessDetected(threshold_seconds: Int)
  /// A named component failed its liveness / readiness check
  HealthCheckFailed(component: String)
  /// An SLO's error budget has been fully consumed
  ErrorBudgetExhausted(slo_name: String)
  /// A named circuit breaker has tripped open
  CircuitBreakerOpen(circuit_name: String)
  /// Operator-initiated execution (break-glass procedure)
  ManualTrigger
}

/// A single ordered step within a runbook.
pub type RunbookStep {
  RunbookStep(
    /// Execution order — lower values execute first (1-indexed)
    order: Int,
    /// Human-readable description of what this step does
    description: String,
    /// The concrete action to execute
    action: RunbookAction,
    /// Maximum time to allow for this step before it is considered failed
    timeout_ms: Int,
    /// Whether to roll back all previous steps if this step fails
    rollback_on_failure: Bool,
  )
}

/// Concrete recovery action executed during a runbook step.
pub type RunbookAction {
  /// Trigger BEAM hot-code reload (zero-downtime bytecode swap)
  HotReload
  /// Send SIGTERM / OTP :stop to the named process
  RestartProcess(name: String)
  /// Flush in-memory caches (ETS tables, Smriti FTS5 cache)
  ClearCache
  /// Reload the Rust NIF (.so) pipeline — requires soft purge
  RefreshNifPipeline
  /// Close and re-establish the Zenoh session
  ReconnectZenoh
  /// Promote cockpit display to Emergency mode (Bright/Emergency)
  EscalateToCockpit
  /// Publish an alert message to the Zenoh control plane
  SendAlert(message: String)
  /// Wait for the given period then retry the preceding step
  WaitAndRetry(ms: Int)
  /// Jidoka: halt all operations and require operator intervention
  JidokaHalt
}

// ---------------------------------------------------------------------------
// Catalog
// ---------------------------------------------------------------------------

/// Return the complete runbook library.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Static catalog ↪ List(Runbook)</morphism>
///   <formal-proof>
///     <P> Pre: none </P>
///     <C> all_runbooks() </C>
///     <Q> Post: list.length(result) >= 10, all IDs unique, all step orders >= 1 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn all_runbooks() -> List(Runbook) {
  [
    runbook_rb001_nif_pipeline(),
    runbook_rb002_zenoh_session(),
    runbook_rb003_cache_corruption(),
    runbook_rb004_process_crash(),
    runbook_rb005_circuit_breaker(),
    runbook_rb006_slo_budget(),
    runbook_rb007_invariant_violation(),
    runbook_rb008_health_check(),
    runbook_rb009_staleness(),
    runbook_rb010_jidoka_halt(),
  ]
}

/// Total number of runbooks in the library.
pub fn runbook_count() -> Int {
  list.length(all_runbooks())
}

/// Find the first runbook whose trigger matches the given signal.
///
/// Returns Ok(Runbook) on match, Err("no runbook for trigger") when none found.
pub fn runbook_for_trigger(trigger: RunbookTrigger) -> Result(Runbook, String) {
  case
    list.find(all_runbooks(), fn(rb) { triggers_match(rb.trigger, trigger) })
  {
    Ok(rb) -> Ok(rb)
    Error(Nil) ->
      Error("no runbook for trigger: " <> trigger_to_string(trigger))
  }
}

/// Serialise the full library to a JSON string for API / telemetry output.
pub fn to_json(runbooks: List(Runbook)) -> String {
  json.object([
    #("page", json.string("Runbook Library")),
    #("count", json.int(list.length(runbooks))),
    #("runbooks", json.array(runbooks, runbook_to_json_object)),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// Individual runbook definitions
// ---------------------------------------------------------------------------

fn runbook_rb001_nif_pipeline() -> Runbook {
  Runbook(
    id: "RB-001",
    name: "NIF Pipeline Recovery",
    trigger: HealthCheckFailed("c3i_nif"),
    steps: [
      RunbookStep(
        order: 1,
        description: "Alert operator of NIF failure",
        action: SendAlert("NIF pipeline failure detected — starting RB-001"),
        timeout_ms: 500,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 2,
        description: "Escalate cockpit to Emergency mode",
        action: EscalateToCockpit,
        timeout_ms: 1000,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 3,
        description: "Reload NIF shared library from disk",
        action: RefreshNifPipeline,
        timeout_ms: 5000,
        rollback_on_failure: True,
      ),
      RunbookStep(
        order: 4,
        description: "Restart c3i_nif worker process",
        action: RestartProcess("c3i_nif"),
        timeout_ms: 3000,
        rollback_on_failure: True,
      ),
      RunbookStep(
        order: 5,
        description: "Wait 2s for NIF process to stabilise",
        action: WaitAndRetry(2000),
        timeout_ms: 3000,
        rollback_on_failure: False,
      ),
    ],
    layer: "L4_SYSTEM",
    severity: "P0",
    estimated_duration_ms: 12_500,
  )
}

fn runbook_rb002_zenoh_session() -> Runbook {
  Runbook(
    id: "RB-002",
    name: "Zenoh Session Recovery",
    trigger: HealthCheckFailed("zenoh_session"),
    steps: [
      RunbookStep(
        order: 1,
        description: "Alert: Zenoh connectivity lost",
        action: SendAlert("Zenoh session lost — starting RB-002"),
        timeout_ms: 500,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 2,
        description: "Close existing Zenoh session cleanly",
        action: ReconnectZenoh,
        timeout_ms: 5000,
        rollback_on_failure: True,
      ),
      RunbookStep(
        order: 3,
        description: "Wait 1s for router to accept new connection",
        action: WaitAndRetry(1000),
        timeout_ms: 2000,
        rollback_on_failure: False,
      ),
    ],
    layer: "L6_ECOSYSTEM",
    severity: "P0",
    estimated_duration_ms: 7500,
  )
}

fn runbook_rb003_cache_corruption() -> Runbook {
  Runbook(
    id: "RB-003",
    name: "Cache Corruption Recovery",
    trigger: InvariantViolation("CACHE-001"),
    steps: [
      RunbookStep(
        order: 1,
        description: "Alert: cache inconsistency detected",
        action: SendAlert("Cache corruption detected — starting RB-003"),
        timeout_ms: 500,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 2,
        description: "Flush all in-memory caches",
        action: ClearCache,
        timeout_ms: 2000,
        rollback_on_failure: True,
      ),
      RunbookStep(
        order: 3,
        description: "Trigger hot reload to rebuild module state",
        action: HotReload,
        timeout_ms: 5000,
        rollback_on_failure: True,
      ),
    ],
    layer: "L4_SYSTEM",
    severity: "P1",
    estimated_duration_ms: 7500,
  )
}

fn runbook_rb004_process_crash() -> Runbook {
  Runbook(
    id: "RB-004",
    name: "Process Crash Recovery",
    trigger: HealthCheckFailed("unknown_process"),
    steps: [
      RunbookStep(
        order: 1,
        description: "Alert: unexpected process exit",
        action: SendAlert("Process crash detected — starting RB-004"),
        timeout_ms: 500,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 2,
        description: "Wait 500ms for OTP supervisor to restart process",
        action: WaitAndRetry(500),
        timeout_ms: 1000,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 3,
        description: "Escalate cockpit display to Bright mode",
        action: EscalateToCockpit,
        timeout_ms: 1000,
        rollback_on_failure: False,
      ),
    ],
    layer: "L4_SYSTEM",
    severity: "P1",
    estimated_duration_ms: 2500,
  )
}

fn runbook_rb005_circuit_breaker() -> Runbook {
  Runbook(
    id: "RB-005",
    name: "Circuit Breaker Reset",
    trigger: CircuitBreakerOpen("inference_tier_1"),
    steps: [
      RunbookStep(
        order: 1,
        description: "Alert: circuit breaker tripped open",
        action: SendAlert("Circuit breaker open — starting RB-005"),
        timeout_ms: 500,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 2,
        description: "Wait 60s for circuit breaker cooldown window",
        action: WaitAndRetry(60_000),
        timeout_ms: 65_000,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 3,
        description: "Restart inference process to clear failure state",
        action: RestartProcess("inference_cortex"),
        timeout_ms: 5000,
        rollback_on_failure: True,
      ),
    ],
    layer: "L5_COGNITIVE",
    severity: "P1",
    estimated_duration_ms: 70_500,
  )
}

fn runbook_rb006_slo_budget() -> Runbook {
  Runbook(
    id: "RB-006",
    name: "SLO Error Budget Recovery",
    trigger: ErrorBudgetExhausted("truth_slo"),
    steps: [
      RunbookStep(
        order: 1,
        description: "Alert: error budget exhausted",
        action: SendAlert("SLO error budget exhausted — starting RB-006"),
        timeout_ms: 500,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 2,
        description: "Escalate cockpit to Emergency mode",
        action: EscalateToCockpit,
        timeout_ms: 1000,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 3,
        description: "Flush caches to remove stale truth violations",
        action: ClearCache,
        timeout_ms: 2000,
        rollback_on_failure: True,
      ),
      RunbookStep(
        order: 4,
        description: "Reload NIF pipeline for fresh data path",
        action: RefreshNifPipeline,
        timeout_ms: 5000,
        rollback_on_failure: True,
      ),
    ],
    layer: "L5_COGNITIVE",
    severity: "P0",
    estimated_duration_ms: 8500,
  )
}

fn runbook_rb007_invariant_violation() -> Runbook {
  Runbook(
    id: "RB-007",
    name: "Invariant Violation Recovery",
    trigger: InvariantViolation("I-01"),
    steps: [
      RunbookStep(
        order: 1,
        description: "Alert: structural invariant violated",
        action: SendAlert(
          "Structural invariant violated — starting RB-007 — render blocked",
        ),
        timeout_ms: 500,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 2,
        description: "Escalate cockpit — operator must investigate",
        action: EscalateToCockpit,
        timeout_ms: 1000,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 3,
        description: "Reconnect Zenoh to refresh state from source",
        action: ReconnectZenoh,
        timeout_ms: 5000,
        rollback_on_failure: True,
      ),
      RunbookStep(
        order: 4,
        description: "Hot reload affected modules",
        action: HotReload,
        timeout_ms: 5000,
        rollback_on_failure: True,
      ),
    ],
    layer: "L0_CONSTITUTIONAL",
    severity: "P0",
    estimated_duration_ms: 11_500,
  )
}

fn runbook_rb008_health_check() -> Runbook {
  Runbook(
    id: "RB-008",
    name: "Health Check Failure Recovery",
    trigger: HealthCheckFailed("health_cascade"),
    steps: [
      RunbookStep(
        order: 1,
        description: "Alert: health cascade check failed",
        action: SendAlert("Health check failure — starting RB-008"),
        timeout_ms: 500,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 2,
        description: "Wait 5s for transient failures to resolve",
        action: WaitAndRetry(5000),
        timeout_ms: 6000,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 3,
        description: "Restart affected system process",
        action: RestartProcess("health_cascade"),
        timeout_ms: 3000,
        rollback_on_failure: True,
      ),
    ],
    layer: "L4_SYSTEM",
    severity: "P1",
    estimated_duration_ms: 9500,
  )
}

fn runbook_rb009_staleness() -> Runbook {
  Runbook(
    id: "RB-009",
    name: "Data Staleness Recovery",
    trigger: StalenessDetected(60),
    steps: [
      RunbookStep(
        order: 1,
        description: "Alert: data freshness threshold exceeded",
        action: SendAlert("Data staleness > 60s — starting RB-009"),
        timeout_ms: 500,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 2,
        description: "Flush stale cache entries",
        action: ClearCache,
        timeout_ms: 2000,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 3,
        description: "Reconnect Zenoh to pull fresh telemetry",
        action: ReconnectZenoh,
        timeout_ms: 5000,
        rollback_on_failure: True,
      ),
    ],
    layer: "L1_ATOMIC_DEBUG",
    severity: "P2",
    estimated_duration_ms: 7500,
  )
}

fn runbook_rb010_jidoka_halt() -> Runbook {
  Runbook(
    id: "RB-010",
    name: "Jidoka Emergency Halt",
    trigger: ManualTrigger,
    steps: [
      RunbookStep(
        order: 1,
        description: "Alert all channels: operator-initiated halt",
        action: SendAlert(
          "JIDOKA HALT initiated by operator — all operations stopping",
        ),
        timeout_ms: 500,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 2,
        description: "Escalate cockpit to Emergency mode",
        action: EscalateToCockpit,
        timeout_ms: 1000,
        rollback_on_failure: False,
      ),
      RunbookStep(
        order: 3,
        description: "Halt all OODA loops — operator intervention required",
        action: JidokaHalt,
        timeout_ms: 5000,
        rollback_on_failure: False,
      ),
    ],
    layer: "L0_CONSTITUTIONAL",
    severity: "P0",
    estimated_duration_ms: 6500,
  )
}

// ---------------------------------------------------------------------------
// Trigger matching
// ---------------------------------------------------------------------------

/// Return True when two RunbookTrigger values represent the same signal class.
/// For parameterised triggers only the constructor tag is compared, not the payload.
fn triggers_match(a: RunbookTrigger, b: RunbookTrigger) -> Bool {
  case a, b {
    InvariantViolation(_), InvariantViolation(_) -> True
    StalenessDetected(_), StalenessDetected(_) -> True
    HealthCheckFailed(c1), HealthCheckFailed(c2) -> c1 == c2
    ErrorBudgetExhausted(s1), ErrorBudgetExhausted(s2) -> s1 == s2
    CircuitBreakerOpen(n1), CircuitBreakerOpen(n2) -> n1 == n2
    ManualTrigger, ManualTrigger -> True
    _, _ -> False
  }
}

// ---------------------------------------------------------------------------
// JSON serialisation helpers
// ---------------------------------------------------------------------------

fn runbook_to_json_object(rb: Runbook) -> json.Json {
  json.object([
    #("id", json.string(rb.id)),
    #("name", json.string(rb.name)),
    #("trigger", json.string(trigger_to_string(rb.trigger))),
    #("layer", json.string(rb.layer)),
    #("severity", json.string(rb.severity)),
    #("step_count", json.int(list.length(rb.steps))),
    #("estimated_duration_ms", json.int(rb.estimated_duration_ms)),
    #("steps", json.array(rb.steps, step_to_json_object)),
  ])
}

fn step_to_json_object(s: RunbookStep) -> json.Json {
  json.object([
    #("order", json.int(s.order)),
    #("description", json.string(s.description)),
    #("action", json.string(action_to_string(s.action))),
    #("timeout_ms", json.int(s.timeout_ms)),
    #("rollback_on_failure", json.bool(s.rollback_on_failure)),
  ])
}

fn trigger_to_string(t: RunbookTrigger) -> String {
  case t {
    InvariantViolation(id) -> "invariant_violation:" <> id
    StalenessDetected(s) -> "staleness_detected:" <> int.to_string(s) <> "s"
    HealthCheckFailed(c) -> "health_check_failed:" <> c
    ErrorBudgetExhausted(s) -> "error_budget_exhausted:" <> s
    CircuitBreakerOpen(n) -> "circuit_breaker_open:" <> n
    ManualTrigger -> "manual_trigger"
  }
}

fn action_to_string(a: RunbookAction) -> String {
  case a {
    HotReload -> "hot_reload"
    RestartProcess(name) -> "restart_process:" <> name
    ClearCache -> "clear_cache"
    RefreshNifPipeline -> "refresh_nif_pipeline"
    ReconnectZenoh -> "reconnect_zenoh"
    EscalateToCockpit -> "escalate_to_cockpit"
    SendAlert(msg) -> "send_alert:" <> string.slice(msg, 0, 40)
    WaitAndRetry(ms) -> "wait_and_retry:" <> int.to_string(ms) <> "ms"
    JidokaHalt -> "jidoka_halt"
  }
}
