//// Read-only ontology projection of the EXISTING preflight policy. No timer,
//// collector, record, admission, model, task or effect interpreter is created.
//// Policy health remains injected-observer DATA, not attested runtime health.

import cepaf_gleam/harness/agent_capabilities as ontology
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/symbiosis_preflight as policy

pub type IdentityLinkage {
  UnknownIdentityLinkage
}

pub type CatalogAttestation {
  CallerBoundCatalogUnattested
}

pub type Relationship {
  RelatedConcept(capability: ontology.Capability)
  CrossCutting(requirement: ontology.Requirement)
  Unmapped(reason: String)
}

pub type DimensionView {
  DimensionView(dimension: policy.Dimension, health: policy.Health)
}

pub type CapabilityView {
  CapabilityView(capability: policy.Capability, dimensions: List(DimensionView))
}

pub type AgentView {
  AgentView(
    agent: ontology.Agent,
    preflight_binding: Option(policy.Binding),
    required_registry: Option(policy.Registry),
    last_service_data: List(policy.ServiceObservation),
    catalog_attestation: CatalogAttestation,
    coverage_health: policy.Health,
    heartbeat_health: policy.Health,
    capabilities: List(CapabilityView),
  )
}

pub type Snapshot {
  Snapshot(
    ontology_candidate_sha256: Option(String),
    linkage: IdentityLinkage,
    agents: List(AgentView),
    authority: ontology.AuthorityState,
  )
}

pub fn preflight_agent(agent: ontology.Agent) -> policy.Agent {
  case agent {
    ontology.Pi -> policy.Pi
    ontology.Claude -> policy.Claude
    ontology.Agy -> policy.Agy
    ontology.Codex -> policy.Codex
  }
}

pub fn ontology_agent(agent: policy.Agent) -> ontology.Agent {
  case agent {
    policy.Pi -> ontology.Pi
    policy.Claude -> ontology.Claude
    policy.Agy -> ontology.Agy
    policy.Codex -> ontology.Codex
  }
}

pub fn dimensions() -> List(policy.Dimension) {
  [policy.Function, policy.Performance, policy.Operation]
}

/// Related concepts do not assert set inclusion or a necessary prerequisite.
/// In particular MCP configuration and functional transport are distinct.
/// No relation transfers a passing observation between these taxonomies.
pub fn crosswalk(capability: policy.Capability) -> Relationship {
  case capability {
    policy.KnowledgeSearch ->
      Unmapped("scoped read_file does not prove KM search")
    policy.KnowledgeRead -> RelatedConcept(ontology.KnowledgeRead)
    policy.KnowledgeWriteback ->
      Unmapped("generic proposal/file write does not prove KM writeback")
    policy.TaskAuthority -> RelatedConcept(ontology.TaskLifecycle)
    policy.TaskExecution -> RelatedConcept(ontology.ToolExecution)
    policy.Verification -> CrossCutting(ontology.IndependentVerification)
    policy.ModelBudget -> CrossCutting(ontology.DurableLiability)
    policy.Transport -> RelatedConcept(ontology.ConfigureMcp)
  }
}

fn valid_sha256(s: String) -> Bool {
  string.byte_size(s) == 71
  && string.starts_with(s, "sha256:")
  && list.all(string.to_graphemes(string.drop_start(s, 7)), fn(c) {
    string.byte_size(c) == 1 && string.contains("0123456789abcdef", c)
  })
}

fn agent_view(
  s: Option(policy.State),
  agent: ontology.Agent,
  now_ms: Int,
) -> AgentView {
  let a = preflight_agent(agent)
  let views =
    list.map(policy.capabilities(), fn(c) {
      CapabilityView(
        c,
        list.map(dimensions(), fn(d) {
          DimensionView(d, case s {
            Some(state) -> policy.status(state, a, c, d, now_ms)
            None -> policy.Unknown
          })
        }),
      )
    })
  case s {
    None ->
      AgentView(
        agent,
        None,
        None,
        [],
        CallerBoundCatalogUnattested,
        policy.Unknown,
        policy.Unknown,
        views,
      )
    Some(state) ->
      AgentView(
        agent,
        Some(policy.binding_snapshot(state, a)),
        policy.registry_snapshot(state, a),
        case policy.coverage_snapshot(state, a) {
          Some(proof) -> proof.services
          None -> []
        },
        CallerBoundCatalogUnattested,
        policy.coverage_health(state, a, now_ms),
        policy.heartbeat_health(state, a, now_ms),
        views,
      )
  }
}

/// SHA256 source/candidate identity is deliberately separate from preflight's
/// exact40hex commit candidate. No truncation/padding/hash alias authenticates
/// their relationship. Invalid identity DATA refuses the projection.
pub fn project(
  state: Option(policy.State),
  ontology_candidate_sha256: Option(String),
  now_ms: Int,
) -> Result(Snapshot, String) {
  use _ <- result.try(case ontology_candidate_sha256 {
    None -> Ok(Nil)
    Some(s) ->
      case valid_sha256(s) {
        True -> Ok(Nil)
        False -> Error("ontology_sha256_data_invalid")
      }
  })
  case now_ms >= -9_000_000_000_000 && now_ms <= 9_000_000_000_000 {
    False -> Error("preflight_monotonic_data_out_of_bounds")
    True ->
      Ok(Snapshot(
        ontology_candidate_sha256,
        UnknownIdentityLinkage,
        list.map(ontology.agents(), fn(a) { agent_view(state, a, now_ms) }),
        ontology.AdmissionRequired,
      ))
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

fn health_name(h: policy.Health) -> String {
  case h {
    policy.Unknown -> "UNKNOWN"
    policy.Ready -> "READY_POLICY_DATA"
    policy.Stopped -> "STOP_POLICY_DATA"
  }
}

pub fn format_snapshot(snapshot: Snapshot) -> String {
  "Preflight view: existing policy DATA; authority remains required.\n"
  <> "Identity link: UNKNOWN. Required-service catalogs: caller-bound, official completeness UNATTESTED.\n"
  <> string.join(
    list.map(snapshot.agents, fn(agent) {
      ontology.name(agent.agent)
      <> ": coverage="
      <> health_name(agent.coverage_health)
      <> "; registered services="
      <> case agent.required_registry {
        None -> "UNKNOWN"
        Some(r) -> int.to_string(list.length(r.required_services))
      }
      <> "; classes="
      <> string.join(
        list.map(agent.capabilities, fn(c) {
          capability_name(c.capability)
          <> "["
          <> string.join(
            list.map(c.dimensions, fn(d) { health_name(d.health) }),
            "/",
          )
          <> "]"
        }),
        ", ",
      )
    }),
    "\n",
  )
  <> "\nDimension order: Function/Performance/Operation. "
  <> "Last service leaf data does not establish freshness, collector authenticity or full system coverage."
}

/// Source-only default for the existing ecology formatter: no snapshot means
/// UNKNOWN, never an invented running monitor or a zero-service coverage pass.
pub fn format_summary() -> String {
  "Preflight source mapping: "
  <> int.to_string(list.length(ontology.agents()))
  <> " agents / "
  <> int.to_string(list.length(policy.capabilities()))
  <> " existing classes / "
  <> int.to_string(list.length(dimensions()))
  <> " dimensions. Snapshot and service coverage: UNKNOWN; identity linkage: UNKNOWN. "
  <> "No monitor started; no authority granted."
}
