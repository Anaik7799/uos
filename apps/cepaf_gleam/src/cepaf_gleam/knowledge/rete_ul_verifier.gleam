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
            Ok(
              ContradictoryRules(
                rule_a: rule.name,
                rule_b: existing.name,
                reason: "Identical conditions yield conflicting verdicts: "
                  <> v1
                  <> " vs "
                  <> v2,
              ),
            )
          _, _ ->
            Ok(
              ShadowedRule(
                rule_name: rule.name,
                shadowed_by: existing.name,
              ),
            )
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
                        Ok(
                          CyclicChaining(
                            rule_name: rule.name,
                            cycle_target: existing.name,
                          ),
                        )
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
  case list.length(conds1) == list.length(conds2) {
    False -> False
    True -> {
      list.all(conds1, fn(c1) {
        list.any(conds2, fn(c2) {
          c1.fact_kind == c2.fact_kind
          && c1.attribute == c2.attribute
          && c1.op == c2.op
          && c1.value == c2.value
        })
      })
    }
  }
}

/// Evaluate forward-chaining rule firing across working memory facts.
pub fn fire_forward_chaining(wm: WorkingMemory) -> WorkingMemory {
  case wm.is_consistent {
    False -> wm
    True -> {
      let fired =
        list.filter(wm.rules, fn(rule) {
          list.all(rule.conditions, fn(cond) {
            list.any(wm.facts, fn(fact) {
              fact.kind == cond.fact_kind
              && check_attribute(fact.attributes, cond.attribute, cond.op, cond.value)
            })
          })
        })

      WorkingMemory(..wm, fired_count: list.length(fired))
    }
  }
}

fn check_attribute(
  attrs: List(#(String, String)),
  attr_name: String,
  op: ReteOp,
  target_val: String,
) -> Bool {
  case list.find(attrs, fn(pair) { pair.0 == attr_name }) {
    Ok(#(_, val)) -> {
      case op {
        OpEq -> val == target_val
        OpNeq -> val != target_val
        OpContains -> string.contains(val, target_val)
      }
    }
    Error(Nil) -> False
  }
}
