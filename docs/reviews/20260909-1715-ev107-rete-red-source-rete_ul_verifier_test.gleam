// Tests for Rete-UL Forward-Chaining Rule Consistency Verifier (EV-107)
// STAMP: SC-SIL6-001, SC-RETE-001, SC-MUDA-001

import cepaf_gleam/knowledge/rete_ul_verifier.{
  ConsequenceAssert, ConsequenceGateVerdict, ContradictoryRules, CyclicChaining,
  OpEq, ReteCondition, ReteRule, ShadowedRule, add_rule, fire_forward_chaining,
  init_working_memory, insert_fact,
}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn init_working_memory_test() {
  let wm = init_working_memory()
  wm.is_consistent |> should.equal(True)
  wm.facts |> should.equal([])
  wm.rules |> should.equal([])
}

pub fn insert_facts_and_fire_test() {
  let wm0 = init_working_memory()
  let wm1 =
    insert_fact(wm0, "tool_invocation", [
      #("tool", "system_health"),
      #("status", "safe"),
    ])

  let rule =
    ReteRule(
      name: "rule_safe_system_health",
      conditions: [
        ReteCondition("tool_invocation", "tool", OpEq, "system_health"),
        ReteCondition("tool_invocation", "status", OpEq, "safe"),
      ],
      consequence: ConsequenceGateVerdict("ALLOW"),
    )

  let wm2 = add_rule(wm1, rule)
  wm2.is_consistent |> should.equal(True)

  let wm3 = fire_forward_chaining(wm2)
  wm3.fired_count |> should.equal(1)
}

pub fn detect_contradictory_rules_test() {
  let wm0 = init_working_memory()
  let conds = [ReteCondition("auth_token", "role", OpEq, "admin")]

  let r1 =
    ReteRule(
      name: "admin_allow",
      conditions: conds,
      consequence: ConsequenceGateVerdict("ALLOW"),
    )

  let r2 =
    ReteRule(
      name: "admin_deny",
      conditions: conds,
      consequence: ConsequenceGateVerdict("DENY"),
    )

  let wm1 = add_rule(wm0, r1)
  let wm2 = add_rule(wm1, r2)

  wm2.is_consistent |> should.equal(False)
  list.length(wm2.anomalies) |> should.equal(1)
  case list.first(wm2.anomalies) {
    Ok(ContradictoryRules(a, b, _)) -> {
      a |> should.equal("admin_deny")
      b |> should.equal("admin_allow")
    }
    _ -> panic as "Expected ContradictoryRules anomaly"
  }
}

pub fn detect_cyclic_chaining_test() {
  let wm0 = init_working_memory()

  let r1 =
    ReteRule(
      name: "cycle_forward",
      conditions: [ReteCondition("fact_A", "val", OpEq, "1")],
      consequence: ConsequenceAssert("fact_B", "val", "2"),
    )

  let r2 =
    ReteRule(
      name: "cycle_backward",
      conditions: [ReteCondition("fact_B", "val", OpEq, "2")],
      consequence: ConsequenceAssert("fact_A", "val", "1"),
    )

  let wm1 = add_rule(wm0, r1)
  let wm2 = add_rule(wm1, r2)

  wm2.is_consistent |> should.equal(False)
  case list.first(wm2.anomalies) {
    Ok(CyclicChaining(a, b)) -> {
      a |> should.equal("cycle_backward")
      b |> should.equal("cycle_forward")
    }
    _ -> panic as "Expected CyclicChaining anomaly"
  }
}

pub fn detect_shadowed_rule_test() {
  let wm0 = init_working_memory()
  let conds = [ReteCondition("node", "state", OpEq, "idle")]

  let r1 =
    ReteRule(
      name: "idle_action_1",
      conditions: conds,
      consequence: ConsequenceGateVerdict("PASS"),
    )

  let r2 =
    ReteRule(
      name: "idle_action_duplicate",
      conditions: conds,
      consequence: ConsequenceGateVerdict("PASS"),
    )

  let wm1 = add_rule(wm0, r1)
  let wm2 = add_rule(wm1, r2)

  wm2.is_consistent |> should.equal(False)
  case list.first(wm2.anomalies) {
    Ok(ShadowedRule(r, s)) -> {
      r |> should.equal("idle_action_duplicate")
      s |> should.equal("idle_action_1")
    }
    _ -> panic as "Expected ShadowedRule anomaly"
  }
}
