import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import uos_swarm/board.{Agent, Causality, Semantics}
import uos_swarm/system_ontology

const shipped_ledger = "swarm/20260907-0440-swarm-board.jsonl"

pub fn registry_validates_test() {
  system_ontology.validate_registry() |> should.equal(Ok(Nil))
}

pub fn registry_has_at_least_160_concepts_test() {
  { list.length(system_ontology.concepts()) >= 160 } |> should.be_true
}

/// Every ontology concept named on the shipped board ledger must resolve through the
/// unified registry (the operator's "all messages on the boards must be aligned" mandate).
pub fn shipped_ledger_fully_aligned_test() {
  let assert Ok(text) = board.file_read(shipped_ledger)
  let #(messages, bad_lines) = board.from_jsonl(text)
  bad_lines |> should.equal([])
  let names = list.flat_map(messages, fn(m) { m.semantics.ontology_concepts })
  { names != [] } |> should.be_true
  let #(_ok, unresolved) = system_ontology.alignment_report(names)
  unresolved |> should.equal([])
}

pub fn resolve_matches_id_english_and_iast_test() {
  let assert Ok(by_id) = system_ontology.resolve("App")
  by_id.id |> should.equal("App")
  let assert Ok(by_english) = system_ontology.resolve("Compositor")
  by_english.id |> should.equal("Compositor")
  let assert Ok(by_iast) = system_ontology.resolve("buddhi")
  by_iast.iast |> should.equal("buddhi")
}

pub fn resolve_is_case_insensitive_fallback_test() {
  let assert Ok(exact) = system_ontology.resolve("Worker")
  let assert Ok(lower) = system_ontology.resolve("worker")
  lower.id |> should.equal(exact.id)
  let assert Ok(upper) = system_ontology.resolve("WORKER")
  upper.id |> should.equal(exact.id)
  system_ontology.resolve("totally-unknown-concept-xyz")
  |> should.equal(Error(Nil))
}

/// The Hindu thinking structures resolve by their IAST rendering.
pub fn thinking_structures_resolve_by_iast_test() {
  let assert Ok(buddhi) = system_ontology.resolve("buddhi")
  buddhi.domain |> should.equal(system_ontology.Thinking)
  let assert Ok(pramana) = system_ontology.resolve("pramāṇa")
  pramana.iast |> should.equal("pramāṇa")
  let assert Ok(vikalpa) = system_ontology.resolve("vikalpa")
  vikalpa.id |> should.equal("citta-vrtti:vikalpa")
  vikalpa.domain |> should.equal(system_ontology.Memory)
}

pub fn every_concept_used_by_the_ledger_resolves_individually_test() {
  let used = [
    "17 Aspect audit", "App", "Compositor", "Driver", "Message / Event",
    "Pilot / run_test", "Worker",
  ]
  list.each(used, fn(name) {
    case system_ontology.resolve(name) {
      Ok(_) -> Nil
      Error(_) -> should.fail()
    }
  })
}

pub fn dictionary_glossary_wiki_carry_devanagari_and_mermaid_test() {
  let dict_md = system_ontology.dictionary_markdown()
  string.contains(dict_md, "बुद्धि") |> should.be_true
  let glossary_md = system_ontology.glossary_markdown()
  string.contains(glossary_md, "बुद्धि") |> should.be_true
  let wiki_md = system_ontology.wiki_markdown()
  string.contains(wiki_md, "```mermaid") |> should.be_true
  string.contains(wiki_md, "graph TD") |> should.be_true
}

pub fn to_json_round_trips_every_concept_test() {
  let json_text = system_ontology.to_json() |> json.to_string
  { string.length(json_text) > 0 } |> should.be_true
  string.contains(json_text, "\"id\"") |> should.be_true
}

pub fn by_domain_by_layer_by_aspect_partition_test() {
  let thinking = system_ontology.by_domain(system_ontology.Thinking)
  { thinking != [] } |> should.be_true
  list.each(thinking, fn(c) {
    c.domain |> should.equal(system_ontology.Thinking)
  })
  let l0 = system_ontology.by_layer(0)
  list.each(l0, fn(c) { c.layer |> should.equal(0) })
  let a15 = system_ontology.by_aspect(15)
  list.each(a15, fn(c) { list.contains(c.aspects, 15) |> should.be_true })
}

pub fn alignment_report_counts_resolved_and_unresolved_test() {
  let #(ok, unresolved) =
    system_ontology.alignment_report(["App", "Worker", "not-a-real-concept"])
  ok |> should.equal(2)
  unresolved |> should.equal(["not-a-real-concept"])
}

/// `board.validate_semantics` still fail-closes on an unknown concept, and still accepts a
/// concept from the unified registry (both the legacy Textual name and a new Hindu-thinking
/// concept id).
pub fn validate_semantics_rejects_unknown_and_accepts_registry_concepts_test() {
  board.validate_semantics(Semantics(
    ["definitely-not-a-concept"],
    [],
    [],
    [],
    0,
  ))
  |> should.equal(Error("unknown ontology concept: definitely-not-a-concept"))
  board.validate_semantics(Semantics(["App"], [], [], [], 0))
  |> should.equal(Ok(Nil))
  board.validate_semantics(Semantics(["antahkarana:buddhi"], [], [], [], 0))
  |> should.equal(Ok(Nil))
}

// Used only to keep the option/board.Causality/Agent imports referenced for a small
// end-to-end sanity check: a drafted message's semantics must validate against the shared
// registry the same way the CLI's `ontology check` does.
pub fn drafted_message_semantics_validate_against_registry_test() {
  let agent = Agent("W-ont-2", "L2", "sonnet")
  let semantics = Semantics(["17 Aspect audit"], [15], [], [], 0)
  board.validate_semantics(semantics) |> should.equal(Ok(Nil))
  agent.id |> should.equal("W-ont-2")
  Causality(None, []) |> should.equal(Causality(None, []))
}
