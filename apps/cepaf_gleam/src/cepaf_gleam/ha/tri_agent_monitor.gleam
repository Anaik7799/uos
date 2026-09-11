//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/tri_agent_monitor</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L3_TRANSACTION</layer>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Local Tri-Agent Surveillance and Activity Monitoring Engine.
////       Intercepts all actions from Claude, AGY, Codex, OpenRouter, and local models.
////       Enforces local processing maximization, fails closed on un-ledgered actions,
////       and triggers seamless autonomous degradation to bare-metal MAX/Mojo Gemma.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>
////       SC-DEFENSE-CONSTITUTION-001, SC-SURVEILLANCE-001, SC-JIDOKA-001,
////       SC-SA-PLAN-001, SC-SOV-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/harness/tool_fenced_dispatcher
import gleam/int
import gleam/json
import gleam/list
import gleam/string

@external(erlang, "cepaf_gleam_ffi", "sha256")
pub fn sha256(data: String) -> String

/// Monitored Agent Identities.
pub type MonitoredAgent {
  AgyAgent
  ClaudeAgent
  CodexAgent
  OpenRouterAgent
  LocalGemmaAgent
  UnknownAgent(name: String)
}

/// Convert monitored agent identity to human-readable string.
pub fn agent_to_string(agent: MonitoredAgent) -> String {
  case agent {
    AgyAgent -> "AGY"
    ClaudeAgent -> "CLAUDE"
    CodexAgent -> "CODEX"
    OpenRouterAgent -> "OPENROUTER"
    LocalGemmaAgent -> "LOCAL_GEMMA_MAX"
    UnknownAgent(name) -> name
  }
}

/// Parse string into MonitoredAgent.
pub fn string_to_agent(str: String) -> MonitoredAgent {
  case string.uppercase(str) {
    "AGY" -> AgyAgent
    "CLAUDE" -> ClaudeAgent
    "CODEX" -> CodexAgent
    "OPENROUTER" -> OpenRouterAgent
    "LOCAL_GEMMA_MAX" | "GEMMA" -> LocalGemmaAgent
    other -> UnknownAgent(other)
  }
}

/// Execution Target: Local Bare-Metal MAX vs External Cloud.
pub type LocalOrCloud {
  LocalBareMetalMax
  ExternalCloudModel
}

/// Agent Activity Classification.
pub type AgentActivityKind {
  ToolCallProposal(tool_name: String, args_summary: String, payload_hash: String)
  CodeSynthesisProposal(file_path: String, diff_size: Int, content_hash: String)
  PlanMutationProposal(plan_id: String, task_id: String, operation: String)
  SystemQueryProposal(query_kind: String, target_subsystem: String)
  InferenceDispatch(model: String, prompt_tokens: Int, target: LocalOrCloud)
}

/// Interception Verdict.
pub type InterceptionVerdict {
  VerdictAllow(reason: String)
  VerdictRequireQuorum(missing_approvals: List(String))
  VerdictAndonHalt(code: Int, violation: String)
  VerdictRerouteToLocal(local_engine: String, fallback_reason: String)
}

/// Convert verdict to string.
pub fn verdict_to_string(verdict: InterceptionVerdict) -> String {
  case verdict {
    VerdictAllow(reason) -> "ALLOW: " <> reason
    VerdictRequireQuorum(approvals) ->
      "REQUIRE_QUORUM: " <> string.join(approvals, ", ")
    VerdictAndonHalt(code, violation) ->
      "ANDON_HALT (" <> int.to_string(code) <> "): " <> violation
    VerdictRerouteToLocal(engine, reason) ->
      "REROUTE_LOCAL (" <> engine <> "): " <> reason
  }
}

/// Check if verdict is a halt.
pub fn is_halted(verdict: InterceptionVerdict) -> Bool {
  case verdict {
    VerdictAndonHalt(_, _) -> True
    _ -> False
  }
}

/// Check if verdict is a reroute to local inference.
pub fn is_rerouted(verdict: InterceptionVerdict) -> Bool {
  case verdict {
    VerdictRerouteToLocal(_, _) -> True
    _ -> False
  }
}

/// Single Audited Activity Record.
pub type ActivityRecord {
  ActivityRecord(
    id: String,
    timestamp_ns: Int,
    agent: MonitoredAgent,
    activity: AgentActivityKind,
    verdict: InterceptionVerdict,
    sha256_digest: String,
  )
}

/// Tri-Agent Surveillance Monitor State.
pub type TriAgentMonitorState {
  TriAgentMonitorState(
    records: List(ActivityRecord),
    total_intercepted: Int,
    total_halted: Int,
    total_rerouted_local: Int,
    cloud_degradation_active: Bool,
    local_only_mode: Bool,
    last_activity_ns: Int,
  )
}

/// Create a fresh tri-agent monitor state.
pub fn new_monitor(local_only: Bool) -> TriAgentMonitorState {
  TriAgentMonitorState(
    records: [],
    total_intercepted: 0,
    total_halted: 0,
    total_rerouted_local: 0,
    cloud_degradation_active: False,
    local_only_mode: local_only,
    last_activity_ns: 0,
  )
}

/// Toggle network blackout / cloud degradation mode (Psi-13).
pub fn set_degradation_mode(
  state: TriAgentMonitorState,
  degraded: Bool,
) -> TriAgentMonitorState {
  TriAgentMonitorState(..state, cloud_degradation_active: degraded)
}

/// Set strict local-only sovereign mode (Psi-11).
pub fn set_local_only_mode(
  state: TriAgentMonitorState,
  local_only: Bool,
) -> TriAgentMonitorState {
  TriAgentMonitorState(..state, local_only_mode: local_only)
}

/// Evaluate constitutional security invariants for proposed agent activity.
pub fn evaluate_security_invariants(
  agent: MonitoredAgent,
  activity: AgentActivityKind,
  state: TriAgentMonitorState,
  quorum_signed: Bool,
  has_valid_lease: Bool,
) -> InterceptionVerdict {
  case activity {
    // 1. External Cloud Inference Dispatch Under Degradation or Local-Only Mode
    InferenceDispatch(_model, _tokens, ExternalCloudModel) -> {
      case state.local_only_mode || state.cloud_degradation_active {
        True ->
          VerdictRerouteToLocal(
            "mojo_max_gemma",
            "Psi-13 Autonomous Degradation: External cloud disconnected or prohibited. Rerouting to bare-metal MAX Gemma.",
          )
        False ->
          VerdictAllow("External cloud dispatch permitted under nominal connectivity.")
      }
    }

    InferenceDispatch(_model, _tokens, LocalBareMetalMax) ->
      VerdictAllow("Local bare-metal MAX execution approved under Psi-11.")

    // 2. Plan Mutation Proposal: Strictly requires valid sa-plan lease token (SC-JIDOKA-001)
    PlanMutationProposal(_plan_id, _task_id, _op) -> {
      case has_valid_lease {
        False ->
          VerdictAndonHalt(
            -32_002,
            "SC-JIDOKA-001: Non-sa-plan mutation attempted by "
              <> agent_to_string(agent)
              <> ". Un-ledgered plan modification forbidden.",
          )
        True ->
          VerdictAllow("Sa-plan mutation authorized with valid execution lease.")
      }
    }

    // 3. Tool Call Proposal: Quorum check for mutating actions & injection filtering
    ToolCallProposal(tool_name, args_summary, _hash) -> {
      let is_mutating = tool_fenced_dispatcher.is_mutating_tool(tool_name)
      case is_mutating, quorum_signed {
        True, False ->
          VerdictRequireQuorum(["CODEX", "AGY"])
        _, _ -> {
          // Check for dangerous exfiltration or unsafe patterns
          case contains_prohibited_exfiltration(args_summary) {
            True ->
              VerdictAndonHalt(
                -32_005,
                "Psi-12: Prohibited external exfiltration or unvetted command pattern detected in tool args.",
              )
            False ->
              VerdictAllow("Tool proposal validated against constitutional invariants.")
          }
        }
      }
    }

    // 4. Code Synthesis Proposal: Check Zero-Muda and file boundaries
    CodeSynthesisProposal(file_path, _diff_size, _hash) -> {
      case contains_zero_muda_violation(file_path) {
        True ->
          VerdictAndonHalt(
            -32_006,
            "Zero-Muda Violation: Target path touches barred components (Bevy, Graphite, foreign NIFs).",
          )
        False -> {
          case is_constitutional_contract_path(file_path), quorum_signed {
            True, False ->
              VerdictRequireQuorum(["CODEX", "AGY"])
            _, _ ->
              VerdictAllow("Code synthesis path approved.")
          }
        }
      }
    }

    // 5. System Query: Always allow read-only queries
    SystemQueryProposal(_query_kind, _target) ->
      VerdictAllow("Read-only system query authorized.")
  }
}

/// Helper: Detect prohibited exfiltration strings.
fn contains_prohibited_exfiltration(content: String) -> Bool {
  let lower = string.lowercase(content)
  string.contains(lower, "curl -x")
  || string.contains(lower, "nc -e")
  || string.contains(lower, "/dev/tcp/")
  || string.contains(lower, "pastebin")
  || string.contains(lower, "ngrok")
}

/// Helper: Detect Zero-Muda barred libraries.
fn contains_zero_muda_violation(path: String) -> Bool {
  let lower = string.lowercase(path)
  string.contains(lower, "bevy") || string.contains(lower, "graphite")
}

/// Helper: Check if path touches core constitutional rules.
fn is_constitutional_contract_path(path: String) -> Bool {
  string.contains(path, "contracts/rules/")
  || string.contains(path, "l0_constitutional")
}

/// Intercept an agent activity proposal, evaluate invariants, and record audit evidence.
pub fn intercept_activity(
  state: TriAgentMonitorState,
  record_id: String,
  agent: MonitoredAgent,
  activity: AgentActivityKind,
  current_time_ns: Int,
  quorum_signed: Bool,
  has_valid_lease: Bool,
) -> #(TriAgentMonitorState, InterceptionVerdict) {
  let verdict =
    evaluate_security_invariants(
      agent,
      activity,
      state,
      quorum_signed,
      has_valid_lease,
    )

  // Compute immutable SHA-256 fingerprint of the interaction
  let activity_raw = case activity {
    ToolCallProposal(t, a, h) -> "TOOL:" <> t <> ":" <> a <> ":" <> h
    CodeSynthesisProposal(p, d, h) ->
      "CODE:" <> p <> ":" <> int.to_string(d) <> ":" <> h
    PlanMutationProposal(p, t, o) -> "PLAN:" <> p <> ":" <> t <> ":" <> o
    SystemQueryProposal(q, sub) -> "QUERY:" <> q <> ":" <> sub
    InferenceDispatch(m, tok, loc) ->
      "INFER:"
      <> m
      <> ":"
      <> int.to_string(tok)
      <> ":"
      <> case loc {
        LocalBareMetalMax -> "LOCAL"
        ExternalCloudModel -> "CLOUD"
      }
  }

  let record_digest =
    sha256(
      record_id
      <> ":"
      <> int.to_string(current_time_ns)
      <> ":"
      <> agent_to_string(agent)
      <> ":"
      <> activity_raw
      <> ":"
      <> verdict_to_string(verdict),
    )

  let record =
    ActivityRecord(
      id: record_id,
      timestamp_ns: current_time_ns,
      agent: agent,
      activity: activity,
      verdict: verdict,
      sha256_digest: record_digest,
    )

  let new_halted = case is_halted(verdict) {
    True -> state.total_halted + 1
    False -> state.total_halted
  }

  let new_rerouted = case is_rerouted(verdict) {
    True -> state.total_rerouted_local + 1
    False -> state.total_rerouted_local
  }

  let new_state =
    TriAgentMonitorState(
      records: [record, ..state.records],
      total_intercepted: state.total_intercepted + 1,
      total_halted: new_halted,
      total_rerouted_local: new_rerouted,
      cloud_degradation_active: state.cloud_degradation_active,
      local_only_mode: state.local_only_mode,
      last_activity_ns: current_time_ns,
    )

  #(new_state, verdict)
}

/// JSON Serialization of an activity record.
pub fn activity_to_json(record: ActivityRecord) -> json.Json {
  json.object([
    #("id", json.string(record.id)),
    #("timestamp_ns", json.int(record.timestamp_ns)),
    #("agent", json.string(agent_to_string(record.agent))),
    #("verdict", json.string(verdict_to_string(record.verdict))),
    #("digest", json.string(record.sha256_digest)),
    #(
      "activity_kind",
      case record.activity {
        ToolCallProposal(t, a, h) ->
          json.object([
            #("kind", json.string("tool_call")),
            #("tool_name", json.string(t)),
            #("args_summary", json.string(a)),
            #("payload_hash", json.string(h)),
          ])
        CodeSynthesisProposal(p, d, h) ->
          json.object([
            #("kind", json.string("code_synthesis")),
            #("file_path", json.string(p)),
            #("diff_size", json.int(d)),
            #("content_hash", json.string(h)),
          ])
        PlanMutationProposal(p, t, o) ->
          json.object([
            #("kind", json.string("plan_mutation")),
            #("plan_id", json.string(p)),
            #("task_id", json.string(t)),
            #("operation", json.string(o)),
          ])
        SystemQueryProposal(q, s) ->
          json.object([
            #("kind", json.string("system_query")),
            #("query_kind", json.string(q)),
            #("target_subsystem", json.string(s)),
          ])
        InferenceDispatch(m, tok, target) ->
          json.object([
            #("kind", json.string("inference_dispatch")),
            #("model", json.string(m)),
            #("tokens", json.int(tok)),
            #(
              "target",
              case target {
                LocalBareMetalMax -> json.string("local_bare_metal_max")
                ExternalCloudModel -> json.string("external_cloud")
              },
            ),
          ])
      },
    ),
  ])
}

/// JSON Serialization of the monitor state.
pub fn to_json(state: TriAgentMonitorState) -> json.Json {
  json.object([
    #("total_intercepted", json.int(state.total_intercepted)),
    #("total_halted", json.int(state.total_halted)),
    #("total_rerouted_local", json.int(state.total_rerouted_local)),
    #("cloud_degradation_active", json.bool(state.cloud_degradation_active)),
    #("local_only_mode", json.bool(state.local_only_mode)),
    #("last_activity_ns", json.int(state.last_activity_ns)),
    #(
      "recent_records",
      json.array(list.take(state.records, 20), activity_to_json),
    ),
  ])
}

/// Human-readable surveillance summary string.
pub fn summary(state: TriAgentMonitorState) -> String {
  "Tri-Agent Monitor [Intercepted="
  <> int.to_string(state.total_intercepted)
  <> ", Halted="
  <> int.to_string(state.total_halted)
  <> ", ReroutedLocal="
  <> int.to_string(state.total_rerouted_local)
  <> ", DegradedMode="
  <> case state.cloud_degradation_active {
    True -> "ACTIVE"
    False -> "NOMINAL"
  }
  <> ", LocalOnly="
  <> case state.local_only_mode {
    True -> "TRUE"
    False -> "FALSE"
  }
  <> "]"
}
