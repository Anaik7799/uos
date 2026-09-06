// ==============================================================================
// Unified Operational System (UOS) - ADK & C3I Master Ontology Engine
//
// Formally models the complete semantic and architectural ontology connecting:
// 1. Google ADK Complete Capabilities (Agents, Workflows, Runners, Sessions, Evals)
// 2. C3I Tri-Pillar Ecology (32 SDLC, 32 SRE, 32 Verification = 96 Agents)
// 3. ZigVM Complete 6-Stage Lifecycle (Ontology, Design, Code, Veri, SRE, KM)
// 4. Mathematical Invariants (Rocha Semiotic Cut, 13D TCM, Hardware Storage Lock)
//
// Zero-Muda Purity: Pure functional Gleam/OTP on BEAM (SC-MUDA-001)
// Storage Safety: HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736" enforced
// ==============================================================================

import gleam/json
import gleam/list
import gleam/string

/// Top-level ontology domain classification
pub type OntologyDomain {
  DomainAdkFramework
  DomainC3iEcology
  DomainZigvmLifecycle
  DomainFormalInvariants
  DomainFractalLayers
}

pub fn domain_to_string(domain: OntologyDomain) -> String {
  case domain {
    DomainAdkFramework -> "Google-ADK-Framework"
    DomainC3iEcology -> "C3I-Agentic-Ecology"
    DomainZigvmLifecycle -> "ZigVM-Complete-Lifecycle"
    DomainFormalInvariants -> "Formal-Mathematical-Invariants"
    DomainFractalLayers -> "Fractal-Layers-L0-L9"
  }
}

/// Ontology entity node in the semantic graph
pub type OntologyEntity {
  OntologyEntity(
    id: String,
    name: String,
    domain: OntologyDomain,
    fractal_layer: Int,
    description: String,
    contract_ref: String,
    tailscale_route: String,
  )
}

/// Semantic relationship predicate
pub type OntologyRelationType {
  RelImplements
  RelSubsumes
  RelGoverns
  RelVerifies
  RelTransmutes
  RelProtects
  RelOrchestrates
}

pub fn relation_type_to_string(rel: OntologyRelationType) -> String {
  case rel {
    RelImplements -> "implements"
    RelSubsumes -> "subsumes"
    RelGoverns -> "governs"
    RelVerifies -> "verifies"
    RelTransmutes -> "transmutes"
    RelProtects -> "protects"
    RelOrchestrates -> "orchestrates"
  }
}

/// Directed semantic edge connecting two ontology entities
pub type OntologyEdge {
  OntologyEdge(
    from_entity: String,
    relation: OntologyRelationType,
    to_entity: String,
    weight: Float,
  )
}

/// Master Ontology Graph
pub type MasterOntologyGraph {
  MasterOntologyGraph(
    version: String,
    timestamp: String,
    entities: List(OntologyEntity),
    edges: List(OntologyEdge),
  )
}

// ------------------------------------------------------------------------------
// Canonical Master Ontology Definitions
// ------------------------------------------------------------------------------

pub fn build_canonical_master_ontology() -> MasterOntologyGraph {
  let entities = [
    // ADK Framework Entities
    OntologyEntity(
      id: "adk-core-agent",
      name: "ADK LlmAgent & BaseAgent Substrate",
      domain: DomainAdkFramework,
      fractal_layer: 5,
      description: "Model-agnostic agent runtime supporting chat, task, and autonomous execution modes.",
      contract_ref: "SC-ADK-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/fpp-agents",
    ),
    OntologyEntity(
      id: "adk-workflow-graph",
      name: "ADK StateGraph Workflow Runtime",
      domain: DomainAdkFramework,
      fractal_layer: 5,
      description: "Directed acyclic and cyclic workflow execution engine with conditional branching and HITL.",
      contract_ref: "SC-ADK-002",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/fpp-topology",
    ),
    OntologyEntity(
      id: "adk-runner-hooks",
      name: "ADK Runner 6-Phase Lifecycle Hooks",
      domain: DomainAdkFramework,
      fractal_layer: 4,
      description: "Execution runtime dispatching Before/After Agent, Model, and Tool hooks.",
      contract_ref: "SC-ADK-003",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/ag-ui/events",
    ),
    OntologyEntity(
      id: "adk-session-deltas",
      name: "ADK Stateful Sessions & RFC-6902 Deltas",
      domain: DomainAdkFramework,
      fractal_layer: 4,
      description: "Session management with atomic state patches, snapshots, and time-travel rollback.",
      contract_ref: "SC-ADK-004",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/fpp-atlas",
    ),
    OntologyEntity(
      id: "adk-memory-store",
      name: "ADK Episodic & Semantic Memory Store",
      domain: DomainAdkFramework,
      fractal_layer: 4,
      description: "Working memory and long-term vector/key-value persistence across interaction cycles.",
      contract_ref: "SC-ADK-005",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/wiki",
    ),
    OntologyEntity(
      id: "adk-mcp-protocol",
      name: "ADK Model Context Protocol (MCP) Federation",
      domain: DomainAdkFramework,
      fractal_layer: 3,
      description: "Standardized vertical tool integration for database, SaaS, and system calls.",
      contract_ref: "SC-ADK-006",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/api/fpp/dictionary",
    ),
    OntologyEntity(
      id: "adk-a2a-protocol",
      name: "ADK Agent-to-Agent (A2A) Swarm Protocol",
      domain: DomainAdkFramework,
      fractal_layer: 6,
      description: "Horizontal inter-agent delegation and remote subagent orchestration.",
      contract_ref: "SC-ADK-007",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/mesh",
    ),
    OntologyEntity(
      id: "adk-eval-framework",
      name: "ADK Evaluation Benchmark Framework (adk eval)",
      domain: DomainAdkFramework,
      fractal_layer: 5,
      description: "Automated test trajectory scoring, criteria rubrics, and simulation environments.",
      contract_ref: "SC-ADK-008",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/checklist",
    ),
    OntologyEntity(
      id: "adk-plugins-guardrails",
      name: "ADK BasePlugin Security Guardrails",
      domain: DomainAdkFramework,
      fractal_layer: 0,
      description: "Security policy enforcers, input/output sanitizers, PII scrubbers, and token quotas.",
      contract_ref: "SC-ADK-010",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/api/verify/checks",
    ),

    // C3I Operational Triad Entities
    OntologyEntity(
      id: "c3i-sdlc-pillar",
      name: "C3I SDLC Operational System (32 Agents)",
      domain: DomainC3iEcology,
      fractal_layer: 9,
      description: "Synthesis, code generation, graph orchestration, and hot-reloading pipeline.",
      contract_ref: "SC-SDLC-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/planning",
    ),
    OntologyEntity(
      id: "c3i-sre-pillar",
      name: "C3I SRE Operational System (32 Agents)",
      domain: DomainC3iEcology,
      fractal_layer: 4,
      description: "Lyapunov stability, freshness monitors, Sa-plan durable leasing, and Rete gates.",
      contract_ref: "SC-SRE-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/",
    ),
    OntologyEntity(
      id: "c3i-verification-pillar",
      name: "C3I Verification Operational System (32 Agents)",
      domain: DomainC3iEcology,
      fractal_layer: 0,
      description: "Full 9-modality testing, Lean 4 proofs, OTP differential, and 18/18 checklist gates.",
      contract_ref: "SC-VERI-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/testing",
    ),

    // ZigVM Complete Lifecycle Stages
    OntologyEntity(
      id: "zigvm-stg1-ontology",
      name: "ZigVM Stage 1: Ontology & Semantics",
      domain: DomainZigvmLifecycle,
      fractal_layer: 8,
      description: "Infranodus semantic networks, Notion ontology, and Gospel/Ortac formal contracts.",
      contract_ref: "SC-ONTO-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/wiki",
    ),
    OntologyEntity(
      id: "zigvm-stg2-design",
      name: "ZigVM Stage 2: Mathematical Design & Atlas",
      domain: DomainZigvmLifecycle,
      fractal_layer: 7,
      description: "Denotational Intent Calculus, 12-layer Algebraic Atlas, and 13D TCM coordinates.",
      contract_ref: "SC-DMC-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/fpp-atlas",
    ),
    OntologyEntity(
      id: "zigvm-stg3-code",
      name: "ZigVM Stage 3: BEAM Code & FPP Transmutation",
      domain: DomainZigvmLifecycle,
      fractal_layer: 3,
      description: "BEAM bytecode synthesis, FPP aerospace component schemas, and zero foreign NIF purity.",
      contract_ref: "SC-FPP-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/fpp-topology",
    ),
    OntologyEntity(
      id: "zigvm-stg4-verification",
      name: "ZigVM Stage 4: Verification & Oracles",
      domain: DomainZigvmLifecycle,
      fractal_layer: 0,
      description: "Full 9-modality test protocol, Lean 4 coordinate proofs, and pinned OTP 30 differential.",
      contract_ref: "SC-VERI-002",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/testing",
    ),
    OntologyEntity(
      id: "zigvm-stg5-sre",
      name: "ZigVM Stage 5: SRE & Cybernetic Resilience",
      domain: DomainZigvmLifecycle,
      fractal_layer: 4,
      description: "Lyapunov stability, dead-man's-switch, Sa-plan durable leasing, and Rete rule gates.",
      contract_ref: "SC-SRE-002",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/",
    ),
    OntologyEntity(
      id: "zigvm-stg6-km",
      name: "ZigVM Stage 6: Knowledge Management & ZK-KM",
      domain: DomainZigvmLifecycle,
      fractal_layer: 8,
      description: "Permanent ZK ADRs (ADR-001..ADR-027), Master MOCs, Hermes wiki engine, and SQLite WAL.",
      contract_ref: "SC-KM-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/zk",
    ),

    // Formal Invariants
    OntologyEntity(
      id: "inv-hardware-storage-lock",
      name: "Hardware OS Storage Interlock",
      domain: DomainFormalInvariants,
      fractal_layer: 0,
      description: "Strict immutability lock on root NVMe HARD_DENIED_SYSTEM_OS_SERIAL = '25503L801736'.",
      contract_ref: "SC-STORAGE-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/api/fpp/intent",
    ),
    OntologyEntity(
      id: "inv-rocha-semiotic-cut",
      name: "Rocha Semiotic Cut Decoupling",
      domain: DomainFormalInvariants,
      fractal_layer: 0,
      description: "Biosemiotic principle enforcing strict separation of symbolic code from physical dynamics.",
      contract_ref: "SC-ROCHA-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/fpp-atlas",
    ),
    OntologyEntity(
      id: "inv-zero-muda-purity",
      name: "Zero-Muda Purity Standard",
      domain: DomainFormalInvariants,
      fractal_layer: 0,
      description: "Permanent exclusion of Bevy and Graphite; pure Erlang graphene_nif.erl.",
      contract_ref: "SC-MUDA-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/checklist",
    ),
    OntologyEntity(
      id: "inv-dmc-disjoint-windows",
      name: "DMC Base-ID Disjoint Memory Windows",
      domain: DomainFormalInvariants,
      fractal_layer: 0,
      description: "Pairwise disjoint memory base-ID intervals across [0x1000, 0x2800) for all 96 agents.",
      contract_ref: "SC-DMC-001",
      tailscale_route: "http://nas-1.tail55d152.ts.net:4100/api/fpp/agents",
    ),
  ]

  let edges = [
    // ADK to C3I Pillar relationships
    OntologyEdge("c3i-sdlc-pillar", RelImplements, "adk-workflow-graph", 1.0),
    OntologyEdge("c3i-sdlc-pillar", RelImplements, "adk-core-agent", 1.0),
    OntologyEdge("c3i-sdlc-pillar", RelOrchestrates, "adk-a2a-protocol", 1.0),
    OntologyEdge("c3i-sdlc-pillar", RelOrchestrates, "adk-mcp-protocol", 1.0),
    OntologyEdge("c3i-sre-pillar", RelGoverns, "adk-runner-hooks", 1.0),
    OntologyEdge("c3i-sre-pillar", RelGoverns, "adk-session-deltas", 1.0),
    OntologyEdge("c3i-sre-pillar", RelProtects, "adk-plugins-guardrails", 1.0),
    OntologyEdge(
      "c3i-verification-pillar",
      RelVerifies,
      "adk-eval-framework",
      1.0,
    ),
    OntologyEdge(
      "c3i-verification-pillar",
      RelVerifies,
      "inv-hardware-storage-lock",
      1.0,
    ),
    OntologyEdge(
      "c3i-verification-pillar",
      RelVerifies,
      "inv-rocha-semiotic-cut",
      1.0,
    ),
    OntologyEdge(
      "c3i-verification-pillar",
      RelVerifies,
      "inv-zero-muda-purity",
      1.0,
    ),
    OntologyEdge(
      "c3i-verification-pillar",
      RelVerifies,
      "inv-dmc-disjoint-windows",
      1.0,
    ),

    // ZigVM Lifecycle Stage Flow
    OntologyEdge("zigvm-stg1-ontology", RelTransmutes, "zigvm-stg2-design", 1.0),
    OntologyEdge("zigvm-stg2-design", RelTransmutes, "zigvm-stg3-code", 1.0),
    OntologyEdge("zigvm-stg3-code", RelVerifies, "zigvm-stg4-verification", 1.0),
    OntologyEdge("zigvm-stg4-verification", RelGoverns, "zigvm-stg5-sre", 1.0),
    OntologyEdge("zigvm-stg5-sre", RelSubsumes, "zigvm-stg6-km", 1.0),

    // Invariant Enforcement
    OntologyEdge(
      "inv-hardware-storage-lock",
      RelProtects,
      "c3i-sre-pillar",
      1.0,
    ),
    OntologyEdge(
      "inv-dmc-disjoint-windows",
      RelProtects,
      "c3i-sdlc-pillar",
      1.0,
    ),
    OntologyEdge("inv-rocha-semiotic-cut", RelGoverns, "zigvm-stg2-design", 1.0),
    OntologyEdge("inv-zero-muda-purity", RelGoverns, "zigvm-stg3-code", 1.0),
  ]

  MasterOntologyGraph(
    version: "2.0.0-UOS-ADK-C3I-CANONICAL",
    timestamp: "20260906-1230-",
    entities: entities,
    edges: edges,
  )
}

// ------------------------------------------------------------------------------
// Query & Validation API
// ------------------------------------------------------------------------------

pub fn total_entities_count(graph: MasterOntologyGraph) -> Int {
  list.length(graph.entities)
}

pub fn total_edges_count(graph: MasterOntologyGraph) -> Int {
  list.length(graph.edges)
}

pub fn find_entity_by_id(
  graph: MasterOntologyGraph,
  id: String,
) -> Result(OntologyEntity, Nil) {
  list.find(graph.entities, fn(e) { e.id == id })
}

pub fn filter_entities_by_domain(
  graph: MasterOntologyGraph,
  domain: OntologyDomain,
) -> List(OntologyEntity) {
  list.filter(graph.entities, fn(e) { e.domain == domain })
}

pub fn verify_master_ontology_integrity(graph: MasterOntologyGraph) -> Bool {
  let has_entities = graph.entities != []
  let has_edges = graph.edges != []
  let all_edges_valid =
    list.all(graph.edges, fn(edge) {
      let from_exists =
        list.any(graph.entities, fn(e) { e.id == edge.from_entity })
      let to_exists = list.any(graph.entities, fn(e) { e.id == edge.to_entity })
      from_exists && to_exists
    })
  has_entities && has_edges && all_edges_valid
}

// ------------------------------------------------------------------------------
// JSON & GraphML Serialization
// ------------------------------------------------------------------------------

pub fn encode_ontology_entity_json(e: OntologyEntity) -> json.Json {
  json.object([
    #("id", json.string(e.id)),
    #("name", json.string(e.name)),
    #("domain", json.string(domain_to_string(e.domain))),
    #("fractal_layer", json.int(e.fractal_layer)),
    #("description", json.string(e.description)),
    #("contract_ref", json.string(e.contract_ref)),
    #("tailscale_route", json.string(e.tailscale_route)),
  ])
}

pub fn encode_ontology_edge_json(edge: OntologyEdge) -> json.Json {
  json.object([
    #("from_entity", json.string(edge.from_entity)),
    #("relation", json.string(relation_type_to_string(edge.relation))),
    #("to_entity", json.string(edge.to_entity)),
    #("weight", json.float(edge.weight)),
  ])
}

pub fn encode_master_ontology_json(graph: MasterOntologyGraph) -> String {
  json.object([
    #("version", json.string(graph.version)),
    #("timestamp", json.string(graph.timestamp)),
    #("total_entities", json.int(total_entities_count(graph))),
    #("total_edges", json.int(total_edges_count(graph))),
    #("entities", json.array(graph.entities, encode_ontology_entity_json)),
    #("edges", json.array(graph.edges, encode_ontology_edge_json)),
  ])
  |> json.to_string
}

/// Serializes the Master Ontology Graph into standard GraphML format
pub fn export_ontology_graphml(graph: MasterOntologyGraph) -> String {
  let header =
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    <> "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\">\n"
    <> "  <graph id=\"UOS_Master_Ontology\" edgedefault=\"directed\">\n"

  let nodes_xml =
    list.map(graph.entities, fn(e) {
      "    <node id=\""
      <> e.id
      <> "\"><data key=\"name\">"
      <> e.name
      <> "</data><data key=\"domain\">"
      <> domain_to_string(e.domain)
      <> "</data></node>\n"
    })
    |> string.join("")

  let edges_xml =
    list.map(graph.edges, fn(edge) {
      "    <edge source=\""
      <> edge.from_entity
      <> "\" target=\""
      <> edge.to_entity
      <> "\"><data key=\"relation\">"
      <> relation_type_to_string(edge.relation)
      <> "</data></edge>\n"
    })
    |> string.join("")

  let footer = "  </graph>\n</graphml>\n"

  header <> nodes_xml <> edges_xml <> footer
}
