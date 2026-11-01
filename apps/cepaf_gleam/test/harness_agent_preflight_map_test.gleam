import cepaf_gleam/harness/agent_capabilities as ontology
import cepaf_gleam/harness/agent_ecology
import cepaf_gleam/harness/agent_preflight_map as map
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import uos_swarm/symbiosis_preflight as policy

const sha = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

fn binding(a: policy.Agent) -> policy.Binding {
  policy.Binding(
    string.repeat("a", 40),
    string.repeat("b", 64),
    "fixture-" <> ontology.name(map.ontology_agent(a)),
  )
}

fn bindings() {
  list.map(policy.agents(), fn(a) { #(a, binding(a)) })
}

fn registry() {
  policy.Registry(policy.Claude, binding(policy.Claude), [
    "fixture:read",
    "fixture:search",
  ])
}

fn state() {
  let assert Ok(s) =
    policy.new_with_registry(bindings(), policy.defaults(), [registry()], 0)
  s
}

fn observation(r: policy.Request, results: policy.Results) {
  policy.Observation(
    r.seq,
    r.binding,
    r.started_ms + 1,
    1,
    results,
    policy.ProbeUnavailable,
  )
}

fn yes() {
  policy.Results(Some(True), Some(True), Some(True))
}

// Drive only the existing pure policy with ordinary successful fixture data.
// No timer/collector/process or native service is started by this helper.
fn seek(
  s: policy.State,
  probe: policy.Probe,
  now: Int,
  fuel: Int,
) -> #(policy.State, policy.Request) {
  let assert True = fuel > 0
  let assert Ok(due) = policy.demand(s, policy.Claude, probe, now)
  let assert Ok(#(next, request)) = policy.poll(due, now)
  case request {
    Some(r) if r.agent == policy.Claude && r.probe == probe -> #(next, r)
    Some(r) -> {
      let assert Ok(done) =
        policy.record(next, r, observation(r, yes()), now + 1)
      seek(done, probe, now + 1000, fuel - 1)
    }
    None -> seek(next, probe, now + 1000, fuel - 1)
  }
}

fn covered() -> #(policy.State, Int) {
  let #(s, r) = seek(state(), policy.CoverageProbe, 0, 100)
  let at = r.started_ms + 1
  let service = fn(id) {
    policy.ServiceObservation(
      r.agent,
      id,
      r.binding,
      policy.ServiceDimension(True, at),
      policy.ServiceDimension(True, at),
      policy.ServiceDimension(True, at),
    )
  }
  let proof =
    policy.CoverageEvidence(r.agent, r.binding, [
      service("fixture:search"),
      service("fixture:read"),
    ])
  let assert Ok(s) =
    policy.record_coverage(s, r, observation(r, yes()), proof, at)
  #(s, at)
}

fn claude(snapshot: map.Snapshot) -> map.AgentView {
  let assert Ok(agent) =
    list.find(snapshot.agents, fn(a) { a.agent == ontology.Claude })
  agent
}

pub fn closed_four_agent_bijection_and_existing_eight_classes_test() {
  list.each(ontology.agents(), fn(a) {
    map.ontology_agent(map.preflight_agent(a)) |> should.equal(a)
  })
  list.length(policy.capabilities()) |> should.equal(8)
  map.dimensions()
  |> should.equal([policy.Function, policy.Performance, policy.Operation])
}

pub fn crosswalk_preserves_unmapped_and_related_concepts_test() {
  let assert map.Unmapped(_) = map.crosswalk(policy.KnowledgeSearch)
  let assert map.Unmapped(_) = map.crosswalk(policy.KnowledgeWriteback)
  map.crosswalk(policy.KnowledgeRead)
  |> should.equal(map.RelatedConcept(ontology.KnowledgeRead))
  map.crosswalk(policy.Transport)
  |> should.equal(map.RelatedConcept(ontology.ConfigureMcp))
  map.crosswalk(policy.Verification)
  |> should.equal(map.CrossCutting(ontology.IndependentVerification))
}

pub fn absent_policy_has_ninety_six_unknown_dimensions_test() {
  let assert Ok(snapshot) = map.project(None, Some(sha), -100)
  let dimensions =
    list.flat_map(snapshot.agents, fn(a) {
      a.required_registry |> should.equal(None)
      a.coverage_health |> should.equal(policy.Unknown)
      list.flat_map(a.capabilities, fn(c) { c.dimensions })
    })
  list.length(dimensions) |> should.equal(96)
  list.all(dimensions, fn(d) { d.health == policy.Unknown }) |> should.be_true
  snapshot.authority |> should.equal(ontology.AdmissionRequired)
}

pub fn exact_state_registry_and_both_candidate_schemes_preserved_test() {
  let s = state()
  let assert Ok(snapshot) = map.project(Some(s), Some(sha), 0)
  let c = claude(snapshot)
  c.required_registry |> should.equal(Some(registry()))
  c.preflight_binding |> should.equal(Some(binding(policy.Claude)))
  snapshot.ontology_candidate_sha256 |> should.equal(Some(sha))
  snapshot.linkage |> should.equal(map.UnknownIdentityLinkage)
  c.catalog_attestation |> should.equal(map.CallerBoundCatalogUnattested)
  c.last_service_data |> should.equal([])
  c.coverage_health |> should.equal(policy.Unknown)
}

pub fn projection_and_read_accessors_do_not_mutate_existing_policy_test() {
  let s = state()
  let before = policy.to_json(s, 0) |> json.to_string
  policy.binding_snapshot(s, policy.Claude)
  |> should.equal(binding(policy.Claude))
  policy.registry_snapshot(s, policy.Claude) |> should.equal(Some(registry()))
  policy.coverage_snapshot(s, policy.Claude) |> should.equal(None)
  let assert Ok(_) = map.project(Some(s), Some(sha), 0)
  policy.to_json(s, 0) |> json.to_string |> should.equal(before)
}

pub fn capability_dimensions_use_existing_policy_independently_test() {
  let #(s, r) = seek(state(), policy.CapabilityProbe(policy.Transport), 0, 100)
  let assert Ok(s) =
    policy.record(
      s,
      r,
      observation(r, policy.Results(Some(True), None, Some(True))),
      r.started_ms + 1,
    )
  let assert Ok(snapshot) = map.project(Some(s), Some(sha), r.started_ms + 1)
  let assert Ok(c) =
    list.find(claude(snapshot).capabilities, fn(c) {
      c.capability == policy.Transport
    })
  c.dimensions
  |> should.equal([
    map.DimensionView(policy.Function, policy.Ready),
    map.DimensionView(policy.Performance, policy.Unknown),
    map.DimensionView(policy.Operation, policy.Ready),
  ])
}

pub fn exact_coverage_leaf_data_and_policy_freshness_are_separate_test() {
  let #(s, at) = covered()
  let assert Ok(fresh) = map.project(Some(s), Some(sha), at)
  let c = claude(fresh)
  c.coverage_health |> should.equal(policy.Ready)
  list.map(c.last_service_data, fn(s) { s.service_id })
  |> should.equal(["fixture:search", "fixture:read"])
  list.each(c.last_service_data, fn(leaf) {
    leaf.binding |> should.equal(binding(policy.Claude))
    leaf.function.observed_ms |> should.equal(at)
    leaf.performance.observed_ms |> should.equal(at)
    leaf.operation.observed_ms |> should.equal(at)
  })
  let assert Ok(stale) = map.project(Some(s), Some(sha), at + 1_800_001)
  claude(stale).coverage_health |> should.equal(policy.Unknown)
  claude(stale).last_service_data |> should.equal(c.last_service_data)
  stale.authority |> should.equal(ontology.AdmissionRequired)
}

pub fn existing_ecology_exposes_source_and_optional_policy_views_test() {
  let text = agent_ecology.format_ecology_summary()
  string.contains(text, "4 agents / 8 existing classes / 3 dimensions")
  |> should.be_true
  string.contains(text, "Snapshot and service coverage: UNKNOWN")
  |> should.be_true
  let assert Ok(view) =
    agent_ecology.format_agent_preflight(Some(state()), Some(sha), 0)
  string.contains(view, "Identity link: UNKNOWN") |> should.be_true
  string.contains(view, "official completeness UNATTESTED") |> should.be_true
  string.contains(view, "Function/Performance/Operation") |> should.be_true
}
