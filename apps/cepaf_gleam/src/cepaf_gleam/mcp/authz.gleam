//// MCP tool-call authorization at the effect boundary.
////
//// Every `tools/call` reaching `mcp/server.gleam` passes through `authorize`
//// after the Fractal-Jidoka bypass check and before the mutating-action
//// preflight. Three independent controls, each fail-closed:
////
//// 1. Rate limit per caller and calendar minute (`planning/enforcer.check_rate_limit`).
//// 2. Path controls: forbidden path patterns for any path-bearing argument, and
////    the SC-TODO-001 planning-ledger rule via `planning/enforcer.enforce_access`.
//// 3. Guardian gate (`bridge/pi_tools.check_gate`) with the policy mode read from
////    `UOS_MCP_GUARDIAN_MODE` (permissive | audit_only | enforce_non_l0 |
////    enforce_all | lockdown).
////
//// INTERIM DEFAULT: when the variable is unset the guardian mode is
//// `audit_only`, because no approval store exists yet for `Blocked` decisions
//// (see checklist row AIC-EC-03). Rate limits and path controls block in every
//// mode. Operators enable blocking guardian decisions by exporting the variable.
//// Policy is code and configuration; it is never read from the request.

import cepaf_gleam/bridge/pi_tools.{
  type FederatedTool, type GateDecision, type GuardianMode, type GuardianPolicy,
  FederatedTool, GuardianPolicy,
}
import cepaf_gleam/planning/enforcer.{type RateLimitState, RateLimitState}
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Denial {
  GuardianDenied(reason: String)
  RateLimited(reason: String)
  AccessDenied(reason: String)
}

pub type Authorization {
  Authorization(agent: String, decision: GateDecision, rate_state: RateLimitState)
}

pub const default_rate_limit_per_minute = 600

pub const guardian_mode_env = "UOS_MCP_GUARDIAN_MODE"

pub const rate_limit_env = "UOS_MCP_RATE_LIMIT_PER_MINUTE"

@external(erlang, "mcp_authz_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)

@external(erlang, "mcp_authz_ffi", "rate_state_get")
fn rate_state_get() -> Result(RateLimitState, Nil)

@external(erlang, "mcp_authz_ffi", "rate_state_put")
fn rate_state_put(state: RateLimitState) -> Nil

@external(erlang, "mcp_authz_ffi", "window_key")
fn window_key() -> String

@external(erlang, "mcp_authz_ffi", "now_iso8601")
fn now_iso8601() -> String

// ---------------------------------------------------------------------------
// JSON-RPC error mapping
// ---------------------------------------------------------------------------

pub fn denial_code(denial: Denial) -> Int {
  case denial {
    GuardianDenied(_) -> -32_003
    RateLimited(_) -> -32_004
    AccessDenied(_) -> -32_005
  }
}

pub fn denial_message(denial: Denial) -> String {
  case denial {
    GuardianDenied(reason) -> "Guardian gate denied: " <> reason
    RateLimited(reason) -> "Rate limit: " <> reason
    AccessDenied(reason) -> "Access denied: " <> reason
  }
}

// ---------------------------------------------------------------------------
// Policy resolution (configuration, never the request)
// ---------------------------------------------------------------------------

pub fn mode_from_string(value: String) -> Option(GuardianMode) {
  case string.lowercase(string.trim(value)) {
    "permissive" -> Some(pi_tools.Permissive)
    "audit_only" | "audit-only" | "audit" -> Some(pi_tools.AuditOnly)
    "enforce_non_l0" | "enforce-non-l0" -> Some(pi_tools.EnforceNonL0)
    "enforce_all" | "enforce-all" | "enforce" -> Some(pi_tools.EnforceAll)
    "lockdown" -> Some(pi_tools.Lockdown)
    _ -> None
  }
}

pub fn policy_for_mode(mode: GuardianMode) -> GuardianPolicy {
  GuardianPolicy(
    mode: mode,
    auto_allow_layers: [],
    audit_all: True,
    emergency_override: False,
  )
}

/// Interim default is `AuditOnly` (see module doc). An unparseable value is
/// treated as unset, never as permissive.
pub fn policy_from_env() -> GuardianPolicy {
  case get_env(guardian_mode_env) {
    Ok(value) ->
      case mode_from_string(value) {
        Some(mode) -> policy_for_mode(mode)
        None -> policy_for_mode(pi_tools.AuditOnly)
      }
    Error(Nil) -> policy_for_mode(pi_tools.AuditOnly)
  }
}

pub fn rate_limit_from_env() -> Int {
  case get_env(rate_limit_env) {
    Ok(value) ->
      case int.parse(string.trim(value)) {
        Ok(n) if n > 0 -> n
        _ -> default_rate_limit_per_minute
      }
    Error(Nil) -> default_rate_limit_per_minute
  }
}

// ---------------------------------------------------------------------------
// Request facts
// ---------------------------------------------------------------------------

/// Caller identity: `params.arguments.actor`, else `params._meta.agent_id`,
/// else an explicit unknown identity that the enforcer denies on protected paths.
pub fn extract_agent(raw_line: String) -> String {
  let actor_decoder = {
    use a <- decode.subfield(["params", "arguments", "actor"], decode.string)
    decode.success(a)
  }
  let meta_decoder = {
    use a <- decode.subfield(["params", "_meta", "agent_id"], decode.string)
    decode.success(a)
  }
  case json.parse(raw_line, actor_decoder) {
    Ok(a) -> a
    Error(_) ->
      case json.parse(raw_line, meta_decoder) {
        Ok(a) -> a
        Error(_) -> "unknown:anonymous"
      }
  }
}

pub fn path_argument_keys() -> List(String) {
  ["path", "file", "file_path", "target", "directory", "source", "destination"]
}

pub fn extract_paths(raw_line: String) -> List(String) {
  list.filter_map(path_argument_keys(), fn(key) {
    let decoder = {
      use p <- decode.subfield(["params", "arguments", key], decode.string)
      decode.success(p)
    }
    json.parse(raw_line, decoder) |> result.replace_error(Nil)
  })
}

fn extract_proof_token(raw_line: String) -> Option(String) {
  let decoder = {
    use t <- decode.subfield(["params", "arguments", "proof_token"], decode.string)
    decode.success(t)
  }
  case json.parse(raw_line, decoder) {
    Ok(t) -> Some(t)
    Error(_) -> None
  }
}

/// Path fragments no MCP tool may read or write. Matching is case-insensitive
/// substring (`enforcer.is_forbidden_path`).
pub fn forbidden_patterns() -> List(String) {
  [
    ".ssh/", "id_rsa", "id_ed25519", ".gnupg/", ".env", "/etc/shadow",
    "/etc/passwd", ".jj/", "var/sa-plan/uos.sqlite3", "priv/ferriskey_nif.so",
    "priv/rusty_vault_nif.so", ".sqlite3-wal", ".sqlite3-shm",
  ]
}

/// The federated catalog entry for a tool, or a synthesized entry: tools the
/// catalog does not know are treated as L3, guardian-gated when mutating.
pub fn federated_tool_for(name: String, mutating: Bool) -> FederatedTool {
  case list.find(pi_tools.all_federated_tools(), fn(t) { t.name == name }) {
    Ok(tool) -> tool
    Error(Nil) ->
      FederatedTool(
        name: name,
        source: pi_tools.C3iTool,
        description: "MCP server tool (not in the federated catalog)",
        fractal_layer: 3,
        gate: case mutating {
          True -> pi_tools.GuardianRequired
          False -> pi_tools.NoGate
        },
      )
  }
}

// ---------------------------------------------------------------------------
// Pure authorization
// ---------------------------------------------------------------------------

/// Authorize one tool call. `window` identifies the current rate-limit window;
/// a state from an older window is reset. Returns the new rate state on success.
pub fn authorize(
  policy: GuardianPolicy,
  rate_state: RateLimitState,
  max_per_window: Int,
  window: String,
  name: String,
  mutating: Bool,
  raw_line: String,
) -> Result(Authorization, Denial) {
  let agent = extract_agent(raw_line)
  let state = case rate_state.window_start == window {
    True -> rate_state
    False -> RateLimitState(counts: dict.new(), window_start: window)
  }
  use state <- result.try(
    enforcer.check_rate_limit(state, agent, max_per_window)
    |> result.map_error(RateLimited),
  )
  use _ <- result.try(check_paths(agent, name, raw_line))
  let tool = federated_tool_for(name, mutating)
  let decision = pi_tools.check_gate(policy, tool)
  case pi_tools.is_allowed(decision) {
    True -> Ok(Authorization(agent: agent, decision: decision, rate_state: state))
    False ->
      Error(GuardianDenied(
        pi_tools.gate_decision_to_string(decision)
        <> " for tool "
        <> name
        <> " (mode "
        <> pi_tools.guardian_mode_to_string(policy.mode)
        <> ")",
      ))
  }
}

fn check_paths(agent: String, name: String, raw_line: String) -> Result(Nil, Denial) {
  let paths = extract_paths(raw_line)
  case list.find(paths, fn(p) { enforcer.is_forbidden_path(p, forbidden_patterns()) }) {
    Ok(p) -> Error(AccessDenied("forbidden path " <> p <> " for tool " <> name))
    Error(Nil) ->
      case
        list.find(paths, fn(p) {
          string.contains(string.lowercase(p), "project_todolist.md")
        })
      {
        Error(Nil) -> Ok(Nil)
        Ok(p) -> {
          let ctx =
            enforcer.RequestContext(
              agent_type: enforcer.classify_agent(agent),
              requested_path: p,
              operation: name,
              timestamp: now_iso8601(),
              stack_trace: None,
              ip_address: None,
              additional_context: dict.new(),
              proof_token: extract_proof_token(raw_line),
            )
          case enforcer.enforce_access(ctx, 0, 3) {
            enforcer.Allowed(_) -> Ok(Nil)
            enforcer.Denied(reason, _) -> Error(AccessDenied(reason))
            enforcer.CircuitOpen(agent_id, count) ->
              Error(AccessDenied(
                "circuit open for "
                <> agent_id
                <> " after "
                <> int.to_string(count)
                <> " violations",
              ))
          }
        }
      }
  }
}

// ---------------------------------------------------------------------------
// Effectful wrapper used by the dispatcher
// ---------------------------------------------------------------------------

/// Resolve policy and limits from configuration, load the serving process's
/// rate state, authorize, persist the new state, and emit one audit line to
/// stderr. The request never influences which policy applies.
pub fn authorize_and_persist(
  name: String,
  mutating: Bool,
  raw_line: String,
) -> Result(Authorization, Denial) {
  let policy = policy_from_env()
  let state = case rate_state_get() {
    Ok(s) -> s
    Error(Nil) -> enforcer.new_rate_limit_state()
  }
  let outcome =
    authorize(
      policy,
      state,
      rate_limit_from_env(),
      window_key(),
      name,
      mutating,
      raw_line,
    )
  case outcome {
    Ok(auth) -> {
      rate_state_put(auth.rate_state)
      io.println_error(audit_line(name, auth.agent, policy, Ok(auth.decision)))
    }
    Error(denial) ->
      io.println_error(audit_line(name, extract_agent(raw_line), policy, Error(denial)))
  }
  outcome
}

pub fn audit_line(
  name: String,
  agent: String,
  policy: GuardianPolicy,
  outcome: Result(GateDecision, Denial),
) -> String {
  let #(verdict, detail) = case outcome {
    Ok(decision) -> #("allowed", pi_tools.gate_decision_to_string(decision))
    Error(denial) -> #("denied", denial_message(denial))
  }
  "[mcp-authz] "
  <> json.to_string(
    json.object([
      #("ts", json.string(now_iso8601())),
      #("tool", json.string(name)),
      #("agent", json.string(agent)),
      #("mode", json.string(pi_tools.guardian_mode_to_string(policy.mode))),
      #("verdict", json.string(verdict)),
      #("detail", json.string(detail)),
    ]),
  )
}
