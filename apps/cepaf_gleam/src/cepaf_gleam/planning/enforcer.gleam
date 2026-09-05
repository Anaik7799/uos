//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/planning/enforcer</module>
////     <fsharp-lineage>Cepaf.Core.Enforcer.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <mesh-domain>Robustness, Impact Analysis</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / CRITICAL</criticality>
////     <stamp-controls>SC-ENFORCE-001 to SC-ENFORCE-025</stamp-controls>
////     <aor-rules>AOR-ENFORCE-001 to AOR-ENFORCE-015</aor-rules>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       F# Record `RequestContext` ≅ Gleam Type `RequestContext`
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/core/types.{type Timestamp}
import cepaf_gleam/planning/safety_kernel.{type ProofToken}
import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string

pub type AgentType {
  Human(user_id: String)
  AIAgent(agent_id: String, model: String)
  SystemProcess(process_id: String)
  UnknownAgent(identifier: String)
}

pub type RequestContext {
  RequestContext(
    agent_type: AgentType,
    requested_path: String,
    operation: String,
    timestamp: Timestamp,
    stack_trace: Option(String),
    ip_address: Option(String),
    additional_context: Dict(String, String),
    proof_token: Option(ProofToken),
  )
}

pub type ViolationRecord {
  ViolationRecord(
    id: String,
    context: RequestContext,
    reason: String,
    severity: String,
    timestamp: Timestamp,
    blocked_by_circuit: Bool,
  )
}

pub type AccessDecision {
  Allowed(reason: String)
  Denied(reason: String, violation: ViolationRecord)
  CircuitOpen(agent_id: String, violation_count: Int)
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">
///     val enforceAccess : RequestContext -> int -> int -> AccessDecision
///   </morphism>
///   <formal-proof>
///     <P> Pre: RequestContext parsed, Mesh state stable. </P>
///     <C> enforce_access(ctx, violation_count, circuit_threshold) </C>
///     <Q> Post: Returns AccessDecision. Will open circuit if violations >= threshold. </Q>
///   </formal-proof>
///   <semantic-note>
///     Replaces F# Active Patterns with nested Gleam `case` switching on boolean logic 
///     and Result states to achieve exhaustive verification.
///   </semantic-note>
/// </c3i-atomic>
pub fn enforce_access(
  ctx: RequestContext,
  violation_count: Int,
  circuit_threshold: Int,
) -> AccessDecision {
  case validate_request(ctx) {
    Ok(_) -> Allowed("All validation layers passed")
    Error(reason) -> {
      let is_blocked = violation_count >= circuit_threshold

      case is_blocked {
        True -> {
          CircuitOpen(
            agent_id: extract_agent_id(ctx.agent_type),
            violation_count: violation_count,
          )
        }
        False -> {
          let violation =
            ViolationRecord(
              id: "violation_id",
              // Should be unique
              context: ctx,
              reason: reason,
              severity: calculate_severity(reason),
              timestamp: ctx.timestamp,
              blocked_by_circuit: False,
            )
          Denied(reason: reason, violation: violation)
        }
      }
    }
  }
}

fn extract_agent_id(agent_type: AgentType) -> String {
  case agent_type {
    Human(id) -> "human:" <> id
    AIAgent(id, model) -> "ai:" <> id <> ":" <> model
    SystemProcess(id) -> "system:" <> id
    UnknownAgent(id) -> "unknown:" <> id
  }
}

fn calculate_severity(reason: String) -> String {
  case string.contains(reason, "SC-TODO-001") {
    True -> "CRITICAL"
    False -> "HIGH"
  }
}

fn validate_request(ctx: RequestContext) -> Result(Nil, String) {
  let path = string.lowercase(ctx.requested_path)
  let is_todolist = string.contains(path, "project_todolist.md")

  case is_todolist, ctx.agent_type {
    True, Human(_) ->
      Error(
        "SC-TODO-001 VIOLATION: Direct manual modification of PROJECT_TODOLIST.md is strictly PROHIBITED.",
      )
    True, UnknownAgent(_) ->
      Error(
        "SC-TODO-001 VIOLATION: Anonymous modification of PROJECT_TODOLIST.md is strictly PROHIBITED.",
      )
    True, _ -> {
      // AI or System must have a valid ProofToken
      case ctx.proof_token {
        option.None ->
          Error(
            "SC-TODO-001 VIOLATION: Modification of PROJECT_TODOLIST.md requires a valid Prometheus ProofToken.",
          )
        option.Some(token) -> {
          safety_kernel.validate_proof_token(
            token,
            ctx.operation,
            extract_agent_id(ctx.agent_type),
            ctx.timestamp,
            300_000,
            // 5 minutes
          )
        }
      }
    }
    False, AIAgent(_, _) | False, SystemProcess(_) -> {
      // Agents and System should always have a token for any operation
      case ctx.proof_token {
        option.None ->
          Error(
            "UNAUTHORIZED: Operation "
            <> ctx.operation
            <> " by "
            <> extract_agent_id(ctx.agent_type)
            <> " requires a valid ProofToken.",
          )
        option.Some(token) -> {
          safety_kernel.validate_proof_token(
            token,
            ctx.operation,
            extract_agent_id(ctx.agent_type),
            ctx.timestamp,
            300_000,
          )
        }
      }
    }
    False, UnknownAgent(_) -> Error("Unknown agents are denied by default")
    False, Human(_) -> Ok(Nil)
  }
}

// =============================================================================
// LAYER 1: AGENT CLASSIFICATION (SC-ENFORCE-003, AOR-ENFORCE-001)
// =============================================================================

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">
///     val classifyAgent : string -> AgentType
///   </morphism>
///   <formal-proof>
///     <P> Pre: identifier is a non-empty colon-delimited string. </P>
///     <C> classify_agent(identifier) </C>
///     <Q> Post: Returns one of Human, AIAgent, SystemProcess, or UnknownAgent.
///         Classification is deterministic and total. </Q>
///   </formal-proof>
///   <semantic-note>
///     Ports F# `classifyAgent` heuristic matching. Uses string prefix
///     conventions ("human:", "ai:", "system:") for structured identifiers,
///     with user-agent heuristics as fallback.
///   </semantic-note>
/// </c3i-atomic>
pub fn classify_agent(identifier: String) -> AgentType {
  let lower = string.lowercase(identifier)
  case string.split(lower, ":") {
    ["human", user_id] -> Human(user_id)
    ["human", user_id, ..rest] ->
      Human(user_id <> ":" <> string.join(rest, ":"))
    ["ai", agent_id, model] -> AIAgent(agent_id, model)
    ["ai", agent_id] -> AIAgent(agent_id, "unknown")
    ["system", process_id] -> SystemProcess(process_id)
    ["system", process_id, ..rest] ->
      SystemProcess(process_id <> ":" <> string.join(rest, ":"))
    _ -> {
      // Heuristic classification (AOR-ENFORCE-008)
      case
        string.contains(lower, "claude"),
        string.contains(lower, "gpt"),
        string.contains(lower, "gemini"),
        string.contains(lower, "grok")
      {
        True, _, _, _ -> AIAgent("heuristic", identifier)
        _, True, _, _ -> AIAgent("heuristic", identifier)
        _, _, True, _ -> AIAgent("heuristic", identifier)
        _, _, _, True -> AIAgent("heuristic", identifier)
        False, False, False, False -> {
          case
            string.contains(lower, "elixir"),
            string.contains(lower, "beam"),
            string.contains(lower, "erlang"),
            string.contains(lower, "dotnet"),
            string.contains(lower, "fsharp")
          {
            True, _, _, _, _ -> SystemProcess("elixir-runtime")
            _, True, _, _, _ -> SystemProcess("beam-runtime")
            _, _, True, _, _ -> SystemProcess("erlang-runtime")
            _, _, _, True, _ -> SystemProcess("fsharp-runtime")
            _, _, _, _, True -> SystemProcess("fsharp-runtime")
            False, False, False, False, False -> UnknownAgent(identifier)
          }
        }
      }
    }
  }
}

// =============================================================================
// LAYER 2: RATE LIMITING (SC-ENFORCE-018, AOR-ENFORCE-009)
// =============================================================================

/// Immutable rate limit state tracking request counts per agent within a
/// time window. The window_start is an ISO-8601 timestamp string.
pub type RateLimitState {
  RateLimitState(counts: Dict(String, Int), window_start: String)
}

/// Create a fresh rate limit state with empty counts.
pub fn new_rate_limit_state() -> RateLimitState {
  RateLimitState(counts: dict.new(), window_start: "")
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">
///     val checkRateLimit : RateLimitState -> string -> int -> Result(RateLimitState, string)
///   </morphism>
///   <formal-proof>
///     <P> Pre: state is a valid RateLimitState, max_per_window > 0. </P>
///     <C> check_rate_limit(state, agent_id, max_per_window) </C>
///     <Q> Post: Ok(new_state) with incremented count if under limit,
///         Error(reason) if agent exceeds max_per_window. State is immutable. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn check_rate_limit(
  state: RateLimitState,
  agent_id: String,
  max_per_window: Int,
) -> Result(RateLimitState, String) {
  let current_count = case dict.get(state.counts, agent_id) {
    Ok(count) -> count
    Error(Nil) -> 0
  }
  case current_count >= max_per_window {
    True ->
      Error(
        "Rate limit exceeded for agent "
        <> agent_id
        <> " (max "
        <> int.to_string(max_per_window)
        <> "/window)",
      )
    False -> {
      let new_counts = dict.insert(state.counts, agent_id, current_count + 1)
      Ok(RateLimitState(..state, counts: new_counts))
    }
  }
}

// =============================================================================
// LAYER 3: CIRCUIT BREAKER MANAGEMENT
// (SC-ENFORCE-004, SC-ENFORCE-013, AOR-ENFORCE-004, AOR-ENFORCE-010)
// =============================================================================

/// Record a new violation to the immutable audit trail.
/// SC-ENFORCE-002: All access attempts MUST be logged.
/// SC-ENFORCE-006: Audit trail MUST be append-only.
pub fn record_violation(
  agent_id: String,
  context: RequestContext,
  reason: String,
  severity: String,
) -> ViolationRecord {
  ViolationRecord(
    id: "v_" <> agent_id <> "_" <> context.timestamp,
    context: context,
    reason: reason,
    severity: severity,
    timestamp: context.timestamp,
    blocked_by_circuit: False,
  )
}

/// Count how many violations exist for a specific agent.
pub fn get_violation_count(
  violations: List(ViolationRecord),
  agent_id: String,
) -> Int {
  list.fold(violations, 0, fn(acc, v) {
    case extract_agent_id(v.context.agent_type) == agent_id {
      True -> acc + 1
      False -> acc
    }
  })
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">
///     val isCircuitOpen : List(ViolationRecord) -> string -> int -> bool
///   </morphism>
///   <formal-proof>
///     <P> Pre: threshold > 0, violations is a valid list. </P>
///     <C> is_circuit_open(violations, agent_id, threshold) </C>
///     <Q> Post: True iff get_violation_count(violations, agent_id) >= threshold.
///         Deterministic, side-effect free. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn is_circuit_open(
  violations: List(ViolationRecord),
  agent_id: String,
  threshold: Int,
) -> Bool {
  get_violation_count(violations, agent_id) >= threshold
}

/// Reset the circuit breaker for a specific agent by removing all their
/// violations from the list. Returns a new filtered list.
/// SC-ENFORCE-013: Circuit breaker reset MUST require manual intervention.
pub fn reset_circuit_breaker(
  violations: List(ViolationRecord),
  agent_id: String,
) -> List(ViolationRecord) {
  list.filter(violations, fn(v) {
    case extract_agent_id(v.context.agent_type) == agent_id {
      True -> False
      False -> True
    }
  })
}

/// Get a list of all agent IDs whose circuit breakers are open
/// (violation count >= threshold).
pub fn get_circuit_open_agents(
  violations: List(ViolationRecord),
  threshold: Int,
) -> List(String) {
  // Collect unique agent IDs
  let agent_ids =
    list.fold(violations, dict.new(), fn(acc, v) {
      let aid = extract_agent_id(v.context.agent_type)
      let count = case dict.get(acc, aid) {
        Ok(c) -> c + 1
        Error(Nil) -> 1
      }
      dict.insert(acc, aid, count)
    })
  // Filter to those at or above threshold
  dict.fold(agent_ids, [], fn(acc, aid, count) {
    case count >= threshold {
      True -> [aid, ..acc]
      False -> acc
    }
  })
}

// =============================================================================
// LAYER 4: PATH VALIDATION (SC-ENFORCE-010, SC-ENFORCE-011, AOR-ENFORCE-007)
// =============================================================================

/// Check if a given path matches any of the forbidden patterns.
/// SC-ENFORCE-010: File path validation MUST be case-insensitive.
/// AOR-ENFORCE-007: VALIDATE all file paths against forbidden list.
pub fn is_forbidden_path(path: String, forbidden_patterns: List(String)) -> Bool {
  let lower_path = string.lowercase(path)
  list.any(forbidden_patterns, fn(pattern) {
    let lower_pattern = string.lowercase(pattern)
    case string.contains(lower_path, lower_pattern) {
      True -> True
      False -> False
    }
  })
}

// =============================================================================
// LAYER 5: BEHAVIORAL ANALYSIS (SC-ENFORCE-023, AOR-ENFORCE-008, AOR-ENFORCE-015)
// =============================================================================

/// Detect suspicious patterns by checking whether an agent has accumulated
/// a high density of violations. The time_window_seconds parameter defines
/// the analysis window; if the agent has 3+ violations with severity
/// "CRITICAL" or "HIGH", the pattern is flagged as suspicious.
///
/// Note: Since Timestamp is a String type, this performs structural analysis
/// on violation density rather than temporal windowing. A full temporal
/// implementation requires Erlang FFI for monotonic time comparison.
pub fn detect_suspicious_pattern(
  violations: List(ViolationRecord),
  agent_id: String,
  _time_window_seconds: Int,
) -> Bool {
  let agent_violations =
    list.filter(violations, fn(v) {
      case extract_agent_id(v.context.agent_type) == agent_id {
        True -> True
        False -> False
      }
    })
  let severe_count =
    list.fold(agent_violations, 0, fn(acc, v) {
      case v.severity {
        "CRITICAL" -> acc + 1
        "HIGH" -> acc + 1
        "MEDIUM" -> acc
        "LOW" -> acc
        _ -> acc
      }
    })
  // Suspicious if 3+ severe violations from the same agent
  severe_count >= 3
}

// =============================================================================
// QUERY & REPORTING (SC-ENFORCE-016, AOR-ENFORCE-012)
// =============================================================================

/// Get all violations for a specific agent, filtered by agent_id.
pub fn get_agent_violations(
  violations: List(ViolationRecord),
  agent_id: String,
) -> List(ViolationRecord) {
  list.filter(violations, fn(v) {
    case extract_agent_id(v.context.agent_type) == agent_id {
      True -> True
      False -> False
    }
  })
}

/// Get all violations matching a given severity level.
pub fn get_violations_by_severity(
  violations: List(ViolationRecord),
  severity: String,
) -> List(ViolationRecord) {
  list.filter(violations, fn(v) {
    case v.severity == severity {
      True -> True
      False -> False
    }
  })
}

/// Get statistics about violations as a dictionary of metric names to counts.
/// Returns: total_violations, unique_agents, critical_count, high_count,
/// medium_count, low_count.
pub fn get_statistics(violations: List(ViolationRecord)) -> Dict(String, Int) {
  let total = list.length(violations)

  // Count unique agents
  let unique_agents =
    list.fold(violations, dict.new(), fn(acc, v) {
      let aid = extract_agent_id(v.context.agent_type)
      dict.insert(acc, aid, True)
    })
    |> dict.size()

  // Count by severity
  let #(critical, high, medium, low) =
    list.fold(violations, #(0, 0, 0, 0), fn(acc, v) {
      let #(c, h, m, l) = acc
      case v.severity {
        "CRITICAL" -> #(c + 1, h, m, l)
        "HIGH" -> #(c, h + 1, m, l)
        "MEDIUM" -> #(c, h, m + 1, l)
        "LOW" -> #(c, h, m, l + 1)
        _ -> #(c, h, m, l)
      }
    })

  dict.new()
  |> dict.insert("total_violations", total)
  |> dict.insert("unique_agents", unique_agents)
  |> dict.insert("critical_count", critical)
  |> dict.insert("high_count", high)
  |> dict.insert("medium_count", medium)
  |> dict.insert("low_count", low)
}

/// Export the violation list as a pipe-delimited audit log string.
/// SC-ENFORCE-019: Audit log rotation MUST preserve history.
pub fn export_audit_log(violations: List(ViolationRecord)) -> String {
  violations
  |> list.map(fn(v) {
    v.timestamp
    <> " | "
    <> v.id
    <> " | "
    <> extract_agent_id(v.context.agent_type)
    <> " | "
    <> v.context.requested_path
    <> " | "
    <> v.context.operation
    <> " | "
    <> v.reason
    <> " | "
    <> v.severity
  })
  |> string.join("\n")
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">
///     val getAgentReport : List(ViolationRecord) -> string -> json.Json
///   </morphism>
///   <formal-proof>
///     <P> Pre: violations is a valid list, agent_id is non-empty. </P>
///     <C> get_agent_report(violations, agent_id) </C>
///     <Q> Post: Returns a well-formed json.Json object containing agent_id,
///         total_violations, critical_count, high_count, circuit_status,
///         and recent_violations (last 5). SC-GLM-UI-003 compliant. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn get_agent_report(
  violations: List(ViolationRecord),
  agent_id: String,
) -> json.Json {
  let agent_violations = get_agent_violations(violations, agent_id)
  let total = list.length(agent_violations)

  let #(critical_count, high_count) =
    list.fold(agent_violations, #(0, 0), fn(acc, v) {
      let #(c, h) = acc
      case v.severity {
        "CRITICAL" -> #(c + 1, h)
        "HIGH" -> #(c, h + 1)
        "MEDIUM" -> #(c, h)
        "LOW" -> #(c, h)
        _ -> #(c, h)
      }
    })

  // Take up to 5 recent violations
  let recent =
    agent_violations
    |> list.take(5)
    |> list.map(fn(v) {
      json.object([
        #("id", json.string(v.id)),
        #("severity", json.string(v.severity)),
        #("reason", json.string(v.reason)),
        #("timestamp", json.string(v.timestamp)),
      ])
    })

  json.object([
    #("agent_id", json.string(agent_id)),
    #("total_violations", json.int(total)),
    #("critical_count", json.int(critical_count)),
    #("high_count", json.int(high_count)),
    #(
      "circuit_status",
      json.string(case total >= 3 {
        True -> "OPEN"
        False -> "CLOSED"
      }),
    ),
    #("recent_violations", json.preprocessed_array(recent)),
  ])
}
