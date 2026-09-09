//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/knowledge/rete_ul_verifier</module>
////     <fsharp-lineage>N/A — Pure Gleam Rete-UL Forward-Chaining Rule Consistency Verifier</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L5_COGNITIVE</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-SIL6-001, SC-RETE-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/list
import gleam/result
import gleam/string

/// Comparison operator for Rete conditions.
pub type ReteOp {
  OpEq
  OpNeq
  OpContains
}

/// A pattern condition on a working memory fact.
pub type ReteCondition {
  ReteCondition(fact_kind: String, attribute: String, op: ReteOp, value: String)
}

/// Action or consequence triggered by a satisfied rule.
pub type ReteConsequence {
  ConsequenceAssert(fact_kind: String, attribute: String, value: String)
  ConsequenceGateVerdict(verdict: String)
}

/// A forward-chaining production rule.
pub type ReteRule {
  ReteRule(
    name: String,
    conditions: List(ReteCondition),
    consequence: ReteConsequence,
  )
}

/// Working Memory Fact.
pub type ReteFact {
  ReteFact(kind: String, attributes: List(#(String, String)))
}

/// Consistency verification anomaly detected in the rule base.
pub type RuleAnomaly {
  ContradictoryRules(rule_a: String, rule_b: String, reason: String)
  CyclicChaining(rule_name: String, cycle_target: String)
  ShadowedRule(rule_name: String, shadowed_by: String)
}

/// Working Memory State.
pub type WorkingMemory {
  WorkingMemory(
    facts: List(ReteFact),
    rules: List(ReteRule),
    anomalies: List(RuleAnomaly),
    is_consistent: Bool,
    fired_count: Int,
  )
}

/// Initialize an empty Working Memory.
pub fn init_working_memory() -> WorkingMemory {
  WorkingMemory(
    facts: [],
    rules: [],
    anomalies: [],
    is_consistent: True,
    fired_count: 0,
  )
}

/// Insert a fact into working memory.
pub fn insert_fact(
  wm: WorkingMemory,
  kind: String,
  attributes: List(#(String, String)),
) -> WorkingMemory {
  let new_fact = ReteFact(kind: kind, attributes: attributes)
  WorkingMemory(..wm, facts: [new_fact, ..wm.facts])
}

/// Register a production rule and run static consistency analysis.
pub fn add_rule(wm: WorkingMemory, rule: ReteRule) -> WorkingMemory {
  let existing_rules = wm.rules
  let new_anomalies = check_rule_consistency(rule, existing_rules)
  let all_anomalies = list.append(new_anomalies, wm.anomalies)
  let consistent = list.is_empty(all_anomalies)

  WorkingMemory(
    ..wm,
    rules: [rule, ..existing_rules],
    anomalies: all_anomalies,
    is_consistent: consistent,
  )
}

/// Check if a newly added rule contradicts, shadows, or cycles with existing rules.
pub fn check_rule_consistency(
  rule: ReteRule,
  existing_rules: List(ReteRule),
) -> List(RuleAnomaly) {
  list.filter_map(existing_rules, fn(existing) {
    // Check 1: Contradictory rules (identical conditions, conflicting gate verdicts)
    case conditions_equal(rule.conditions, existing.conditions) {
      True -> {
        case rule.consequence, existing.consequence {
          ConsequenceGateVerdict(v1), ConsequenceGateVerdict(v2) if v1 != v2 ->
            Ok(ContradictoryRules(
              rule_a: rule.name,
              rule_b: existing.name,
              reason: "Identical conditions yield conflicting verdicts: "
                <> v1
                <> " vs "
                <> v2,
            ))
          _, _ if rule.consequence == existing.consequence ->
            Ok(ShadowedRule(rule_name: rule.name, shadowed_by: existing.name))
          _, _ -> Error(Nil)
        }
      }
      False -> {
        // Check 2: Cyclic immediate forward-chaining
        case rule.consequence {
          ConsequenceAssert(k1, a1, _) -> {
            let has_cycle =
              list.any(existing.conditions, fn(c) {
                c.fact_kind == k1 && c.attribute == a1
              })
            case has_cycle {
              True -> {
                case existing.consequence {
                  ConsequenceAssert(k2, a2, _) -> {
                    let reciprocal =
                      list.any(rule.conditions, fn(c) {
                        c.fact_kind == k2 && c.attribute == a2
                      })
                    case reciprocal {
                      True ->
                        Ok(CyclicChaining(
                          rule_name: rule.name,
                          cycle_target: existing.name,
                        ))
                      False -> Error(Nil)
                    }
                  }
                  _ -> Error(Nil)
                }
              }
              False -> Error(Nil)
            }
          }
          _ -> Error(Nil)
        }
      }
    }
  })
}

fn conditions_equal(
  conds1: List(ReteCondition),
  conds2: List(ReteCondition),
) -> Bool {
  // Conditions are a conjunction. Repetition does not change its meaning,
  // and equality must be symmetric even when one list contains duplicates.
  list.all(conds1, fn(c) { list.contains(conds2, c) })
  && list.all(conds2, fn(c) { list.contains(conds1, c) })
}

pub const maximum_facts = 256

pub const maximum_rules = 64

pub const maximum_attributes = 8

pub const maximum_conditions = 8

pub const maximum_string_bytes = 256

pub const maximum_match_steps = 100_000

/// A refusal returns no partial memory or verdict. Cached consistency fields
/// are never sufficient to validate a public WorkingMemory constructor.
pub type ForwardError {
  InvalidWorkingMemory
  InconsistentRules
  InvalidWorkBudget
  FactCapacity
  WorkExhausted
  ConflictingVerdicts
}

/// Local observations only. A gate verdict never authorizes an external effect.
/// `match_steps` counts rule, condition, fact and attribute visits, including
/// assertion deduplication. Bounded input validation is separate from this count.
pub type ForwardRun {
  ForwardRun(
    memory: WorkingMemory,
    verdicts: List(#(String, String)),
    match_steps: Int,
  )
}

type Execution {
  Execution(
    facts: List(ReteFact),
    fired_count: Int,
    verdicts: List(#(String, String)),
    remaining: Int,
  )
}

/// Compatibility projection. On refusal the supplied value is preserved;
/// callers that need to distinguish refusal must use the checked API.
pub fn fire_forward_chaining(wm: WorkingMemory) -> WorkingMemory {
  case try_fire_forward_chaining(wm) {
    Ok(run) -> run.memory
    Error(_) -> wm
  }
}

/// Compute the least fact closure of the accepted static assertion rules.
/// Each condition is existential over facts, preserving the historical matching
/// semantics; conditions do not introduce variable bindings or same-fact joins.
/// Facts are only added. OpNeq means an existing unequal attribute, not absence.
/// Every rule fires at most once per invocation. Gate observations and fact sets
/// are order independent on successful runs; presentation order and work use are
/// allowed to differ. A smaller budget can therefore refuse one ordering sooner.
/// Existing conservative pairwise warnings still veto execution; they are not
/// a complete logical consistency proof. Legacy builders are not bounded APIs.
pub fn try_fire_forward_chaining(
  wm: WorkingMemory,
) -> Result(ForwardRun, ForwardError) {
  try_fire_forward_chaining_with_budget(wm, maximum_match_steps)
}

pub fn try_fire_forward_chaining_with_budget(
  wm: WorkingMemory,
  budget: Int,
) -> Result(ForwardRun, ForwardError) {
  use _ <- result.try(case budget >= 1 && budget <= maximum_match_steps {
    True -> Ok(Nil)
    False -> Error(InvalidWorkBudget)
  })
  use _ <- result.try(validate_forward_memory(wm))
  use final <- result.try(run_round(
    wm.rules,
    [],
    Execution(wm.facts, 0, [], budget),
    False,
  ))
  Ok(ForwardRun(
    WorkingMemory(..wm, facts: final.facts, fired_count: final.fired_count),
    list.reverse(final.verdicts),
    budget - final.remaining,
  ))
}

fn bounded_all(items: List(a), left: Int, valid: fn(a) -> Bool) -> Bool {
  case items {
    [] -> True
    [_, ..] if left <= 0 -> False
    [item, ..rest] -> valid(item) && bounded_all(rest, left - 1, valid)
  }
}

fn valid_value(value: String) -> Bool {
  string.byte_size(value) <= maximum_string_bytes
}

fn valid_name(value: String) -> Bool {
  value != "" && valid_value(value)
}

fn valid_fact(fact: ReteFact) -> Bool {
  valid_name(fact.kind)
  && bounded_all(fact.attributes, maximum_attributes, fn(pair) {
    valid_name(pair.0) && valid_value(pair.1)
  })
  && {
    let names = list.map(fact.attributes, fn(pair) { pair.0 })
    list.length(list.unique(names)) == list.length(names)
  }
}

fn valid_rule(rule: ReteRule) -> Bool {
  valid_name(rule.name)
  && bounded_all(rule.conditions, maximum_conditions, fn(c) {
    valid_name(c.fact_kind) && valid_name(c.attribute) && valid_value(c.value)
  })
  && case rule.consequence {
    ConsequenceAssert(kind, attribute, value) ->
      valid_name(kind) && valid_name(attribute) && valid_value(value)
    ConsequenceGateVerdict(verdict) -> valid_name(verdict)
  }
}

fn rules_are_consistent(rules: List(ReteRule)) -> Bool {
  case rules {
    [] -> True
    [rule, ..rest] ->
      list.is_empty(check_rule_consistency(rule, rest))
      && rules_are_consistent(rest)
  }
}

fn validate_forward_memory(wm: WorkingMemory) -> Result(Nil, ForwardError) {
  case wm.is_consistent && list.is_empty(wm.anomalies) {
    False -> Error(InconsistentRules)
    True -> {
      case
        bounded_all(wm.facts, maximum_facts, valid_fact)
        && bounded_all(wm.rules, maximum_rules, valid_rule)
      {
        False -> Error(InvalidWorkingMemory)
        True -> {
          let names = list.map(wm.rules, fn(rule) { rule.name })
          case list.length(list.unique(names)) == list.length(names) {
            False -> Error(InvalidWorkingMemory)
            True ->
              case rules_are_consistent(wm.rules) {
                False -> Error(InconsistentRules)
                True -> Ok(Nil)
              }
          }
        }
      }
    }
  }
}

fn visit(remaining: Int) -> Result(Int, ForwardError) {
  case remaining > 0 {
    True -> Ok(remaining - 1)
    False -> Error(WorkExhausted)
  }
}

fn check_attributes(
  attrs: List(#(String, String)),
  attr_name: String,
  op: ReteOp,
  target_val: String,
  remaining: Int,
) -> Result(#(Bool, Int), ForwardError) {
  case attrs {
    [] -> Ok(#(False, remaining))
    [#(name, value), ..rest] -> {
      use remaining <- result.try(visit(remaining))
      case name == attr_name {
        False -> check_attributes(rest, attr_name, op, target_val, remaining)
        True ->
          Ok(#(
            case op {
              OpEq -> value == target_val
              OpNeq -> value != target_val
              OpContains -> string.contains(value, target_val)
            },
            remaining,
          ))
      }
    }
  }
}

fn check_facts(
  facts: List(ReteFact),
  condition: ReteCondition,
  remaining: Int,
) -> Result(#(Bool, Int), ForwardError) {
  case facts {
    [] -> Ok(#(False, remaining))
    [fact, ..rest] -> {
      use remaining <- result.try(visit(remaining))
      case fact.kind == condition.fact_kind {
        False -> check_facts(rest, condition, remaining)
        True -> {
          use #(matched, remaining) <- result.try(check_attributes(
            fact.attributes,
            condition.attribute,
            condition.op,
            condition.value,
            remaining,
          ))
          case matched {
            True -> Ok(#(True, remaining))
            False -> check_facts(rest, condition, remaining)
          }
        }
      }
    }
  }
}

fn check_conditions(
  conditions: List(ReteCondition),
  facts: List(ReteFact),
  remaining: Int,
) -> Result(#(Bool, Int), ForwardError) {
  case conditions {
    [] -> Ok(#(True, remaining))
    [condition, ..rest] -> {
      use remaining <- result.try(visit(remaining))
      use #(matched, remaining) <- result.try(check_facts(
        facts,
        condition,
        remaining,
      ))
      case matched {
        False -> Ok(#(False, remaining))
        True -> check_conditions(rest, facts, remaining)
      }
    }
  }
}

fn apply_consequence(
  rule: ReteRule,
  state: Execution,
) -> Result(Execution, ForwardError) {
  case rule.consequence {
    ConsequenceGateVerdict(verdict) -> {
      case state.verdicts {
        [#(_, previous), ..] if previous != verdict ->
          Error(ConflictingVerdicts)
        _ ->
          Ok(
            Execution(..state, verdicts: [
              #(rule.name, verdict),
              ..state.verdicts
            ]),
          )
      }
    }
    ConsequenceAssert(kind, attribute, value) -> {
      use #(present, remaining) <- result.try(check_facts(
        state.facts,
        ReteCondition(kind, attribute, OpEq, value),
        state.remaining,
      ))
      case present {
        True -> Ok(Execution(..state, remaining: remaining))
        False ->
          case list.length(state.facts) < maximum_facts {
            False -> Error(FactCapacity)
            True ->
              Ok(
                Execution(
                  ..state,
                  facts: [ReteFact(kind, [#(attribute, value)]), ..state.facts],
                  remaining: remaining,
                ),
              )
          }
      }
    }
  }
}

fn run_round(
  pending: List(ReteRule),
  deferred: List(ReteRule),
  state: Execution,
  progressed: Bool,
) -> Result(Execution, ForwardError) {
  case pending {
    [] ->
      case progressed && !list.is_empty(deferred) {
        True -> run_round(list.reverse(deferred), [], state, False)
        False -> Ok(state)
      }
    [rule, ..rest] -> {
      use remaining <- result.try(visit(state.remaining))
      use #(matched, remaining) <- result.try(check_conditions(
        rule.conditions,
        state.facts,
        remaining,
      ))
      let state = Execution(..state, remaining: remaining)
      case matched {
        False -> run_round(rest, [rule, ..deferred], state, progressed)
        True -> {
          use state <- result.try(apply_consequence(rule, state))
          run_round(
            rest,
            deferred,
            Execution(..state, fired_count: state.fired_count + 1),
            True,
          )
        }
      }
    }
  }
}
