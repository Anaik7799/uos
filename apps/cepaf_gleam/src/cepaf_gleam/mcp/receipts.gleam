//// Durable Receipt Ledger for idempotent MCP mutations and uncertain-effect
//// reconciliation across worker crashes or broken pipes.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolError, type UncertainReceipt, NonRetryable, ToolError,
  UncertainReceipt,
}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type ReceiptState {
  IntentRecorded
  OutcomeCommitted(Outcome)
  EffectUncertain(UncertainReceipt)
}

pub type ReceiptEntry {
  ReceiptEntry(
    intent_id: String,
    route: String,
    tool: String,
    payload_hash: String,
    candidate: String,
    state: ReceiptState,
  )
}

pub type ReceiptLedger {
  ReceiptLedger(candidate: String, entries: Dict(String, ReceiptEntry))
}

pub fn new_ledger(candidate: String) -> ReceiptLedger {
  ReceiptLedger(candidate: candidate, entries: dict.new())
}

pub fn hash_payload(tool: String, fields: List(#(String, String))) -> String {
  let canonical =
    fields
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(kv) { kv.0 <> "=" <> kv.1 })
    |> string.join("&")
  files.digest(tool <> ":" <> canonical)
}

pub fn record_intent(
  ledger: ReceiptLedger,
  intent_id intent_id: String,
  route route: String,
  tool tool: String,
  payload_hash payload_hash: String,
) -> Result(ReceiptLedger, ToolError) {
  case dict.get(ledger.entries, intent_id) {
    Ok(existing) ->
      case
        existing.payload_hash == payload_hash
        && existing.tool == tool
        && existing.route == route
      {
        True -> Ok(ledger)
        False ->
          Error(ToolError(
            code: "IDEMPOTENCY_CONFLICT",
            reason: "Same intent_id "
              <> intent_id
              <> " submitted with conflicting payload hash",
            retryability: NonRetryable,
          ))
      }
    Error(_) -> {
      let entry =
        ReceiptEntry(
          intent_id: intent_id,
          route: route,
          tool: tool,
          payload_hash: payload_hash,
          candidate: ledger.candidate,
          state: IntentRecorded,
        )
      Ok(
        ReceiptLedger(
          ..ledger,
          entries: dict.insert(ledger.entries, intent_id, entry),
        ),
      )
    }
  }
}

pub fn mark_uncertain(
  ledger: ReceiptLedger,
  intent_id intent_id: String,
  reason reason: String,
) -> #(UncertainReceipt, ReceiptLedger) {
  let #(route, tool) = case dict.get(ledger.entries, intent_id) {
    Ok(entry) -> #(entry.route, entry.tool)
    Error(_) -> #("public", "unknown")
  }
  let receipt =
    UncertainReceipt(
      intent_id: intent_id,
      route: route,
      tool: tool,
      reason: reason,
      candidate: ledger.candidate,
    )
  let updated = case dict.get(ledger.entries, intent_id) {
    Ok(entry) ->
      dict.insert(
        ledger.entries,
        intent_id,
        ReceiptEntry(..entry, state: EffectUncertain(receipt)),
      )
    Error(_) -> ledger.entries
  }
  #(receipt, ReceiptLedger(..ledger, entries: updated))
}

pub fn mark_complete(
  ledger: ReceiptLedger,
  intent_id intent_id: String,
  outcome outcome: Outcome,
) -> ReceiptLedger {
  case dict.get(ledger.entries, intent_id) {
    Ok(entry) ->
      case entry.state {
        IntentRecorded ->
          ReceiptLedger(
            ..ledger,
            entries: dict.insert(
              ledger.entries,
              intent_id,
              ReceiptEntry(..entry, state: OutcomeCommitted(outcome)),
            ),
          )
        OutcomeCommitted(_) | EffectUncertain(_) -> ledger
      }
    Error(_) -> ledger
  }
}

pub fn reconcile_uncertain(
  ledger: ReceiptLedger,
  intent_id intent_id: String,
  resolved_outcome resolved_outcome: Outcome,
) -> Result(ReceiptLedger, ToolError) {
  case dict.get(ledger.entries, intent_id) {
    Ok(entry) ->
      case entry.state {
        EffectUncertain(_) ->
          Ok(
            ReceiptLedger(
              ..ledger,
              entries: dict.insert(
                ledger.entries,
                intent_id,
                ReceiptEntry(..entry, state: OutcomeCommitted(resolved_outcome)),
              ),
            ),
          )
        IntentRecorded | OutcomeCommitted(_) ->
          Error(ToolError(
            code: "RECONCILE_TARGET_NOT_UNCERTAIN",
            reason: "Intent is not in EffectUncertain state",
            retryability: NonRetryable,
          ))
      }
    Error(_) ->
      Error(ToolError(
        code: "RECONCILE_TARGET_NOT_UNCERTAIN",
        reason: "Intent is not in EffectUncertain state",
        retryability: NonRetryable,
      ))
  }
}

pub fn lookup(ledger: ReceiptLedger, intent_id: String) -> Option(ReceiptEntry) {
  case dict.get(ledger.entries, intent_id) {
    Ok(entry) -> Some(entry)
    Error(_) -> None
  }
}
