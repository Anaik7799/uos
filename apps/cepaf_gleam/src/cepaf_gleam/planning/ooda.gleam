//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/planning/ooda</module>
////     <fsharp-lineage>Cepaf.OodaController.fs</fsharp-lineage></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><criticality>DAL-A / SIL-6</criticality>
////     <stamp-controls>SC-OODA-001, SC-ORCH-004</stamp-controls></compliance>
//// </c3i-module>

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string

// =============================================================================
// Type Definitions — OODA Cybernetic Control Loop
// =============================================================================

/// Observation severity levels for the OODA observe phase.
pub type Severity {
  Info
  Warning
  Critical
}

/// A single observation from the system (health check, metric, event).
pub type Observation {
  Observation(
    source: String,
    message: String,
    severity: Severity,
    timestamp: String,
  )
}

/// Recognised patterns from the orient phase.
pub type Pattern {
  HealthDegradation
  ContainerStartup
  ContainerFailure
  ResourceExhaustion
  NetworkIssue
  DependencyFailure
  SecurityViolation
  UnknownPattern
}

/// How wide-reaching the detected issue is.
pub type ImpactScope {
  SingleContainer
  System
}

/// Orient phase output — classified assessment of observations.
pub type Assessment {
  Assessment(
    pattern: Pattern,
    observations: List(Observation),
    impact: ImpactScope,
  )
}

/// Action types the OODA controller can decide to execute.
pub type ActionType {
  NoAction
  WaitAndRetry(duration_ms: Int)
  RestartContainer(name: String)
  StopContainer(name: String)
  ApplyPatch(from: String, to: String)
  AbortPipeline
  EmergencyStop
  Alert(message: String)
}

/// Decide phase output — a scored, reasoned action selection.
pub type Decision {
  Decision(action: ActionType, score: Float, reason: String)
}

/// Complete OODA cycle record for telemetry and audit.
pub type OodaCycle {
  OodaCycle(
    observations: List(Observation),
    assessment: Assessment,
    decision: Decision,
    cycle_time_ms: Int,
  )
}

// =============================================================================
// 1. observe_from_health — Health check → Observation
// =============================================================================

/// Convert a container health status string into an Observation.
/// Healthy→Info, Unhealthy→Critical, NoHealthcheck→Warning.
pub fn observe_from_health(status: String) -> Observation {
  let #(severity, message) = case string.lowercase(status) {
    "healthy" -> #(Info, "Container health check passed")
    "unhealthy" -> #(Critical, "Container health check FAILED")
    "nohealthcheck" -> #(Warning, "Container has no health check configured")
    _ -> #(Warning, "Unknown health status: " <> status)
  }
  Observation(
    source: "health_check",
    message: message,
    severity: severity,
    timestamp: "",
  )
}

// =============================================================================
// 2. observe_from_metric — Metric threshold breach → Observation
// =============================================================================

/// Create an Observation from a named metric when it breaches a threshold.
pub fn observe_from_metric(
  name: String,
  value: Float,
  threshold: Float,
) -> Observation {
  case value >. threshold {
    True ->
      Observation(
        source: "metric/" <> name,
        message: name
          <> " = "
          <> float.to_string(value)
          <> " exceeds threshold "
          <> float.to_string(threshold),
        severity: Warning,
        timestamp: "",
      )
    False ->
      Observation(
        source: "metric/" <> name,
        message: name
          <> " = "
          <> float.to_string(value)
          <> " within threshold "
          <> float.to_string(threshold),
        severity: Info,
        timestamp: "",
      )
  }
}

// =============================================================================
// 3. observe_from_event — Generic event → Observation
// =============================================================================

/// Wrap an arbitrary source/message pair as an Info-level Observation.
pub fn observe_from_event(source: String, message: String) -> Observation {
  Observation(source: source, message: message, severity: Info, timestamp: "")
}

// =============================================================================
// TPS Optimization — Cybernetic Performance (SC-OODA-TPS-001)
// =============================================================================

pub type TPSObjective {
  TPSObjective(target_tps: Int, current_tps: Float, efficiency: Float)
}

/// A single OODA process execution, now designed for asynchronous pipelining.
/// Decouples ingress (Observe/Orient) from egress (Decide/Act).
pub fn run_async_cycle(
  observations: List(Observation),
  _objective: TPSObjective,
) -> OodaCycle {
  // Cycle metrics would be tracked here in a real integration
  let cycle_time = 10
  // ms simulation

  let assessment = orient(observations)
  let decision = decide(assessment)

  // Decoupled Act phase - in a real actor-based system, this would be an async message
  let _ = act(decision)

  OodaCycle(
    observations: observations,
    assessment: assessment,
    decision: decision,
    cycle_time_ms: cycle_time,
  )
}

pub fn calculate_efficiency(obj: TPSObjective) -> Float {
  case obj.target_tps {
    0 -> 1.0
    target -> obj.current_tps /. int.to_float(target)
  }
}

// =============================================================================
// 4. orient — Classify observations into an Assessment
// =============================================================================

/// Orient phase: classify a list of observations into a Pattern and
/// determine the ImpactScope.
pub fn orient(observations: List(Observation)) -> Assessment {
  let pattern = case observations {
    [] -> UnknownPattern
    [first, ..rest] -> {
      let base_pattern = classify_observation(first)
      // If there are mixed critical signals, escalate
      let has_critical =
        list.any([first, ..rest], fn(o) {
          case o.severity {
            Critical -> True
            _ -> False
          }
        })
      case has_critical {
        True ->
          case base_pattern {
            UnknownPattern -> HealthDegradation
            other -> other
          }
        False -> base_pattern
      }
    }
  }

  let critical_count =
    list.count(observations, fn(o) {
      case o.severity {
        Critical -> True
        _ -> False
      }
    })

  let impact = case critical_count > 1 {
    True -> System
    False -> SingleContainer
  }

  Assessment(pattern: pattern, observations: observations, impact: impact)
}

/// Classify a single observation by inspecting its message content.
fn classify_observation(obs: Observation) -> Pattern {
  classify_error(obs.message)
}

// =============================================================================
// 5. classify_error — High-Performance Pattern Matcher (SC-OODA-TPS-002)
// =============================================================================

const error_patterns = [
  #(["segfault", "sigsegv", "crashed", "exited with code"], ContainerFailure),
  #(
    ["oom", "out of memory", "disk full", "resource exhausted"],
    ResourceExhaustion,
  ),
  #(
    ["port conflict", "connection refused", "timeout", "network unreachable"],
    NetworkIssue,
  ),
  #(["db init", "database", "dependency", "missing module"], DependencyFailure),
  #(["permission", "denied", "unauthorized", "forbidden"], SecurityViolation),
  #(["health check failed", "unhealthy", "degraded"], HealthDegradation),
  #(["starting", "initializing", "typo"], ContainerStartup),
]

/// Optimized error classification using single-pass logic to reduce string allocations.
pub fn classify_error(message: String) -> Pattern {
  let lower = string.lowercase(message)

  error_patterns
  |> list.find_map(fn(pattern_tuple) {
    let #(keywords, pattern) = pattern_tuple
    case list.any(keywords, fn(k) { string.contains(lower, k) }) {
      True -> Ok(pattern)
      False -> Error(Nil)
    }
  })
  |> result.unwrap(UnknownPattern)
}

// =============================================================================
// 7. act_fix — Autonomous System Repair (SC-ORCH-004)
// =============================================================================

@external(erlang, "cepaf_gleam_ffi", "os_cmd")
fn os_cmd(cmd: String) -> String

/// Execute a recovery action directly via L0 substrate FFI for autonomous fixing.
pub fn act_fix(action: ActionType) -> String {
  case action {
    RestartContainer(name) -> {
      io.println("OODA: Autonomous Fix -> Restarting container: " <> name)
      os_cmd("podman restart " <> name)
    }
    EmergencyStop -> {
      io.println("OODA: Autonomous Fix -> EMERGENCY DRAIN ACTIVATED")
      os_cmd("podman stop --all")
    }
    Alert(msg) -> {
      io.println("OODA: Alert -> " <> msg)
      "Alert sent"
    }
    _ -> "No autonomous effector for action type"
  }
}

// =============================================================================
// 6. decide — Select best action from assessment
// =============================================================================

/// Decide phase: given an Assessment, produce a scored Decision.
pub fn decide(assessment: Assessment) -> Decision {
  case assessment.observations {
    // No observations — nothing to do
    [] ->
      Decision(
        action: NoAction,
        score: score_action(NoAction),
        reason: "No observations — system nominal",
      )
    // Single observation — targeted response
    [single] -> decide_single(single, assessment)
    // Multiple observations — check for criticality escalation
    _multiple -> decide_multiple(assessment)
  }
}

/// Decide for a single observation based on its pattern.
fn decide_single(obs: Observation, assessment: Assessment) -> Decision {
  case obs.severity {
    Critical -> {
      let action = action_for_pattern(assessment.pattern)
      Decision(
        action: action,
        score: score_action(action),
        reason: "Critical observation: " <> obs.message,
      )
    }
    Warning -> {
      let action = WaitAndRetry(duration_ms: 5000)
      Decision(
        action: action,
        score: score_action(action),
        reason: "Warning — retry after cooldown: " <> obs.message,
      )
    }
    Info ->
      Decision(
        action: NoAction,
        score: score_action(NoAction),
        reason: "Informational only: " <> obs.message,
      )
  }
}

/// Decide when there are multiple observations.
fn decide_multiple(assessment: Assessment) -> Decision {
  let critical_count =
    list.count(assessment.observations, fn(o) {
      case o.severity {
        Critical -> True
        _ -> False
      }
    })

  case critical_count {
    // Multiple criticals → EmergencyStop
    n if n > 1 ->
      Decision(
        action: EmergencyStop,
        score: score_action(EmergencyStop),
        reason: "Multiple critical observations ("
          <> int.to_string(n)
          <> ") — emergency stop",
      )
    // Exactly one critical among many — targeted action
    1 -> {
      let action = action_for_pattern(assessment.pattern)
      Decision(
        action: action,
        score: score_action(action),
        reason: "Single critical in batch — targeted response for "
          <> pattern_to_string(assessment.pattern),
      )
    }
    // No criticals — just monitor
    _ ->
      Decision(
        action: WaitAndRetry(duration_ms: 3000),
        score: score_action(WaitAndRetry(duration_ms: 3000)),
        reason: "Multiple warnings — monitoring with retry",
      )
  }
}

/// Map a Pattern to its default remediation action.
fn action_for_pattern(pattern: Pattern) -> ActionType {
  case pattern {
    ContainerFailure -> RestartContainer(name: "unknown")
    ResourceExhaustion -> StopContainer(name: "unknown")
    NetworkIssue -> WaitAndRetry(duration_ms: 10_000)
    DependencyFailure -> AbortPipeline
    SecurityViolation -> EmergencyStop
    HealthDegradation -> RestartContainer(name: "unknown")
    ContainerStartup -> WaitAndRetry(duration_ms: 5000)
    UnknownPattern -> Alert(message: "Unknown pattern detected")
  }
}

// =============================================================================
// 7. score_action — Impact × (1−Risk) / Effort heuristic
// =============================================================================

/// Score an action using the Impact × (1−Risk) / Effort formula.
pub fn score_action(action: ActionType) -> Float {
  let #(impact, risk, effort) = case action {
    NoAction -> #(0.0, 0.0, 1.0)
    WaitAndRetry(_) -> #(0.3, 0.1, 1.0)
    RestartContainer(_) -> #(0.8, 0.3, 2.0)
    StopContainer(_) -> #(0.7, 0.5, 1.5)
    ApplyPatch(_, _) -> #(0.9, 0.4, 3.0)
    AbortPipeline -> #(0.6, 0.6, 1.0)
    EmergencyStop -> #(1.0, 0.8, 1.0)
    Alert(_) -> #(0.2, 0.0, 1.0)
  }
  // Impact × (1 − Risk) / Effort
  { impact *. { 1.0 -. risk } } /. effort
}

// =============================================================================
// 8. act — Execute a decision (stub implementations)
// =============================================================================

/// Act phase: execute the decided action. Returns Ok(description) on
/// success or Error(reason) on failure. Currently stub implementations.
pub fn act(decision: Decision) -> Result(String, String) {
  case decision.action {
    NoAction -> Ok("No action required")
    WaitAndRetry(ms) -> Ok("Waiting " <> int.to_string(ms) <> "ms before retry")
    RestartContainer(name) -> Ok("Restart signal sent to container: " <> name)
    StopContainer(name) -> Ok("Stop signal sent to container: " <> name)
    ApplyPatch(from, to) -> Ok("Patch applied: " <> from <> " -> " <> to)
    AbortPipeline -> Ok("Pipeline aborted")
    EmergencyStop ->
      Error("EMERGENCY STOP executed — manual intervention required")
    Alert(msg) -> Ok("Alert raised: " <> msg)
  }
}

// =============================================================================
// 9. run_cycle — Full O→O→D→A pipeline
// =============================================================================

/// Run a complete OODA cycle: Observe (already done) → Orient → Decide → Act.
/// Returns the full OodaCycle record for audit and telemetry.
pub fn run_cycle(observations: List(Observation)) -> OodaCycle {
  // Orient
  let assessment = orient(observations)
  // Decide
  let decision = decide(assessment)
  // Act (side-effects, result captured but cycle always completes)
  let _act_result = act(decision)
  // Cycle time is synthetic in this stub — real impl uses monotonic clock
  let cycle_time_ms = 1

  OodaCycle(
    observations: observations,
    assessment: assessment,
    decision: decision,
    cycle_time_ms: cycle_time_ms,
  )
}

// =============================================================================
// 10. get_cycle_metrics — Extract metrics Dict from a cycle
// =============================================================================

/// Extract key metrics from a completed OodaCycle as a string Dict.
pub fn get_cycle_metrics(cycle: OodaCycle) -> Dict(String, String) {
  let observation_count = list.length(cycle.observations)
  let critical_count =
    list.count(cycle.observations, fn(o) {
      case o.severity {
        Critical -> True
        _ -> False
      }
    })

  dict.from_list([
    #("observation_count", int.to_string(observation_count)),
    #("critical_count", int.to_string(critical_count)),
    #("pattern", pattern_to_string(cycle.assessment.pattern)),
    #("impact", impact_to_string(cycle.assessment.impact)),
    #("action", action_type_to_string(cycle.decision.action)),
    #("score", float.to_string(cycle.decision.score)),
    #("cycle_time_ms", int.to_string(cycle.cycle_time_ms)),
    #("reason", cycle.decision.reason),
  ])
}

// =============================================================================
// 11. is_healthy — No critical observations in the cycle
// =============================================================================

/// Returns True if the cycle contains no Critical-severity observations.
pub fn is_healthy(cycle: OodaCycle) -> Bool {
  list.all(cycle.observations, fn(o) {
    case o.severity {
      Critical -> False
      _ -> True
    }
  })
}

// =============================================================================
// 12. cycle_to_json — Serialize for AG-UI STATE_SNAPSHOT
// =============================================================================

/// Serialize a complete OodaCycle to JSON for AG-UI STATE_SNAPSHOT events.
pub fn cycle_to_json(cycle: OodaCycle) -> json.Json {
  json.object([
    #(
      "observations",
      json.array(cycle.observations, fn(o) {
        json.object([
          #("source", json.string(o.source)),
          #("message", json.string(o.message)),
          #("severity", json.string(severity_to_string(o.severity))),
          #("timestamp", json.string(o.timestamp)),
        ])
      }),
    ),
    #(
      "assessment",
      json.object([
        #("pattern", json.string(pattern_to_string(cycle.assessment.pattern))),
        #("impact", json.string(impact_to_string(cycle.assessment.impact))),
        #(
          "observation_count",
          json.int(list.length(cycle.assessment.observations)),
        ),
      ]),
    ),
    #(
      "decision",
      json.object([
        #("action", json.string(action_type_to_string(cycle.decision.action))),
        #("score", json.float(cycle.decision.score)),
        #("reason", json.string(cycle.decision.reason)),
      ]),
    ),
    #("cycle_time_ms", json.int(cycle.cycle_time_ms)),
  ])
}

// =============================================================================
// String serialization helpers (exhaustive pattern matching per SC-GLM-CORE-003)
// =============================================================================

fn severity_to_string(severity: Severity) -> String {
  case severity {
    Info -> "info"
    Warning -> "warning"
    Critical -> "critical"
  }
}

fn pattern_to_string(pattern: Pattern) -> String {
  case pattern {
    HealthDegradation -> "health_degradation"
    ContainerStartup -> "container_startup"
    ContainerFailure -> "container_failure"
    ResourceExhaustion -> "resource_exhaustion"
    NetworkIssue -> "network_issue"
    DependencyFailure -> "dependency_failure"
    SecurityViolation -> "security_violation"
    UnknownPattern -> "unknown_pattern"
  }
}

fn impact_to_string(scope: ImpactScope) -> String {
  case scope {
    SingleContainer -> "single_container"
    System -> "system"
  }
}

fn action_type_to_string(action: ActionType) -> String {
  case action {
    NoAction -> "no_action"
    WaitAndRetry(ms) -> "wait_and_retry(" <> int.to_string(ms) <> "ms)"
    RestartContainer(name) -> "restart_container(" <> name <> ")"
    StopContainer(name) -> "stop_container(" <> name <> ")"
    ApplyPatch(from, to) -> "apply_patch(" <> from <> " -> " <> to <> ")"
    AbortPipeline -> "abort_pipeline"
    EmergencyStop -> "emergency_stop"
    Alert(msg) -> "alert(" <> msg <> ")"
  }
}
