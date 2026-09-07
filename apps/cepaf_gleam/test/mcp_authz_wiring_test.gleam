//// Authorization at the MCP tool-call effect boundary (mcp/authz.gleam).

import cepaf_gleam/bridge/pi_tools
import cepaf_gleam/mcp/authz
import cepaf_gleam/mcp/server
import cepaf_gleam/planning/enforcer
import gleam/json
import gleam/option.{Some}
import gleam/string
import gleeunit/should

fn raw(name: String, arguments: json.Json) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.string("authz-" <> name)),
    #("method", json.string("tools/call")),
    #(
      "params",
      json.object([#("name", json.string(name)), #("arguments", arguments)]),
    ),
  ])
  |> json.to_string
}

fn authorize_with(
  mode: pi_tools.GuardianMode,
  name: String,
  mutating: Bool,
  arguments: json.Json,
) -> Result(authz.Authorization, authz.Denial) {
  authz.authorize(
    authz.policy_for_mode(mode),
    enforcer.new_rate_limit_state(),
    10,
    "window-1",
    name,
    mutating,
    raw(name, arguments),
  )
}

// --- guardian gate -----------------------------------------------------------

pub fn permissive_allows_guardian_gated_tool_test() {
  authorize_with(pi_tools.Permissive, "plan_add", True, json.object([]))
  |> should.be_ok
}

pub fn audit_only_allows_gated_tool_with_audit_decision_test() {
  let assert Ok(auth) =
    authorize_with(pi_tools.AuditOnly, "plan_add", True, json.object([]))
  case auth.decision {
    pi_tools.AllowedWithAudit(_) -> Nil
    _ -> should.fail()
  }
}

pub fn enforce_all_blocks_guardian_gated_tool_test() {
  let assert Error(authz.GuardianDenied(reason)) =
    authorize_with(pi_tools.EnforceAll, "plan_add", True, json.object([]))
  reason |> string.contains("guardian_required_enforced") |> should.be_true
}

pub fn lockdown_blocks_gated_and_allows_readonly_test() {
  authorize_with(pi_tools.Lockdown, "server_restart", True, json.object([]))
  |> should.be_error
  authorize_with(pi_tools.Lockdown, "plan_list", False, json.object([]))
  |> should.be_ok
  // L4+ tools are blocked in lockdown mode
  authorize_with(pi_tools.Lockdown, "system_health", False, json.object([]))
  |> should.be_error
}

pub fn unknown_mutating_tool_is_guardian_gated_under_enforce_test() {
  let assert Error(authz.GuardianDenied(_)) =
    authorize_with(
      pi_tools.EnforceNonL0,
      "sa_workflow_start",
      True,
      json.object([]),
    )
  authorize_with(pi_tools.EnforceNonL0, "sa_plan_status", False, json.object([]))
  |> should.be_ok
}

pub fn policy_is_never_taken_from_the_request_test() {
  // A caller claiming a mode in its arguments changes nothing.
  let args = json.object([#("guardian_mode", json.string("permissive"))])
  authorize_with(pi_tools.EnforceAll, "plan_add", True, args)
  |> should.be_error
}

// --- rate limit ---------------------------------------------------------------

pub fn rate_limit_denies_third_call_when_max_is_two_test() {
  let policy = authz.policy_for_mode(pi_tools.Permissive)
  let line = raw("system_health", json.object([#("actor", json.string("ai:agent-a:m"))]))
  let assert Ok(a1) =
    authz.authorize(policy, enforcer.new_rate_limit_state(), 2, "w", "system_health", False, line)
  let assert Ok(a2) =
    authz.authorize(policy, a1.rate_state, 2, "w", "system_health", False, line)
  let assert Error(authz.RateLimited(_)) =
    authz.authorize(policy, a2.rate_state, 2, "w", "system_health", False, line)
  // A new window resets the counter.
  authz.authorize(policy, a2.rate_state, 2, "w2", "system_health", False, line)
  |> should.be_ok
}

pub fn rate_limit_is_per_agent_test() {
  let policy = authz.policy_for_mode(pi_tools.Permissive)
  let a = raw("system_health", json.object([#("actor", json.string("ai:a:m"))]))
  let b = raw("system_health", json.object([#("actor", json.string("ai:b:m"))]))
  let assert Ok(s1) =
    authz.authorize(policy, enforcer.new_rate_limit_state(), 1, "w", "system_health", False, a)
  authz.authorize(policy, s1.rate_state, 1, "w", "system_health", False, b)
  |> should.be_ok
}

// --- path controls -------------------------------------------------------------

pub fn forbidden_path_is_denied_test() {
  let args = json.object([#("path", json.string("/home/an/.ssh/id_rsa"))])
  let assert Error(authz.AccessDenied(reason)) =
    authorize_with(pi_tools.Permissive, "read_file", False, args)
  reason |> string.contains("forbidden path") |> should.be_true
}

pub fn sa_plan_database_is_not_readable_through_mcp_test() {
  let args = json.object([#("path", json.string("var/sa-plan/uos.sqlite3"))])
  authorize_with(pi_tools.Permissive, "read_file", False, args)
  |> should.be_error
}

pub fn todolist_by_anonymous_agent_is_denied_by_enforcer_test() {
  let args = json.object([#("path", json.string("PROJECT_TODOLIST.md"))])
  let assert Error(authz.AccessDenied(reason)) =
    authorize_with(pi_tools.Permissive, "read_file", False, args)
  reason |> string.contains("SC-TODO-001") |> should.be_true
}

pub fn todolist_by_ai_agent_without_proof_token_is_denied_test() {
  let args =
    json.object([
      #("path", json.string("docs/PROJECT_TODOLIST.md")),
      #("actor", json.string("ai:claude:fable")),
    ])
  authorize_with(pi_tools.Permissive, "read_file", False, args)
  |> should.be_error
}

pub fn ordinary_path_is_allowed_test() {
  let args = json.object([#("path", json.string("README.md"))])
  authorize_with(pi_tools.Permissive, "read_file", False, args)
  |> should.be_ok
}

// --- request facts ---------------------------------------------------------------

pub fn extract_agent_prefers_actor_then_meta_then_unknown_test() {
  authz.extract_agent(raw("x", json.object([#("actor", json.string("human:an"))])))
  |> should.equal("human:an")
  authz.extract_agent("{\"params\":{\"_meta\":{\"agent_id\":\"ai:codex:astra\"}}}")
  |> should.equal("ai:codex:astra")
  authz.extract_agent(raw("x", json.object([])))
  |> should.equal("unknown:anonymous")
}

pub fn mode_from_string_rejects_garbage_test() {
  authz.mode_from_string("enforce_all")
  |> should.equal(Some(pi_tools.EnforceAll))
  authz.mode_from_string("yolo")
  |> should.equal(option.None)
}

// --- end to end through the dispatcher -------------------------------------------

pub fn e2e_forbidden_path_returns_json_rpc_32005_test() {
  let assert Some(response) =
    server.handle_request_raw(raw(
      "read_file",
      json.object([#("path", json.string("/home/an/.ssh/id_rsa"))]),
    ))
  response |> string.contains("\"code\":-32005") |> should.be_true
  response |> string.contains("forbidden path") |> should.be_true
}

pub fn e2e_readonly_tool_is_not_denied_under_default_configuration_test() {
  let assert Some(response) =
    server.handle_request_raw(raw("system_health", json.object([])))
  response |> string.contains("\"code\":-32003") |> should.be_false
  response |> string.contains("\"code\":-32004") |> should.be_false
  response |> string.contains("\"code\":-32005") |> should.be_false
}
