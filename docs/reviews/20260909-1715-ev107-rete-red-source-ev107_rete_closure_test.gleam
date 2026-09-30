import cepaf_gleam/knowledge/rete_ul_verifier as rete
import gleam/list
import gleeunit/should

fn condition(kind: String, value: String) -> rete.ReteCondition {
  rete.ReteCondition(kind, "value", rete.OpEq, value)
}

fn assertion(name: String, from: String, into: String) -> rete.ReteRule {
  rete.ReteRule(name, [condition(from, "yes")], rete.ConsequenceAssert(into, "value", "yes"))
}

fn has_fact(wm: rete.WorkingMemory, kind: String) -> Bool {
  list.any(wm.facts, fn(fact) {
    fact.kind == kind && list.contains(fact.attributes, #("value", "yes"))
  })
}

pub fn assertions_materialize_test() {
  let wm = rete.init_working_memory()
    |> rete.insert_fact("seed", [#("value", "yes")])
    |> rete.add_rule(assertion("derive", "seed", "derived"))
    |> rete.fire_forward_chaining
  has_fact(wm, "derived") |> should.be_true
  wm.fired_count |> should.equal(1)
}

pub fn reverse_order_chain_reaches_fixed_point_test() {
  let wm = rete.init_working_memory()
    |> rete.insert_fact("seed", [#("value", "yes")])
    |> rete.add_rule(assertion("first", "seed", "middle"))
    |> rete.add_rule(assertion("second", "middle", "final"))
    |> rete.fire_forward_chaining
  has_fact(wm, "middle") |> should.be_true
  has_fact(wm, "final") |> should.be_true
  wm.fired_count |> should.equal(2)
  let again = rete.fire_forward_chaining(wm)
  again.facts |> should.equal(wm.facts)
  again.fired_count |> should.equal(2)
}

pub fn existing_assertion_is_not_duplicated_test() {
  let initial = rete.init_working_memory()
    |> rete.insert_fact("seed", [#("value", "yes")])
    |> rete.insert_fact("derived", [#("value", "yes"), #("other", "retained")])
    |> rete.add_rule(assertion("derive", "seed", "derived"))
  let final = rete.fire_forward_chaining(initial)
  final.facts |> should.equal(initial.facts)
  final.fired_count |> should.equal(1)
}

pub fn duplicated_condition_does_not_shadow_a_distinct_conjunction_test() {
  let a = condition("a", "yes")
  let b = condition("b", "yes")
  let repeated = rete.ReteRule("repeated", [a, a], rete.ConsequenceGateVerdict("PASS"))
  let distinct = rete.ReteRule("distinct", [a, b], rete.ConsequenceGateVerdict("PASS"))
  rete.check_rule_consistency(repeated, [distinct]) |> should.equal([])
  rete.check_rule_consistency(distinct, [repeated]) |> should.equal([])
}
