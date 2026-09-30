import cepaf_gleam/knowledge/rete_ul_verifier as rete
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should

fn condition(kind: String, value: String) -> rete.ReteCondition {
  rete.ReteCondition(kind, "value", rete.OpEq, value)
}

fn assertion(name: String, from: String, into: String) -> rete.ReteRule {
  rete.ReteRule(
    name,
    [condition(from, "yes")],
    rete.ConsequenceAssert(into, "value", "yes"),
  )
}

fn has_fact(wm: rete.WorkingMemory, kind: String) -> Bool {
  list.any(wm.facts, fn(fact) {
    fact.kind == kind && list.contains(fact.attributes, #("value", "yes"))
  })
}

pub fn assertions_materialize_test() {
  let wm =
    rete.init_working_memory()
    |> rete.insert_fact("seed", [#("value", "yes")])
    |> rete.add_rule(assertion("derive", "seed", "derived"))
    |> rete.fire_forward_chaining
  has_fact(wm, "derived") |> should.be_true
  wm.fired_count |> should.equal(1)
}

pub fn reverse_order_chain_reaches_fixed_point_test() {
  let wm =
    rete.init_working_memory()
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
  let initial =
    rete.init_working_memory()
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
  let repeated =
    rete.ReteRule("repeated", [a, a], rete.ConsequenceGateVerdict("PASS"))
  let distinct =
    rete.ReteRule("distinct", [a, b], rete.ConsequenceGateVerdict("PASS"))
  rete.check_rule_consistency(repeated, [distinct]) |> should.equal([])
  rete.check_rule_consistency(distinct, [repeated]) |> should.equal([])
}

pub fn distinct_assertions_share_a_condition_test() {
  let wm =
    rete.init_working_memory()
    |> rete.insert_fact("seed", [#("value", "yes")])
    |> rete.add_rule(assertion("left", "seed", "left"))
    |> rete.add_rule(assertion("right", "seed", "right"))
  wm.is_consistent |> should.be_true
  let final = rete.fire_forward_chaining(wm)
  has_fact(final, "left") |> should.be_true
  has_fact(final, "right") |> should.be_true
  final.fired_count |> should.equal(2)
}

fn raw(
  facts: List(rete.ReteFact),
  rules: List(rete.ReteRule),
) -> rete.WorkingMemory {
  rete.WorkingMemory(facts, rules, [], True, 99)
}

fn fact(kind: String) -> rete.ReteFact {
  rete.ReteFact(kind, [#("value", "yes")])
}

fn range(count: Int) -> List(Int) {
  int.range(0, count, [], fn(acc, n) { [n, ..acc] }) |> list.reverse
}

pub fn empty_memory_and_invalid_budget_test() {
  let wm = raw([], [])
  let assert Ok(run) = rete.try_fire_forward_chaining_with_budget(wm, 1)
  run.memory.facts |> should.equal([])
  run.memory.fired_count |> should.equal(0)
  run.verdicts |> should.equal([])
  run.match_steps |> should.equal(0)
  list.each([-1, 0, rete.maximum_match_steps + 1], fn(budget) {
    rete.try_fire_forward_chaining_with_budget(wm, budget)
    |> should.equal(Error(rete.InvalidWorkBudget))
  })
}

pub fn gate_observations_follow_derived_facts_test() {
  let verdict =
    rete.ReteRule(
      "gate",
      [condition("derived", "yes")],
      rete.ConsequenceGateVerdict("PASS"),
    )
  let wm =
    raw([fact("seed")], [verdict, assertion("derive", "seed", "derived")])
  let assert Ok(run) = rete.try_fire_forward_chaining(wm)
  run.verdicts |> should.equal([#("gate", "PASS")])
  run.memory.fired_count |> should.equal(2)
  has_fact(run.memory, "derived") |> should.be_true
}

pub fn conflicting_live_verdicts_refuse_without_partial_memory_test() {
  let first =
    rete.ReteRule(
      "allow",
      [condition("seed", "yes")],
      rete.ConsequenceGateVerdict("ALLOW"),
    )
  let last =
    rete.ReteRule(
      "deny",
      [condition("derived", "yes")],
      rete.ConsequenceGateVerdict("DENY"),
    )
  let wm =
    raw([fact("seed")], [first, assertion("derive", "seed", "derived"), last])
  rete.try_fire_forward_chaining(wm)
  |> should.equal(Error(rete.ConflictingVerdicts))
  rete.fire_forward_chaining(wm) |> should.equal(wm)
  wm.facts |> should.equal([fact("seed")])
}

pub fn forged_cached_consistency_does_not_bypass_rule_checks_test() {
  let first =
    rete.ReteRule(
      "allow",
      [condition("seed", "yes")],
      rete.ConsequenceGateVerdict("ALLOW"),
    )
  let second =
    rete.ReteRule("deny", first.conditions, rete.ConsequenceGateVerdict("DENY"))
  let wm = raw([fact("seed")], [first, second])
  rete.try_fire_forward_chaining(wm)
  |> should.equal(Error(rete.InconsistentRules))
  rete.fire_forward_chaining(wm) |> should.equal(wm)
  let cycle =
    raw([fact("a")], [assertion("ab", "a", "b"), assertion("ba", "b", "a")])
  rete.try_fire_forward_chaining(cycle)
  |> should.equal(Error(rete.InconsistentRules))
}

pub fn identical_condition_sets_are_symmetric_test() {
  let a = condition("a", "yes")
  let first = rete.ReteRule("first", [a], rete.ConsequenceGateVerdict("PASS"))
  let second =
    rete.ReteRule("second", [a, a], rete.ConsequenceGateVerdict("FAIL"))
  let assert [rete.ContradictoryRules(_, _, _)] =
    rete.check_rule_consistency(first, [second])
  let assert [rete.ContradictoryRules(_, _, _)] =
    rete.check_rule_consistency(second, [first])
}

pub fn same_id_or_duplicate_attribute_refuses_test() {
  let rule = assertion("same", "seed", "derived")
  let bad_rules =
    raw([fact("seed")], [
      rule,
      rete.ReteRule(..rule, conditions: [condition("other", "yes")]),
    ])
  rete.try_fire_forward_chaining(bad_rules)
  |> should.equal(Error(rete.InvalidWorkingMemory))
  let bad_fact = rete.ReteFact("seed", [#("value", "yes"), #("value", "no")])
  let bad_facts = raw([bad_fact], [rule])
  rete.try_fire_forward_chaining(bad_facts)
  |> should.equal(Error(rete.InvalidWorkingMemory))
  rete.fire_forward_chaining(bad_facts) |> should.equal(bad_facts)
}

pub fn exactly_full_memory_deduplicates_but_cannot_grow_test() {
  let facts = range(256) |> list.map(fn(n) { fact(int.to_string(n)) })
  let assert Ok(run) = rete.try_fire_forward_chaining(raw(facts, []))
  list.length(run.memory.facts) |> should.equal(256)
  let already =
    rete.ReteRule("already", [], rete.ConsequenceAssert("255", "value", "yes"))
  let assert Ok(same) = rete.try_fire_forward_chaining(raw(facts, [already]))
  same.memory.facts |> should.equal(facts)
  same.memory.fired_count |> should.equal(1)
  let growth =
    rete.ReteRule("new", [], rete.ConsequenceAssert("new", "value", "yes"))
  let wm = raw(facts, [growth])
  rete.try_fire_forward_chaining(wm) |> should.equal(Error(rete.FactCapacity))
  rete.fire_forward_chaining(wm) |> should.equal(wm)
  rete.try_fire_forward_chaining(raw([fact("excess"), ..facts], []))
  |> should.equal(Error(rete.InvalidWorkingMemory))
}

pub fn rule_capacity_and_large_raw_list_refuse_test() {
  let rules =
    range(64)
    |> list.map(fn(n) {
      assertion(
        int.to_string(n),
        "absent" <> int.to_string(n),
        "out" <> int.to_string(n),
      )
    })
  let assert Ok(run) = rete.try_fire_forward_chaining(raw([], rules))
  run.memory.fired_count |> should.equal(0)
  rete.try_fire_forward_chaining(
    raw([], [assertion("65", "absent", "out"), ..rules]),
  )
  |> should.equal(Error(rete.InvalidWorkingMemory))
  rete.try_fire_forward_chaining(raw(list.repeat(fact("seed"), 10_000), []))
  |> should.equal(Error(rete.InvalidWorkingMemory))
}

pub fn attribute_and_condition_capacities_test() {
  let attributes = range(8) |> list.map(fn(n) { #(int.to_string(n), "yes") })
  let valid = raw([rete.ReteFact("seed", attributes)], [])
  let assert Ok(_) = rete.try_fire_forward_chaining(valid)
  rete.try_fire_forward_chaining(
    raw([rete.ReteFact("seed", [#("ninth", "yes"), ..attributes])], []),
  )
  |> should.equal(Error(rete.InvalidWorkingMemory))
  let conditions =
    range(8) |> list.map(fn(n) { condition(int.to_string(n), "yes") })
  let rule =
    rete.ReteRule("eight", conditions, rete.ConsequenceGateVerdict("PASS"))
  let assert Ok(_) = rete.try_fire_forward_chaining(raw([], [rule]))
  rete.try_fire_forward_chaining(
    raw([], [
      rete.ReteRule(..rule, conditions: [
        condition("ninth", "yes"),
        ..conditions
      ]),
    ]),
  )
  |> should.equal(Error(rete.InvalidWorkingMemory))
}

pub fn metadata_limits_count_utf8_bytes_test() {
  let exact = string.repeat("é", 128)
  let oversized = exact <> "é"
  let assert Ok(_) =
    rete.try_fire_forward_chaining(
      raw([rete.ReteFact(exact, [#(exact, exact)])], []),
    )
  list.each(
    [
      raw([rete.ReteFact(oversized, [#("a", "b")])], []),
      raw([rete.ReteFact("kind", [#(oversized, "b")])], []),
      raw([rete.ReteFact("kind", [#("a", oversized)])], []),
      raw([rete.ReteFact("", [])], []),
      raw([rete.ReteFact("kind", [#("", "b")])], []),
      raw([], [rete.ReteRule("", [], rete.ConsequenceGateVerdict("PASS"))]),
      raw([], [rete.ReteRule("gate", [], rete.ConsequenceGateVerdict(""))]),
    ],
    fn(wm) {
      rete.try_fire_forward_chaining(wm)
      |> should.equal(Error(rete.InvalidWorkingMemory))
    },
  )
}

pub fn precise_work_boundary_refuses_before_returning_partial_result_test() {
  let wm =
    raw([fact("seed")], [
      assertion("second", "middle", "last"),
      assertion("first", "seed", "middle"),
    ])
  let assert Ok(full) = rete.try_fire_forward_chaining(wm)
  let assert Ok(exact) =
    rete.try_fire_forward_chaining_with_budget(wm, full.match_steps)
  exact |> should.equal(full)
  rete.try_fire_forward_chaining_with_budget(wm, full.match_steps - 1)
  |> should.equal(Error(rete.WorkExhausted))
  let gate =
    raw([], [rete.ReteRule("gate", [], rete.ConsequenceGateVerdict("PASS"))])
  let assert Ok(one) = rete.try_fire_forward_chaining_with_budget(gate, 1)
  one.match_steps |> should.equal(1)
}

pub fn finite_cycles_terminate_and_existing_facts_are_retained_test() {
  let wm =
    raw([fact("a")], [
      assertion("ab", "a", "b"),
      assertion("bc", "b", "c"),
      assertion("ca", "c", "a"),
    ])
  let assert Ok(run) = rete.try_fire_forward_chaining(wm)
  list.length(run.memory.facts) |> should.equal(3)
  run.memory.fired_count |> should.equal(3)
  let assert Ok(again) = rete.try_fire_forward_chaining(run.memory)
  again.memory.facts |> should.equal(run.memory.facts)
  again.memory.fired_count |> should.equal(3)
}

pub fn comparisons_preserve_existential_matching_semantics_test() {
  let facts = [
    rete.ReteFact("entry", [#("a", "left-right")]),
    rete.ReteFact("entry", [#("b", "different")]),
  ]
  let rule =
    rete.ReteRule(
      "all",
      [
        rete.ReteCondition("entry", "a", rete.OpContains, "right"),
        rete.ReteCondition("entry", "b", rete.OpNeq, "expected"),
      ],
      rete.ConsequenceGateVerdict("MATCH"),
    )
  let assert Ok(run) = rete.try_fire_forward_chaining(raw(facts, [rule]))
  run.verdicts |> should.equal([#("all", "MATCH")])
  let absent =
    rete.ReteRule(
      "absent",
      [rete.ReteCondition("entry", "missing", rete.OpNeq, "value")],
      rete.ConsequenceGateVerdict("MUST_NOT_MATCH"),
    )
  let assert Ok(no_match) = rete.try_fire_forward_chaining(raw(facts, [absent]))
  no_match.memory.fired_count |> should.equal(0)
  no_match.verdicts |> should.equal([])
}
