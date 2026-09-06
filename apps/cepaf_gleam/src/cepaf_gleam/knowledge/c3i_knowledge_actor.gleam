//// =============================================================================
//// Canonical Module: cepaf_gleam/knowledge/c3i_knowledge_actor.gleam
//// Language: Pure Gleam / BEAM OTP 29
//// Security / Reliability: SIL-6 / Rocha Biosemiotic Semantic Closure
//// Contract: SPEC-C3I-KNOWLEDGE-RUNTIME-001, SC-KM-001, SC-CHECKLIST-001
//// =============================================================================

import cepaf_gleam/knowledge/c3i_knowledge_runtime.{
  type AntiPatternSpec, type CitedKnowledgeItem, type KnowledgeRecallResult,
  compute_decayed_trust, get_c3i_knowledge_runtime_status,
  get_standard_anti_patterns, ingest_c3i_knowledge_inventory, query_cited_recall,
}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/string

/// State held by the C3I Knowledge Actor
pub type State {
  State(
    inventory: List(CitedKnowledgeItem),
    anti_patterns: List(AntiPatternSpec),
    queries_handled: Int,
    ingestions_handled: Int,
  )
}

/// Messages accepted by the C3I Knowledge Actor
pub type Message {
  QueryKnowledge(
    query: String,
    min_trust: Float,
    reply_to: Subject(List(CitedKnowledgeItem)),
  )
  CitedRecall(
    query: String,
    min_trust: Float,
    reply_to: Subject(KnowledgeRecallResult),
  )
  IngestItem(item: CitedKnowledgeItem, reply_to: Subject(Result(Nil, String)))
  ApplyDecay(age_increment_days: Float, reply_to: Subject(Int))
  GetStatus(reply_to: Subject(String))
  Reset
}

/// Initializes state with authoritative C3I default inventory and anti-patterns
pub fn initial_state() -> State {
  State(
    inventory: ingest_c3i_knowledge_inventory(),
    anti_patterns: get_standard_anti_patterns(),
    queries_handled: 0,
    ingestions_handled: 0,
  )
}

/// Start the supervised C3I Knowledge Actor
pub fn start() -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new(initial_state())
  |> actor.on_message(handle_message)
  |> actor.start()
}

/// Message handler for the C3I Knowledge Actor
pub fn handle_message(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    QueryKnowledge(query, min_trust, reply_to) -> {
      let filtered =
        state.inventory
        |> list.filter(fn(item) {
          item.decayed_trust >=. min_trust
          && {
            string.is_empty(query)
            || string.contains(
              string.lowercase(item.title),
              string.lowercase(query),
            )
            || string.contains(
              string.lowercase(item.citation_text),
              string.lowercase(query),
            )
          }
        })
      process.send(reply_to, filtered)
      let new_state =
        State(..state, queries_handled: state.queries_handled + 1)
      actor.continue(new_state)
    }

    CitedRecall(query, min_trust, reply_to) -> {
      let recall_result = query_cited_recall(query, min_trust)
      process.send(reply_to, recall_result)
      let new_state =
        State(..state, queries_handled: state.queries_handled + 1)
      actor.continue(new_state)
    }

    IngestItem(item, reply_to) -> {
      case string.is_empty(item.id) || string.is_empty(item.title) {
        True -> {
          process.send(
            reply_to,
            Error("Invalid item: ID and title must not be empty"),
          )
          actor.continue(state)
        }
        False -> {
          let updated_inv = [item, ..state.inventory]
          process.send(reply_to, Ok(Nil))
          let new_state =
            State(
              ..state,
              inventory: updated_inv,
              ingestions_handled: state.ingestions_handled + 1,
            )
          actor.continue(new_state)
        }
      }
    }

    ApplyDecay(age_increment_days, reply_to) -> {
      let updated_inv =
        state.inventory
        |> list.map(fn(item) {
          let new_decayed =
            compute_decayed_trust(item.decayed_trust, age_increment_days, 1.0)
          c3i_knowledge_runtime.CitedKnowledgeItem(
            ..item,
            decayed_trust: new_decayed,
          )
        })
      let count = list.length(updated_inv)
      process.send(reply_to, count)
      let new_state = State(..state, inventory: updated_inv)
      actor.continue(new_state)
    }

    GetStatus(reply_to) -> {
      let status = get_c3i_knowledge_runtime_status()
      process.send(reply_to, status)
      actor.continue(state)
    }

    Reset -> {
      actor.continue(initial_state())
    }
  }
}
