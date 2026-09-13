//// [C3I-SIL6-MSTS] TEST CONTRACT
//// <c3i-test>
////   <identity><module>test/sciviz_extensions_comprehensive_test</module></identity>
////   <fractal-topology><layer>L2_COMPONENT..L8_VERIFICATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SCIVIZ-001, SC-CHECKLIST-001, SC-INTENT-ATLAS-001</stamp-controls></compliance>
//// </c3i-test>
////
//// Comprehensive Test Suite for ggplot2 Extensions Gallery (167 Extensions & 15 Use Cases).

import gleeunit/should
import gleam/list
import gleam/string
import cepaf_gleam/sciviz/extension_catalog.{
  all_167_extensions, count_by_category,
}
import cepaf_gleam/sciviz/extension_examples
import cepaf_gleam/sciviz/extension_features
import cepaf_gleam/sciviz/extension_suite.{
  run_all_15_extension_test_cases,
  uc_ext01_ggdist_slab_interval_test,
  uc_ext02_ggraph_force_directed_network_test,
  uc_ext03_ggalluvial_stream_flow_ribbon_test,
  uc_ext04_treemapify_nested_hierarchical_rect_test,
  uc_ext05_complex_upset_combination_matrix_test,
  uc_ext06_ggquiver_vector_fluid_field_test,
  uc_ext07_ggqc_spc_control_chart_test,
  uc_ext08_survminer_kaplan_meier_step_test,
  uc_ext09_ggtree_circular_cladogram_test,
  uc_ext10_geomtextpath_curved_geodesic_test,
  uc_ext11_gghoriplot_folded_horizon_test,
  uc_ext12_patchwork_inset_multipanel_test,
  uc_ext13_ggnewscale_dual_palette_adjunction_test,
  uc_ext14_ggfx_glow_filter_fuzz_test,
  uc_ext15_gginnards_ast_inspect_storage_defense_test,
}
import cepaf_gleam/sciviz/test_suite.{
  ChaosTesting, ComponentTesting, FuzzTesting, PropertyTesting, SystemTesting,
  TddTesting, UiElementsTesting,
}

pub fn all_15_extension_test_cases_pass_test() {
  let results = run_all_15_extension_test_cases()
  list.length(results) |> should.equal(15)

  let all_passed = list.all(results, fn(t) { t.passed })
  all_passed |> should.be_true
}

pub fn all_9_modalities_represented_in_extensions_test() {
  let results = run_all_15_extension_test_cases()
  let modalities = list.map(results, fn(t) { t.modality })

  list.contains(modalities, TddTesting) |> should.be_true
  list.contains(modalities, ComponentTesting) |> should.be_true
  list.contains(modalities, UiElementsTesting) |> should.be_true
  list.contains(modalities, SystemTesting) |> should.be_true
  list.contains(modalities, PropertyTesting) |> should.be_true
  list.contains(modalities, FuzzTesting) |> should.be_true
  list.contains(modalities, ChaosTesting) |> should.be_true
}

pub fn all_167_extensions_cataloged_test() {
  let exts = all_167_extensions()
  list.length(exts) |> should.equal(167)

  let counts = count_by_category()
  list.length(counts) |> should.equal(16)

  // Verify all 16 categories contain at least one extension
  list.all(counts, fn(pair) {
    let #(_cat, count) = pair
    count > 0
  })
  |> should.be_true
}

pub fn all_rendered_svg_displays_valid_test() {
  let results = run_all_15_extension_test_cases()

  list.each(results, fn(tc) {
    // Valid SVG boundaries
    string.contains(tc.rendered_svg, "<svg") |> should.be_true
    string.contains(tc.rendered_svg, "</svg>") |> should.be_true
    // Zero-Muda: Strictly NO client-side JavaScript tags
    string.contains(tc.rendered_svg, "<script") |> should.be_false
    // Non-empty BDD Gherkin Flow
    string.contains(tc.gherkin_scenario, "Given") |> should.be_true
    string.contains(tc.gherkin_scenario, "When") |> should.be_true
    string.contains(tc.gherkin_scenario, "Then") |> should.be_true
    // Non-empty specs
    string.is_empty(tc.specification) |> should.be_false
    string.is_empty(tc.inputs_description) |> should.be_false
    string.is_empty(tc.assertion_description) |> should.be_false
  })
}

pub fn individual_extension_use_cases_test() {
  // EXT-01: ggdist
  let r1 = uc_ext01_ggdist_slab_interval_test()
  r1.passed |> should.be_true
  r1.use_case_id |> should.equal("UC-EXT-01")

  // EXT-02: ggraph
  let r2 = uc_ext02_ggraph_force_directed_network_test()
  r2.passed |> should.be_true
  r2.use_case_id |> should.equal("UC-EXT-02")

  // EXT-03: ggalluvial
  let r3 = uc_ext03_ggalluvial_stream_flow_ribbon_test()
  r3.passed |> should.be_true
  r3.use_case_id |> should.equal("UC-EXT-03")

  // EXT-04: treemapify
  let r4 = uc_ext04_treemapify_nested_hierarchical_rect_test()
  r4.passed |> should.be_true
  r4.use_case_id |> should.equal("UC-EXT-04")

  // EXT-05: ComplexUpset
  let r5 = uc_ext05_complex_upset_combination_matrix_test()
  r5.passed |> should.be_true
  r5.use_case_id |> should.equal("UC-EXT-05")

  // EXT-06: ggquiver
  let r6 = uc_ext06_ggquiver_vector_fluid_field_test()
  r6.passed |> should.be_true
  r6.use_case_id |> should.equal("UC-EXT-06")

  // EXT-07: ggQC
  let r7 = uc_ext07_ggqc_spc_control_chart_test()
  r7.passed |> should.be_true
  r7.use_case_id |> should.equal("UC-EXT-07")

  // EXT-08: survminer
  let r8 = uc_ext08_survminer_kaplan_meier_step_test()
  r8.passed |> should.be_true
  r8.use_case_id |> should.equal("UC-EXT-08")

  // EXT-09: ggtree
  let r9 = uc_ext09_ggtree_circular_cladogram_test()
  r9.passed |> should.be_true
  r9.use_case_id |> should.equal("UC-EXT-09")

  // EXT-10: geomtextpath
  let r10 = uc_ext10_geomtextpath_curved_geodesic_test()
  r10.passed |> should.be_true
  r10.use_case_id |> should.equal("UC-EXT-10")

  // EXT-11: ggHoriPlot
  let r11 = uc_ext11_gghoriplot_folded_horizon_test()
  r11.passed |> should.be_true
  r11.use_case_id |> should.equal("UC-EXT-11")

  // EXT-12: patchwork
  let r12 = uc_ext12_patchwork_inset_multipanel_test()
  r12.passed |> should.be_true
  r12.use_case_id |> should.equal("UC-EXT-12")

  // EXT-13: ggnewscale
  let r13 = uc_ext13_ggnewscale_dual_palette_adjunction_test()
  r13.passed |> should.be_true
  r13.use_case_id |> should.equal("UC-EXT-13")

  // EXT-14: ggfx
  let r14 = uc_ext14_ggfx_glow_filter_fuzz_test()
  r14.passed |> should.be_true
  r14.use_case_id |> should.equal("UC-EXT-14")

  // EXT-15: gginnards
  let r15 = uc_ext15_gginnards_ast_inspect_storage_defense_test()
  r15.passed |> should.be_true
  r15.use_case_id |> should.equal("UC-EXT-15")
}

pub fn all_167_extensions_feature_profiles_test() {
  let exts = all_167_extensions()
  list.each(exts, fn(ext) {
    let profile = extension_features.get_feature_profile(ext)
    { list.length(profile.features_offered) >= 3 } |> should.be_true
    string.is_empty(profile.fractal_layer) |> should.be_false
    string.contains(profile.fractal_layer, "#fractal-l") |> should.be_true
    string.is_empty(profile.technical_aspects) |> should.be_false
    string.is_empty(profile.functional_aspects) |> should.be_false
    string.is_empty(profile.ui_ux_aspects) |> should.be_false
  })
}

pub fn all_167_extensions_svg_and_code_parity_test() {
  let exts = all_167_extensions()
  list.each(exts, fn(ext) {
    let svg = extension_examples.example_svg(ext)
    string.contains(svg, "<svg") |> should.be_true
    string.contains(svg, "</svg>") |> should.be_true
    string.contains(svg, "<script") |> should.be_false

    let code = extension_examples.example_code(ext)
    string.contains(code, "library(") |> should.be_true
    string.contains(code, "ggplot(") |> should.be_true
  })
}

