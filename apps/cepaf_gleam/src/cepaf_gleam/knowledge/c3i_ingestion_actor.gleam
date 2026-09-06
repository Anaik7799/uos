//// =============================================================================
//// Canonical Module: cepaf_gleam/knowledge/c3i_ingestion_actor.gleam
//// Language: Pure Gleam / BEAM OTP 29
//// Security / Reliability: SIL-6 / Zero-Trust Ingress Interception
//// Contract: SPEC-C3I-KNOWLEDGE-RUNTIME-001, SC-MUDA-001, SC-STORAGE-SAFETY-001
//// =============================================================================

import cepaf_gleam/knowledge/c3i_knowledge_runtime.{
  type AntiPatternSpec, type CitedKnowledgeItem, detect_anti_patterns,
  detect_zero_trust_ingress_violations, get_standard_anti_patterns,
}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor

/// Ingestion evaluation summary for a batch of items
pub type IngestionBatchReport {
  IngestionBatchReport(
    total_received: Int,
    admitted_count: Int,
    rejected_count: Int,
    zero_trust_violations: Int,
    anti_patterns_detected: Int,
  )
}

/// Cumulative ingestion metrics
pub type IngestionMetrics {
  IngestionMetrics(
    batches_processed: Int,
    total_items_admitted: Int,
    total_items_rejected: Int,
    zero_trust_violations: Int,
  )
}

/// Actor internal state
pub type State {
  State(
    batches_processed: Int,
    total_items_admitted: Int,
    total_items_rejected: Int,
    zero_trust_violations: Int,
    anti_patterns: List(AntiPatternSpec),
  )
}

/// Messages accepted by the C3I Ingestion Actor
pub type Message {
  ValidatePayload(content: String, reply_to: Subject(Result(Nil, String)))
  SanitizeAndIngest(
    items: List(CitedKnowledgeItem),
    reply_to: Subject(IngestionBatchReport),
  )
  GetMetrics(reply_to: Subject(IngestionMetrics))
  Reset
}

/// Initial state builder
pub fn initial_state() -> State {
  State(
    batches_processed: 0,
    total_items_admitted: 0,
    total_items_rejected: 0,
    zero_trust_violations: 0,
    anti_patterns: get_standard_anti_patterns(),
  )
}

/// Start the supervised C3I Ingestion Actor
pub fn start() -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new(initial_state())
  |> actor.on_message(handle_message)
  |> actor.start()
}

/// Message handler for the Ingestion Actor
pub fn handle_message(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    ValidatePayload(content, reply_to) -> {
      let violation = detect_zero_trust_ingress_violations(content)
      case violation {
        Ok(Nil) -> {
          let detected = detect_anti_patterns(content)
          case list.is_empty(detected) {
            True -> {
              process.send(reply_to, Ok(Nil))
              actor.continue(state)
            }
            False -> {
              process.send(
                reply_to,
                Error("Anti-pattern detected in ingress payload"),
              )
              actor.continue(state)
            }
          }
        }
        Error(err) -> {
          process.send(reply_to, Error(err))
          let new_state =
            State(
              ..state,
              zero_trust_violations: state.zero_trust_violations + 1,
            )
          actor.continue(new_state)
        }
      }
    }

    SanitizeAndIngest(items, reply_to) -> {
      let total = list.length(items)
      let #(admitted, rejected, zt_count, ap_count) =
        list.fold(items, #(0, 0, 0, 0), fn(acc, item) {
          let #(adm, rej, zt, ap) = acc
          let zt_res = detect_zero_trust_ingress_violations(item.citation_text)
          case zt_res {
            Error(_) -> #(adm, rej + 1, zt + 1, ap)
            Ok(Nil) -> {
              let detected = detect_anti_patterns(item.citation_text)
              case list.is_empty(detected) {
                False -> #(adm, rej + 1, zt, ap + 1)
                True -> #(adm + 1, rej, zt, ap)
              }
            }
          }
        })

      let report =
        IngestionBatchReport(
          total_received: total,
          admitted_count: admitted,
          rejected_count: rejected,
          zero_trust_violations: zt_count,
          anti_patterns_detected: ap_count,
        )
      process.send(reply_to, report)

      let new_state =
        State(
          ..state,
          batches_processed: state.batches_processed + 1,
          total_items_admitted: state.total_items_admitted + admitted,
          total_items_rejected: state.total_items_rejected + rejected,
          zero_trust_violations: state.zero_trust_violations + zt_count,
        )
      actor.continue(new_state)
    }

    GetMetrics(reply_to) -> {
      let metrics =
        IngestionMetrics(
          batches_processed: state.batches_processed,
          total_items_admitted: state.total_items_admitted,
          total_items_rejected: state.total_items_rejected,
          zero_trust_violations: state.zero_trust_violations,
        )
      process.send(reply_to, metrics)
      actor.continue(state)
    }

    Reset -> {
      actor.continue(initial_state())
    }
  }
}
