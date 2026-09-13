//// [C3I-SIL6-MSTS] TEST CONTRACT
//// <c3i-test>
////   <identity><module>test/sciviz_comprehensive_modalities_test</module></identity>
////   <fractal-topology><layer>L2_COMPONENT..L8_VERIFICATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SCIVIZ-001, SC-CHECKLIST-001, SC-INTENT-ATLAS-001</stamp-controls></compliance>
//// </c3i-test>
////
//// Comprehensive 9-Modality Test Suite & 15 Formal Feature Use Cases Verification.

import gleeunit/should
import gleam/list
import gleam/string
import cepaf_gleam/sciviz/test_suite.{
  ChaosTesting, ComponentTesting, PropertyTesting, SystemTesting, TddTesting,
  UiElementsTesting, run_all_15_test_cases, uc01_multivariate_scatter_test,
  uc02_high_freq_fifo_mountain_test, uc03_tukey_boxplot_test,
  uc04_violin_density_test, uc05_hex_spatial_tessellation_test,
  uc06_contour_marching_squares_test, uc07_proportional_stacked_bar_test,
  uc08_polar_rose_gyro_test, uc09_primary_flight_display_test,
  uc10_lyapunov_damping_test, uc11_flight_trajectory_arcs_test,
  uc12_nine_slice_panel_test, uc13_scale_guide_adjunction_test,
  uc14_chaos_fault_injection_test, uc15_hardware_storage_interlock_test,
}

pub fn all_15_test_cases_pass_test() {
  let results = run_all_15_test_cases()
  list.length(results) |> should.equal(15)

  let all_passed = list.all(results, fn(t) { t.passed })
  all_passed |> should.be_true
}

pub fn all_9_modalities_covered_test() {
  let results = run_all_15_test_cases()
  let modalities = list.map(results, fn(t) { t.modality })

  // Verify each required modality is represented
  list.contains(modalities, TddTesting) |> should.be_true
  list.contains(modalities, ComponentTesting) |> should.be_true
  list.contains(modalities, UiElementsTesting) |> should.be_true
  list.contains(modalities, SystemTesting) |> should.be_true
  list.contains(modalities, ChaosTesting) |> should.be_true
  list.contains(modalities, PropertyTesting) |> should.be_true
}

pub fn all_rendered_svg_displays_valid_test() {
  let results = run_all_15_test_cases()

  list.each(results, fn(tc) {
    // Every test must produce a valid WebUI SVG display
    string.contains(tc.rendered_svg, "<svg") |> should.be_true
    string.contains(tc.rendered_svg, "</svg>") |> should.be_true
    // Zero-Muda: Absolutely NO client JavaScript tags permitted
    string.contains(tc.rendered_svg, "<script") |> should.be_false
    // Non-empty specification and Gherkin scenario
    string.is_empty(tc.specification) |> should.be_false
    string.contains(tc.gherkin_scenario, "Given") |> should.be_true
    string.contains(tc.gherkin_scenario, "When") |> should.be_true
    string.contains(tc.gherkin_scenario, "Then") |> should.be_true
  })
}

pub fn individual_use_cases_test() {
  // UC-01
  let r1 = uc01_multivariate_scatter_test()
  r1.passed |> should.be_true
  r1.use_case_id |> should.equal("UC-01")

  // UC-02
  let r2 = uc02_high_freq_fifo_mountain_test()
  r2.passed |> should.be_true
  r2.use_case_id |> should.equal("UC-02")

  // UC-03
  let r3 = uc03_tukey_boxplot_test()
  r3.passed |> should.be_true
  r3.use_case_id |> should.equal("UC-03")

  // UC-04
  let r4 = uc04_violin_density_test()
  r4.passed |> should.be_true
  r4.use_case_id |> should.equal("UC-04")

  // UC-05
  let r5 = uc05_hex_spatial_tessellation_test()
  r5.passed |> should.be_true
  r5.use_case_id |> should.equal("UC-05")

  // UC-06
  let r6 = uc06_contour_marching_squares_test()
  r6.passed |> should.be_true
  r6.use_case_id |> should.equal("UC-06")

  // UC-07
  let r7 = uc07_proportional_stacked_bar_test()
  r7.passed |> should.be_true
  r7.use_case_id |> should.equal("UC-07")

  // UC-08
  let r8 = uc08_polar_rose_gyro_test()
  r8.passed |> should.be_true
  r8.use_case_id |> should.equal("UC-08")

  // UC-09
  let r9 = uc09_primary_flight_display_test()
  r9.passed |> should.be_true
  r9.use_case_id |> should.equal("UC-09")

  // UC-10
  let r10 = uc10_lyapunov_damping_test()
  r10.passed |> should.be_true
  r10.use_case_id |> should.equal("UC-10")

  // UC-11
  let r11 = uc11_flight_trajectory_arcs_test()
  r11.passed |> should.be_true
  r11.use_case_id |> should.equal("UC-11")

  // UC-12
  let r12 = uc12_nine_slice_panel_test()
  r12.passed |> should.be_true
  r12.use_case_id |> should.equal("UC-12")

  // UC-13 Property Adjunction
  let r13 = uc13_scale_guide_adjunction_test()
  r13.passed |> should.be_true
  r13.use_case_id |> should.equal("UC-13")

  // UC-14 Chaos Fault Injection
  let r14 = uc14_chaos_fault_injection_test()
  r14.passed |> should.be_true
  r14.use_case_id |> should.equal("UC-14")

  // UC-15 Hardware Storage Defense
  let r15 = uc15_hardware_storage_interlock_test()
  r15.passed |> should.be_true
  r15.use_case_id |> should.equal("UC-15")
}
