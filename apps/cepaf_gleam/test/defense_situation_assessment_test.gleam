//// =============================================================================
//// [C3I-SIL6-MSTS] Defense Situation Assessment Unit Test Suite
//// =============================================================================

import cepaf_gleam/ha/defense_situation_assessment.{
  assessment_to_json, evaluate_defense_posture, posture_level,
  posture_to_string, render_ansi_banner,
}
import cepaf_gleam/ha/health_derivative.{HealthSample}
import cepaf_gleam/ha/lyapunov_proof.{Stable, Unstable}
import cepaf_gleam/ha/tri_agent_monitor.{
  ClaudeAgent, PlanMutationProposal,
  intercept_activity, new_monitor, set_degradation_mode,
}
import gleam/json
import gleam/string
import gleeunit/should

pub fn defcon4_nominal_test() {
  let monitor = new_monitor(False)
  let samples = [
    HealthSample(1_000, 1.0),
    HealthSample(2_000, 1.0),
    HealthSample(3_000, 1.0),
  ]

  let assessment =
    evaluate_defense_posture(3_000_000_000, monitor, samples, -0.01)

  should.equal(posture_level(assessment.posture), 4)
  should.equal(assessment.lyapunov_verdict, Stable)
  should.equal(assessment.composite_health, 1.0)
  should.equal(assessment.local_processing_ratio, 1.0)
  should.be_true(string.contains(
    posture_to_string(assessment.posture),
    "DEFCON_4_NOMINAL",
  ))

  let banner = render_ansi_banner(assessment)
  should.be_true(string.contains(banner, "[DEFCON 4: NOMINAL]"))

  let json_str = json.to_string(assessment_to_json(assessment))
  should.be_true(string.contains(json_str, "\"defcon_level\":4"))
  should.be_true(string.contains(json_str, "\"lyapunov_verdict\":\"STABLE\""))
}

pub fn defcon3_elevated_test() {
  let monitor = new_monitor(False)
  // Valid lease mutation passes without halt
  let #(mon1, _) =
    intercept_activity(
      monitor,
      "act-auth",
      ClaudeAgent,
      PlanMutationProposal("plan-defense", "task-auth", "step"),
      1_000_000_000,
      False,
      True,
    )
  let samples = [
    HealthSample(1_000, 0.82),
    HealthSample(2_000, 0.82),
  ]

  let assessment =
    evaluate_defense_posture(2_000_000_000, mon1, samples, -0.005)

  should.equal(posture_level(assessment.posture), 3)
  should.be_true(string.contains(
    posture_to_string(assessment.posture),
    "DEFCON_3_ELEVATED",
  ))
}

pub fn defcon2_warning_test() {
  let monitor = new_monitor(False)
  let samples = [
    HealthSample(1_000, 0.95),
    HealthSample(2_000, 0.90),
  ]

  let assessment =
    evaluate_defense_posture(2_000_000_000, monitor, samples, 0.08)

  should.equal(posture_level(assessment.posture), 2)
  should.equal(assessment.lyapunov_verdict, Unstable)
  should.be_true(string.contains(
    posture_to_string(assessment.posture),
    "DEFCON_2_WARNING",
  ))
}

pub fn defcon1_emergency_test() {
  let monitor = new_monitor(False) |> set_degradation_mode(True)

  // Invalid lease mutation triggers Jidoka Andon Halt
  let #(mon1, _v) =
    intercept_activity(
      monitor,
      "act-bad",
      ClaudeAgent,
      PlanMutationProposal("plan-unauth", "task-unauth", "inject_step"),
      1_000_000_000,
      False,
      False,
    )

  let samples = [HealthSample(1_000, 0.70)]
  let assessment =
    evaluate_defense_posture(1_000_000_000, mon1, samples, 0.12)

  should.equal(posture_level(assessment.posture), 1)
  should.equal(assessment.lyapunov_verdict, Unstable)
  should.be_true(string.contains(
    posture_to_string(assessment.posture),
    "DEFCON_1_EMERGENCY",
  ))

  let json_str = json.to_string(assessment_to_json(assessment))
  should.be_true(string.contains(json_str, "\"defcon_level\":1"))
}
