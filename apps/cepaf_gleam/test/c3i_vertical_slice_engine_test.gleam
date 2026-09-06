//// Unit Test Suite for C3I Knowledge Runtime Vertical Slice Engine
//// Verifies 5 pipeline stages + end-to-end execution

import gleam/list
import gleam/string
import gleeunit/should
import cepaf_gleam/knowledge/c3i_vertical_slice_engine.{
  ConformanceFailed, ConformancePassed,
}

pub fn journal_ingestion_test() {
  let record =
    c3i_vertical_slice_engine.ingest_journal_entry(
      "docs/journal/20260906-2000-uos-master-session-handover-to-codex-journal.md",
    )
  record.journal_id |> should.equal("JRN-20260906-2000-HANDOVER")
  record.sections_count |> should.equal(13)
  record.all_13_sections_present |> should.equal(True)
  string.starts_with(record.content_digest, "sha256:") |> should.equal(True)
}

pub fn cited_retrieval_test() {
  let items = c3i_vertical_slice_engine.retrieve_cited_knowledge("C3I")
  list.length(items) |> should.equal(1)
}

pub fn rust_ocaml_conformance_test() {
  let d1 = "sha256:abcd"
  let d2 = "sha256:abcd"
  let d3 = "sha256:different"

  let verdict1 = c3i_vertical_slice_engine.evaluate_rust_ocaml_conformance(d1, d2)
  case verdict1 {
    ConformancePassed(rust_ver, ocaml_ver, contract, matched) -> {
      rust_ver |> should.equal("c3i_nif-1.9.0")
      ocaml_ver |> should.equal("hermes-gospel-0.1.0")
      contract |> should.equal("spec_parity_equality")
      matched |> should.equal(True)
    }
    ConformanceFailed(..) -> should.fail()
  }

  let verdict2 = c3i_vertical_slice_engine.evaluate_rust_ocaml_conformance(d1, d3)
  case verdict2 {
    ConformancePassed(..) -> should.fail()
    ConformanceFailed(reason) ->
      string.contains(reason, "Digest mismatch") |> should.equal(True)
  }
}

pub fn callable_ocaml_lookup_test() {
  let receipt =
    c3i_vertical_slice_engine.execute_callable_ocaml_lookup(
      "retrieval_query",
      "IDEMP-TEST-001",
    )
  receipt.status |> should.equal("COMMITTED")
  receipt.oracle_verdict |> should.equal("GOSPEL_CONTRACT_VERIFIED")
  receipt.error_code |> should.equal(0)
}

pub fn end_to_end_vertical_slice_test() {
  let result = c3i_vertical_slice_engine.run_knowledge_vertical_slice("C3I")
  result.status |> should.equal("OPERATIONAL")
  result.verified_green |> should.equal(True)
  result.journal.all_13_sections_present |> should.equal(True)
  list.length(result.cited_items) |> should.equal(1)

  let json_str = c3i_vertical_slice_engine.encode_vertical_slice_json(result)
  string.contains(json_str, "\"status\":\"OPERATIONAL\"") |> should.equal(True)
  string.contains(json_str, "\"verified_green\":true") |> should.equal(True)
  string.contains(json_str, "SLICE-C3I-KNOWLEDGE-001") |> should.equal(True)
}
