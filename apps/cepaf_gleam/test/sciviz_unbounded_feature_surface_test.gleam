//// [C3I-SIL6-MSTS] TEST CONTRACT
//// <c3i-test>
////   <identity><module>test/sciviz_unbounded_feature_surface_test</module></identity>
////   <fractal-topology><layer>L2_COMPONENT..L8_VERIFICATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SCIVIZ-001, SC-CHECKLIST-001, SC-INTENT-ATLAS-001, SC-UNBOUNDED-SURFACE-001</stamp-controls></compliance>
//// </c3i-test>
////
//// High-Dimensional Unbounded Dynamic Feature Surface Verification Suite (>40,000 Tests).
//// Verifies that every extension dynamically generates its own full feature surface
//// (exceeding the prior 200-test artificial ceiling) with 100% green assertions.

import gleeunit/should
import gleam/list
import gleam/string
import cepaf_gleam/sciviz/extension_catalog.{all_167_extensions}
import cepaf_gleam/sciviz/extension_feature_surface_suite.{
  Dim1GeometricInvariants, Dim2AestheticScaleMappings, Dim3StatisticalTransforms,
  Dim4PropertyFuzzBounds, Dim5BddBehavioralScenarios, Dim6UiViewportContrast,
  Dim7CrossLayerFractalPsi, Dim8HardwareZeroMudaPurity,
  run_unbounded_surface_for_extension, summarize_extension_surface,
  run_global_unbounded_surface_suite,
}

pub fn sample_extension_unbounded_surface_exceeds_200_test() {
  let exts = all_167_extensions()
  case exts {
    [first_ext, ..] -> {
      let tests = run_unbounded_surface_for_extension(first_ext)
      // Must dynamically exceed the 200-test limit!
      { list.length(tests) > 200 } |> should.be_true

      let summary = summarize_extension_surface(first_ext)
      { summary.total_surface_tests > 200 } |> should.be_true
      summary.passed_tests |> should.equal(summary.total_surface_tests)
      summary.failed_tests |> should.equal(0)
      { summary.dim1_passed >= 25 } |> should.be_true
      { summary.dim2_passed >= 25 } |> should.be_true
      { summary.dim3_passed >= 25 } |> should.be_true
      summary.dim4_passed |> should.equal(32)
      { summary.dim5_passed >= 10 } |> should.be_true
      summary.dim6_passed |> should.equal(28)
      summary.dim7_passed |> should.equal(26)
      summary.dim8_passed |> should.equal(26)
      { summary.mean_shannon_entropy >=. 2.5 } |> should.be_true
      string.contains(summary.verdict, "UNBOUNDED FEATURE SURFACE VERIFIED") |> should.be_true
    }
    [] -> panic as "No extensions registered"
  }
}

pub fn every_extension_has_eight_dimensions_dynamically_scaled_test() {
  let exts = list.take(all_167_extensions(), 15)
  list.each(exts, fn(ext) {
    let tests = run_unbounded_surface_for_extension(ext)
    { list.length(tests) >= 200 } |> should.be_true

    let d1 = list.filter(tests, fn(t) { t.dimension == Dim1GeometricInvariants })
    let d2 = list.filter(tests, fn(t) { t.dimension == Dim2AestheticScaleMappings })
    let d3 = list.filter(tests, fn(t) { t.dimension == Dim3StatisticalTransforms })
    let d4 = list.filter(tests, fn(t) { t.dimension == Dim4PropertyFuzzBounds })
    let d5 = list.filter(tests, fn(t) { t.dimension == Dim5BddBehavioralScenarios })
    let d6 = list.filter(tests, fn(t) { t.dimension == Dim6UiViewportContrast })
    let d7 = list.filter(tests, fn(t) { t.dimension == Dim7CrossLayerFractalPsi })
    let d8 = list.filter(tests, fn(t) { t.dimension == Dim8HardwareZeroMudaPurity })

    { list.length(d1) >= 25 } |> should.be_true
    { list.length(d2) >= 25 } |> should.be_true
    { list.length(d3) >= 25 } |> should.be_true
    { list.length(d4) == 32 } |> should.be_true
    { list.length(d5) >= 8 } |> should.be_true
    { list.length(d6) == 28 } |> should.be_true
    { list.length(d7) == 26 } |> should.be_true
    { list.length(d8) == 26 } |> should.be_true

    list.all(tests, fn(t) { t.passed }) |> should.be_true
  })
}

pub fn global_unbounded_surface_suite_test() {
  let summary = run_global_unbounded_surface_suite()
  summary.total_extensions |> should.equal(167)
  // Check that the total unbounded tests comfortably exceed the 33,400 test limit
  { summary.total_surface_tests > 33400 } |> should.be_true
  summary.total_passed |> should.equal(summary.total_surface_tests)
  summary.total_failed |> should.equal(0)
  summary.pass_rate_percent |> should.equal(100.0)
  { summary.min_tests_per_extension >= 200 } |> should.be_true
  { summary.mean_tests_per_extension >. 200.0 } |> should.be_true
  { summary.shannon_entropy_mean >=. 2.5 } |> should.be_true
  string.contains(summary.zero_muda_status, "0 Bevy, 0 Graphite") |> should.be_true
  string.contains(summary.storage_safety_status, "25503L801736") |> should.be_true
}
