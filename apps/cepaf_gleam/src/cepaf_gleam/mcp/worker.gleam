//// Isolated MCP Worker Execution with per-call deadlines, crash classification,
//// and receipt reconciliation.

import cepaf_gleam/mcp/evidence
import cepaf_gleam/mcp/receipts.{
  type ReceiptLedger, EffectUncertain, OutcomeCommitted, ReceiptEntry,
}
import cepaf_gleam/mcp/types.{
  type Outcome, NonRetryable, Refused, Retryable, ToolError, Uncertain,
}
import gleam/option.{Some}

pub type WorkerActionResult {
  WorkerSuccess(String)
  WorkerFailure(String)
  WorkerTimeout(Int)
  SimulatedCrashBeforeEffect(String)
  SimulatedCrashAfterEffect(String)
}

pub fn run_isolated_with_receipts(
  ledger: ReceiptLedger,
  intent_id intent_id: String,
  route route: String,
  tool tool: String,
  payload_hash payload_hash: String,
  action action: fn() -> WorkerActionResult,
) -> #(Outcome, ReceiptLedger) {
  case
    receipts.record_intent(
      ledger,
      intent_id: intent_id,
      route: route,
      tool: tool,
      payload_hash: payload_hash,
    )
  {
    Error(conflict_err) -> #(Refused(conflict_err), ledger)
    Ok(ledger_with_intent) ->
      case receipts.lookup(ledger_with_intent, intent_id) {
        Some(ReceiptEntry(state: OutcomeCommitted(stored_outcome), ..)) ->
          #(stored_outcome, ledger_with_intent)
        Some(ReceiptEntry(state: EffectUncertain(_), ..)) ->
          #(
            Refused(ToolError(
              code: "UNCERTAIN_RECEIPT_RECONCILE_REQUIRED",
              reason: "Uncertain effect latched Andon; explicit reconcile required",
              retryability: NonRetryable,
            )),
            ledger_with_intent,
          )
        _ -> run_action(
          ledger_with_intent,
          intent_id: intent_id,
          route: route,
          tool: tool,
          action: action,
        )
      }
  }
}

fn run_action(
  ledger_with_intent ledger_with_intent: ReceiptLedger,
  intent_id intent_id: String,
  route route: String,
  tool tool: String,
  action action: fn() -> WorkerActionResult,
) -> #(Outcome, ReceiptLedger) {
  case action() {
        WorkerSuccess(payload) -> {
          let outcome =
            evidence.classify_backend_payload(
              route,
              tool,
              payload,
              ledger_with_intent.candidate,
            )
          let updated =
            receipts.mark_complete(
              ledger_with_intent,
              intent_id: intent_id,
              outcome: outcome,
            )
          #(outcome, updated)
        }
        WorkerFailure(reason) -> {
          let outcome =
            Refused(ToolError(
              code: "WORKER_ISOLATED_FAILURE",
              reason: reason,
              retryability: NonRetryable,
            ))
          #(outcome, ledger_with_intent)
        }
        WorkerTimeout(budget_ms) -> {
          let outcome =
            Refused(ToolError(
              code: "WORKER_DEADLINE_EXCEEDED",
              reason: "Worker exceeded deadline budget_ms",
              retryability: Retryable,
            ))
          let _ = budget_ms
          #(outcome, ledger_with_intent)
        }
        SimulatedCrashBeforeEffect(reason) -> {
          let outcome =
            Refused(ToolError(
              code: "WORKER_CRASH_BEFORE_EFFECT",
              reason: reason,
              retryability: Retryable,
            ))
          #(outcome, ledger_with_intent)
        }
        SimulatedCrashAfterEffect(reason) -> {
          let #(receipt, updated) =
            receipts.mark_uncertain(
              ledger_with_intent,
              intent_id: intent_id,
              reason: reason,
            )
          #(Uncertain(receipt), updated)
        }
  }
}
