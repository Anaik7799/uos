// Hook Subsystem RETE-UL Rule Tests (SC-BOOTSTRAP-005)
// 13 tests: D-1..D-3 data-plane + C-1..C-10 control-plane
// All rules must fire (not stubs) — verifies GRL salience + condition logic.

import cepaf_gleam/rules/engine.{evaluate_hook_control, evaluate_hook_snapshot}
import gleeunit/should

// ─── Data-plane tests ────────────────────────────────────────────────────────

// D-1: age < 5 s → EmitCached (salience 100)
pub fn d1_snapshot_fresh_test() {
  let result = evaluate_hook_snapshot(1000, True)
  result.decision |> should.equal("EmitCached")
}

// D-2: age >= 5 s, daemon healthy → EmitCachedStale (salience 90)
pub fn d2_snapshot_stale_healthy_test() {
  let result = evaluate_hook_snapshot(10_000, True)
  result.decision |> should.equal("EmitCachedStale")
}

// D-3: age >= 5 s, daemon unhealthy → EmbeddedFallback (salience 80)
pub fn d3_snapshot_stale_unhealthy_test() {
  let result = evaluate_hook_snapshot(10_000, False)
  result.decision |> should.equal("EmbeddedFallback")
}

// ─── Control-plane tests ─────────────────────────────────────────────────────

// C-1: Bayesian posterior low → WatchdogKill (salience 100)
pub fn c1_bayesian_health_low_test() {
  let result =
    evaluate_hook_control(
      True,
      False,
      False,
      False,
      False,
      False,
      False,
      False,
      False,
      False,
    )
  result.decision |> should.equal("WatchdogKill")
}

// C-2: Entropy high (posterior not low) → P0Alarm (salience 100)
pub fn c2_entropy_alarm_test() {
  let result =
    evaluate_hook_control(
      False,
      True,
      False,
      False,
      False,
      False,
      False,
      False,
      False,
      False,
    )
  result.decision |> should.equal("P0Alarm")
}

// C-3: PID error → PIDTuneCache (salience 90)
pub fn c3_pid_error_test() {
  let result =
    evaluate_hook_control(
      False,
      False,
      True,
      False,
      False,
      False,
      False,
      False,
      False,
      False,
    )
  result.decision |> should.equal("PIDTuneCache")
}

// C-4: Lyapunov drift → LyapunovAlert (salience 90)
pub fn c4_lyapunov_drift_test() {
  let result =
    evaluate_hook_control(
      False,
      False,
      False,
      True,
      False,
      False,
      False,
      False,
      False,
      False,
    )
  result.decision |> should.equal("LyapunovAlert")
}

// C-5: GA cycle elapsed → GeneticEvolve (salience 80)
pub fn c5_ga_cycle_test() {
  let result =
    evaluate_hook_control(
      False,
      False,
      False,
      False,
      True,
      False,
      False,
      False,
      False,
      False,
    )
  result.decision |> should.equal("GeneticEvolve")
}

// C-6: MDP transitions ready → MDPRefresh (salience 80)
pub fn c6_mdp_refresh_test() {
  let result =
    evaluate_hook_control(
      False,
      False,
      False,
      False,
      False,
      True,
      False,
      False,
      False,
      False,
    )
  result.decision |> should.equal("MDPRefresh")
}

// C-7: Mutual info high → RuleInduction (salience 75)
pub fn c7_rule_induction_test() {
  let result =
    evaluate_hook_control(
      False,
      False,
      False,
      False,
      False,
      False,
      True,
      False,
      False,
      False,
    )
  result.decision |> should.equal("RuleInduction")
}

// C-8: Shadow ready → PromoteShadow (salience 70)
pub fn c8_ab_shadow_ready_test() {
  let result =
    evaluate_hook_control(
      False,
      False,
      False,
      False,
      False,
      False,
      False,
      True,
      False,
      False,
    )
  result.decision |> should.equal("PromoteShadow")
}

// C-9: Smriti write failed → SmritiAlert (salience 95)
pub fn c9_smriti_write_fail_test() {
  let result =
    evaluate_hook_control(
      False,
      False,
      False,
      False,
      False,
      False,
      False,
      False,
      True,
      False,
    )
  result.decision |> should.equal("SmritiAlert")
}

// C-10: Policy refuse → RefuseHook (salience 100)
pub fn c10_policy_refuse_test() {
  let result =
    evaluate_hook_control(
      False,
      False,
      False,
      False,
      False,
      False,
      False,
      False,
      False,
      True,
    )
  result.decision |> should.equal("RefuseHook")
}
