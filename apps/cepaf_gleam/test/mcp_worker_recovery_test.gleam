import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/dispatch
import cepaf_gleam/mcp/evidence
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/supervisor as mcp_sup
import cepaf_gleam/mcp/types.{
  ClientProfile, Complete, NonRetryable, Refused, TaskScopedMutation,
  Uncertain,
}
import cepaf_gleam/mcp/worker
import cepaf_gleam/uos_sup
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleeunit/should

pub fn gateway_is_actual_root_child_test() {
  let root_spec = uos_sup.uos_root_spec()
  let all_children =
    list.flat_map(root_spec.domains, fn(domain) { domain.children })
  list.contains(all_children, "mcp_unified_gateway")
  |> should.be_true()

  let assert Ok(tree) = mcp_sup.start_supervised_gateway()
  mcp_sup.is_gateway_alive(tree)
  |> should.be_true()
  mcp_sup.child_id(tree)
  |> should.equal("mcp_unified_gateway")
}

pub fn crash_after_effect_before_reply_is_uncertain_test() {
  let ledger = receipts.new_ledger("commit-cand-04")
  let intent_id = "intent-crash-after-effect-01"
  let payload_hash = receipts.hash_payload("sa_task_complete", [
    #("plan_id", "20261029-1913-mcp-server-completion"),
    #("task_id", "T04"),
  ])

  let assert Ok(ledger1) =
    receipts.record_intent(
      ledger,
      intent_id: intent_id,
      route: "public",
      tool: "sa_task_complete",
      payload_hash: payload_hash,
    )

  // Worker crashes after side-effect committed before reply could be returned
  let outcome =
    worker.run_isolated_with_receipts(
      ledger1,
      intent_id: intent_id,
      route: "public",
      tool: "sa_task_complete",
      payload_hash: payload_hash,
      action: fn() { worker.SimulatedCrashAfterEffect("effect_committed_pipe_broken") },
    )

  case outcome {
    #(Uncertain(receipt), _updated_ledger) -> {
      receipt.intent_id |> should.equal(intent_id)
      receipt.tool |> should.equal("sa_task_complete")
      receipt.candidate |> should.equal("commit-cand-04")
    }
    _ -> should.fail()
  }
}

pub fn same_id_conflicting_payload_refused_test() {
  let ledger = receipts.new_ledger("commit-cand-04")
  let intent_id = "req-idempotent-42"
  let hash_a = receipts.hash_payload("plan_update", [#("task_id", "T04"), #("state", "executing")])
  let hash_b = receipts.hash_payload("plan_update", [#("task_id", "T04"), #("state", "completed")])

  let assert Ok(ledger1) =
    receipts.record_intent(
      ledger,
      intent_id: intent_id,
      route: "public",
      tool: "plan_update",
      payload_hash: hash_a,
    )

  case
    receipts.record_intent(
      ledger1,
      intent_id: intent_id,
      route: "public",
      tool: "plan_update",
      payload_hash: hash_b,
    )
  {
    Ok(_) -> should.fail()
    Error(err) -> {
      err.code |> should.equal("IDEMPOTENCY_CONFLICT")
      err.retryability |> should.equal(NonRetryable)
    }
  }
}

pub fn matching_replay_returns_committed_without_reexecuting_test() {
  let ledger = receipts.new_ledger("commit-cand-04")
  let intent_id = "intent-replay-committed-01"
  let payload_hash =
    receipts.hash_payload("sa_task_complete", [
      #("plan_id", "20261029-1913-mcp-server-completion"),
      #("task_id", "T04"),
    ])

  let #(first_outcome, ledger1) =
    worker.run_isolated_with_receipts(
      ledger,
      intent_id: intent_id,
      route: "public",
      tool: "sa_task_complete",
      payload_hash: payload_hash,
      action: fn() { worker.WorkerSuccess("{\"ok\":true}") },
    )

  case first_outcome {
    Complete("{\"ok\":true}", _) -> Nil
    _ -> should.fail()
  }

  // Exact replay must return the committed outcome without re-executing action.
  let #(replay_outcome, _ledger2) =
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

  case replay_outcome {
    Complete(value, _) -> value |> should.equal("{\"ok\":true}")
    _ -> should.fail()
  }
}

pub fn uncertain_replay_refuses_until_explicit_reconcile_test() {
  let ledger = receipts.new_ledger("commit-cand-04")
  let intent_id = "intent-replay-uncertain-01"
  let payload_hash =
    receipts.hash_payload("sa_task_complete", [
      #("plan_id", "20261029-1913-mcp-server-completion"),
      #("task_id", "T04"),
    ])

  let #(crash_outcome, ledger1) =
    worker.run_isolated_with_receipts(
      ledger,
      intent_id: intent_id,
      route: "public",
      tool: "sa_task_complete",
      payload_hash: payload_hash,
      action: fn() {
        worker.SimulatedCrashAfterEffect("effect_committed_pipe_broken")
      },
    )

  case crash_outcome {
    Uncertain(_) -> Nil
    _ -> should.fail()
  }

  // Replaying an EffectUncertain intent must refuse and latch Andon, not re-run.
  let #(refused_outcome, ledger2) =
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

  case refused_outcome {
    Refused(err) ->
      err.code |> should.equal("UNCERTAIN_RECEIPT_RECONCILE_REQUIRED")
    _ -> should.fail()
  }

  // Explicit reconciliation resolves the uncertain effect.
  let resolved_outcome =
    evidence.classify_backend_payload(
      "public",
      "sa_task_complete",
      "{\"ok\":true}",
      "commit-cand-04",
    )
  let assert Ok(ledger3) =
    receipts.reconcile_uncertain(
      ledger2,
      intent_id: intent_id,
      resolved_outcome: resolved_outcome,
    )

  let #(reconciled_outcome, _ledger4) =
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

  case reconciled_outcome {
    Complete(value, _) -> value |> should.equal("{\"ok\":true}")
    _ -> should.fail()
  }
}

pub fn poisoned_worker_is_replaced_test() {
  let assert Ok(pool) = mcp_sup.start_worker_pool(size: 2)
  let initial_gen = mcp_sup.active_worker_generation(pool)

  // First invocation poisons/times out the worker
  let poisoned_outcome =
    dispatch.execute_on_pool(
      pool,
      route: "public",
      tool: "verification_run",
      intent_id: "poison-01",
      simulate: dispatch.SimulateWorkerPoison("native_port_hung"),
    )

  case poisoned_outcome {
    #(Refused(err), pool_after_poison) -> {
      err.code |> should.equal("WORKER_ISOLATED_FAILURE")
      // Replacement worker must have incremented generation and succeed cleanly
      let next_gen = mcp_sup.active_worker_generation(pool_after_poison)
      should.be_true(next_gen > initial_gen)

      let assert Ok(spec) = registry.lookup("public", "plan_status")
      let p =
        principal.from_launcher_env(
          actor: "agy-worker-20261030",
          client: ClientProfile("agy"),
          workspace_root: "/home/an/NAS-setup/uos",
          session_id: "sess-004",
        )
      let ctx =
        admission.AdmissionContext(
          principal: p,
          mode: admission.EnforcedMode,
          now_ms: 1_000_000,
          workspace_root: "/home/an/NAS-setup/uos",
          task_fence: Some(admission.TaskFence(
            plan_id: "20261029-1913-mcp-server-completion",
            task_id: "T04",
            worker_id: "agy-worker-20261030",
            attempt: 1,
            task_state: admission.TaskExecuting,
            lease_until_ms: 5_000_000,
            grant: Some(admission.GrantTicket(
              grant_id: "g-04",
              scope: TaskScopedMutation,
              revoked: False,
              expires_at_ms: 5_000_000,
              workspace_root: "/home/an/NAS-setup/uos",
            )),
          )),
        )
      let assert Ok(call) = admission.admit(ctx, spec, dict.new())
      let #(clean_outcome, _) =
        dispatch.dispatch_validated(
          pool_after_poison,
          ctx,
          call,
          fn(_args) { Ok("{\"status\":\"healthy\"}") },
        )
      case clean_outcome {
        Complete(val, ev) -> {
          val |> should.equal("{\"status\":\"healthy\"}")
          ev.tool |> should.equal("plan_status")
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}
