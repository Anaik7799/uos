//// Authorization at the MCP tool-call effect boundary (mcp/authz.gleam).

import cepaf_gleam/bridge/pi_tools
import cepaf_gleam/mcp/adapters/analysis
import cepaf_gleam/mcp/adapters/control
import cepaf_gleam/mcp/adapters/features
import cepaf_gleam/mcp/adapters/knowledge
import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/adapters/planning_write
import cepaf_gleam/mcp/adapters/system_observation
import cepaf_gleam/mcp/adapters/vault_metadata
import cepaf_gleam/mcp/adapters/verification
import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/authz
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types.{
  ClientProfile, Complete, Refused, TaskScopedMutation,
}
import cepaf_gleam/planning/enforcer
import gleam/dict
import gleam/json
import gleam/list
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
  authorize_with(
    pi_tools.EnforceNonL0,
    "sa_plan_status",
    False,
    json.object([]),
  )
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
  let line =
    raw("system_health", json.object([#("actor", json.string("ai:agent-a:m"))]))
  let assert Ok(a1) =
    authz.authorize(
      policy,
      enforcer.new_rate_limit_state(),
      2,
      "w",
      "system_health",
      False,
      line,
    )
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
    authz.authorize(
      policy,
      enforcer.new_rate_limit_state(),
      1,
      "w",
      "system_health",
      False,
      a,
    )
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
  authz.extract_agent(raw(
    "x",
    json.object([#("actor", json.string("human:an"))]),
  ))
  |> should.equal("human:an")
  authz.extract_agent(
    "{\"params\":{\"_meta\":{\"agent_id\":\"ai:codex:astra\"}}}",
  )
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

fn authenticated_context() -> admission.AdmissionContext {
  admission.AdmissionContext(
    principal: principal.from_launcher_env(
      "trusted-worker",
      ClientProfile("codex"),
      "/workspace",
      "session",
    ),
    mode: admission.EnforcedMode,
    now_ms: 1000,
    workspace_root: "/workspace",
    task_fence: Some(admission.TaskFence(
      plan_id: "authority-plan",
      task_id: "authority-task",
      worker_id: "trusted-worker",
      attempt: 1,
      task_state: admission.TaskExecuting,
      lease_until_ms: 2000,
      grant: Some(admission.GrantTicket(
        "grant",
        TaskScopedMutation,
        False,
        2000,
        "/workspace",
      )),
    )),
  )
}

fn authenticated_backends() -> server.ServerBackends {
  server.ServerBackends(
    planning_read: planning_read.sample_canonical_store("plan", []),
    planning_write: planning_write.new_store(),
    observation: system_observation.ObservedSnapshot(
      "candidate",
      "test",
      1000,
      100,
      Some([]),
      dict.from_list([#("system_health.status", "healthy")]),
    ),
    control: control.ControlBackend("candidate", 0, True, dict.new()),
    verification_runner: fn(_) { verification.CheckExecuted(0, "ok", 1) },
    knowledge: knowledge.new_corpus(
      "/workspace",
      ["public", "private"],
      4096,
      4,
    )
      |> knowledge.with_entry(knowledge.CorpusEntry(
        "readme.md",
        knowledge.RegularFile,
        "public",
        "public knowledge",
      ))
      |> knowledge.with_entry(knowledge.CorpusEntry(
        "private.md",
        knowledge.RegularFile,
        "private",
        "private knowledge",
      )),
    vault: vault_metadata.SupervisedVault(
      "/workspace",
      False,
      True,
      [],
      dict.new(),
      [],
    ),
    analysis: analysis.MaxDaemonOffline("fixture has no daemon"),
    features: features.FeatureEvidenceStore(
      "candidate",
      93,
      [],
      [],
      dict.new(),
      dict.new(),
    ),
  )
}

pub fn authenticated_dispatch_routes_all_nine_public_families_test() {
  let context = authenticated_context()
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let backends = authenticated_backends()
  // Each family must return its adapter's successful typed outcome.
  list.each(
    [
      #("sa_plan_status", dict.new()),
      #("system_health", dict.new()),
      #("registry_status", dict.new()),
      #("verification_run", dict.new()),
      #("read_file", dict.from_list([#("path", "readme.md")])),
      #("vault_status", dict.new()),
      #("lyapunov_trend_predict", dict.from_list([#("series", "3.0,2.0,1.0")])),
      #("harness_execution_progress", dict.new()),
    ],
    fn(entry) {
      let #(outcome, unchanged_pool, _) =
        server.execute_authenticated(context, pool, backends, entry.0, entry.1)
      let assert Complete(_, evidence) = outcome
      evidence.tool |> should.equal(entry.0)
      case entry.0 {
        "registry_status" ->
          dict.size(unchanged_pool.ledger.entries) |> should.equal(1)
        _ -> unchanged_pool |> should.equal(pool)
      }
    },
  )

  let add_args =
    dict.from_list([
      #("plan_id", "plan"),
      #("task_id", "target"),
      #("intent_id", "add-target"),
    ])
  let #(added, pool, backends) =
    server.execute_authenticated(context, pool, backends, "plan_add", add_args)
  let assert Complete(_, _) = added
  let #(replayed, replay_pool, replay_backends) =
    server.execute_authenticated(context, pool, backends, "plan_add", add_args)
  replayed |> should.equal(added)
  replay_pool |> should.equal(pool)
  replay_backends |> should.equal(backends)

  let #(claimed, pool, backends) =
    server.execute_authenticated(
      context,
      pool,
      backends,
      "sa_task_claim",
      dict.from_list([
        #("plan_id", "plan"),
        #("task_id", "target"),
        #("worker", "evil-impersonator"),
      ]),
    )
  let assert Complete(_, _) = claimed
  let assert Ok(task) =
    dict.get(backends.planning_write.tasks, #("plan", "target"))
  task.worker |> should.equal(principal.actor_id(context.principal))
  task.attempt |> should.equal(1)

  // A distinct intent really reaches the adapter, preserving its refusal code.
  let #(refusal, _, refused_backends) =
    server.execute_authenticated(
      context,
      pool,
      backends,
      "plan_add",
      dict.insert(add_args, "intent_id", "duplicate-task"),
    )
  let assert Refused(err) = refusal
  err.code |> should.equal("TASK_ALREADY_EXISTS")
  refused_backends |> should.equal(backends)
  let #(conflict, _, _) =
    server.execute_authenticated(
      context,
      pool,
      backends,
      "plan_add",
      dict.insert(add_args, "task_id", "different"),
    )
  let assert Refused(err) = conflict
  err.code |> should.equal("IDEMPOTENCY_CONFLICT")

  // No caller argument can supply the principal scope missing from its API.
  let #(private_read, _, _) =
    server.execute_authenticated(
      context,
      pool,
      backends,
      "read_file",
      dict.from_list([#("path", "private.md"), #("scopes", "private")]),
    )
  let assert Refused(err) = private_read
  err.code |> should.equal("CROSS_PRINCIPAL_SCOPE_FORBIDDEN")
}

pub fn authenticated_dispatch_refuses_workspace_mismatch_and_ungranted_mutation_test() {
  let context = authenticated_context()
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let backends = authenticated_backends()
  let mismatched =
    admission.AdmissionContext(..context, workspace_root: "/another-workspace")
  let #(outcome, returned_pool, returned_backends) =
    server.execute_authenticated(
      mismatched,
      pool,
      backends,
      "sa_plan_status",
      dict.new(),
    )
  let assert Refused(err) = outcome
  err.code |> should.equal("PRINCIPAL_WORKSPACE_MISMATCH")
  returned_pool |> should.equal(pool)
  returned_backends |> should.equal(backends)

  let assert Some(fence) = context.task_fence
  let ungranted =
    admission.AdmissionContext(
      ..context,
      task_fence: Some(admission.TaskFence(..fence, grant: option.None)),
    )
  let #(outcome, returned_pool, returned_backends) =
    server.execute_authenticated(
      ungranted,
      pool,
      backends,
      "plan_add",
      dict.from_list([#("plan_id", "plan"), #("task_id", "target")]),
    )
  let assert Refused(err) = outcome
  err.code |> should.equal("MISSING_AUTHORITY_GRANT")
  returned_pool |> should.equal(pool)
  returned_backends |> should.equal(backends)

  let #(unknown, _, _) =
    server.execute_authenticated(
      context,
      pool,
      backends,
      "not-a-tool",
      dict.new(),
    )
  let assert Refused(err) = unknown
  err.code |> should.equal("UNKNOWN_ROUTE_OR_TOOL")
}
