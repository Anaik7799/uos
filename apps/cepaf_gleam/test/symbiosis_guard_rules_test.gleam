import cepaf_gleam/ha/guard_rules as old
import cepaf_gleam/ha/symbiosis_guard_rules as bridge
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import uos_swarm/symbiosis_preflight as p

fn binding() {
  p.Binding(
    string.repeat("a", 40),
    string.repeat("b", 64),
    "private-session-not-for-json",
  )
}

fn bindings() {
  list.map(p.agents(), fn(a) { #(a, binding()) })
}

fn initial() {
  let assert Ok(s) = p.new(bindings(), p.defaults(), 0)
  s
}

fn yes() {
  p.Results(Some(True), Some(True), Some(True))
}

fn finish(s: p.State, r: p.Request, results: p.Results, now: Int) {
  let o =
    p.Observation(
      r.seq,
      r.binding,
      now,
      now - r.started_ms,
      results,
      p.ProbeFailed,
    )
  let assert Ok(s) = p.record(s, r, o, now)
  s
}

fn target(
  s: p.State,
  a: p.Agent,
  probe: p.Probe,
  now: Int,
  remaining: Int,
) -> #(p.State, p.Request, Int) {
  let assert True = remaining > 0
  let assert Ok(#(s, request)) = p.poll(s, now)
  case request {
    Some(r) if r.agent == a && r.probe == probe -> #(s, r, now)
    Some(r) ->
      target(finish(s, r, yes(), now), a, probe, now + 1000, remaining - 1)
    None -> target(s, a, probe, now + 1000, remaining - 1)
  }
}

fn find(
  a: bridge.Analysis,
  agent: p.Agent,
  scope: bridge.Scope,
) -> bridge.Fact {
  let assert Ok(f) =
    list.find(bridge.facts(a), fn(f) { f.agent == agent && f.scope == scope })
  f
}

fn corresponding(a: bridge.Analysis, f: bridge.Fact) -> old.RuleEvaluation {
  let assert Ok(#(_, e)) =
    list.find(list.zip(bridge.facts(a), bridge.evaluations(a)), fn(pair) {
      pair.0 == f
    })
  e
}

pub fn initial_exact104_facts_unique_evaluations_four_agent_parity_test() {
  let a = bridge.evaluate(initial(), 0)
  list.length(bridge.facts(a)) |> should.equal(104)
  list.length(bridge.evaluations(a)) |> should.equal(104)
  list.each(p.agents(), fn(agent) {
    list.count(bridge.facts(a), fn(f) { f.agent == agent }) |> should.equal(26)
    list.each(bridge.facts(a), fn(f) {
      f.decision |> should.equal(bridge.ScopeUnknown)
    })
  })
  list.each(bridge.evaluations(a), fn(e) {
    list.count(bridge.evaluations(a), fn(other) { other.rule_id == e.rule_id })
    |> should.equal(1)
  })
}

pub fn every_agent_and_dimension_failure_or_unknown_has_independent_typed_diagnostic_test() {
  list.each(p.agents(), fn(agent) {
    list.each([p.Function, p.Performance, p.Operation], fn(dimension) {
      list.each([Some(False), None], fn(value) {
        let #(s, r, now) =
          target(initial(), agent, p.CapabilityProbe(p.Transport), 0, 1000)
        let result = case dimension {
          p.Function -> p.Results(value, Some(True), Some(True))
          p.Performance -> p.Results(Some(True), value, Some(True))
          p.Operation -> p.Results(Some(True), Some(True), value)
        }
        let s = finish(s, r, result, now)
        let a = bridge.evaluate(s, now)
        let f =
          find(a, agent, bridge.CapabilityDimension(p.Transport, dimension))
        let expected = case value {
          Some(False) -> bridge.ScopedStop
          _ -> bridge.ScopeUnknown
        }
        f.decision |> should.equal(expected)
        let e = corresponding(a, f)
        e.condition_met |> should.be_true
        e.salience
        |> should.equal(case value {
          Some(False) -> 90
          _ -> 60
        })
        case e.action {
          old.LogWarning(_) -> Nil
          _ -> panic as "only_diagnostic_log_value_permitted"
        }
        list.each([p.Function, p.Performance, p.Operation], fn(other) {
          case other != dimension {
            True ->
              find(a, agent, bridge.CapabilityDimension(p.Transport, other)).decision
              |> should.equal(bridge.ScopedObservation)
            False -> Nil
          }
        })
      })
    })
  })
}

pub fn ready_scope_no_action_never_grants_authority_test() {
  let #(s, r, now) =
    target(initial(), p.Codex, p.CapabilityProbe(p.Verification), 0, 1000)
  let a = bridge.evaluate(finish(s, r, yes(), now), now)
  let f =
    find(a, p.Codex, bridge.CapabilityDimension(p.Verification, p.Function))
  f.decision |> should.equal(bridge.ScopedObservation)
  let e = corresponding(a, f)
  e.condition_met |> should.be_false
  e.action |> should.equal(old.NoAction)
  let text = json.to_string(bridge.to_json(a))
  list.each(
    [
      "\"authority\":\"NONE\"",
      "\"runtime_enforcement\":false",
      "\"registered_with_engine\":false",
      "\"proxy_float_encoding\":false",
      "EXTERNAL_COLLECTOR_PREMISE_NOT_PROVEN_BY_PROJECTION",
      "OFFICIAL_CATALOG_COMPLETENESS_NOT_PROVEN",
    ],
    fn(s) { string.contains(text, s) |> should.be_true },
  )
}

pub fn heartbeat_success_never_promotes_capability_or_legacy_coverage_test() {
  let assert Ok(#(s, Some(r))) = p.poll(initial(), 0)
  let a = bridge.evaluate(finish(s, r, p.Results(None, None, Some(True)), 0), 0)
  find(a, p.Claude, bridge.AgentHeartbeat).decision
  |> should.equal(bridge.ScopedObservation)
  list.each(p.capabilities(), fn(c) {
    list.each([p.Function, p.Performance, p.Operation], fn(d) {
      find(a, p.Claude, bridge.CapabilityDimension(c, d)).decision
      |> should.equal(bridge.ScopeUnknown)
    })
  })
  find(a, p.Claude, bridge.RequiredServiceCoverage).decision
  |> should.equal(bridge.ScopeUnknown)
}

pub fn malformed_or_regressed_monotonic_time_is_scoped_stop_test() {
  let #(s, r, now) =
    target(initial(), p.Codex, p.CapabilityProbe(p.KnowledgeRead), 0, 1000)
  let s = finish(s, r, yes(), now)
  list.each([-9_000_000_000_001, 9_000_000_000_001, now - 1], fn(at) {
    list.each(bridge.facts(bridge.evaluate(s, at)), fn(f) {
      f.decision |> should.equal(bridge.ScopedStop)
    })
  })
}

pub fn stale_freshness_is_unknown_not_invented_failure_cause_test() {
  let #(s, r, now) =
    target(initial(), p.Codex, p.CapabilityProbe(p.KnowledgeRead), 0, 1000)
  let a = bridge.evaluate(finish(s, r, yes(), now), now + 300_001)
  find(a, p.Codex, bridge.CapabilityDimension(p.KnowledgeRead, p.Function)).decision
  |> should.equal(bridge.ScopeUnknown)
}

pub fn grouped_rca_is_lossless_scoped_partition_not_global_jidoka_test() {
  let #(s, r, now) =
    target(initial(), p.Pi, p.CapabilityProbe(p.ModelBudget), 0, 1000)
  let a =
    bridge.evaluate(
      finish(s, r, p.Results(Some(False), None, Some(True)), now),
      now,
    )
  list.fold(bridge.rca_groups(a), 0, fn(total, g) { total + g.count })
  |> should.equal(104)
  list.each(bridge.rca_groups(a), fn(g) {
    { g.count > 0 && g.count <= 26 } |> should.be_true
  })
  list.any(bridge.rca_groups(a), fn(g) {
    g.agent == p.Pi
    && g.layer == bridge.L0
    && g.classification == bridge.StopRequiresInvestigation
  })
  |> should.be_true
  list.each(bridge.evaluations(a), fn(e) {
    case e.action {
      old.NoAction | old.LogWarning(_) -> Nil
      _ -> panic as "effectful_rule_action_forbidden"
    }
  })
}

pub fn canonical_section6_primary_scope_mapping_retains_explicit_unassigned_layers_test() {
  // Independent expected projection from
  // docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md §6.
  list.length(bridge.layers()) |> should.equal(10)
  bridge.layer_for(bridge.CapabilityDimension(p.TaskAuthority, p.Operation))
  |> should.equal(bridge.L0)
  bridge.layer_for(bridge.AgentHeartbeat) |> should.equal(bridge.L2)
  bridge.layer_for(bridge.CapabilityDimension(p.TaskExecution, p.Operation))
  |> should.equal(bridge.L3)
  bridge.layer_for(bridge.CapabilityDimension(p.Verification, p.Function))
  |> should.equal(bridge.L9)
  list.each([p.KnowledgeRead, p.KnowledgeSearch, p.KnowledgeWriteback], fn(c) {
    bridge.layer_for(bridge.CapabilityDimension(c, p.Function))
    |> should.equal(bridge.L4)
  })
  bridge.layer_for(bridge.CapabilityDimension(p.ModelBudget, p.Operation))
  |> should.equal(bridge.L0)
  bridge.layer_for(bridge.CapabilityDimension(p.Transport, p.Operation))
  |> should.equal(bridge.L7)
  bridge.layer_for(bridge.RequiredServiceCoverage) |> should.equal(bridge.L6)
  let a = bridge.evaluate(initial(), 0)
  list.each([bridge.L1, bridge.L5, bridge.L8], fn(layer) {
    list.any(bridge.facts(a), fn(f) { f.layer == layer }) |> should.be_false
  })
  let text = json.to_string(bridge.to_json(a))
  list.each(["L1", "L5", "L8"], fn(layer) {
    string.contains(
      text,
      "\"layer\":\"" <> layer <> "\",\"projected_fact_count\":0",
    )
    |> should.be_true
  })
  string.contains(text, "NO_FACTS_ASSIGNED_BY_PRIMARY_SCOPE_MAPPING")
  |> should.be_true
  string.contains(
    text,
    "CANONICAL_SECTION_6_PRIMARY_SCOPE_PROJECTION_NOT_FULL_LAYER_CROSSPRODUCT",
  )
  |> should.be_true
}

pub fn projection_does_not_expand_existing105_rule_catalog_or_leak_binding_test() {
  list.length(old.all_rules()) |> should.equal(105)
  let a = bridge.evaluate(initial(), 0)
  list.any(old.all_rules(), fn(r) { string.starts_with(r.id, "SYM-PREFLIGHT:") })
  |> should.be_false
  let text = json.to_string(bridge.to_json(a))
  list.each(
    [
      "private-session-not-for-json",
      string.repeat("a", 40),
      string.repeat("b", 64),
    ],
    fn(secret) { string.contains(text, secret) |> should.be_false },
  )
  bridge.to_json(a) |> json.to_string |> should.equal(text)
}

pub fn configured_exact_coverage_ready_is_only_scoped_registry_observation_test() {
  let assert Ok(s) =
    p.new_with_registry(
      bindings(),
      p.defaults(),
      [p.Registry(p.Agy, binding(), ["actual-service-id"])],
      0,
    )
  let #(s, r, now) = target(s, p.Agy, p.CoverageProbe, 0, 1000)
  let d = p.ServiceDimension(True, now)
  let proof =
    p.CoverageEvidence(p.Agy, binding(), [
      p.ServiceObservation(p.Agy, "actual-service-id", binding(), d, d, d),
    ])
  let o =
    p.Observation(
      r.seq,
      r.binding,
      now,
      now - r.started_ms,
      yes(),
      p.ProbeFailed,
    )
  let assert Ok(s) = p.record_coverage(s, r, o, proof, now)
  let a = bridge.evaluate(s, now)
  find(a, p.Agy, bridge.RequiredServiceCoverage).decision
  |> should.equal(bridge.ScopedObservation)
  find(a, p.Codex, bridge.RequiredServiceCoverage).decision
  |> should.equal(bridge.ScopeUnknown)
  json.to_string(bridge.to_json(a))
  |> string.contains("actual-service-id")
  |> should.be_false
}
