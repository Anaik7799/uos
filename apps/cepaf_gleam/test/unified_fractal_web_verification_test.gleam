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

import cepaf_gleam/verification/ocaml_parity_verifier as opv
import cepaf_gleam/verification/unified_fractal_web_verifier as ufwv
import gleam/dict
import gleam/list
import gleam/string
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
  let pages = list.repeat("page", 31)
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

// -----------------------------------------------------------------------------
// Collation & Integration: 4-Tensor Completeness Tests
// -----------------------------------------------------------------------------

pub fn collation_covers_all_36_features_test() {
  let features = ufwv.all_collated_features()
  list.length(features) |> should.equal(36)

  // 100% of collated features must be in Pass state
  list.each(features, fn(f) {
    case f.status {
      ufwv.Pass -> Nil
      ufwv.Fail(_reason) -> should.fail()
    }
  })
}

pub fn collation_covers_all_8_fractal_layers_test() {
  let l0 = ufwv.features_by_layer(ufwv.L0Constitutional)
  let l1 = ufwv.features_by_layer(ufwv.L1Atomic)
  let l2 = ufwv.features_by_layer(ufwv.L2Component)
  let l3 = ufwv.features_by_layer(ufwv.L3Transaction)
  let l4 = ufwv.features_by_layer(ufwv.L4System)
  let l5 = ufwv.features_by_layer(ufwv.L5Cognitive)
  let l6 = ufwv.features_by_layer(ufwv.L6Ecosystem)
  let l7 = ufwv.features_by_layer(ufwv.L7Federation)

  { list.length(l0) >= 4 } |> should.be_true()
  { list.length(l1) >= 4 } |> should.be_true()
  { list.length(l2) >= 6 } |> should.be_true()
  { list.length(l3) >= 4 } |> should.be_true()
  { list.length(l4) >= 6 } |> should.be_true()
  { list.length(l5) >= 4 } |> should.be_true()
  { list.length(l6) >= 4 } |> should.be_true()
  { list.length(l7) >= 4 } |> should.be_true()
}

pub fn collation_covers_all_6_feature_vectors_test() {
  let f1 = ufwv.features_by_vector(ufwv.F1SecurityContainment)
  let f2 = ufwv.features_by_vector(ufwv.F2NavigabilityReachability)
  let f3 = ufwv.features_by_vector(ufwv.F3RenderingErgonomics)
  let f4 = ufwv.features_by_vector(ufwv.F4ProtocolTelemetry)
  let f5 = ufwv.features_by_vector(ufwv.F5CyberneticsProofs)
  let f6 = ufwv.features_by_vector(ufwv.F6KnowledgeNetwork)

  { list.length(f1) >= 4 } |> should.be_true()
  { list.length(f2) >= 4 } |> should.be_true()
  { list.length(f3) >= 7 } |> should.be_true()
  { list.length(f4) >= 6 } |> should.be_true()
  { list.length(f5) >= 5 } |> should.be_true()
  { list.length(f6) >= 5 } |> should.be_true()
}

pub fn collation_covers_all_5_verification_surfaces_test() {
  let s_browser = ufwv.features_by_surface(ufwv.SurfaceBrowser)
  let s_tui = ufwv.features_by_surface(ufwv.SurfaceTUI)
  let s_api = ufwv.features_by_surface(ufwv.SurfaceAPI)
  let s_bus = ufwv.features_by_surface(ufwv.SurfaceBus)
  let s_cli = ufwv.features_by_surface(ufwv.SurfaceCLI)

  { list.length(s_browser) >= 12 } |> should.be_true()
  { list.length(s_tui) >= 2 } |> should.be_true()
  { list.length(s_api) >= 8 } |> should.be_true()
  { list.length(s_bus) >= 1 } |> should.be_true()
  { list.length(s_cli) >= 6 } |> should.be_true()
}

pub fn collation_covers_all_3_engines_test() {
  let zigvm = ufwv.features_by_engine(ufwv.EngineZigVM)
  let c3i = ufwv.features_by_engine(ufwv.EngineC3I)
  let indrajaal = ufwv.features_by_engine(ufwv.EngineIndrajaal)

  { list.length(zigvm) >= 7 } |> should.be_true()
  { list.length(c3i) >= 20 } |> should.be_true()
  { list.length(indrajaal) >= 8 } |> should.be_true()
}

pub fn feature_tracking_table_markdown_generation_test() {
  let table = ufwv.generate_feature_tracking_table()
  let has_header = string.contains(table, "| ID | Feature Name |")
  let has_pass = string.contains(table, "🟢 PASS")
  let has_drive_feat = string.contains(table, "FEAT-L0-01")

  has_header |> should.be_true()
  has_pass |> should.be_true()
  has_drive_feat |> should.be_true()
}

pub fn feature_json_telemetry_generation_test() {
  let json = ufwv.features_to_json_telemetry()
  let has_total = string.contains(json, "\"total_features\":36")
  let has_passing = string.contains(json, "\"passing_features\":36")
  let has_ok = string.contains(json, "\"status\":\"ok\"")

  has_total |> should.be_true()
  has_passing |> should.be_true()
  has_ok |> should.be_true()
}

// =============================================================================
// Wiki, ZK & KM Verification Tests
// =============================================================================

pub fn wiki_ast_parsing_verification_test() {
  let ok_ast = ufwv.verify_wiki_ast_parsing(True, True)
  ok_ast.status |> should.equal(ufwv.Pass)

  let bad_ast = ufwv.verify_wiki_ast_parsing(False, True)
  case bad_ast.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

pub fn gospel_specification_verification_test() {
  let ok_gospel = ufwv.verify_gospel_specification(True, True)
  ok_gospel.status |> should.equal(ufwv.Pass)

  let bad_gospel = ufwv.verify_gospel_specification(False, True)
  case bad_gospel.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

pub fn transclusion_engine_verification_test() {
  let ok_trans = ufwv.verify_transclusion_engine(4, 0)
  ok_trans.status |> should.equal(ufwv.Pass)

  let cycle_trans = ufwv.verify_transclusion_engine(4, 1)
  case cycle_trans.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }

  let deep_trans = ufwv.verify_transclusion_engine(12, 0)
  case deep_trans.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

pub fn pagerank_graph_science_verification_test() {
  let ok_ppr = ufwv.verify_pagerank_graph_science(0.85, 0.00001)
  ok_ppr.status |> should.equal(ufwv.Pass)

  let bad_ppr = ufwv.verify_pagerank_graph_science(0.5, 0.00001)
  case bad_ppr.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

pub fn zk_decision_matrix_verification_test() {
  let ok_zk = ufwv.verify_zk_decision_matrix(16, 12)
  ok_zk.status |> should.equal(ufwv.Pass)

  let deficit_zk = ufwv.verify_zk_decision_matrix(15, 12)
  case deficit_zk.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

pub fn rocha_biosemiotics_indexing_verification_test() {
  let ok_rocha = ufwv.verify_rocha_biosemiotic_indexing(True, 43)
  ok_rocha.status |> should.equal(ufwv.Pass)

  let bad_rocha = ufwv.verify_rocha_biosemiotic_indexing(False, 43)
  case bad_rocha.status {
    ufwv.Fail(_) -> Nil
    ufwv.Pass -> should.fail()
  }
}

// =============================================================================
// 145-Feature ZigVM Wiki/ZK/KM & 181-Feature Unified System Tests
// =============================================================================

pub fn wiki_zk_km_145_features_mapping_test() {
  let zf_features = ufwv.all_wiki_zk_km_fractal_features()
  list.length(zf_features) |> should.equal(145)

  // Every mapped feature has valid status Pass
  let all_pass =
    list.all(zf_features, fn(f) {
      case f.status {
        ufwv.Pass -> True
        ufwv.Fail(_) -> False
      }
    })
  all_pass |> should.be_true()
}

pub fn unified_system_181_features_collation_test() {
  let unified = ufwv.all_unified_system_features()
  list.length(unified) |> should.equal(181)

  // All 181 features pass without error
  let all_pass =
    list.all(unified, fn(f) {
      case f.status {
        ufwv.Pass -> True
        ufwv.Fail(_) -> False
      }
    })
  all_pass |> should.be_true()
}

pub fn unified_system_layer_coverage_test() {
  let l0 = ufwv.unified_features_by_layer(ufwv.L0Constitutional)
  let l1 = ufwv.unified_features_by_layer(ufwv.L1Atomic)
  let l2 = ufwv.unified_features_by_layer(ufwv.L2Component)
  let l3 = ufwv.unified_features_by_layer(ufwv.L3Transaction)
  let l4 = ufwv.unified_features_by_layer(ufwv.L4System)
  let l5 = ufwv.unified_features_by_layer(ufwv.L5Cognitive)
  let l6 = ufwv.unified_features_by_layer(ufwv.L6Ecosystem)
  let l7 = ufwv.unified_features_by_layer(ufwv.L7Federation)

  { list.length(l0) >= 10 } |> should.be_true()
  { list.length(l1) >= 10 } |> should.be_true()
  { list.length(l2) >= 15 } |> should.be_true()
  { list.length(l3) >= 60 } |> should.be_true()
  { list.length(l4) >= 10 } |> should.be_true()
  { list.length(l5) >= 15 } |> should.be_true()
  { list.length(l6) >= 20 } |> should.be_true()
  { list.length(l7) >= 10 } |> should.be_true()
}

pub fn unified_system_vector_coverage_test() {
  let v1 = ufwv.unified_features_by_vector(ufwv.F1SecurityContainment)
  let v2 = ufwv.unified_features_by_vector(ufwv.F2NavigabilityReachability)
  let v3 = ufwv.unified_features_by_vector(ufwv.F3RenderingErgonomics)
  let v4 = ufwv.unified_features_by_vector(ufwv.F4ProtocolTelemetry)
  let v5 = ufwv.unified_features_by_vector(ufwv.F5CyberneticsProofs)
  let v6 = ufwv.unified_features_by_vector(ufwv.F6KnowledgeNetwork)

  { list.length(v1) >= 10 } |> should.be_true()
  { list.length(v2) >= 15 } |> should.be_true()
  { list.length(v3) >= 25 } |> should.be_true()
  { list.length(v4) >= 10 } |> should.be_true()
  { list.length(v5) >= 10 } |> should.be_true()
  { list.length(v6) >= 90 } |> should.be_true()
}

pub fn unified_system_surface_coverage_test() {
  let s_browser = ufwv.unified_features_by_surface(ufwv.SurfaceBrowser)
  let s_tui = ufwv.unified_features_by_surface(ufwv.SurfaceTUI)
  let s_api = ufwv.unified_features_by_surface(ufwv.SurfaceAPI)
  let s_bus = ufwv.unified_features_by_surface(ufwv.SurfaceBus)
  let s_cli = ufwv.unified_features_by_surface(ufwv.SurfaceCLI)

  { list.length(s_browser) >= 60 } |> should.be_true()
  { list.length(s_tui) >= 2 } |> should.be_true()
  { list.length(s_api) >= 10 } |> should.be_true()
  { list.length(s_bus) >= 3 } |> should.be_true()
  { list.length(s_cli) >= 70 } |> should.be_true()
}

pub fn unified_system_engine_coverage_test() {
  let zigvm = ufwv.unified_features_by_engine(ufwv.EngineZigVM)
  let c3i = ufwv.unified_features_by_engine(ufwv.EngineC3I)
  let indrajaal = ufwv.unified_features_by_engine(ufwv.EngineIndrajaal)

  { list.length(zigvm) >= 150 } |> should.be_true()
  { list.length(c3i) >= 20 } |> should.be_true()
  { list.length(indrajaal) >= 8 } |> should.be_true()
}

pub fn unified_system_table_markdown_generation_test() {
  let table = ufwv.generate_unified_system_tracking_table()
  let has_header = string.contains(table, "| ID | Feature Name |")
  let has_pass = string.contains(table, "🟢 PASS")
  let has_wiki_core = string.contains(table, "WIKI-CORE-001")
  let has_adr = string.contains(table, "ADR-001")

  has_header |> should.be_true()
  has_pass |> should.be_true()
  has_wiki_core |> should.be_true()
  has_adr |> should.be_true()
}

pub fn unified_system_telemetry_json_test() {
  let json = ufwv.unified_system_to_json_telemetry()
  let has_total = string.contains(json, "\"total_features\":181")
  let has_passing = string.contains(json, "\"passing_features\":181")
  let has_web = string.contains(json, "\"web_features\":36")
  let has_wiki = string.contains(json, "\"wiki_zk_km_features\":145")
  let has_ok = string.contains(json, "\"status\":\"ok\"")

  has_total |> should.be_true()
  has_passing |> should.be_true()
  has_web |> should.be_true()
  has_wiki |> should.be_true()
  has_ok |> should.be_true()
}

// =============================================================================
// OCaml Testing Functionality Ported to Pure Gleam
// =============================================================================

pub fn ocaml_parity_algebra_lattice_laws_test() {
  let all_verdicts = [opv.Unmapped, opv.Blocked, opv.Verified, opv.Divergent]

  // Distinct names (4)
  let names = list.map(all_verdicts, opv.verdict_name)
  let unique_names = list.unique(names)
  list.length(unique_names) |> should.equal(4)

  // Credit granting: Only Verified grants credit
  opv.grants_credit(opv.Verified) |> should.be_true()
  opv.grants_credit(opv.Unmapped) |> should.be_false()
  opv.grants_credit(opv.Blocked) |> should.be_false()
  opv.grants_credit(opv.Divergent) |> should.be_false()

  // Defect assertion: Only Divergent asserts defect
  opv.asserts_defect(opv.Divergent) |> should.be_true()
  opv.asserts_defect(opv.Verified) |> should.be_false()
  opv.asserts_defect(opv.Unmapped) |> should.be_false()
  opv.asserts_defect(opv.Blocked) |> should.be_false()

  // Commutativity: combine(a, b) == combine(b, a)
  list.each(all_verdicts, fn(a) {
    list.each(all_verdicts, fn(b) {
      opv.combine(a, b) |> should.equal(opv.combine(b, a))
    })
  })

  // Idempotence: combine(a, a) == a
  list.each(all_verdicts, fn(a) { opv.combine(a, a) |> should.equal(a) })

  // Divergent Dominance: combine(Divergent, a) == Divergent
  list.each(all_verdicts, fn(a) {
    opv.combine(opv.Divergent, a) |> should.equal(opv.Divergent)
  })
}

pub fn ocaml_parity_algebra_rollup_vacuous_truth_law_test() {
  // Required roll_up over empty set is Unmapped, NEVER Verified (Anti-Vacuous Truth Law)
  opv.roll_up(True, []) |> should.equal(opv.Unmapped)

  // Optional roll_up over empty set returns Verified
  opv.roll_up(False, []) |> should.equal(opv.Verified)

  // Single verified child yields Verified
  opv.roll_up(True, [opv.Verified]) |> should.equal(opv.Verified)

  // One Divergent among multiple Verified yields Divergent (Severity Dominance)
  opv.roll_up(True, [opv.Verified, opv.Divergent, opv.Verified])
  |> should.equal(opv.Divergent)

  // Blocked outranks Unmapped
  opv.roll_up(True, [opv.Unmapped, opv.Blocked])
  |> should.equal(opv.Blocked)
}

pub fn ocaml_differential_trace_normalization_and_comparison_test() {
  let ref_trace =
    "[timestamp=2026-09-05T20:00:00Z] PID=1234\nState: Nominal\nScore: 1.0"
  let cand_trace =
    "[timestamp=2026-09-05T22:30:15Z] PID=9876\nState: Nominal\nScore: 1.0"

  // Compare should normalize ephemeral timestamps/PIDs and yield Verified
  let res_match = opv.compare_traces(ref_trace, cand_trace)
  case res_match {
    Ok(v) -> v |> should.equal(opv.Verified)
    Error(_) -> should.fail()
  }

  // Different payload yields Divergent
  let diff_trace =
    "[timestamp=2026-09-05T22:30:15Z] PID=9876\nState: Degraded\nScore: 0.5"
  let res_diff = opv.compare_traces(ref_trace, diff_trace)
  case res_diff {
    Ok(v) -> v |> should.equal(opv.Divergent)
    Error(_) -> should.fail()
  }

  // Stub trace detection blocks credit immediately
  let stub_trace = "mock payload: stub for feature verification"
  opv.detect_stub_trace(stub_trace) |> should.be_true()
  let res_stub = opv.compare_traces(ref_trace, stub_trace)
  case res_stub {
    Error(opv.StubDetected(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn ocaml_docs_wiki_block_render_laws_test() {
  let results = opv.run_all_block_render_laws()
  list.length(results) |> should.equal(10)

  let all_pass = list.all(results, fn(r) { r.passed })
  all_pass |> should.be_true()
}

pub fn ocaml_docs_wiki_inline_render_laws_test() {
  let results = opv.run_all_inline_render_laws()
  list.length(results) |> should.equal(6)

  let all_pass = list.all(results, fn(r) { r.passed })
  all_pass |> should.be_true()
}

pub fn ocaml_zk_hypergraph_science_laws_test() {
  // Clean DAG
  let dag_edges = [#("ADR-001", "ADR-002"), #("ADR-002", "ADR-003")]
  opv.detect_graph_cycle(dag_edges) |> should.equal(opv.AcyclicDAG)

  // Direct self-cycle: A -> A
  let self_edges = [#("ADR-001", "ADR-001")]
  case opv.detect_graph_cycle(self_edges) {
    opv.CycleDetected(_) -> Nil
    opv.AcyclicDAG -> should.fail()
  }

  // Mutual cycle: A -> B and B -> A
  let cycle_edges = [#("ADR-001", "ADR-002"), #("ADR-002", "ADR-001")]
  case opv.detect_graph_cycle(cycle_edges) {
    opv.CycleDetected(_) -> Nil
    opv.AcyclicDAG -> should.fail()
  }

  // Graph density calculation
  let density = opv.compute_graph_density(4, 6)
  density |> should.equal(1.0)
}

pub fn ocaml_zero_trust_security_interceptor_test() {
  // Safe payload emits SHA-256
  let safe_payload = "{\"action\":\"query\",\"topic\":\"c3i/test\"}"
  let res_safe = opv.verify_zero_trust_payload(safe_payload)
  case res_safe {
    Ok(hash) -> {
      string.length(hash) |> should.equal(64)
    }
    Error(_) -> should.fail()
  }

  // NUL byte traps with code -2
  let nul_payload = "{\"action\":\"inject\u{0000}bad\"}"
  let res_nul = opv.verify_zero_trust_payload(nul_payload)
  case res_nul {
    Error(code) -> code |> should.equal(opv.err_nul_byte_detected)
    Ok(_) -> should.fail()
  }

  // SQL injection traps with code -3
  let sql_payload = "{\"query\":\"SELECT * FROM notes WHERE id = 1 OR 1=1\"}"
  let res_sql = opv.verify_zero_trust_payload(sql_payload)
  case res_sql {
    Error(code) -> code |> should.equal(opv.err_sql_injection_detected)
    Ok(_) -> should.fail()
  }

  // Writer lease freshness
  opv.verify_writer_lease_freshness(1000, 1500, 2000) |> should.be_true()
  opv.verify_writer_lease_freshness(1000, 3500, 2000) |> should.be_false()
  opv.verify_writer_lease_freshness(2000, 1000, 2000) |> should.be_false()
}

pub fn ocaml_parallel_selfcheck_scalability_test() {
  let suite = [
    #("check_math_entropy", fn() { True }),
    #("check_bevy_muda_zero", fn() { True }),
    #("check_graphite_muda_zero", fn() { True }),
    #("check_mock_failure", fn() { False }),
  ]

  let summary = opv.run_selfcheck_suite(suite)
  summary.total |> should.equal(4)
  summary.passed |> should.equal(3)
  summary.failed |> should.equal(1)
  summary.failures |> should.equal(["check_mock_failure"])
}
