//// =============================================================================
//// Test Module: test/knowledge_annotation_actor_test.gleam
//// Subject: Knowledge Annotation Actor & Rocha Cybernetics Invariants
//// Contract: SC-ROCHA-001, SC-KM-001, SC-CHECKLIST-001
//// =============================================================================

import gleeunit/should
import gleam/erlang/process
import cepaf_gleam/knowledge/annotation_actor.{
  Completed, DocAnnotationResult, GetMetrics, Idle, KnowledgeMetrics,
  Reset, ScanDocument, TriggerAnnotationRun, calculate_sheaf_coherence,
  inspect_document, initial_state, start,
}

pub fn inspect_document_rocha_closure_test() {
  let valid_doc =
    "# Sample Knowledge Note\n"
    <> "Tailscale Link: http://nas-1.tail55d152.ts.net:4100/docs/zk/sample.md\n"
    <> "Tags: #rocha-semiotics #cybernetics #km-triad #zero-muda #fractal-l5\n"
    <> "Transclusions: [[wiki:index]] and [[zk:moc]]\n"

  let res = inspect_document("docs/zk/sample.md", valid_doc)
  res.has_rocha_semiotics |> should.equal(True)
  res.has_cybernetics |> should.equal(True)
  res.has_km_triad |> should.equal(True)
  res.has_zero_muda |> should.equal(True)
  res.has_tailscale_link |> should.equal(True)
  res.wiki_transclusions_count |> should.equal(1)
  res.zk_transclusions_count |> should.equal(1)
  res.fractal_layer |> should.equal("#fractal-l5")
  res.is_semiotically_closed |> should.equal(True)
}

pub fn inspect_document_fail_closed_test() {
  let invalid_doc = "# Orphan Note Without Tags or Tailscale"
  let res = inspect_document("docs/orphan.md", invalid_doc)
  res.has_rocha_semiotics |> should.equal(False)
  res.has_cybernetics |> should.equal(False)
  res.has_tailscale_link |> should.equal(False)
  res.is_semiotically_closed |> should.equal(False)
}

pub fn annotation_actor_full_lifecycle_test() {
  let assert Ok(started) = start()
  let subject = started.data

  let client = process.new_subject()

  // 1. Initial metrics
  process.send(subject, GetMetrics(client))
  let metrics1 = process.receive(client, 1000)
  let assert Ok(m1) = metrics1
  m1.total_runs |> should.equal(0)
  m1.documents_scanned |> should.equal(0)

  // 2. Scan a valid document
  let doc_client = process.new_subject()
  let sample_text =
    "Content with http://nas-1.tail55d152.ts.net:4100 #rocha-semiotics #zero-muda #fractal-l0 [[wiki:test]]"
  process.send(subject, ScanDocument("test.md", sample_text, doc_client))
  let doc_res = process.receive(doc_client, 1000)
  let assert Ok(r) = doc_res
  r.has_rocha_semiotics |> should.equal(True)
  r.has_tailscale_link |> should.equal(True)

  // 3. Trigger annotation run
  process.send(subject, TriggerAnnotationRun(client))
  let metrics2 = process.receive(client, 1000)
  let assert Ok(m2) = metrics2
  m2.total_runs |> should.equal(1)
  m2.documents_scanned |> should.equal(1)
  m2.rocha_tagged_count |> should.equal(1)
  m2.tailscale_linked_count |> should.equal(1)
  m2.status |> should.equal(Completed)
  { m2.sheaf_coherence_score >. 0.0 } |> should.equal(True)
}

pub fn sheaf_coherence_calculation_test() {
  let s0 = initial_state()
  calculate_sheaf_coherence(s0) |> should.equal(1.0)
}
