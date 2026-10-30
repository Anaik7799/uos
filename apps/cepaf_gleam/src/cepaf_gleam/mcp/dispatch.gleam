//// Unified MCP Dispatch Pipeline: Admission -> Effect-Time Re-Verification ->
//// Isolated Worker Execution -> Evidence Classification & Receipt Recording.

import cepaf_gleam/mcp/admission.{
  type AdmissionContext, type ValidatedCall, verify_at_effect_time,
}
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/supervisor.{type WorkerPool, WorkerPool}
import cepaf_gleam/mcp/types.{type Outcome, Refused}
import cepaf_gleam/mcp/worker.{
  SimulatedCrashAfterEffect, SimulatedCrashBeforeEffect, WorkerFailure,
  WorkerSuccess, WorkerTimeout,
}
import gleam/dict.{type Dict}
import gleam/int
import gleam/option

pub type SimulatedExecution {
  SimulateSuccess(String)
  SimulateWorkerPoison(String)
  SimulateWorkerTimeout(Int)
  SimulateCrashBeforeEffect(String)
  SimulateCrashAfterEffect(String)
}

pub fn execute_on_pool(
  pool: WorkerPool,
  route route: String,
  tool tool: String,
  intent_id intent_id: String,
  simulate simulate: SimulatedExecution,
) -> #(Outcome, WorkerPool) {
  let payload_hash = receipts.hash_payload(tool, [#("intent_id", intent_id)])
  case simulate {
    SimulateWorkerPoison(reason) -> {
      let #(outcome, updated_ledger) =
        worker.run_isolated_with_receipts(
          pool.ledger,
          intent_id: intent_id,
          route: route,
          tool: tool,
          payload_hash: payload_hash,
          action: fn() { WorkerFailure(reason) },
        )
      let replaced = supervisor.replace_poisoned_worker(pool)
      #(outcome, WorkerPool(..replaced, ledger: updated_ledger))
    }
    SimulateWorkerTimeout(budget_ms) -> {
      let #(outcome, updated_ledger) =
        worker.run_isolated_with_receipts(
          pool.ledger,
          intent_id: intent_id,
          route: route,
          tool: tool,
          payload_hash: payload_hash,
          action: fn() { WorkerTimeout(budget_ms) },
        )
      let replaced = supervisor.replace_poisoned_worker(pool)
      #(outcome, WorkerPool(..replaced, ledger: updated_ledger))
    }
    SimulateCrashBeforeEffect(reason) -> {
      let #(outcome, updated_ledger) =
        worker.run_isolated_with_receipts(
          pool.ledger,
          intent_id: intent_id,
          route: route,
          tool: tool,
          payload_hash: payload_hash,
          action: fn() { SimulatedCrashBeforeEffect(reason) },
        )
      let replaced = supervisor.replace_poisoned_worker(pool)
      #(outcome, WorkerPool(..replaced, ledger: updated_ledger))
    }
    SimulateCrashAfterEffect(reason) -> {
      let #(outcome, updated_ledger) =
        worker.run_isolated_with_receipts(
          pool.ledger,
          intent_id: intent_id,
          route: route,
          tool: tool,
          payload_hash: payload_hash,
          action: fn() { SimulatedCrashAfterEffect(reason) },
        )
      let replaced = supervisor.replace_poisoned_worker(pool)
      #(outcome, WorkerPool(..replaced, ledger: updated_ledger))
    }
    SimulateSuccess(payload) -> {
      let #(outcome, updated_ledger) =
        worker.run_isolated_with_receipts(
          pool.ledger,
          intent_id: intent_id,
          route: route,
          tool: tool,
          payload_hash: payload_hash,
          action: fn() { WorkerSuccess(payload) },
        )
      #(outcome, WorkerPool(..pool, ledger: updated_ledger))
    }
  }
}

pub fn dispatch_validated(
  pool: WorkerPool,
  context: AdmissionContext,
  call: ValidatedCall,
  handler: fn(Dict(String, String)) -> Result(String, String),
) -> #(Outcome, WorkerPool) {
  case verify_at_effect_time(context, call) {
    Error(err) -> #(Refused(err), pool)
    Ok(verified) -> {
      let fields = dict.to_list(verified.arguments)
      let payload_hash = receipts.hash_payload(verified.spec.name, fields)
      let owner_hash =
        receipts.hash_payload(verified.spec.name, [
          #("actor", principal.actor_id(verified.principal)),
          #("workspace", principal.workspace_root(verified.principal)),
          #("plan_id", option.unwrap(verified.plan_id, "")),
          #("task_id", option.unwrap(verified.task_id, "")),
          #("attempt", int.to_string(option.unwrap(verified.attempt, 0))),
          #("grant_id", option.unwrap(verified.grant_id, "")),
        ])
      let logical_id = case dict.get(verified.arguments, "intent_id") {
        Ok(id) if id != "" -> id
        _ -> payload_hash
      }
      let intent_id =
        verified.spec.route
        <> ":"
        <> verified.spec.name
        <> ":"
        <> owner_hash
        <> ":"
        <> logical_id
      let #(outcome, updated_ledger) =
        worker.run_isolated_with_receipts(
          pool.ledger,
          intent_id: intent_id,
          route: verified.spec.route,
          tool: verified.spec.name,
          payload_hash: payload_hash,
          action: fn() {
            case handler(verified.arguments) {
              Ok(payload) -> WorkerSuccess(payload)
              Error(reason) -> WorkerFailure(reason)
            }
          },
        )
      #(outcome, WorkerPool(..pool, ledger: updated_ledger))
    }
  }
}
