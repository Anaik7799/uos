//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// Tri-Language Test Orchestrator & Universal Observability Test Suite
//// STAMP: SC-GLM-UI-001, SC-ZMOF-001, SC-CHECKLIST-001

import cepaf_gleam/testing/tri_language_orchestrator
import gleam/json
import gleam/string
import gleeunit/should

pub fn gleam_orchestrator_runs_all_three_tiers_test() {
  let report = tri_language_orchestrator.run_all_tests()

  // 1. All three language tiers must pass when executed by Gleam
  should.be_true(report.all_passed)
  should.be_true(report.gleam_result.passed)
  should.be_true(report.ocaml_result.passed)
  should.be_true(report.mojo_result.passed)

  // 2. Verified telemetry across Zenoh and ETS
  should.be_true(report.gleam_result.telemetry_verified)
  should.be_true(report.ocaml_result.telemetry_verified)
  should.be_true(report.mojo_result.telemetry_verified)
  should.be_true(report.zenoh_active)
  should.be_true(report.ets_entries_count >= 10)

  // 3. W3C Trace ID & Span ID present
  should.be_true(string.length(report.trace_id) == 32)
  should.be_true(string.length(report.span_id) == 16)

  // 4. Fractal Logging verification
  should.be_true(string.contains(report.fractal_log, "[C3I-FRACTAL-LOG]"))
  should.be_true(string.contains(report.fractal_log, "verdict=PASS"))
  should.be_true(string.contains(report.fractal_log, "layers=L0..L7"))

  // 5. JSON serialization verification
  let json_str =
    tri_language_orchestrator.report_to_json(report) |> json.to_string()
  should.be_true(string.contains(json_str, "\"all_passed\":true"))
  should.be_true(string.contains(json_str, "Hermes_Engine"))
  should.be_true(string.contains(json_str, "Modular_MAX"))
  should.be_true(string.contains(json_str, "BEAM_OTP29"))
}

pub fn global_test_observability_snapshot_test() {
  let snapshot = tri_language_orchestrator.global_test_observability_snapshot()
  let snap_str = json.to_string(snapshot)

  should.be_true(string.contains(snap_str, "uos_c3i_global_test_observability"))
  should.be_true(string.contains(snap_str, "100%_CONVERGED_GREEN"))
  should.be_true(string.contains(snap_str, "\"gleam_beam\":\"PASSED\""))
  should.be_true(string.contains(snap_str, "\"ocaml_hermes\":\"PASSED\""))
  should.be_true(string.contains(snap_str, "\"mojo_modular_max\":\"PASSED\""))
  should.be_true(string.contains(snap_str, "L0_Constitutional"))
  should.be_true(string.contains(snap_str, "L5_Cognitive"))
  should.be_true(string.contains(snap_str, "L6_Ecosystem"))
}
