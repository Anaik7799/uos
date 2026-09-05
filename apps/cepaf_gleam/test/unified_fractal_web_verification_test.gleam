// =============================================================================
// [C3I-SIL6-UFWV-TEST] UNIFIED FRACTAL WEB VERIFICATION TEST SUITE
// =============================================================================
// Integrates all webpage and website checks across ZigVM, C3I, and Indrajaal:
// - ZigVM: GitBook 4-axis navigation, TyXML algebraic escaping, ZK PageRank,
//          Ruliology 7-law rewrite system (L1..L7), block anchors (^id)
// - C3I: C1-C8 Gold Standard, 4 Math Gates, 31-page complete nav graph (SCC=1),
//        Triple-Interface Parity, AG-UI 32 events, Dark Cockpit HMI transitions
// - Indrajaal: 18/18 Comprehensive Checklist, cohesive site shell, dual view mode,
//              filesystem jail, /api/verify/checks typed JSON telemetry
// Full Fractal Coverage: Layers L0 through L7.
// =============================================================================

import cepaf_gleam/verification/unified_fractal_web_verifier as ufwv
import gleam/dict
import gleam/list
import gleeunit/should

// -----------------------------------------------------------------------------
// L0 Constitutional: Safety Interlocks & Zero-Muda Purity
// -----------------------------------------------------------------------------

pub fn l0_root_os_drive_safety_lock_test() {
  let res_pass = ufwv.verify_root_os_drive_safety("25503L801736")
  res_pass.status |> should.equal(ufwv.Pass)
  res_pass.score |> should.equal(1.0)
  res_pass.layer |> should.equal(ufwv.L0Constitutional)

  let res_fail = ufwv.verify_root_os_drive_safety("WRONG_SERIAL_OS_WIPE")
  case res_fail.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

pub fn l0_zero_muda_purity_test() {
  let res_pass = ufwv.verify_zero_muda_purity(False, False, False)
  res_pass.status |> should.equal(ufwv.Pass)

  let res_bevy_fail = ufwv.verify_zero_muda_purity(True, False, False)
  case res_bevy_fail.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }

  let res_nif_fail = ufwv.verify_zero_muda_purity(False, False, True)
  case res_nif_fail.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

pub fn l0_2oo3_constitutional_consensus_test() {
  let res_3of3 = ufwv.verify_2oo3_constitutional_consensus(True, True, True)
  res_3of3.status |> should.equal(ufwv.Pass)

  let res_2of3 = ufwv.verify_2oo3_constitutional_consensus(True, False, True)
  res_2of3.status |> should.equal(ufwv.Pass)

  let res_1of3 = ufwv.verify_2oo3_constitutional_consensus(False, True, False)
  case res_1of3.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }

  let res_0of3 = ufwv.verify_2oo3_constitutional_consensus(False, False, False)
  case res_0of3.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// L1 Atomic: TyXML Escaping & Ruliology Tag Rewrite Laws
// -----------------------------------------------------------------------------

pub fn l1_tyxml_algebraic_escaping_test() {
  let raw = "<div class=\"hero\" data-title='C3I & ZigVM'>"
  let escaped = ufwv.verify_tyxml_algebraic_escaping(raw)
  escaped
  |> should.equal(
    "&lt;div class=&quot;hero&quot; data-title=&#39;C3I &amp; ZigVM&#39;&gt;",
  )
}

pub fn l1_block_anchor_syntax_test() {
  let block_with_anchor = "This is a key architectural decision. ^adr-001"
  ufwv.verify_block_anchor_syntax(block_with_anchor)
  |> should.equal(Ok("adr-001"))

  let block_without_anchor = "Plain content block without anchor"
  ufwv.verify_block_anchor_syntax(block_without_anchor)
  |> should.equal(Error(Nil))
}

pub fn l1_ruliology_tag_laws_test() {
  let tags = ["#rocha-semiotics", "#cybernetics", "#km-triad", "#zero-muda"]
  let laws = ufwv.evaluate_ruliology_tag_laws(tags)
  laws.l1_fidelity |> should.be_true()
  laws.l2_normal_form |> should.be_true()
  laws.l3_idempotence |> should.be_true()
  laws.l4_termination |> should.be_true()
  laws.l5_transparency |> should.be_true()
  laws.l6_detection |> should.be_true()
  laws.l7_live_corpus |> should.be_true()
}

// -----------------------------------------------------------------------------
// L2 Component: Visuals, Data Grids & Dark Cockpit HMI
// -----------------------------------------------------------------------------

pub fn l2_c1_page_structure_test() {
  let res_ok = ufwv.verify_c1_page_structure(7)
  res_ok.status |> should.equal(ufwv.Pass)

  let res_small = ufwv.verify_c1_page_structure(4)
  case res_small.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

pub fn l2_c3_data_grid_dimensions_test() {
  let res_ok = ufwv.verify_c3_data_grid(4, 5)
  res_ok.status |> should.equal(ufwv.Pass)

  let res_shallow = ufwv.verify_c3_data_grid(2, 5)
  case res_shallow.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

pub fn l2_dark_cockpit_mode_transitions_test() {
  // Nominal -> Dark
  ufwv.compute_dark_cockpit_mode(0, 0, 0) |> should.equal(ufwv.Dark)

  // Warning -> Dim
  ufwv.compute_dark_cockpit_mode(1, 0, 0) |> should.equal(ufwv.Dim)

  // Single error -> NormalMode
  ufwv.compute_dark_cockpit_mode(0, 1, 0) |> should.equal(ufwv.NormalMode)

  // 3+ errors -> Bright
  ufwv.compute_dark_cockpit_mode(0, 3, 0) |> should.equal(ufwv.Bright)

  // Critical alarm -> EmergencyMode (takes precedence)
  ufwv.compute_dark_cockpit_mode(5, 5, 1) |> should.equal(ufwv.EmergencyMode)
}

// -----------------------------------------------------------------------------
// L3 Transaction: AG-UI 32 Events & Triple-Interface Parity
// -----------------------------------------------------------------------------

pub fn l3_agui_32_events_count_test() {
  ufwv.total_agui_events |> should.equal(32)
}

pub fn l3_triple_interface_parity_test() {
  let res_ok = ufwv.verify_triple_interface_parity(True, True, True)
  res_ok.status |> should.equal(ufwv.Pass)

  let res_no_tui = ufwv.verify_triple_interface_parity(True, True, False)
  case res_no_tui.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// L4 System: 31-Page Complete Graph & 18/18 Comprehensive Checklist
// -----------------------------------------------------------------------------

pub fn l4_navigation_graph_topology_test() {
  let pages =
    list.repeat("page", 31)
  let graph = ufwv.verify_nav_graph(pages)
  graph.vertex_count |> should.equal(31)
  graph.edge_count |> should.equal(930)
  { graph.density >=. 0.99 } |> should.be_true()
  graph.scc_count |> should.equal(1)
}

pub fn l4_comprehensive_checklist_18_checks_test() {
  let summary = ufwv.evaluate_comprehensive_checklist()
  summary.domains_total |> should.equal(5)
  summary.domains_passing |> should.equal(5)
  summary.checks_total |> should.equal(18)
  summary.checks_passing |> should.equal(18)
  summary.all_green |> should.be_true()
}

// -----------------------------------------------------------------------------
// L5 Cognitive: 4 Mathematical Quality Gates & Cybernetics
// -----------------------------------------------------------------------------

pub fn l5_mathematical_quality_gates_test() {
  // Nominal passing values: H=2.67, CCM=92%, DEA=5%, ITQS=0.88
  let res_pass = ufwv.evaluate_math_gates(2.67, 0.92, 0.05, 0.88)
  res_pass.all_gates_pass |> should.be_true()
  res_pass.entropy_pass |> should.be_true()
  res_pass.ccm_pass |> should.be_true()
  res_pass.dea_pass |> should.be_true()
  res_pass.itqs_pass |> should.be_true()

  // Low entropy fails
  let res_low_h = ufwv.evaluate_math_gates(2.1, 0.92, 0.05, 0.88)
  res_low_h.all_gates_pass |> should.be_false()

  // High divergence fails
  let res_high_dea = ufwv.evaluate_math_gates(2.67, 0.92, 0.15, 0.88)
  res_high_dea.all_gates_pass |> should.be_false()
}

// -----------------------------------------------------------------------------
// L6 Ecosystem: ZK Note Identity Cards & PageRank Science
// -----------------------------------------------------------------------------

pub fn l6_pagerank_and_zk_identity_test() {
  let nodes = ["ADR-001", "ADR-002", "MOC-MASTER"]
  let edges = [
    #("MOC-MASTER", "ADR-001"),
    #("MOC-MASTER", "ADR-002"),
    #("ADR-001", "ADR-002"),
  ]
  let pr = ufwv.calculate_simple_pagerank(nodes, edges, 0.85)
  dict.size(pr) |> should.equal(3)

  let note_card =
    ufwv.ZkNoteCard(
      id: "note-uuid-001",
      slug: "20260904-adr-001",
      title: "Rete Fact Schema",
      in_degree: 5,
      out_degree: 3,
      pagerank: 0.33,
      eigenvector_centrality: 0.72,
    )
  note_card.in_degree |> should.equal(5)
}

// -----------------------------------------------------------------------------
// L7 Federation: Tailnet FQDN & Real-Time Verification Telemetry
// -----------------------------------------------------------------------------

pub fn l7_tailscale_fqdn_and_telemetry_test() {
  ufwv.tailnet_base_fqdn
  |> should.equal("http://nas-1.tail55d152.ts.net:4100")
  ufwv.peer_runtime_host
  |> should.equal("http://vm-1.tail55d152.ts.net:8088")

  let t = ufwv.get_telemetry_payload()
  t.status |> should.equal("ok")
  t.contract |> should.equal("SC-ROCHA-001")
  t.domains_passing |> should.equal(5)
  t.checks_passing |> should.equal(18)
  t.ev_cycles_passing |> should.equal(20)
  t.zero_muda |> should.be_true()
  t.storage_safety |> should.be_true()
  t.dal_a |> should.equal("SIL-6")
}

// -----------------------------------------------------------------------------
// Master Fractal Verification Run Across All 8 Layers
// -----------------------------------------------------------------------------

pub fn master_full_fractal_verification_runner_test() {
  let report = ufwv.run_full_fractal_verification()
  report.total_checks |> should.equal(8)
  report.passed_checks |> should.equal(8)
  report.failed_checks |> should.equal(0)
  report.layers_evaluated |> should.equal(8)
  report.is_ratified |> should.be_true()
}
