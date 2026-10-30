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
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/route_convergence.{
  type RouteGrant, RouteGrant, admit_converged, execute_converged,
}
import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolSpec, ClientProfile, Complete, Modern20260728,
  NonRetryable, PrivateDevelopmentView, PrivateSuccessorView, Refused,
  TaskScopedMutation, ToolError,
}
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should

const workspace = "/home/an/NAS-setup/uos"

const candidate = "active-candidate-T14"

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
    active_candidate: candidate,
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
  admission.AdmissionContext(
    principal: principal.from_launcher_env(
      "T14-worker",
      ClientProfile("test"),
      workspace,
      "T14-session",
    ),
    mode: admission.EnforcedMode,
    now_ms: 1_000_000,
    workspace_root: workspace,
    task_fence: Some(admission.TaskFence(
      plan_id: "T14-plan",
      task_id: "T14-task",
      worker_id: "T14-worker",
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
    store_with([#("T-failed", receipt("T-failed", candidate, 1, None, None))])
  run(failed, "T-failed").0
  |> refused_code
  |> should.equal("COMPLETION_EVIDENCE_REQUIRED")

  let conflicted =
    store_with([
      #(
        "T-conflict",
        receipt("T-conflict", candidate, 0, Some("HOLD"), Some("APPROVED")),
      ),
    ])
  run(conflicted, "T-conflict").0
  |> refused_code
  |> should.equal("COMPLETION_EVIDENCE_REQUIRED")

  let valid =
    store_with([
      #("T14-task", receipt("T14-task", candidate, 0, None, None)),
    ])
  case run(valid, "T14-task").0 {
    Complete(_, evidence) -> {
      evidence.candidate |> should.equal(candidate)
      evidence.route |> should.equal("development")
      evidence.tool |> should.equal("harness_finish")
    }
    _ -> should.fail()
  }

  // The receipt must be bound to the finishing task id, not merely present
  // under the requested key.
  let receipt_id_mismatch =
    store_with([#("T14-task", receipt("T-other", candidate, 0, None, None))])
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
    store_with([#(task_id, receipt(task_id, candidate, 0, None, None))])
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
          evidence.candidate |> should.equal(candidate)
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
  first_evidence.candidate |> should.equal(candidate)
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
