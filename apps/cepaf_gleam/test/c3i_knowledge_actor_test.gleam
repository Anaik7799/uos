import cepaf_gleam/knowledge/c3i_ingestion_actor.{
  GetMetrics, ValidatePayload,
}
import cepaf_gleam/knowledge/c3i_knowledge_actor.{
  ApplyDecay, CitedRecall, IngestItem, QueryKnowledge,
}
import cepaf_gleam/knowledge/c3i_knowledge_runtime.{
  CitedKnowledgeItem, JournalEntry,
}
import gleam/list
import gleam/otp/actor
import gleeunit/should

pub fn start_and_query_knowledge_actor_test() {
  let assert Ok(started) = c3i_knowledge_actor.start()
  let subject = started.data

  let items =
    actor.call(subject, 500, fn(reply_to) { QueryKnowledge("", 0.0, reply_to) })
  list.length(items)
  |> should.equal(5)
}

pub fn ingest_new_item_actor_test() {
  let assert Ok(started) = c3i_knowledge_actor.start()
  let subject = started.data

  let new_item =
    CitedKnowledgeItem(
      id: "TEST-ITEM-01",
      title: "Test Ingested Article",
      category: JournalEntry,
      source_path: "docs/journal/test.md",
      citation_text: "Pure Gleam verified note",
      initial_trust: 1.0,
      decayed_trust: 1.0,
      verified: True,
    )

  let res =
    actor.call(subject, 500, fn(reply_to) { IngestItem(new_item, reply_to) })
  res |> should.be_ok()

  let items =
    actor.call(subject, 500, fn(reply_to) { QueryKnowledge("", 0.0, reply_to) })
  list.length(items)
  |> should.equal(6)
}

pub fn cited_recall_actor_test() {
  let assert Ok(started) = c3i_knowledge_actor.start()
  let subject = started.data

  let recall =
    actor.call(subject, 500, fn(reply_to) {
      CitedRecall("Journal", 0.5, reply_to)
    })
  recall.ocaml_oracle_verified |> should.be_true()
  recall.total_items |> should.equal(1)
}

pub fn apply_decay_actor_test() {
  let assert Ok(started) = c3i_knowledge_actor.start()
  let subject = started.data

  let count =
    actor.call(subject, 500, fn(reply_to) { ApplyDecay(1.0, reply_to) })
  count |> should.equal(5)

  let items =
    actor.call(subject, 500, fn(reply_to) { QueryKnowledge("", 0.0, reply_to) })
  let assert Ok(first) = list.first(items)
  should.be_true(first.decayed_trust <. first.initial_trust)
}

pub fn ingestion_actor_zero_trust_filter_test() {
  let assert Ok(started) = c3i_ingestion_actor.start()
  let subject = started.data

  // Safe payload
  let safe_res =
    actor.call(subject, 500, fn(reply_to) {
      ValidatePayload("Pure Gleam code", reply_to)
    })
  safe_res |> should.be_ok()

  // Malicious NUL byte payload
  let nul_res =
    actor.call(subject, 500, fn(reply_to) {
      ValidatePayload("Malicious payload\u{0000}bad", reply_to)
    })
  nul_res |> should.be_error()

  // Malicious SQL injection payload
  let sql_res =
    actor.call(subject, 500, fn(reply_to) {
      ValidatePayload("SELECT * FROM passwords; DROP TABLE users;", reply_to)
    })
  sql_res |> should.be_error()

  // Verify metrics
  let metrics =
    actor.call(subject, 500, fn(reply_to) { GetMetrics(reply_to) })
  metrics.zero_trust_violations |> should.equal(2)
}
