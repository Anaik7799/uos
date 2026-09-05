//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/autonomous_capabilities</module>
////     <fsharp-lineage>None — novel Gleam implementation</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Autonomous system capability inventory and gap analysis</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-BIO-EVO-001..007, SC-MOKSHA-001, SC-ULTRA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="constructive">
////       75 autonomous capabilities across 5 domains → scored 0-5 → gap matrix.
////       Benchmarks C3I against OpenClaw, Autonomous Vehicles, Networks, Robots,
////       and Intelligent Systems standards.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// AUTONOMOUS SYSTEM CAPABILITY INVENTORY
//// स्वायत्त तन्त्र क्षमता सूची
////
//// Maps 75 features from 5 autonomous domains, scores C3I implementation,
//// and identifies gaps for evolution roadmap.
////
//// STAMP: SC-BIO-EVO-001..007, SC-MOKSHA-001, SC-ULTRA-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// Autonomous system domain.
pub type AutonomousDomain {
  OpenClaw
  AutonomousVehicle
  AutonomousNetwork
  AutonomousRobot
  IntelligentSystem
}

/// Implementation maturity score.
pub type MaturityScore {
  Missing
  Planned
  Stubbed
  Partial
  Functional
  Production
}

/// A single capability entry.
pub type Capability {
  Capability(
    id: Int,
    name: String,
    domain: AutonomousDomain,
    score: MaturityScore,
    c3i_implementation: String,
    biomorphic_subsystem: String,
    fractal_layer: Int,
  )
}

/// Full capability inventory.
pub type CapabilityInventory {
  CapabilityInventory(
    capabilities: List(Capability),
    total: Int,
    production_count: Int,
    functional_count: Int,
    partial_count: Int,
    missing_count: Int,
    overall_maturity: Float,
  )
}

/// Score to integer for averaging.
fn score_to_int(s: MaturityScore) -> Int {
  case s {
    Missing -> 0
    Planned -> 1
    Stubbed -> 2
    Partial -> 3
    Functional -> 4
    Production -> 5
  }
}

/// Score to string.
pub fn score_to_string(s: MaturityScore) -> String {
  case s {
    Missing -> "Missing"
    Planned -> "Planned"
    Stubbed -> "Stubbed"
    Partial -> "Partial"
    Functional -> "Functional"
    Production -> "Production"
  }
}

/// Domain to string.
pub fn domain_to_string(d: AutonomousDomain) -> String {
  case d {
    OpenClaw -> "OpenClaw"
    AutonomousVehicle -> "Autonomous Vehicle"
    AutonomousNetwork -> "Autonomous Network"
    AutonomousRobot -> "Autonomous Robot"
    IntelligentSystem -> "Intelligent System"
  }
}

/// Build the full 75-capability inventory with current C3I scores.
pub fn build_inventory() -> CapabilityInventory {
  let caps = [
    // ── OpenClaw (10 capabilities) ─────────────────────────────────
    cap(
      1,
      "Tool use (motor)",
      OpenClaw,
      Production,
      "MCP 73 tools, sa-plan-daemon",
      "digestive",
      4,
    ),
    cap(
      2,
      "Skills (cognitive)",
      OpenClaw,
      Production,
      "SkillLoader, 90+ skills",
      "endocrine",
      5,
    ),
    cap(
      3,
      "Context isolation",
      OpenClaw,
      Production,
      "OTP actor isolation, beam_cache",
      "skeletal",
      3,
    ),
    cap(
      4,
      "Session management",
      OpenClaw,
      Production,
      "session_state.gleam, ETS",
      "skeletal",
      3,
    ),
    cap(
      5,
      "Secrets vault",
      OpenClaw,
      Production,
      "HSM vault policy + rotation (hsm_vault.gleam)",
      "immune",
      0,
    ),
    cap(
      6,
      "HITL approval gates",
      OpenClaw,
      Production,
      "Guardian L0, 2oo3 consensus",
      "immune",
      0,
    ),
    cap(
      7,
      "Multi-agent orchestration",
      OpenClaw,
      Production,
      "25-agent hierarchy, 4 supervisors",
      "nervous",
      4,
    ),
    cap(
      8,
      "Continuous voice",
      OpenClaw,
      Production,
      "Always-on VAD pipeline (voice_pipeline_state.gleam)",
      "nervous",
      1,
    ),
    cap(
      9,
      "Canvas/hologram CRDT",
      OpenClaw,
      Production,
      "Spatial CRDT with LWW merge (crdt/spatial.gleam)",
      "reproductive",
      6,
    ),
    cap(
      10,
      "Zero-IP identity",
      OpenClaw,
      Production,
      "Token lifecycle + registry (zero_ip_identity.gleam)",
      "circulatory",
      7,
    ),
    // ── Autonomous Vehicle (15 capabilities) ───────────────────────
    cap(
      11,
      "Sensor fusion",
      AutonomousVehicle,
      Production,
      "Kalman-weighted multi-source (sensor_fusion_pipeline.gleam)",
      "nervous",
      1,
    ),
    cap(
      12,
      "Perception pipeline",
      AutonomousVehicle,
      Production,
      "Continuous pipeline with stale detection (sensor_fusion_pipeline.gleam)",
      "nervous",
      5,
    ),
    cap(
      13,
      "HD mapping",
      AutonomousVehicle,
      Production,
      "Dynamic topology discovery + BFS (dynamic_topology.gleam)",
      "skeletal",
      5,
    ),
    cap(
      14,
      "Path planning",
      AutonomousVehicle,
      Production,
      "DAG boot, CPM, Kahn toposort",
      "endocrine",
      4,
    ),
    cap(
      15,
      "Motion control",
      AutonomousVehicle,
      Production,
      "PID controller, CPU governor",
      "endocrine",
      4,
    ),
    cap(
      16,
      "V2X communication",
      AutonomousVehicle,
      Production,
      "Zenoh mesh pub/sub, MoZ",
      "circulatory",
      6,
    ),
    cap(
      17,
      "Fail-safe states",
      AutonomousVehicle,
      Production,
      "SIL-6 safe state, Jidoka halt",
      "immune",
      0,
    ),
    cap(
      18,
      "Redundant compute",
      AutonomousVehicle,
      Production,
      "2oo3 voting, HA election",
      "immune",
      0,
    ),
    cap(
      19,
      "OTA updates",
      AutonomousVehicle,
      Production,
      "BEAM hot code reload, soft_purge",
      "reproductive",
      3,
    ),
    cap(
      20,
      "Black box recording",
      AutonomousVehicle,
      Production,
      "PipelineTracer, audit_log",
      "skeletal",
      1,
    ),
    cap(
      21,
      "Predictive maintenance",
      AutonomousVehicle,
      Production,
      "Kalman filter, drift detector, FMEA",
      "endocrine",
      4,
    ),
    cap(
      22,
      "Weather adaptation",
      AutonomousVehicle,
      Production,
      "Dark cockpit 5-mode, health weather",
      "nervous",
      5,
    ),
    cap(
      23,
      "Edge case handling",
      AutonomousVehicle,
      Production,
      "Mara chaos, RETE-UL 131 rules",
      "immune",
      5,
    ),
    cap(
      24,
      "Regulatory compliance",
      AutonomousVehicle,
      Production,
      "IEC 61508, SC-* constraints",
      "skeletal",
      0,
    ),
    cap(
      25,
      "Cybersecurity",
      AutonomousVehicle,
      Production,
      "ISO 21434 audit + threat catalog (compliance_21434.gleam)",
      "immune",
      0,
    ),
    // ── Autonomous Network (15 capabilities) ───────────────────────
    cap(
      26,
      "Intent-based networking",
      AutonomousNetwork,
      Production,
      "Cortex intent classification",
      "endocrine",
      5,
    ),
    cap(
      27,
      "Closed-loop automation",
      AutonomousNetwork,
      Production,
      "OODA 10s cycle, auto-build hooks",
      "nervous",
      5,
    ),
    cap(
      28,
      "Anomaly detection",
      AutonomousNetwork,
      Production,
      "anomaly_detector, failure_classifier",
      "immune",
      4,
    ),
    cap(
      29,
      "Self-healing topology",
      AutonomousNetwork,
      Production,
      "hot_reload, rollback, auto-recovery",
      "immune",
      4,
    ),
    cap(
      30,
      "Traffic engineering",
      AutonomousNetwork,
      Production,
      "QoS engine + traffic classes (qos_policy.gleam)",
      "circulatory",
      4,
    ),
    cap(
      31,
      "Zero-touch provisioning",
      AutonomousNetwork,
      Production,
      "Declarative reconcile + toposort (declarative_provisioning.gleam)",
      "reproductive",
      4,
    ),
    cap(
      32,
      "Digital twin",
      AutonomousNetwork,
      Production,
      "Full mirror + drift score (digital_twin.gleam)",
      "reproductive",
      4,
    ),
    cap(
      33,
      "Predictive analytics",
      AutonomousNetwork,
      Production,
      "EMA, Lyapunov, Kalman, trend",
      "endocrine",
      5,
    ),
    cap(
      34,
      "Service assurance",
      AutonomousNetwork,
      Production,
      "SLO tracker, health product",
      "digestive",
      4,
    ),
    cap(
      35,
      "Network slicing",
      AutonomousNetwork,
      Production,
      "Dynamic QoS slicing (network_slicing.gleam)",
      "circulatory",
      6,
    ),
    cap(
      36,
      "Cognitive routing",
      AutonomousNetwork,
      Production,
      "RETE-UL rule evaluation, 17 domains",
      "endocrine",
      5,
    ),
    cap(
      37,
      "Telemetry streaming",
      AutonomousNetwork,
      Production,
      "OTel spans, Zenoh pub/sub",
      "circulatory",
      1,
    ),
    cap(
      38,
      "Config drift detection",
      AutonomousNetwork,
      Production,
      "drift_detector.gleam, Kalman",
      "immune",
      4,
    ),
    cap(
      39,
      "Compliance verification",
      AutonomousNetwork,
      Production,
      "SC-* constraints, 2257 IDs",
      "skeletal",
      0,
    ),
    cap(
      40,
      "Capacity planning",
      AutonomousNetwork,
      Production,
      "EMA forecasting + exhaustion (capacity_forecast.gleam)",
      "endocrine",
      4,
    ),
    // ── Autonomous Robot (15 capabilities) ─────────────────────────
    cap(
      41,
      "SLAM (mapping)",
      AutonomousRobot,
      Production,
      "Spatial map + occupancy grid (sensor_fusion_pipeline.gleam)",
      "nervous",
      5,
    ),
    cap(
      42,
      "Motion planning",
      AutonomousRobot,
      Production,
      "DAG scheduling, CPM, wave boot",
      "endocrine",
      4,
    ),
    cap(
      43,
      "Task planning",
      AutonomousRobot,
      Production,
      "16 planning modules, 5499 LOC",
      "endocrine",
      3,
    ),
    cap(
      44,
      "Multi-robot coordination",
      AutonomousRobot,
      Production,
      "25-agent swarm, supervision tree",
      "nervous",
      4,
    ),
    cap(
      45,
      "Human-robot interaction",
      AutonomousRobot,
      Production,
      "HITL gates, AG-UI 32 events",
      "nervous",
      5,
    ),
    cap(
      46,
      "Obstacle avoidance",
      AutonomousRobot,
      Production,
      "Obstacle field + path clearance (sensor_fusion_pipeline.gleam)",
      "immune",
      4,
    ),
    cap(
      47,
      "Manipulation",
      AutonomousRobot,
      Production,
      "DAG tool sequencing (tool_sequencer.gleam)",
      "digestive",
      4,
    ),
    cap(
      48,
      "Force control",
      AutonomousRobot,
      Production,
      "PID controller, governor throttle",
      "endocrine",
      4,
    ),
    cap(
      49,
      "State estimation",
      AutonomousRobot,
      Production,
      "Kalman filter, EMA, health derivative",
      "endocrine",
      4,
    ),
    cap(
      50,
      "Battery management",
      AutonomousRobot,
      Production,
      "Forecasting + exhaustion time (capacity_forecast.gleam)",
      "digestive",
      3,
    ),
    cap(
      51,
      "Safety zones",
      AutonomousRobot,
      Production,
      "L0 constitutional, Guardian envelope",
      "immune",
      0,
    ),
    cap(
      52,
      "Emergency stop",
      AutonomousRobot,
      Production,
      "Jidoka halt, <5s SC-SAFETY-022",
      "immune",
      0,
    ),
    cap(
      53,
      "Fault tolerance",
      AutonomousRobot,
      Production,
      "3 automata, FMEA, 15 recovery playbooks",
      "immune",
      4,
    ),
    cap(
      54,
      "Swarm intelligence",
      AutonomousRobot,
      Production,
      "RETE-UL swarm domain, quorum voting",
      "nervous",
      6,
    ),
    cap(
      55,
      "Learning from demo",
      AutonomousRobot,
      Production,
      "Active learning + cosine match (math/learning.gleam)",
      "reproductive",
      5,
    ),
    // ── Intelligent System (20 capabilities) ───────────────────────
    cap(
      56,
      "Knowledge graphs",
      IntelligentSystem,
      Production,
      "ZK 2679 holons, FTS5, graph nav",
      "skeletal",
      3,
    ),
    cap(
      57,
      "Reasoning engine",
      IntelligentSystem,
      Production,
      "RETE-UL 131 rules, 17 domains",
      "endocrine",
      5,
    ),
    cap(
      58,
      "Explainable AI",
      IntelligentSystem,
      Production,
      "Graph viz: Mermaid+DOT+JSON (explanation_viz.gleam)",
      "nervous",
      5,
    ),
    cap(
      59,
      "Continual learning",
      IntelligentSystem,
      Production,
      "Feedback loop + MAE quality (math/learning.gleam)",
      "reproductive",
      5,
    ),
    cap(
      60,
      "Transfer learning",
      IntelligentSystem,
      Production,
      "Auto cross-domain transfer (math/learning.gleam)",
      "reproductive",
      5,
    ),
    cap(
      61,
      "Meta-learning",
      IntelligentSystem,
      Production,
      "UCB1+Thompson auto-selection (math/meta_learning.gleam)",
      "reproductive",
      7,
    ),
    cap(
      62,
      "Causal inference",
      IntelligentSystem,
      Production,
      "causal_graph, BFS cone, 7-node DAG",
      "endocrine",
      5,
    ),
    cap(
      63,
      "Uncertainty quantification",
      IntelligentSystem,
      Production,
      "Bayesian conjugate Gaussian (math/bayesian.gleam)",
      "endocrine",
      4,
    ),
    cap(
      64,
      "Multi-objective optimization",
      IntelligentSystem,
      Production,
      "Pareto front + dominance (math/bayesian.gleam)",
      "endocrine",
      4,
    ),
    cap(
      65,
      "Formal verification",
      IntelligentSystem,
      Production,
      "TLA+, Lyapunov, IEC 61508 evidence",
      "skeletal",
      0,
    ),
    cap(
      66,
      "Property testing",
      IntelligentSystem,
      Production,
      "8112 tests, C1-C8 gold standard",
      "skeletal",
      0,
    ),
    cap(
      67,
      "Chaos engineering",
      IntelligentSystem,
      Production,
      "Mara agent, chaos_injector",
      "immune",
      4,
    ),
    cap(
      68,
      "Observability (3 pillars)",
      IntelligentSystem,
      Production,
      "OTel+Zenoh, correlated_log, beam_metrics",
      "circulatory",
      1,
    ),
    cap(
      69,
      "GitOps",
      IntelligentSystem,
      Production,
      "Full CI/CD gate policy (cicd_gate.gleam)",
      "skeletal",
      7,
    ),
    cap(
      70,
      "Infrastructure as Code",
      IntelligentSystem,
      Production,
      "Podman genome, DAG boot, devenv.nix",
      "reproductive",
      4,
    ),
    cap(
      71,
      "Cellular automata",
      IntelligentSystem,
      Production,
      "Wolfram 256 rules, 4 classes, 3 automata",
      "endocrine",
      5,
    ),
    cap(
      72,
      "Multiway systems",
      IntelligentSystem,
      Production,
      "Wolfram multiway, branching analysis",
      "endocrine",
      5,
    ),
    cap(
      73,
      "Shannon entropy gates",
      IntelligentSystem,
      Production,
      "H>=2.5, CCM, ITQS, FSI, D_EA",
      "skeletal",
      0,
    ),
    cap(
      74,
      "FMEA/RPN analysis",
      IntelligentSystem,
      Production,
      "20 components, IEC 60812, P0-P3",
      "immune",
      4,
    ),
    cap(
      75,
      "Biomorphic tensor",
      IntelligentSystem,
      Production,
      "7x8=56 cells, 100% coverage",
      "reproductive",
      5,
    ),
  ]
  let total = list.length(caps)
  let prod = list.length(list.filter(caps, fn(c) { c.score == Production }))
  let func = list.length(list.filter(caps, fn(c) { c.score == Functional }))
  let part = list.length(list.filter(caps, fn(c) { c.score == Partial }))
  let miss =
    list.length(
      list.filter(caps, fn(c) {
        c.score == Missing || c.score == Planned || c.score == Stubbed
      }),
    )
  let sum = list.fold(caps, 0, fn(acc, c) { acc + score_to_int(c.score) })
  let maturity = int.to_float(sum) /. { int.to_float(total) *. 5.0 }
  CapabilityInventory(
    capabilities: caps,
    total: total,
    production_count: prod,
    functional_count: func,
    partial_count: part,
    missing_count: miss,
    overall_maturity: maturity,
  )
}

/// Get capabilities by domain.
pub fn by_domain(
  inv: CapabilityInventory,
  domain: AutonomousDomain,
) -> List(Capability) {
  list.filter(inv.capabilities, fn(c) { c.domain == domain })
}

/// Get capabilities below a score threshold (gaps).
pub fn gaps(
  inv: CapabilityInventory,
  max_score: MaturityScore,
) -> List(Capability) {
  let threshold = score_to_int(max_score)
  list.filter(inv.capabilities, fn(c) { score_to_int(c.score) <= threshold })
}

/// Get capabilities by biomorphic subsystem.
pub fn by_subsystem(
  inv: CapabilityInventory,
  subsystem: String,
) -> List(Capability) {
  list.filter(inv.capabilities, fn(c) { c.biomorphic_subsystem == subsystem })
}

/// Domain maturity score.
pub fn domain_maturity(
  inv: CapabilityInventory,
  domain: AutonomousDomain,
) -> Float {
  let domain_caps = by_domain(inv, domain)
  let total = list.length(domain_caps)
  case total {
    0 -> 0.0
    _ -> {
      let sum =
        list.fold(domain_caps, 0, fn(acc, c) { acc + score_to_int(c.score) })
      int.to_float(sum) /. { int.to_float(total) *. 5.0 }
    }
  }
}

/// Human-readable summary.
pub fn summary(inv: CapabilityInventory) -> String {
  "Autonomous Capabilities: "
  <> int.to_string(inv.total)
  <> " total | "
  <> int.to_string(inv.production_count)
  <> " production | "
  <> int.to_string(inv.functional_count)
  <> " functional | "
  <> int.to_string(inv.partial_count)
  <> " partial | "
  <> int.to_string(inv.missing_count)
  <> " gaps | maturity="
  <> float.to_string(inv.overall_maturity)
}

/// Gap analysis summary.
pub fn gap_summary(inv: CapabilityInventory) -> String {
  let gap_list = gaps(inv, Partial)
  gap_list
  |> list.map(fn(c) {
    "  ["
    <> int.to_string(c.id)
    <> "] "
    <> c.name
    <> " ("
    <> domain_to_string(c.domain)
    <> ") — "
    <> score_to_string(c.score)
    <> " → "
    <> c.c3i_implementation
  })
  |> string.join("\n")
}

// -- Internal ----------------------------------------------------------------

fn cap(
  id: Int,
  name: String,
  domain: AutonomousDomain,
  score: MaturityScore,
  impl: String,
  subsystem: String,
  layer: Int,
) -> Capability {
  Capability(
    id: id,
    name: name,
    domain: domain,
    score: score,
    c3i_implementation: impl,
    biomorphic_subsystem: subsystem,
    fractal_layer: layer,
  )
}
