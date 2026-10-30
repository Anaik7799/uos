//// T14 route parity tests: one converged execution path preserves route-bound
//// grants, completion evidence, candidate binding, and wire schema digests.

import cepaf_gleam/mcp/adapters/analysis
import cepaf_gleam/mcp/adapters/control
import cepaf_gleam/mcp/adapters/features.{
  type ExecutionReceipt, type FeatureEvidenceStore, ExecutionReceipt,
  FeatureEvidenceStore,
}
import cepaf_gleam/mcp/adapters/knowledge
import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/adapters/planning_write
import cepaf_gleam/mcp/adapters/system_observation
import cepaf_gleam/mcp/adapters/vault_metadata
import cepaf_gleam/mcp/adapters/verification
import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/route_convergence.{
  type RouteGrant, RouteGrant, admit_converged, execute_converged,
}
import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolError, type ToolSpec, AuditOnly, ClientProfile,
  Complete, ControlMutation, Modern20260728, NonRetryable,
  PrivateDevelopmentView, PrivateSuccessorView, Refused, TaskScopedMutation,
  ToolError,
}
import gleam/dict
import gleam/dynamic
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should
import simplifile

@external(erlang, "file", "set_cwd")
fn erl_set_cwd(path: String) -> Result(Nil, dynamic.Dynamic)

const workspace = "/home/an/NAS-setup/uos"

fn active_candidate() -> String {
  candidate_id.current()
}

fn receipt(
  task_id: String,
  receipt_candidate: String,
  exit_code: Int,
  raw: Option(String),
  wrapper: Option(String),
) -> ExecutionReceipt {
  ExecutionReceipt(
    feature_or_task_id: task_id,
    candidate_commit: receipt_candidate,
    exit_code: exit_code,
    raw_review_verdict: raw,
    wrapper_verdict: wrapper,
    output_sha256: "sha-" <> task_id,
  )
}

fn store_with(
  receipts: List(#(String, ExecutionReceipt)),
) -> FeatureEvidenceStore {
  FeatureEvidenceStore(
    active_candidate: active_candidate(),
    admitted_ev_ceiling: 93,
    capabilities: [],
    completed_task_ids: list.map(receipts, fn(entry) { entry.0 }),
    receipts: dict.from_list(receipts),
    intents: dict.new(),
  )
}

fn ticket() -> admission.GrantTicket {
  admission.GrantTicket(
    grant_id: "T14-route-grant",
    scope: TaskScopedMutation,
    revoked: False,
    expires_at_ms: 9_999_999_999_999,
    workspace_root: workspace,
  )
}

fn context() -> admission.AdmissionContext {
  context_for_actor("T14-worker")
}

fn context_for_actor(actor: String) -> admission.AdmissionContext {
  admission.AdmissionContext(
    principal: principal.from_launcher_env(
      actor,
      ClientProfile("test"),
      workspace,
      "T14-session-" <> actor,
    ),
    mode: admission.EnforcedMode,
    now_ms: 1_000_000,
    workspace_root: workspace,
    task_fence: Some(admission.TaskFence(
      plan_id: "T14-plan",
      task_id: "T14-task",
      worker_id: actor,
      attempt: 1,
      task_state: admission.TaskExecuting,
      lease_until_ms: 9_999_999_999_999,
      grant: Some(ticket()),
    )),
  )
}

fn grant(route: String, tools: List(String)) -> RouteGrant {
  RouteGrant(route, tools, ticket())
}

fn refused_code(outcome: Outcome) -> String {
  case outcome {
    Refused(ToolError(code, _, _)) -> code
    _ -> panic as "expected Refused outcome"
  }
}

fn ignored_handler(
  _spec: ToolSpec,
  _args: dict.Dict(String, String),
) -> Result(String, String) {
  Ok("{\"ok\":true}")
}

fn finish_args(task_id: String) -> dict.Dict(String, String) {
  dict.from_list([
    #("task_id", task_id),
    #("journal_path", "/tmp/journal"),
    #("build_intent_id", "build-1"),
    #("test_intent_id", "test-1"),
  ])
}

pub fn same_name_different_route_does_not_expand_grant_test() {
  let dev_specs = registry.definitions(Modern20260728, PrivateDevelopmentView)
  let succ_specs = registry.definitions(Modern20260728, PrivateSuccessorView)
  list.length(dev_specs) |> should.equal(21)
  list.length(succ_specs) |> should.equal(15)

  let overlapping = [
    "harness_finish",
    "harness_read_file",
    "harness_write_file",
  ]
  list.each(overlapping, fn(name) {
    let assert Ok(dev_spec) = registry.lookup("development", name)
    let assert Ok(succ_spec) = registry.lookup("successor", name)
    dev_spec.route |> should.equal("development")
    succ_spec.route |> should.equal("successor")
    registry.verify_schema_digest(dev_spec, dev_spec.input_schema)
    |> should.be_ok
    registry.verify_schema_digest(succ_spec, succ_spec.input_schema)
    |> should.be_ok
    let assert Ok(dev_def) =
      list.find(dev_specs, fn(spec) { spec.name == name })
    let assert Ok(succ_def) =
      list.find(succ_specs, fn(spec) { spec.name == name })
    dev_spec.schema_digest |> should.equal(dev_def.schema_digest)
    succ_spec.schema_digest |> should.equal(succ_def.schema_digest)
  })

  let assert Ok(dev_finish) = registry.lookup("development", "harness_finish")
  let assert Ok(succ_finish) = registry.lookup("successor", "harness_finish")
  dev_finish.schema_digest |> should.not_equal(succ_finish.schema_digest)

  let dev_grant = grant("development", ["harness_finish"])
  admit_converged(
    context(),
    Some(dev_grant),
    "development",
    "harness_finish",
    dict.new(),
  )
  |> should.be_ok
  admit_converged(
    context(),
    Some(dev_grant),
    "successor",
    "harness_finish",
    dict.new(),
  )
  |> should.be_error

  case
    admit_converged(
      context(),
      Some(dev_grant),
      "successor",
      "harness_finish",
      dict.new(),
    )
  {
    Error(err) -> {
      err.code |> should.equal("CROSS_ROUTE_GRANT_FORBIDDEN")
      err.retryability |> should.equal(NonRetryable)
    }
    Ok(_) -> should.fail()
  }

  let succ_grant = grant("successor", ["harness_finish"])
  admit_converged(
    context(),
    Some(succ_grant),
    "successor",
    "harness_finish",
    dict.new(),
  )
  |> should.be_ok
  case
    admit_converged(
      context(),
      Some(succ_grant),
      "development",
      "harness_finish",
      dict.new(),
    )
  {
    Error(err) -> err.code |> should.equal("CROSS_ROUTE_GRANT_FORBIDDEN")
    Ok(_) -> should.fail()
  }
}

pub fn legacy_finish_cannot_bypass_completion_evidence_test() {
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let dev_grant = grant("development", ["harness_finish"])
  let run = fn(store: FeatureEvidenceStore, task_id: String) -> #(
    Outcome,
    supervisor.WorkerPool,
  ) {
    execute_converged(
      pool,
      context(),
      Some(dev_grant),
      store,
      "development",
      "harness_finish",
      finish_args(task_id),
      ignored_handler,
    )
  }

  let no_receipt = store_with([])
  run(no_receipt, "T-missing").0
  |> refused_code
  |> should.equal("COMPLETION_EVIDENCE_REQUIRED")

  let stale =
    store_with([
      #("T-stale", receipt("T-stale", "old-candidate", 0, None, None)),
    ])
  run(stale, "T-stale").0
  |> refused_code
  |> should.equal("COMPLETION_EVIDENCE_REQUIRED")

  let failed =
    store_with([
      #("T-failed", receipt("T-failed", active_candidate(), 1, None, None)),
    ])
  run(failed, "T-failed").0
  |> refused_code
  |> should.equal("COMPLETION_EVIDENCE_REQUIRED")

  let conflicted =
    store_with([
      #(
        "T-conflict",
        receipt(
          "T-conflict",
          active_candidate(),
          0,
          Some("HOLD"),
          Some("APPROVED"),
        ),
      ),
    ])
  run(conflicted, "T-conflict").0
  |> refused_code
  |> should.equal("COMPLETION_EVIDENCE_REQUIRED")

  let valid =
    store_with([
      #("T14-task", receipt("T14-task", active_candidate(), 0, None, None)),
    ])
  case run(valid, "T14-task").0 {
    Complete(_, evidence) -> {
      evidence.candidate |> should.equal(active_candidate())
      evidence.route |> should.equal("development")
      evidence.tool |> should.equal("harness_finish")
    }
    _ -> should.fail()
  }

  // The receipt must be bound to the finishing task id, not merely present
  // under the requested key.
  let receipt_id_mismatch =
    store_with([
      #("T14-task", receipt("T-other", active_candidate(), 0, None, None)),
    ])
  run(receipt_id_mismatch, "T14-task").0
  |> refused_code
  |> should.equal("COMPLETION_EVIDENCE_REQUIRED")

  // The active task fence id must match the finishing task id.
  let assert Some(fence) = context().task_fence
  let fence_mismatch =
    admission.AdmissionContext(
      ..context(),
      task_fence: Some(admission.TaskFence(..fence, task_id: "T-other-fence")),
    )
  execute_converged(
    pool,
    fence_mismatch,
    Some(dev_grant),
    valid,
    "development",
    "harness_finish",
    finish_args("T14-task"),
    ignored_handler,
  ).0
  |> refused_code
  |> should.equal("COMPLETION_EVIDENCE_REQUIRED")
}

pub fn all_fifteen_successor_tools_same_candidate_test() {
  let successor_specs =
    registry.definitions(Modern20260728, PrivateSuccessorView)
  list.length(successor_specs) |> should.equal(15)

  let all_specs = registry.all_specs()
  list.length(all_specs) |> should.equal(101)
  list.count(all_specs, fn(spec) { spec.route == "development" })
  |> should.equal(21)
  list.count(all_specs, fn(spec) { spec.route == "public" })
  |> should.equal(65)
  list.count(all_specs, fn(spec) { spec.route == "successor" })
  |> should.equal(15)

  let names = list.map(successor_specs, fn(spec) { spec.name })
  let successor_grant = grant("successor", names)
  let task_id = "T14-task"
  let store =
    store_with([
      #(task_id, receipt(task_id, active_candidate(), 0, None, None)),
    ])
  let assert Ok(pool) = supervisor.start_worker_pool(1)

  let #(_final_pool, completed_count) =
    list.fold(successor_specs, #(pool, 0), fn(acc, spec) {
      let #(current_pool, count) = acc
      let args = case spec.name {
        "harness_finish" -> finish_args(task_id)
        _ -> dict.new()
      }
      let #(outcome, next_pool) =
        execute_converged(
          current_pool,
          context(),
          Some(successor_grant),
          store,
          "successor",
          spec.name,
          args,
          ignored_handler,
        )
      case outcome {
        Complete(_, evidence) -> {
          evidence.candidate |> should.equal(active_candidate())
          evidence.route |> should.equal("successor")
          evidence.tool |> should.equal(spec.name)
        }
        _ -> should.fail()
      }
      registry.verify_schema_digest(spec, spec.input_schema) |> should.be_ok
      #(next_pool, count + 1)
    })
  completed_count |> should.equal(15)
}

pub fn foreign_candidate_completion_evidence_is_refused_test() {
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let dev_grant = grant("development", ["harness_read_file"])
  // Commit a read-only private call bound to the pool ledger candidate.
  let #(first, committed_pool) =
    execute_converged(
      pool,
      context(),
      Some(dev_grant),
      store_with([]),
      "development",
      "harness_read_file",
      dict.new(),
      ignored_handler,
    )
  let assert Complete(_, first_evidence) = first
  first_evidence.candidate |> should.equal(active_candidate())
  // Replay the committed receipt under a ledger naming a foreign candidate;
  // the stored ledger outcome keeps the original pool ledger candidate, so
  // the converged path must refuse instead of silently relabeling it.
  let foreign_pool =
    supervisor.WorkerPool(
      ..committed_pool,
      ledger: receipts.ReceiptLedger(
        candidate: "foreign-candidate",
        entries: committed_pool.ledger.entries,
      ),
    )
  execute_converged(
    foreign_pool,
    context(),
    Some(dev_grant),
    store_with([]),
    "development",
    "harness_read_file",
    dict.new(),
    ignored_handler,
  ).0
  |> refused_code
  |> should.equal("CANDIDATE_EVIDENCE_MISMATCH")
}

fn server_backends(store: FeatureEvidenceStore) -> server.ServerBackends {
  server.ServerBackends(
    planning_read: planning_read.sample_canonical_store("plan", []),
    planning_write: planning_write.new_store(),
    observation: system_observation.ObservedSnapshot(
      active_candidate(),
      "test",
      1000,
      100,
      Some([]),
      dict.from_list([#("system_health.status", "healthy")]),
    ),
    control: control.ControlBackend(active_candidate(), 0, True, dict.new()),
    verification_runner: fn(_) { verification.CheckExecuted(0, "ok", 1) },
    knowledge: knowledge.new_corpus(
      "/workspace",
      ["public", "private"],
      4096,
      4,
    ),
    vault: vault_metadata.SupervisedVault(
      "/workspace",
      False,
      True,
      [],
      dict.new(),
      [],
    ),
    analysis: analysis.MaxDaemonOffline("fixture has no daemon"),
    features: store,
  )
}

pub fn server_execute_route_authenticated_converges_public_and_private_test() {
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let store = store_with([])
  let backends = server_backends(store)

  // Public route: the convergence gate admits first, then the authoritative
  // public dispatcher handles it.
  let #(public_outcome, public_pool, public_backends) =
    server.execute_route_authenticated(
      context(),
      None,
      pool,
      backends,
      "public",
      "harness_execution_progress",
      dict.new(),
      ignored_handler,
    )
  let assert Complete(_, public_evidence) = public_outcome
  public_evidence.route |> should.equal("public")
  public_evidence.tool |> should.equal("harness_execution_progress")
  public_pool |> should.equal(pool)
  public_backends |> should.equal(backends)

  // Development route: converged private execution rewrites evidence to the
  // active candidate and the requested route/tool.
  let dev_grant = grant("development", ["harness_read_file"])
  let #(dev_outcome, _dev_pool, _dev_backends) =
    server.execute_route_authenticated(
      context(),
      Some(dev_grant),
      pool,
      backends,
      "development",
      "harness_read_file",
      dict.new(),
      ignored_handler,
    )
  let assert Complete(_, dev_evidence) = dev_outcome
  dev_evidence.route |> should.equal("development")
  dev_evidence.tool |> should.equal("harness_read_file")
  dev_evidence.candidate |> should.equal(store.active_candidate)

  // Successor route: same converged contract under a different route grant.
  let succ_grant = grant("successor", ["harness_read_file"])
  let #(succ_outcome, _succ_pool, _succ_backends) =
    server.execute_route_authenticated(
      context(),
      Some(succ_grant),
      pool,
      backends,
      "successor",
      "harness_read_file",
      dict.new(),
      ignored_handler,
    )
  let assert Complete(_, succ_evidence) = succ_outcome
  succ_evidence.route |> should.equal("successor")
  succ_evidence.tool |> should.equal("harness_read_file")
  succ_evidence.candidate |> should.equal(store.active_candidate)

  // Unknown route: refused through the convergence gate.
  let #(unknown, unknown_pool, _unknown_backends) =
    server.execute_route_authenticated(
      context(),
      None,
      pool,
      backends,
      "regression",
      "harness_read_file",
      dict.new(),
      ignored_handler,
    )
  unknown |> refused_code |> should.equal("UNKNOWN_ROUTE_OR_TOOL")
  unknown_pool |> should.equal(pool)
}

// ---------------------------------------------------------------------------
// T23-C01: route grant ticket validation and fence binding
// ---------------------------------------------------------------------------

fn admission_error_code(result: Result(a, ToolError)) -> String {
  case result {
    Error(err) -> err.code
    Ok(_) -> panic as "expected Error"
  }
}

pub fn revoked_expired_or_foreign_route_grant_ticket_refused_test() {
  // Revoked route grant ticket is refused before admission.
  let revoked =
    RouteGrant(
      "development",
      ["harness_read_file"],
      admission.GrantTicket(..ticket(), revoked: True),
    )
  admit_converged(
    context(),
    Some(revoked),
    "development",
    "harness_read_file",
    dict.new(),
  )
  |> admission_error_code
  |> should.equal("ROUTE_GRANT_REVOKED")

  // Expired route grant ticket is refused.
  let expired =
    RouteGrant(
      "development",
      ["harness_read_file"],
      admission.GrantTicket(..ticket(), expires_at_ms: 500),
    )
  admit_converged(
    context(),
    Some(expired),
    "development",
    "harness_read_file",
    dict.new(),
  )
  |> admission_error_code
  |> should.equal("ROUTE_GRANT_EXPIRED")

  // Foreign workspace route grant ticket is refused.
  let foreign =
    RouteGrant(
      "development",
      ["harness_read_file"],
      admission.GrantTicket(..ticket(), workspace_root: "/foreign-workspace"),
    )
  admit_converged(
    context(),
    Some(foreign),
    "development",
    "harness_read_file",
    dict.new(),
  )
  |> admission_error_code
  |> should.equal("ROUTE_GRANT_WORKSPACE_MISMATCH")

  // Blank grant id is refused.
  let blank =
    RouteGrant(
      "development",
      ["harness_read_file"],
      admission.GrantTicket(..ticket(), grant_id: "   "),
    )
  admit_converged(
    context(),
    Some(blank),
    "development",
    "harness_read_file",
    dict.new(),
  )
  |> admission_error_code
  |> should.equal("ROUTE_GRANT_ID_REQUIRED")

  // AuditOnly scope can never authorize a route grant.
  let audit_only =
    RouteGrant(
      "development",
      ["harness_read_file"],
      admission.GrantTicket(..ticket(), scope: AuditOnly),
    )
  admit_converged(
    context(),
    Some(audit_only),
    "development",
    "harness_read_file",
    dict.new(),
  )
  |> admission_error_code
  |> should.equal("ROUTE_GRANT_SCOPE_INSUFFICIENT")

  // The route ticket must match the active fence authority grant id.
  let mismatched =
    RouteGrant(
      "development",
      ["harness_read_file"],
      admission.GrantTicket(..ticket(), grant_id: "other-route-ticket"),
    )
  admit_converged(
    context(),
    Some(mismatched),
    "development",
    "harness_read_file",
    dict.new(),
  )
  |> admission_error_code
  |> should.equal("ROUTE_GRANT_TICKET_MISMATCH")
}

// ---------------------------------------------------------------------------
// T23-C03: receipt entries are isolated per authenticated principal
// ---------------------------------------------------------------------------

pub fn private_route_replay_isolated_across_principals_test() {
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let dev_grant = grant("development", ["harness_read_file"])
  let store = store_with([])

  let #(first_outcome, first_pool) =
    execute_converged(
      pool,
      context_for_actor("T14-worker-a"),
      Some(dev_grant),
      store,
      "development",
      "harness_read_file",
      dict.new(),
      ignored_handler,
    )
  let assert Complete(_, _) = first_outcome

  let #(second_outcome, second_pool) =
    execute_converged(
      first_pool,
      context_for_actor("T14-worker-b"),
      Some(dev_grant),
      store,
      "development",
      "harness_read_file",
      dict.new(),
      ignored_handler,
    )
  let assert Complete(_, _) = second_outcome

  // Two distinct principals issuing the same logical private-route call must
  // never collapse into (or read) one shared receipt entry.
  dict.size(first_pool.ledger.entries) |> should.equal(1)
  dict.size(second_pool.ledger.entries) |> should.equal(2)
}

// ---------------------------------------------------------------------------
// T23-C04: route grant scope and full ticket equality on private reads
// ---------------------------------------------------------------------------

pub fn same_id_audit_only_or_inconsistent_fence_ticket_refused_on_private_read_test() {
  // The fence authority ticket carries the same grant_id as the route ticket
  // but an AuditOnly scope: the scope gate must fire before any equality check.
  let assert Some(fence) = context().task_fence
  let audit_fence =
    admission.TaskFence(
      ..fence,
      grant: Some(admission.GrantTicket(..ticket(), scope: AuditOnly)),
    )
  let audit_context =
    admission.AdmissionContext(..context(), task_fence: Some(audit_fence))
  admit_converged(
    audit_context,
    Some(grant("development", ["harness_read_file"])),
    "development",
    "harness_read_file",
    dict.new(),
  )
  |> admission_error_code
  |> should.equal("ROUTE_GRANT_SCOPE_INSUFFICIENT")

  // Same grant_id, valid but different scope from the route ticket: the full
  // ticket equality gate must refuse rather than treating the id as sufficient.
  let control_fence =
    admission.TaskFence(
      ..fence,
      grant: Some(admission.GrantTicket(..ticket(), scope: ControlMutation)),
    )
  let control_context =
    admission.AdmissionContext(..context(), task_fence: Some(control_fence))
  admit_converged(
    control_context,
    Some(grant("development", ["harness_read_file"])),
    "development",
    "harness_read_file",
    dict.new(),
  )
  |> admission_error_code
  |> should.equal("ROUTE_GRANT_TICKET_MISMATCH")
}

// ---------------------------------------------------------------------------
// T23-C05: attempt bumps execute a fresh handler, never stale replay
// ---------------------------------------------------------------------------

pub fn private_read_attempt_bump_executes_fresh_handler_test() {
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let dev_grant = grant("development", ["harness_read_file"])
  let store = store_with([])

  let #(first, committed_pool) =
    execute_converged(
      pool,
      context(),
      Some(dev_grant),
      store,
      "development",
      "harness_read_file",
      dict.new(),
      fn(_, _) { Ok("{\"epoch\":\"first\"}") },
    )
  let assert Complete("{\"epoch\":\"first\"}", _) = first

  let assert Some(fence) = context().task_fence
  let bumped_context =
    admission.AdmissionContext(
      ..context(),
      task_fence: Some(admission.TaskFence(..fence, attempt: 2)),
    )
  let #(second, pool2) =
    execute_converged(
      committed_pool,
      bumped_context,
      Some(dev_grant),
      store,
      "development",
      "harness_read_file",
      dict.new(),
      fn(_, _) { Ok("{\"epoch\":\"second\"}") },
    )
  // A bumped attempt must execute the fresh handler, not replay "first".
  let assert Complete("{\"epoch\":\"second\"}", _) = second
  dict.size(pool2.ledger.entries) |> int.to_string |> should.equal("2")
}

// ---------------------------------------------------------------------------
// T23-C06: empty/generic candidate evidence is refused without relabeling
// ---------------------------------------------------------------------------

pub fn empty_or_generic_candidate_evidence_is_refused_without_relabeling_test() {
  supervisor.start_worker_pool_for_candidate(size: 1, candidate: "")
  |> should.be_error
  supervisor.start_worker_pool_for_candidate(size: 1, candidate: "uos-mcp")
  |> should.be_error

  list.each(["uos-mcp", ""], fn(bad_candidate) {
    let assert Ok(base_pool) = supervisor.start_worker_pool(1)
    let pool =
      supervisor.WorkerPool(
        ..base_pool,
        ledger: receipts.new_ledger(bad_candidate),
      )
    let store =
      FeatureEvidenceStore(..store_with([]), active_candidate: bad_candidate)
    execute_converged(
      pool,
      context(),
      Some(grant("development", ["harness_read_file"])),
      store,
      "development",
      "harness_read_file",
      dict.new(),
      ignored_handler,
    ).0
    |> refused_code
    |> should.equal("CANDIDATE_EVIDENCE_MISMATCH")
  })
}

// ---------------------------------------------------------------------------
// T23-C07: `_client_schema_digest` pin is enforced inside admit_converged
// ---------------------------------------------------------------------------

pub fn client_schema_digest_pin_enforced_in_admit_converged_test() {
  let assert Ok(spec) = registry.lookup("development", "harness_read_file")

  admit_converged(
    context(),
    Some(grant("development", ["harness_read_file"])),
    "development",
    "harness_read_file",
    dict.from_list([#("_client_schema_digest", "stale-digest")]),
  )
  |> admission_error_code
  |> should.equal("SCHEMA_MIGRATION_REQUIRED")

  admit_converged(
    context(),
    Some(grant("development", ["harness_read_file"])),
    "development",
    "harness_read_file",
    dict.from_list([#("_client_schema_digest", spec.schema_digest)]),
  )
  |> should.be_ok
}

// ---------------------------------------------------------------------------
// T23-R3-C01: a public mutation attempt bump must execute a fresh handler
// ---------------------------------------------------------------------------

pub fn public_mutation_attempt_bump_executes_fresh_handler_test() {
  let assert Ok(pool0) = supervisor.start_worker_pool(1)
  let backends0 = server_backends(store_with([]))
  let args =
    dict.from_list([
      #("plan_id", "attempt-bump-plan"),
      #("task_id", "attempt-bump-task"),
    ])

  let assert Some(base_fence) = context().task_fence
  let fence1 =
    admission.TaskFence(
      ..base_fence,
      plan_id: "attempt-bump-plan",
      task_id: "attempt-bump-task",
      attempt: 1,
    )
  let context1 =
    admission.AdmissionContext(..context(), task_fence: Some(fence1))
  let assert Some(grant_ticket) = fence1.grant
  let pub_grant = Some(RouteGrant("public", ["plan_add"], grant_ticket))

  let #(outcome1, pool1, backends1) =
    server.execute_route_authenticated(
      context1,
      pub_grant,
      pool0,
      backends0,
      "public",
      "plan_add",
      args,
      ignored_handler,
    )
  let assert Complete(_, _) = outcome1
  dict.size(pool1.ledger.entries) |> should.equal(1)
  dict.has_key(backends1.planning_write.tasks, #(
    "attempt-bump-plan",
    "attempt-bump-task",
  ))
  |> should.equal(True)

  // Replay the exact same attempt-1 call against fresh backends0: the
  // committed receipt must be returned without re-executing the handler.
  let #(replay_outcome, pool_replayed, backends_replayed) =
    server.execute_route_authenticated(
      context1,
      pub_grant,
      pool1,
      backends0,
      "public",
      "plan_add",
      args,
      ignored_handler,
    )
  let assert Complete(_, _) = replay_outcome
  dict.size(pool_replayed.ledger.entries) |> should.equal(1)
  dict.has_key(backends_replayed.planning_write.tasks, #(
    "attempt-bump-plan",
    "attempt-bump-task",
  ))
  |> should.equal(False)

  // Bumping the attempt busts the public replay cache and executes the fresh
  // handler against the still-fresh backends0.
  let fence2 = admission.TaskFence(..fence1, attempt: 2)
  let context2 =
    admission.AdmissionContext(..context(), task_fence: Some(fence2))
  let #(bumped_outcome, pool2, backends2) =
    server.execute_route_authenticated(
      context2,
      pub_grant,
      pool1,
      backends0,
      "public",
      "plan_add",
      args,
      ignored_handler,
    )
  let assert Complete(_, _) = bumped_outcome
  dict.size(pool2.ledger.entries) |> should.equal(2)
  dict.has_key(backends2.planning_write.tasks, #(
    "attempt-bump-plan",
    "attempt-bump-task",
  ))
  |> should.equal(True)
}

// ---------------------------------------------------------------------------
// T23-R3-C02: candidate identity from an unrecognized root fails closed
// ---------------------------------------------------------------------------

pub fn candidate_id_from_unrecognized_root_fails_closed_test() {
  candidate_id.from_root("/tmp") |> should.equal("UNOBSERVED_CANDIDATE_SOURCE")
  candidate_id.is_valid("UNOBSERVED_CANDIDATE_SOURCE") |> should.equal(False)
  candidate_id.is_sha256_digest("UNOBSERVED_CANDIDATE_SOURCE")
  |> should.equal(False)

  let assert Ok(orig_cwd) = simplifile.current_directory()
  let _ = erl_set_cwd("/tmp")
  let tmp_cand = candidate_id.current()
  let _ = erl_set_cwd(orig_cwd)
  tmp_cand |> should.equal("UNOBSERVED_CANDIDATE_SOURCE")
  candidate_id.is_valid(tmp_cand) |> should.equal(False)
}
