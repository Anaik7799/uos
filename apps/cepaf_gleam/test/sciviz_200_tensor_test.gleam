//// [C3I-SIL6-MSTS] TEST CONTRACT
//// <c3i-test>
////   <identity><module>test/sciviz_200_tensor_test</module></identity>
////   <fractal-topology><layer>L2_COMPONENT..L8_VERIFICATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SCIVIZ-001, SC-CHECKLIST-001, SC-INTENT-ATLAS-001, SC-TENSOR-200-001</stamp-controls></compliance>
//// </c3i-test>
////
//// High-Dimensional 200-Tests-Per-Extension Verification Suite (33,400 Tests Total).

import gleeunit/should
import gleam/list
import gleam/string
import cepaf_gleam/sciviz/extension_catalog.{all_167_extensions}
import cepaf_gleam/sciviz/extension_200_tensor_suite.{
  Dim1GeometricInvariants, Dim2AestheticScaleMappings, Dim3StatisticalTransforms,
  Dim4PropertyFuzzBounds, Dim5BddBehavioralScenarios, Dim6UiViewportContrast,
  Dim7CrossLayerFractalPsi, Dim8HardwareZeroMudaPurity,
  run_200_tests_for_extension, summarize_extension_tensor,
  run_global_33400_tensor_suite,
}

pub fn sample_extension_runs_exactly_200_tests_test() {
  let exts = all_167_extensions()
  case exts {
    [first_ext, ..] -> {
      let tests = run_200_tests_for_extension(first_ext)
      list.length(tests) |> should.equal(200)

      let summary = summarize_extension_tensor(first_ext)
      summary.total_tests |> should.equal(200)
      summary.passed_tests |> should.equal(200)
      summary.failed_tests |> should.equal(0)
      summary.dim1_passed |> should.equal(25)
      summary.dim2_passed |> should.equal(25)
      summary.dim3_passed |> should.equal(25)
      summary.dim4_passed |> should.equal(25)
      summary.dim5_passed |> should.equal(25)
      summary.dim6_passed |> should.equal(25)
      summary.dim7_passed |> should.equal(25)
      summary.dim8_passed |> should.equal(25)
      { summary.mean_shannon_entropy >=. 2.5 } |> should.be_true
    }
    [] -> panic as "No extensions registered"
  }
}

pub fn every_extension_has_eight_dimensions_of_25_checks_test() {
  let exts = list.take(all_167_extensions(), 10)
  list.each(exts, fn(ext) {
    let tests = run_200_tests_for_extension(ext)
    list.length(tests) |> should.equal(200)

    let d1 = list.filter(tests, fn(t) { t.dimension == Dim1GeometricInvariants })
    let d2 = list.filter(tests, fn(t) { t.dimension == Dim2AestheticScaleMappings })
    let d3 = list.filter(tests, fn(t) { t.dimension == Dim3StatisticalTransforms })
    let d4 = list.filter(tests, fn(t) { t.dimension == Dim4PropertyFuzzBounds })
    let d5 = list.filter(tests, fn(t) { t.dimension == Dim5BddBehavioralScenarios })
    let d6 = list.filter(tests, fn(t) { t.dimension == Dim6UiViewportContrast })
    let d7 = list.filter(tests, fn(t) { t.dimension == Dim7CrossLayerFractalPsi })
    let d8 = list.filter(tests, fn(t) { t.dimension == Dim8HardwareZeroMudaPurity })

    list.length(d1) |> should.equal(25)
    list.length(d2) |> should.equal(25)
    list.length(d3) |> should.equal(25)
    list.length(d4) |> should.equal(25)
    list.length(d5) |> should.equal(25)
    list.length(d6) |> should.equal(25)
    list.length(d7) |> should.equal(25)
    list.length(d8) |> should.equal(25)

    list.all(tests, fn(t) { t.passed }) |> should.be_true
  })
}

pub fn global_33400_tests_summary_test() {
  let summary = run_global_33400_tensor_suite()
  summary.total_extensions |> should.equal(167)
  summary.total_tests |> should.equal(33400)
  summary.total_passed |> should.equal(33400)
  summary.total_failed |> should.equal(0)
  summary.pass_rate_percent |> should.equal(100.0)
  { summary.shannon_entropy_mean >=. 2.5 } |> should.be_true
  string.contains(summary.zero_muda_status, "0 Bevy, 0 Graphite") |> should.be_true
  string.contains(summary.storage_safety_status, "25503L801736") |> should.be_true
}
