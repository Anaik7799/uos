//// Explicit typed ADVISORY projection, not registration with any live engine.
//// Existing105 scalar guard rules remain unchanged. No sentinel floats, effects,
//// global halt, restart, task mutation or admission authority are introduced.

import cepaf_gleam/ha/guard_rules as guards
import gleam/json
import gleam/list
import uos_swarm/symbiosis_preflight as policy

pub type Scope {
  AgentHeartbeat
  CapabilityDimension(policy.Capability, policy.Dimension)
  RequiredServiceCoverage
}

pub type Decision {
  ScopedStop
  ScopeUnknown
  ScopedObservation
}

pub type Layer {
  L0
  L1
  L2
  L3
  L4
  L5
  L6
  L7
  L8
  L9
}

pub type RcaClass {
  StopRequiresInvestigation
  UnknownRequiresEvidence
  NoCurrentFinding
}

pub type Fact {
  Fact(
    agent: policy.Agent,
    scope: Scope,
    health: policy.Health,
    decision: Decision,
    layer: Layer,
  )
}

pub type RcaGroup {
  RcaGroup(
    agent: policy.Agent,
    layer: Layer,
    classification: RcaClass,
    count: Int,
  )
}

pub opaque type Analysis {
  Analysis(
    facts: List(Fact),
    evaluations: List(guards.RuleEvaluation),
    rca_groups: List(RcaGroup),
  )
}

pub fn layers() -> List(Layer) {
  [L0, L1, L2, L3, L4, L5, L6, L7, L8, L9]
}

/// Primary scope projection of canonical
/// docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md §6.
/// This mapping is not a full layer cross-product or runtime coverage claim.
pub fn layer_for(scope: Scope) -> Layer {
  case scope {
    AgentHeartbeat -> L2
    RequiredServiceCoverage -> L6
    CapabilityDimension(capability, _) ->
      case capability {
        policy.TaskAuthority -> L0
        policy.TaskExecution -> L3
        policy.Verification -> L9
        policy.KnowledgeSearch | policy.KnowledgeRead -> L4
        policy.KnowledgeWriteback -> L4
        policy.ModelBudget -> L0
        policy.Transport -> L7
      }
  }
}

fn decision(health: policy.Health) -> Decision {
  case health {
    policy.Stopped -> ScopedStop
    policy.Unknown -> ScopeUnknown
    policy.Ready -> ScopedObservation
  }
}

fn fact(agent: policy.Agent, scope: Scope, health: policy.Health) -> Fact {
  Fact(agent, scope, health, decision(health), layer_for(scope))
}

fn agent_name(a: policy.Agent) -> String {
  case a {
    policy.Claude -> "claude"
    policy.Pi -> "pi"
    policy.Agy -> "agy"
    policy.Codex -> "codex"
  }
}

fn capability_name(c: policy.Capability) -> String {
  case c {
    policy.KnowledgeSearch -> "knowledge_search"
    policy.KnowledgeRead -> "knowledge_read"
    policy.KnowledgeWriteback -> "knowledge_writeback"
    policy.TaskAuthority -> "task_authority"
    policy.TaskExecution -> "task_execution"
    policy.Verification -> "verification"
    policy.ModelBudget -> "model_budget"
    policy.Transport -> "transport"
  }
}

fn dimension_name(d: policy.Dimension) -> String {
  case d {
    policy.Function -> "function"
    policy.Performance -> "performance"
    policy.Operation -> "operation"
  }
}

fn scope_name(scope: Scope) -> String {
  case scope {
    AgentHeartbeat -> "heartbeat"
    RequiredServiceCoverage -> "required_service_coverage"
    CapabilityDimension(c, d) -> capability_name(c) <> ":" <> dimension_name(d)
  }
}

fn layer_name(layer: Layer) -> String {
  case layer {
    L0 -> "L0"
    L1 -> "L1"
    L2 -> "L2"
    L3 -> "L3"
    L4 -> "L4"
    L5 -> "L5"
    L6 -> "L6"
    L7 -> "L7"
    L8 -> "L8"
    L9 -> "L9"
  }
}

fn decision_name(d: Decision) -> String {
  case d {
    ScopedStop -> "SCOPED_STOP_ADVISORY"
    ScopeUnknown -> "SCOPE_UNKNOWN"
    ScopedObservation -> "SCOPED_OBSERVATION"
  }
}

fn rca_class(d: Decision) -> RcaClass {
  case d {
    ScopedStop -> StopRequiresInvestigation
    ScopeUnknown -> UnknownRequiresEvidence
    ScopedObservation -> NoCurrentFinding
  }
}

fn rca_name(c: RcaClass) -> String {
  case c {
    StopRequiresInvestigation -> "stop_requires_investigation"
    UnknownRequiresEvidence -> "unknown_requires_evidence"
    NoCurrentFinding -> "no_current_finding"
  }
}

fn evaluation(f: Fact) -> guards.RuleEvaluation {
  let description = agent_name(f.agent) <> ":" <> scope_name(f.scope)
  // LogWarning is a returned diagnostic VALUE; this module never executes it.
  let #(action, salience) = case f.decision {
    ScopedStop -> #(
      guards.LogWarning("Scoped observation stopped: " <> description),
      90,
    )
    ScopeUnknown -> #(
      guards.LogWarning("Scoped evidence unknown: " <> description),
      60,
    )
    ScopedObservation -> #(guards.NoAction, 0)
  }
  guards.RuleEvaluation(
    "SYM-PREFLIGHT:" <> description,
    "TypedSymbiosisPreflight",
    f.decision != ScopedObservation,
    action,
    salience,
  )
}

/// Sole integration seam: callers must explicitly invoke this pure function.
/// Facts inherit the policy's evidence premises; they do not authenticate its
/// injected observations or prove that a configured registry is the official catalog.
pub fn evaluate(state: policy.State, now_ms: Int) -> Analysis {
  let facts =
    list.flat_map(policy.agents(), fn(agent) {
      let dimensions =
        list.flat_map(policy.capabilities(), fn(c) {
          list.map(
            [policy.Function, policy.Performance, policy.Operation],
            fn(d) {
              fact(
                agent,
                CapabilityDimension(c, d),
                policy.status(state, agent, c, d, now_ms),
              )
            },
          )
        })
      [
        fact(
          agent,
          AgentHeartbeat,
          policy.heartbeat_health(state, agent, now_ms),
        ),
        fact(
          agent,
          RequiredServiceCoverage,
          policy.coverage_health(state, agent, now_ms),
        ),
        ..dimensions
      ]
    })
  let groups =
    list.flat_map(policy.agents(), fn(a) {
      list.flat_map(layers(), fn(layer) {
        list.filter_map(
          [StopRequiresInvestigation, UnknownRequiresEvidence, NoCurrentFinding],
          fn(classification) {
            let count =
              list.count(facts, fn(f) {
                f.agent == a
                && f.layer == layer
                && rca_class(f.decision) == classification
              })
            case count > 0 {
              True -> Ok(RcaGroup(a, layer, classification, count))
              False -> Error(Nil)
            }
          },
        )
      })
    })
  Analysis(facts, list.map(facts, evaluation), groups)
}

pub fn facts(a: Analysis) -> List(Fact) {
  a.facts
}

pub fn evaluations(a: Analysis) -> List(guards.RuleEvaluation) {
  a.evaluations
}

pub fn rca_groups(a: Analysis) -> List(RcaGroup) {
  a.rca_groups
}

pub fn to_json(a: Analysis) -> json.Json {
  json.object([
    #("schema", json.string("uos-symbiosis-advisory-guard-projection-v1")),
    #("authority", json.string("NONE")),
    #("runtime_enforcement", json.bool(False)),
    #("registered_with_engine", json.bool(False)),
    #("proxy_float_encoding", json.bool(False)),
    #(
      "observation_authentication",
      json.string("EXTERNAL_COLLECTOR_PREMISE_NOT_PROVEN_BY_PROJECTION"),
    ),
    #(
      "registry_completeness",
      json.string("OFFICIAL_CATALOG_COMPLETENESS_NOT_PROVEN"),
    ),
    #(
      "fractal_scope",
      json.string(
        "CANONICAL_SECTION_6_PRIMARY_SCOPE_PROJECTION_NOT_FULL_LAYER_CROSSPRODUCT",
      ),
    ),
    #(
      "layer_fact_counts",
      json.array(layers(), fn(layer) {
        let count = list.count(a.facts, fn(f) { f.layer == layer })
        json.object([
          #("layer", json.string(layer_name(layer))),
          #("projected_fact_count", json.int(count)),
          #(
            "mapping_status",
            json.string(case count {
              0 -> "NO_FACTS_ASSIGNED_BY_PRIMARY_SCOPE_MAPPING"
              _ -> "MAPPED_FACTS_NOT_RUNTIME_COVERAGE_PROOF"
            }),
          ),
        ])
      }),
    ),
    #("fact_count", json.int(list.length(a.facts))),
    #(
      "stopped_scopes",
      json.int(list.count(a.facts, fn(f) { f.decision == ScopedStop })),
    ),
    #(
      "unknown_scopes",
      json.int(list.count(a.facts, fn(f) { f.decision == ScopeUnknown })),
    ),
    #(
      "observed_scopes",
      json.int(list.count(a.facts, fn(f) { f.decision == ScopedObservation })),
    ),
    #(
      "facts",
      json.array(a.facts, fn(f) {
        json.object([
          #("agent", json.string(agent_name(f.agent))),
          #("scope", json.string(scope_name(f.scope))),
          #("decision", json.string(decision_name(f.decision))),
          #("layer", json.string(layer_name(f.layer))),
        ])
      }),
    ),
    #(
      "rca_groups",
      json.array(a.rca_groups, fn(g) {
        json.object([
          #("agent", json.string(agent_name(g.agent))),
          #("layer", json.string(layer_name(g.layer))),
          #("classification", json.string(rca_name(g.classification))),
          #("count", json.int(g.count)),
        ])
      }),
    ),
  ])
}
