//// T20 Assuring Gates: formal lattice dominance, two-lattice STM
//// non-interference, killed-worker descendant containment, overload/backpressure
//// refusal and a 10,000-request concurrency-16 warm-read benchmark.

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
import cepaf_gleam/mcp/evidence
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/prompts
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/resources
import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/subscriptions
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/transports/stdio
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/wire
import cepaf_gleam/mcp/worker
import gleam/dict
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Erlang FFI: monotonic microsecond clock for the performance gates.
// ---------------------------------------------------------------------------

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time() -> Int

@external(erlang, "erlang", "convert_time_unit")
fn convert_time_unit(value: Int, from: atom.Atom, to: atom.Atom) -> Int

fn now_us() -> Int {
  convert_time_unit(
    monotonic_time(),
    atom.create("native"),
    atom.create("microsecond"),
  )
}

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

fn authenticated_context() -> admission.AdmissionContext {
  admission.AdmissionContext(
    principal: principal.from_launcher_env(
      "trusted-worker",
      types.ClientProfile("codex"),
      "/workspace",
      "session",
    ),
    mode: admission.EnforcedMode,
    now_ms: 1000,
    workspace_root: "/workspace",
    task_fence: Some(admission.TaskFence(
      plan_id: "assurance-plan",
      task_id: "assurance-task",
      worker_id: "trusted-worker",
      attempt: 1,
      task_state: admission.TaskExecuting,
      lease_until_ms: 5000,
      grant: Some(admission.GrantTicket(
        "grant",
        types.TaskScopedMutation,
        False,
        5000,
        "/workspace",
      )),
    )),
  )
}

// The overload benchmark exercises ControlActuation tools (`safety_status`), so
// it needs a ControlMutation grant scope rather than a task-scoped one.
fn control_authority_context() -> admission.AdmissionContext {
  admission.AdmissionContext(
    principal: principal.from_launcher_env(
      "trusted-worker",
      types.ClientProfile("codex"),
      "/workspace",
      "session",
    ),
    mode: admission.EnforcedMode,
    now_ms: 1000,
    workspace_root: "/workspace",
    task_fence: Some(admission.TaskFence(
      plan_id: "assurance-plan",
      task_id: "assurance-task",
      worker_id: "trusted-worker",
      attempt: 1,
      task_state: admission.TaskExecuting,
      lease_until_ms: 5000,
      grant: Some(admission.GrantTicket(
        "grant",
        types.ControlMutation,
        False,
        5000,
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
      "assurance-observation",
      1000,
      100,
      Some([]),
      dict.from_list([#("status", "healthy")]),
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
    analysis: analysis.MaxDaemonOffline("assurance fixture has no daemon"),
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

fn assurance_principal() -> principal.Principal {
  principal.from_launcher_env(
    actor: "trusted-worker",
    client: types.ClientProfile("codex"),
    workspace_root: "/workspace",
    session_id: "assurance-session",
  )
}

fn public_resource_registry() -> resources.ResourceRegistry {
  resources.registry(
    [
      resources.ResourceEntry(
        uri: "uos://workspace/public/report",
        title: "Public Report",
        mime_type: "text/plain",
        visibility: resources.PublicResource,
        owner_actor: "trusted-worker",
        workspace_root: "/workspace",
        content: "public",
      ),
    ],
    [],
  )
}

fn assurance_prompt_registry() -> List(prompts.PromptSpec) {
  [
    prompts.PromptSpec(
      name: "summarize_plan",
      description: "Summarize a plan",
      required_args: ["plan_id"],
      template_body: "Summarize {{plan_id}}",
    ),
  ]
}

fn assurance_stdio_session() -> Result(stdio.StdioSession, types.ToolError) {
  stdio.new_session(
    actor_id: "trusted-worker",
    client_name: "codex",
    workspace_root: "/workspace",
    session_id: "assurance-session",
    profile: types.Legacy20241105,
    deadline_ms: 1000,
  )
}

fn complete_handler(
  _principal: principal.Principal,
  message: wire.NormalizedMessage,
) -> types.Outcome {
  types.Complete(
    message.canonical_json,
    types.EvidenceRecord(
      candidate: "assurance",
      route: "assurance/route",
      tool: "ping",
      declaration_state: "declared",
      implementation_state: "implemented",
      execution_state: "executed",
      formal_state: "unrun",
      admission_state: "not_admitted",
      output_sha256: "0",
    ),
  )
}

// ---------------------------------------------------------------------------
// 1. Lattice dominance + deterministic PRNG fuzz
// ---------------------------------------------------------------------------

fn lcg_next(seed: Int) -> Int {
  { { seed * 1_103_515_245 } + 12_345 } % 2_147_483_648
}

fn fuzz_inputs() -> List(String) {
  int.range(from: 0, to: 200, with: [], run: fn(acc, index) {
    let seed = lcg_next(lcg_next(index + 1))
    let variant = seed % 5
    let input = case variant {
      0 -> "<fuzz-" <> int.to_string(seed) <> ">not-json"
      1 -> "{\"jsonrpc\":\"2.0\",\"a\":\"" <> "\u{0000}" <> "\"}"
      2 -> {
        let depth = seed % 40 + 33
        string.repeat("{", depth) <> string.repeat("}", depth) <> "\n"
      }
      3 -> "uos://workspace/" <> string.repeat("../", seed % 5 + 1) <> "secret"
      _ -> "{\"jsonrpc\":\"2.0\",\"id\":" <> int.to_string(seed)
    }
    [input, ..acc]
  })
}

pub fn deny_dominates_composition_test() {
  let assert Ok(plan_add_spec) = registry.lookup("public", "plan_add")
  let assert Ok(control_spec) = registry.lookup("public", "control_loop")

  // Every one of the 2*2*2*2*2*3*2 = 192 fence combinations. The mutation
  // lattice only reaches Ok when every single dimension is valid. ControlActuation
  // tools additionally require a ControlMutation (or ReleaseAuthority) scope.
  list.each(
    [
      #(plan_add_spec, types.TaskScopedMutation),
      #(control_spec, types.ControlMutation),
    ],
    fn(spec_and_scope) {
      let #(spec, grant_scope) = spec_and_scope
      list.each([admission.EnforcedMode, admission.AuditOnlyMode], fn(mode) {
        list.each([False, True], fn(revoked) {
          list.each([False, True], fn(expired) {
            list.each([True, False], fn(workspace_match) {
              list.each([True, False], fn(worker_match) {
                list.each(
                  [
                    admission.TaskAvailable,
                    admission.TaskExecuting,
                    admission.TaskCompleted,
                  ],
                  fn(task_state) {
                    list.each([True, False], fn(route_grant_match) {
                      let all_valid =
                        mode == admission.EnforcedMode
                        && !revoked
                        && !expired
                        && workspace_match
                        && worker_match
                        && task_state == admission.TaskExecuting
                        && route_grant_match
                      let principal_workspace = case workspace_match {
                        True -> "/workspace"
                        False -> "/foreign-workspace"
                      }
                      let worker_id = case worker_match {
                        True -> "trusted-worker"
                        False -> "foreign-worker"
                      }
                      let grant_workspace = case route_grant_match {
                        True -> "/workspace"
                        False -> "/foreign-workspace"
                      }
                      let grant_expires = case expired {
                        True -> 500
                        False -> 5000
                      }
                      let context =
                        admission.AdmissionContext(
                          principal: principal.from_launcher_env(
                            actor: "trusted-worker",
                            client: types.ClientProfile("codex"),
                            workspace_root: principal_workspace,
                            session_id: "assurance-session",
                          ),
                          mode: mode,
                          now_ms: 1000,
                          workspace_root: "/workspace",
                          task_fence: Some(admission.TaskFence(
                            plan_id: "assurance-plan",
                            task_id: "assurance-task",
                            worker_id: worker_id,
                            attempt: 1,
                            task_state: task_state,
                            lease_until_ms: 5000,
                            grant: Some(admission.GrantTicket(
                              grant_id: "grant",
                              scope: grant_scope,
                              revoked: revoked,
                              expires_at_ms: grant_expires,
                              workspace_root: grant_workspace,
                            )),
                          )),
                        )
                      let verdict = admission.admit(context, spec, dict.new())
                      case all_valid {
                        True -> {
                          verdict |> should.be_ok
                          Nil
                        }
                        False -> {
                          verdict |> should.be_error
                          Nil
                        }
                      }
                    })
                  },
                )
              })
            })
          })
        })
      })
    },
  )

  // Deterministic PRNG fuzz: malformed / deep / NUL / URI inputs must never
  // reach a Complete outcome and must never crash the decoders.
  let resource_registry = public_resource_registry()
  let transport_principal = assurance_principal()
  list.each(fuzz_inputs(), fn(input) {
    let wire_failed = case wire.decode_request(types.Legacy20241105, input) {
      Error(_) -> True
      Ok(_) -> False
    }
    wire_failed |> should.be_true

    let stdio_failed = case assurance_stdio_session() {
      Error(_) -> True
      Ok(session) -> {
        let result = stdio.ingest_chunk(session, input, 0, complete_handler)
        case result {
          Error(_) -> True
          Ok(#(_, emitted)) -> emitted == []
        }
      }
    }
    stdio_failed |> should.be_true

    let resource_failed = case
      resources.read_resource(
        resource_registry,
        resources.empty_cache(),
        transport_principal,
        input,
      )
    {
      Error(_) -> True
      Ok(_) -> False
    }
    resource_failed |> should.be_true
  })
}

// ---------------------------------------------------------------------------
// 2. Two-lattice STM non-interference
// ---------------------------------------------------------------------------

pub fn task_scoped_mutation_refused_for_control_actuation_test() {
  let assert Ok(spec) = registry.lookup("public", "control_loop")
  // `authenticated_context` carries a TaskScopedMutation grant. That scope may
  // authorize Mutating tools, but never a ControlActuation tool.
  case
    admission.admit(
      authenticated_context(),
      spec,
      dict.from_list([#("mode", "step")]),
    )
  {
    Ok(_) -> should.fail()
    Error(err) -> err.code |> should.equal("CONTROL_MUTATION_SCOPE_REQUIRED")
  }
}

type Observer {
  ObsSystemHealth
  ObsOodaDecide
  ObsPlanStatus
  ObsStpa
  ObsRete
  ObsFeatures
  ObsResource
  ObsPrompt
}

pub fn observer_cannot_change_authority_test() {
  let context = authenticated_context()
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let backends = authenticated_backends()

  let initial_write = backends.planning_write
  let initial_control = backends.control
  let initial_fence = context.task_fence
  let initial_ledger = pool.ledger

  let resource_registry = public_resource_registry()
  let resource_cache = resources.empty_cache()
  let prompt_registry = assurance_prompt_registry()

  let observer_indices =
    int.range(from: 0, to: 50, with: [], run: fn(acc, index) { [index, ..acc] })
  let observers =
    list.map(observer_indices, fn(index) {
      case index % 8 {
        0 -> ObsSystemHealth
        1 -> ObsOodaDecide
        2 -> ObsPlanStatus
        3 -> ObsStpa
        4 -> ObsRete
        5 -> ObsFeatures
        6 -> ObsResource
        _ -> ObsPrompt
      }
    })

  let assert 50 = list.length(observers)

  let #(final_pool, final_backends) =
    list.fold(observers, #(pool, backends), fn(state, observer) {
      let #(current_pool, current_backends) = state
      case observer {
        ObsSystemHealth -> {
          let #(_, next_pool, next_backends) =
            server.execute_authenticated(
              context,
              current_pool,
              current_backends,
              "system_health",
              dict.new(),
            )
          #(next_pool, next_backends)
        }
        ObsOodaDecide -> {
          let #(_, next_pool, next_backends) =
            server.execute_authenticated(
              context,
              current_pool,
              current_backends,
              "ooda_decide",
              dict.new(),
            )
          #(next_pool, next_backends)
        }
        ObsPlanStatus -> {
          let #(_, next_pool, next_backends) =
            server.execute_authenticated(
              context,
              current_pool,
              current_backends,
              "sa_plan_status",
              dict.new(),
            )
          #(next_pool, next_backends)
        }
        ObsStpa -> {
          let #(_, next_pool, next_backends) =
            server.execute_authenticated(
              context,
              current_pool,
              current_backends,
              "stpa_fmea_hazard",
              dict.from_list([
                #("severity", "2"),
                #("occurrence", "3"),
                #("detection", "4"),
              ]),
            )
          #(next_pool, next_backends)
        }
        ObsRete -> {
          let #(_, next_pool, next_backends) =
            server.execute_authenticated(
              context,
              current_pool,
              current_backends,
              "rete_rule_conflict",
              dict.from_list([
                #("rules", "door_open:allow,door_open:deny"),
              ]),
            )
          #(next_pool, next_backends)
        }
        ObsFeatures -> {
          let #(_, next_pool, next_backends) =
            server.execute_authenticated(
              context,
              current_pool,
              current_backends,
              "mcp_capability_inventory",
              dict.new(),
            )
          #(next_pool, next_backends)
        }
        ObsResource -> {
          let _ =
            resources.read_resource(
              resource_registry,
              resource_cache,
              context.principal,
              "uos://workspace/public/report",
            )
          let _ =
            resources.list_resources(
              resource_registry,
              resource_cache,
              context.principal,
              resources.page_default,
              0,
            )
          #(current_pool, current_backends)
        }
        ObsPrompt -> {
          let _ =
            prompts.get_prompt(
              prompt_registry,
              "summarize_plan",
              dict.from_list([#("plan_id", "plan-1")]),
            )
          let _ = prompts.list_prompts(prompt_registry)
          #(current_pool, current_backends)
        }
      }
    })

  #(final_backends.planning_write, final_backends.control)
  |> should.equal(#(initial_write, initial_control))
  final_backends.planning_write.tasks
  |> should.equal(initial_write.tasks)
  final_backends.control.controllers
  |> should.equal(initial_control.controllers)
  final_pool.ledger |> should.equal(initial_ledger)
  final_pool |> should.equal(pool)
  context.task_fence |> should.equal(initial_fence)
}

// ---------------------------------------------------------------------------
// 3. Killed worker descendant containment + receipt reconciliation + replacement
// ---------------------------------------------------------------------------

pub fn killed_worker_leaves_no_unowned_descendants_test() {
  // An isolated worker mid-effect spawns a linked child, then is killed. The
  // kill signal must take the whole linked subtree down with it.
  let child_subject = process.new_subject()
  let worker_pid =
    process.spawn_unlinked(fn() {
      let child_pid = process.spawn(fn() { process.sleep_forever() })
      process.send(child_subject, child_pid)
      process.sleep_forever()
    })

  let assert Ok(child_pid) = process.receive(child_subject, 1000)
  process.is_alive(worker_pid) |> should.be_true
  process.is_alive(child_pid) |> should.be_true

  process.kill(worker_pid)
  process.sleep(50)

  process.is_alive(worker_pid) |> should.be_false
  process.is_alive(child_pid) |> should.be_false

  // A crash after the effect is latched EffectUncertain: blind replay is
  // blocked until an explicit reconcile resolves it.
  let ledger = receipts.new_ledger("assurance-candidate")
  let intent_id = "assurance-crash-after-effect"
  let payload_hash =
    receipts.hash_payload("sa_task_complete", [
      #("plan_id", "assurance-plan"),
      #("task_id", "assurance-task"),
    ])

  let #(crash_outcome, ledger1) =
    worker.run_isolated_with_receipts(
      ledger,
      intent_id: intent_id,
      route: "public",
      tool: "sa_task_complete",
      payload_hash: payload_hash,
      action: fn() {
        worker.SimulatedCrashAfterEffect("mid_effect_worker_killed")
      },
    )
  let assert types.Uncertain(receipt) = crash_outcome
  receipt.intent_id |> should.equal(intent_id)
  receipt.tool |> should.equal("sa_task_complete")

  let #(blind_replay, ledger2) =
    worker.run_isolated_with_receipts(
      ledger1,
      intent_id: intent_id,
      route: "public",
      tool: "sa_task_complete",
      payload_hash: payload_hash,
      action: fn() {
        should.fail()
        worker.WorkerSuccess("unreachable")
      },
    )
  let assert types.Refused(blind_error) = blind_replay
  blind_error.code
  |> should.equal("UNCERTAIN_RECEIPT_RECONCILE_REQUIRED")

  let resolved =
    evidence.classify_backend_payload(
      "public",
      "sa_task_complete",
      "{\"ok\":true}",
      "assurance-candidate",
    )
  let assert Ok(ledger3) =
    receipts.reconcile_uncertain(
      ledger2,
      intent_id: intent_id,
      resolved_outcome: resolved,
    )

  let #(reconciled, _) =
    worker.run_isolated_with_receipts(
      ledger3,
      intent_id: intent_id,
      route: "public",
      tool: "sa_task_complete",
      payload_hash: payload_hash,
      action: fn() {
        should.fail()
        worker.WorkerSuccess("unreachable")
      },
    )
  let assert types.Complete(value, _) = reconciled
  value |> should.equal("{\"ok\":true}")

  // Poisoned-worker replacement increments the generation and leaves the next
  // call on the fresh generation clean.
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let initial_generation = supervisor.active_worker_generation(pool)
  let replacement = supervisor.replace_poisoned_worker(pool)
  supervisor.active_worker_generation(replacement)
  |> should.equal(initial_generation + 1)

  let #(clean, _) =
    worker.run_isolated_with_receipts(
      replacement.ledger,
      intent_id: "assurance-post-replacement",
      route: "public",
      tool: "plan_status",
      payload_hash: receipts.hash_payload("plan_status", []),
      action: fn() { worker.WorkerSuccess("{\"status\":\"healthy\"}") },
    )
  let assert types.Complete(clean_value, _) = clean
  clean_value |> should.equal("{\"status\":\"healthy\"}")
}

// ---------------------------------------------------------------------------
// 4. Overload refusal budget + 10,000-request concurrency-16 benchmark
// ---------------------------------------------------------------------------

type BenchResult {
  BenchResult(tag: String, elapsed_us: Int)
}

const refusal_budget_us = 50_000

const warm_read_p95_budget_us = 250_000

pub fn overload_refuses_within_budget_test() {
  let subscriber = assurance_principal()

  // --- Part A1: subscription backpressure synchronously refuses over 128 ---
  let assert Ok(initial_store) =
    subscriptions.subscribe(
      subscriptions.empty_store(),
      types.Modern20260728,
      subscriber,
      "assurance-sub",
      subscriptions.ResourceSubscription("uos://workspace/public/report"),
    )
  let full_store =
    int.range(
      from: 0,
      to: subscriptions.max_pending_notifications,
      with: initial_store,
      run: fn(store, index) {
        let assert Ok(next) =
          subscriptions.push_notification(
            store,
            "assurance-sub",
            "n" <> int.to_string(index),
          )
        next
      },
    )

  // Warm the refusal paths once so first-call module loading and JIT do not
  // count against the synchronous refusal budget measured below.
  let _ = subscriptions.push_notification(full_store, "assurance-sub", "warm")

  let backpressure_start = now_us()
  let assert Error(backpressure) =
    subscriptions.push_notification(full_store, "assurance-sub", "overflow")
  let backpressure_elapsed = now_us() - backpressure_start
  backpressure.code |> should.equal("SUBSCRIPTION_BACKPRESSURE_LIMIT")
  { backpressure_elapsed < refusal_budget_us } |> should.be_true

  // --- Part A2: oversized stdio frame refuses within budget ---
  // Buffer a full-size partial frame (setup, unmeasured); the measured call is
  // the single byte that pushes the in-progress frame beyond 1 MiB.
  let assert Ok(frame_session) = assurance_stdio_session()
  let assert Ok(#(full_buffer_session, _)) =
    stdio.ingest_chunk(
      frame_session,
      string.repeat("a", stdio.max_frame_bytes),
      0,
      complete_handler,
    )
  let frame_start = now_us()
  let assert Error(frame_error) =
    stdio.ingest_chunk(full_buffer_session, "a", 0, complete_handler)
  let frame_elapsed = now_us() - frame_start
  frame_error.code |> should.equal("STDIO_FRAME_TOO_LARGE")
  { frame_elapsed < refusal_budget_us } |> should.be_true

  // --- Part A3: slow-frame deadline refuses within budget ---
  let assert Ok(deadline_session) = assurance_stdio_session()
  let assert Ok(#(partial_session, _)) =
    stdio.ingest_chunk(
      deadline_session,
      "{\"jsonrpc\":\"2.0\",\"id\":2,",
      0,
      complete_handler,
    )
  let deadline_start = now_us()
  let assert Error(deadline_error) =
    stdio.ingest_chunk(
      partial_session,
      "\"method\":\"ping\"}",
      2000,
      complete_handler,
    )
  let deadline_elapsed = now_us() - deadline_start
  deadline_error.code |> should.equal("STDIO_FRAME_DEADLINE_EXCEEDED")
  { deadline_elapsed < refusal_budget_us } |> should.be_true

  // --- Part B: 16 concurrent workers * 625 warm reads = 10,000 requests ---
  let context = control_authority_context()
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let backends = authenticated_backends()
  let results: process.Subject(BenchResult) = process.new_subject()
  let worker_count = 16
  let per_worker = 625

  int.range(from: 0, to: worker_count, with: Nil, run: fn(_, _worker) {
    process.spawn_unlinked(fn() {
      int.range(from: 0, to: per_worker, with: Nil, run: fn(_, request) {
        let tool = case request % 5 {
          0 -> "sa_plan_status"
          1 -> "system_health"
          2 -> "safety_status"
          3 -> "vault_status"
          _ -> "mcp_capability_inventory"
        }
        let start = now_us()
        let #(outcome, _, _) =
          server.execute_authenticated(
            context,
            pool,
            backends,
            tool,
            dict.new(),
          )
        let elapsed = now_us() - start
        let tag = case outcome {
          types.Complete(_, _) -> "complete"
          _ -> "other"
        }
        process.send(results, BenchResult(tag, elapsed))
        Nil
      })
      Nil
    })
    Nil
  })

  let collected =
    int.range(from: 0, to: worker_count * per_worker, with: [], run: fn(acc, _) {
      let assert Ok(result) = process.receive(results, 60_000)
      [result, ..acc]
    })

  list.length(collected) |> should.equal(10_000)
  list.count(collected, fn(result) { result.tag == "complete" })
  |> should.equal(10_000)

  let sorted_times =
    collected
    |> list.map(fn(result) { result.elapsed_us })
    |> list.sort(int.compare)
  let p95_index = { 95 * list.length(sorted_times) + 99 } / 100 - 1
  let assert Ok(p95_us) =
    sorted_times
    |> list.drop(p95_index)
    |> list.first
  { p95_us <= warm_read_p95_budget_us } |> should.be_true
}
