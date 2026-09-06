//// =============================================================================
//// [UOS-FPP-ATLAS-TEST] NASA JPL F Prime 5-Tier Algebraic Atlas Test Suite
//// =============================================================================
//// Formally tests the Category-Theoretic Atlas & Sheaf-Theoretic Invariants:
//// 1. 5-Tier category hierarchy construction (AST, Topology, BEAM, Sheaf, Semiotics)
//// 2. Functorial morphisms & composition associativity
//// 3. Sheaf restriction map and boundary gluing consistency
//// 4. Atlas JSON serialization for web cockpit telemetry
//// =============================================================================

import cepaf_gleam/fpp/algebraic_atlas.{
  GluingConflict, GluingSuccess, TelemetrySection, atlas_to_json,
  build_fpp_algebraic_atlas, verify_sheaf_gluing, verify_sheaf_restriction,
}
import cepaf_gleam/fpp/topology.{canonical_harness_model}
import gleam/string
import gleeunit/should

pub fn fpp_algebraic_atlas_construction_test() {
  let model = canonical_harness_model()
  let report = build_fpp_algebraic_atlas(model)

  report.tiers_count |> should.equal(5)
  { report.objects_count >= 15 } |> should.be_true
  { report.morphisms_count >= 15 } |> should.be_true
  report.associativity_preserved |> should.be_true
  report.gluing_verified |> should.be_true
}

pub fn fpp_sheaf_restriction_test() {
  let parent =
    TelemetrySection(subtopology_name: "RootSubtopo", channels: [
      #(10, "3.14"),
      #(20, "100.0"),
      #(30, "nominal"),
    ])

  let restricted = verify_sheaf_restriction(parent, [10, 30])
  restricted.channels |> should.equal([#(10, "3.14"), #(30, "nominal")])
}

pub fn fpp_sheaf_gluing_consistency_test() {
  // Two sections agreeing on mutual channel 20
  let sec1 =
    TelemetrySection(subtopology_name: "Subtopo1", channels: [
      #(10, "3.14"),
      #(20, "agree"),
    ])
  let sec2 =
    TelemetrySection(subtopology_name: "Subtopo2", channels: [
      #(20, "agree"),
      #(30, "99.9"),
    ])

  let res = verify_sheaf_gluing(sec1, sec2, [20])
  case res {
    GluingSuccess(glued) -> {
      glued.channels
      |> should.equal([#(10, "3.14"), #(20, "agree"), #(30, "99.9")])
    }
    GluingConflict(_) -> False |> should.be_true
  }
}

pub fn fpp_sheaf_gluing_conflict_test() {
  // Two sections disagreeing on mutual channel 20
  let sec1 =
    TelemetrySection(subtopology_name: "Subtopo1", channels: [#(20, "value_a")])
  let sec2 =
    TelemetrySection(subtopology_name: "Subtopo2", channels: [#(20, "value_b")])

  let res = verify_sheaf_gluing(sec1, sec2, [20])
  case res {
    GluingSuccess(_) -> False |> should.be_true
    GluingConflict(err) -> err |> string.contains("disagrees") |> should.be_true
  }
}

pub fn fpp_algebraic_atlas_json_test() {
  let model = canonical_harness_model()
  let report = build_fpp_algebraic_atlas(model)
  let json_str = atlas_to_json(report)

  json_str
  |> string.contains("\"contract\":\"SC-FPP-ATLAS-001\"")
  |> should.be_true
  json_str |> string.contains("\"tiers_count\":5") |> should.be_true
  json_str |> string.contains("Tier0:FppAST") |> should.be_true
  json_str |> string.contains("Tier1:FppTopo") |> should.be_true
  json_str |> string.contains("Tier2:BeamActor") |> should.be_true
  json_str |> string.contains("Tier3:SheafTel") |> should.be_true
  json_str |> string.contains("Tier4:RochaSemiotic") |> should.be_true
}
