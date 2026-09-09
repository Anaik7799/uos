import cepaf_gleam/agents/ooda_shruti_copilot.{
  AstAnomaly, advance_ooda_phase, compute_shruti_consonance, get_copilot_summary,
  init_copilot, record_ast_anomaly, remediate_anomaly, select_phase_shruti,
}
import cepaf_gleam/ui/state.{
  OodaAct, OodaDecide, OodaObserve, OodaOrient, OodaVerify,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn init_copilot_test() {
  let copilot = init_copilot()
  copilot.current_phase |> should.equal(OodaObserve)
  copilot.cycle_count |> should.equal(1)
  copilot.active_shruti.swara |> should.equal("Sa")
  copilot.is_andon_active |> should.equal(False)
  should.be_true(copilot.harmonic_consonance >. 0.0)
}

pub fn phase_advance_test() {
  let c0 = init_copilot()
  let c1 = advance_ooda_phase(c0, 1000)
  c1.current_phase |> should.equal(OodaOrient)
  c1.active_shruti.swara |> should.equal("Re2")

  let c2 = advance_ooda_phase(c1, 2000)
  c2.current_phase |> should.equal(OodaDecide)
  c2.active_shruti.swara |> should.equal("Ga2")

  let c3 = advance_ooda_phase(c2, 3000)
  c3.current_phase |> should.equal(OodaAct)
  c3.active_shruti.swara |> should.equal("ma1")

  let c4 = advance_ooda_phase(c3, 4000)
  c4.current_phase |> should.equal(OodaVerify)
  c4.active_shruti.swara |> should.equal("Pa")

  // Full cycle completion increments cycle_count and wraps to Observe
  let c5 = advance_ooda_phase(c4, 5000)
  c5.current_phase |> should.equal(OodaObserve)
  c5.cycle_count |> should.equal(2)
}

pub fn shruti_consonance_test() {
  let s_sa = select_phase_shruti(OodaObserve)
  let cons_stable = compute_shruti_consonance(s_sa, -3.5)
  let cons_unstable = compute_shruti_consonance(s_sa, 1.2)

  should.be_true(cons_stable >. cons_unstable)
  should.be_true(cons_stable <=. 1.0)
}

pub fn anomaly_injection_and_remediation_test() {
  let copilot = init_copilot()
  let anomaly =
    AstAnomaly(
      id: "anom-01",
      anomaly_type: "UndefinedPatternMatch",
      severity: 0.92,
      file_path: "apps/cepaf_gleam/src/sample.gleam",
      suggested_patch: "+ case result { Ok(v) -> v, Error(e) -> fallback }",
      resolved: False,
    )

  // Critical anomaly should trip Andon stop line
  let c_alert = record_ast_anomaly(copilot, anomaly)
  c_alert.is_andon_active |> should.equal(True)
  should.be_true(c_alert.lyapunov_exponent >. 0.0)

  // Advancing phase when Andon is active should be inhibited (fail-closed)
  let c_halted = advance_ooda_phase(c_alert, 6000)
  c_halted.current_phase |> should.equal(OodaObserve)

  // Remediate anomaly
  let c_fixed = remediate_anomaly(c_alert, "anom-01")
  c_fixed.remediated_count |> should.equal(1)
  c_fixed.is_andon_active |> should.equal(False)
  should.be_true(c_fixed.lyapunov_exponent <. 0.0)

  // Now phase advancement succeeds
  let c_resumed = advance_ooda_phase(c_fixed, 7000)
  c_resumed.current_phase |> should.equal(OodaOrient)
}

pub fn unknown_remediation_id_leaves_state_unchanged_test() {
  let critical =
    AstAnomaly("critical", "UndefinedPatternMatch", 0.92, "a.gleam", "patch", False)
  let alerted = init_copilot() |> record_ast_anomaly(critical)

  remediate_anomaly(alerted, "unknown") |> should.equal(alerted)
}

pub fn repeated_remediation_id_is_idempotent_test() {
  let critical =
    AstAnomaly("critical", "UndefinedPatternMatch", 0.92, "a.gleam", "patch", False)
  let fixed = init_copilot() |> record_ast_anomaly(critical) |> remediate_anomaly("critical")

  remediate_anomaly(fixed, "critical") |> should.equal(fixed)
}

pub fn unresolved_critical_anomaly_keeps_andon_active_test() {
  let first = AstAnomaly("first", "TypeError", 0.93, "a.gleam", "patch", False)
  let second = AstAnomaly("second", "TypeError", 0.94, "b.gleam", "patch", False)
  let alerted = init_copilot() |> record_ast_anomaly(first) |> record_ast_anomaly(second)
  let partially_fixed = remediate_anomaly(alerted, "first")

  partially_fixed.remediated_count |> should.equal(1)
  partially_fixed.is_andon_active |> should.be_true()
  partially_fixed.lyapunov_exponent |> should.equal(alerted.lyapunov_exponent)
}

pub fn copilot_summary_test() {
  let copilot = init_copilot()
  let summary = get_copilot_summary(copilot)
  should.be_true(summary != "")
}
