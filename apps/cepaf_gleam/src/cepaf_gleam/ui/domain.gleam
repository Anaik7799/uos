import gleam/list
import gleam/option.{type Option, None, Some}

/// Shared UI domain types for the triple-interface mandate (SC-GLM-UI-001).
/// ALL Lustre components, Wisp endpoints, and TUI views MUST import from this module.
/// No per-interface type duplication permitted (SC-GLM-UI-009).
///
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-009
/// Represents a c3i page/view that must be rendered across all 3 interfaces.
pub type Page {
  Dashboard
  Planning
  Immune
  Knowledge
  Zenoh
  Cockpit
  Verification
  Substrate
  Metabolic
  Podman
  Mcp
  Kms
  Telemetry
  Federation
  HealthGrid
  Prajna
  Agents
  Holon
  Config
  Git
  Database
  Bridge
  Smriti
  PlanningDashboard
  Integrity
  Evolution
  Biomorphic
  HomeostasisPage
  Bicameral
  Singularity
  ComponentDemo
  Auth
}

/// Canonical browser/API route inventory. This is the shared source for
/// navigation, API discovery, page evidence strips, and documentation.
pub fn all_pages() -> List(Page) {
  [
    Dashboard, Planning, Immune, Knowledge, Zenoh, Cockpit, Verification,
    Substrate, Metabolic, Podman, Mcp, Kms, Telemetry, Federation, HealthGrid,
    Prajna, Agents, Holon, Config, Git, Database, Bridge, Smriti,
    PlanningDashboard, Integrity, Evolution, Biomorphic, HomeostasisPage,
    Bicameral, Singularity, ComponentDemo, Auth,
  ]
}

/// Resolve a canonical URL path back to a page variant.
pub fn path_to_page(path: String) -> Option(Page) {
  case list.find(all_pages(), fn(page) { page_to_path(page) == path }) {
    Ok(page) -> Some(page)
    Error(_) -> None
  }
}

/// Health status shared across all interfaces.
pub type HealthStatus {
  Healthy
  Degraded(reason: String)
  Critical(reason: String)
  Unknown
}

/// Device status for the health grid.
pub type DeviceStatus {
  Online
  Offline
  Maintenance
}

/// Device health record for the grid.
pub type DeviceHealth {
  DeviceHealth(
    id: String,
    health_score: Float,
    device_type: String,
    status: DeviceStatus,
    last_seen: Int,
  )
}

/// Telemetry data point — sourced from Zenoh, rendered by all 3 interfaces.
pub type TelemetryPoint {
  TelemetryPoint(key: String, value: Float, timestamp: Int, unit: String)
}

/// Biometric voice status for real-time feedback.
pub type VoiceStatus {
  VoiceIdle
  VoiceListening
  VoiceProcessing
  VoiceAuthenticating
  VoiceAuthenticated(user: String)
  VoiceRejected(reason: String)
}

/// Navigation action — same semantics in Web, API, and TUI.
pub type Action {
  Navigate(page: Page)
  Refresh
  Execute(command: String)
  Subscribe(topic: String)
  Unsubscribe(topic: String)
  RequestApproval(id: String, description: String, level: Int)
  BiometricVerify(embedding_b64: String)
}

/// Rendering context — carries session state for all 3 interfaces.
pub type RenderContext {
  RenderContext(
    page: Page,
    health: HealthStatus,
    telemetry: List(TelemetryPoint),
    zenoh_connected: Bool,
  )
}

/// Convert page to URL path (Wisp routing) and TUI tab name.
pub fn page_to_path(page: Page) -> String {
  case page {
    Dashboard -> "/dashboard"
    Planning -> "/planning"
    Immune -> "/immune"
    Knowledge -> "/knowledge"
    Zenoh -> "/zenoh"
    Cockpit -> "/cockpit"
    Verification -> "/verification"
    Substrate -> "/substrate"
    Metabolic -> "/metabolic"
    Podman -> "/podman"
    Mcp -> "/mcp"
    Kms -> "/kms"
    Telemetry -> "/telemetry"
    Federation -> "/federation"
    HealthGrid -> "/health-grid"
    Prajna -> "/prajna"
    Agents -> "/agents"
    Holon -> "/holon"
    Config -> "/config"
    Git -> "/git"
    Database -> "/database"
    Bridge -> "/bridge"
    Smriti -> "/smriti"
    PlanningDashboard -> "/planning-dashboard"
    Integrity -> "/integrity"
    Evolution -> "/evolution"
    Biomorphic -> "/biomorphic"
    HomeostasisPage -> "/homeostasis"
    Bicameral -> "/bicameral"
    Singularity -> "/singularity"
    ComponentDemo -> "/components"
    Auth -> "/auth"
  }
}

/// Convert page to human-readable label.
pub fn page_to_label(page: Page) -> String {
  case page {
    Dashboard -> "Dashboard"
    Planning -> "Planning"
    Immune -> "Immune System"
    Knowledge -> "Knowledge (Smriti)"
    Zenoh -> "Zenoh Mesh"
    Cockpit -> "Cockpit"
    Verification -> "Verification"
    Substrate -> "Substrate"
    Metabolic -> "Metabolic"
    Podman -> "Podman"
    Mcp -> "MCP Server"
    Kms -> "KMS Catalog"
    Telemetry -> "Telemetry"
    Federation -> "Federation (L7)"
    HealthGrid -> "Device Health Grid"
    Prajna -> "Prajna Biomorphic"
    Agents -> "Cybernetic Agents"
    Holon -> "Holon Identity"
    Config -> "Mesh Configuration"
    Git -> "Git Intelligence"
    Database -> "Database"
    Bridge -> "Bridge"
    Smriti -> "Smriti Knowledge"
    PlanningDashboard -> "Planning Dashboard"
    Integrity -> "Mathematical Integrity"
    Evolution -> "Evolution Vectors"
    Biomorphic -> "Biomorphic Matrix"
    HomeostasisPage -> "Homeostasis Controls"
    Bicameral -> "Bicameral Sign-Off"
    Singularity -> "Singularity Estimation"
    ComponentDemo -> "Component Demo"
    Auth -> "Authentication"
  }
}

/// Map a page to its primary fractal layer.
pub fn page_fractal_layer(page: Page) -> FractalLayer {
  case page {
    Dashboard -> L5Cognitive
    Planning -> L3Transaction
    Immune -> L0Constitutional
    Knowledge -> L5Cognitive
    Zenoh -> L6Ecosystem
    Cockpit -> L5Cognitive
    Verification -> L0Constitutional
    Substrate -> L3Transaction
    Metabolic -> L1AtomicDebug
    Podman -> L4System
    Mcp -> L6Ecosystem
    Kms -> L0Constitutional
    Telemetry -> L1AtomicDebug
    Federation -> L7Federation
    HealthGrid -> L4System
    Prajna -> L5Cognitive
    Agents -> L5Cognitive
    Holon -> L3Transaction
    Config -> L4System
    Git -> L1AtomicDebug
    Database -> L3Transaction
    Bridge -> L6Ecosystem
    Smriti -> L5Cognitive
    PlanningDashboard -> L3Transaction
    Integrity -> L0Constitutional
    Evolution -> L5Cognitive
    Biomorphic -> L5Cognitive
    HomeostasisPage -> L2Component
    Bicameral -> L0Constitutional
    Singularity -> L7Federation
    ComponentDemo -> L2Component
    Auth -> L0Constitutional
  }
}

/// Human-readable data-plane source for the current implementation.
pub fn page_data_plane(page: Page) -> String {
  case page {
    Dashboard -> "NIF-backed dashboard, plan status, WebSocket snapshot"
    Planning -> "Smriti planning database through c3i_nif.plan_*"
    Immune -> "System immune and health NIFs"
    Knowledge -> "Smriti/Zettelkasten FTS and semantic indexes"
    Zenoh -> "Zenoh mesh health and publish/subscribe state"
    Cockpit -> "Shared mesh state, health cascade, cockpit mode"
    Verification -> "Verification, guard grid, page-spec and proof endpoints"
    Substrate -> "Boot/substrate state and system topology"
    Metabolic -> "Runtime load, resource, and metabolic health models"
    Podman -> "Podman/container inventory and control endpoints"
    Mcp -> "MCP server/tool/session registry"
    Kms -> "KMS checkpoint catalog and vault policy evidence"
    Telemetry -> "OTel, Zenoh, BEAM and SLO telemetry"
    Federation -> "L7 federation state; live peer source currently fails closed"
    HealthGrid -> "System health; live device inventory currently fails closed"
    Prajna -> "Biomorphic cockpit and holon/circuit state"
    Agents -> "Agent hierarchy, OODA, AG-UI events and state"
    Holon -> "Holon identity and relationship metadata"
    Config -> "Mesh configuration and runtime environment evidence"
    Git -> "Repository, branch and source-control health"
    Database -> "Smriti/sqlite status; catalog source is explicitly wired"
    Bridge -> "Pi/Matrix/agent bridge state"
    Smriti -> "Knowledge catalog and ZK metrics"
    PlanningDashboard -> "Planning task status, OODA and safety panels"
    Integrity -> "Mathematical integrity metrics and proof state"
    Evolution -> "Evolution vectors and fitness evidence"
    Biomorphic -> "Biomorphic matrix and symbiosis tensor"
    HomeostasisPage -> "PID/homeostasis model and health cascade"
    Bicameral -> "Two-key sign-off and Guardian approval state"
    Singularity -> "Singularity estimation and federation risk model"
    ComponentDemo -> "A2UI component catalog and renderer evidence"
    Auth -> "Authentication, OIDC/RBAC and L0 access-control surfaces"
  }
}

/// Human-readable control-plane entry points for a page.
pub fn page_control_plane(page: Page) -> String {
  case page {
    Dashboard -> "GET /dashboard, GET /api/v1/dashboard, WS /ws/dashboard"
    Planning -> "GET /planning, /api/v1/plan/*, authenticated planning POSTs"
    Immune -> "GET /immune, GET /api/v1/immune"
    Knowledge -> "GET /knowledge, GET /api/v1/knowledge/search"
    Zenoh -> "GET /zenoh, GET /api/v1/zenoh, POST /api/v1/zenoh/publish"
    Cockpit -> "GET /cockpit, GET /api/v1/cockpit/mode"
    Verification -> "GET /verification, GET /api/v1/page-spec/*"
    Substrate -> "GET /substrate, GET /api/v1/substrate"
    Metabolic -> "GET /metabolic, GET /api/v1/metabolic"
    Podman -> "GET /podman, GET /api/v1/podman, authenticated Podman POSTs"
    Mcp -> "GET /mcp, GET /api/v1/mcp"
    Kms -> "GET /kms, GET /api/v1/kms"
    Telemetry -> "GET /telemetry, GET /api/v1/telemetry"
    Federation -> "GET /federation, GET /api/v1/federation"
    HealthGrid -> "GET /health-grid, GET /api/v1/health_grid"
    Prajna -> "GET /prajna, GET /api/v1/prajna"
    Agents -> "GET /agents, GET /api/v1/agents, /ag-ui/*"
    Holon -> "GET /holon, GET /api/v1/holon"
    Config -> "GET /config, GET /api/v1/config"
    Git -> "GET /git, GET /api/v1/git"
    Database -> "GET /database, GET /api/v1/db"
    Bridge -> "GET /bridge, GET /api/v1/bridge"
    Smriti -> "GET /smriti, GET /api/v1/smriti"
    PlanningDashboard ->
      "GET /planning-dashboard, GET /api/v1/planning_dashboard"
    Integrity -> "GET /integrity, GET /api/v1/integrity"
    Evolution -> "GET /evolution, GET /api/v1/evolution"
    Biomorphic -> "GET /biomorphic, GET /api/v1/biomorphic"
    HomeostasisPage -> "GET /homeostasis, GET /api/v1/homeostasis"
    Bicameral -> "GET /bicameral, GET /api/v1/bicameral"
    Singularity -> "GET /singularity, GET /api/v1/singularity"
    ComponentDemo -> "GET /components, GET /api/v1/components"
    Auth -> "GET /auth, GET /api/v1/iam/*"
  }
}

/// Primary clients that should be able to consume this page's capability.
pub fn page_primary_clients(page: Page) -> List(String) {
  let base = ["Browser SSR", "REST JSON", "TUI ANSI"]
  case page {
    Dashboard | Agents | PlanningDashboard -> list.append(base, ["AG-UI"])
    ComponentDemo -> list.append(base, ["A2UI"])
    _ -> base
  }
}

/// Fractal layer assignment for UI elements.
pub type FractalLayer {
  L0Constitutional
  L1AtomicDebug
  L2Component
  L3Transaction
  L4System
  L5Cognitive
  L6Ecosystem
  L7Federation
}

/// Capabilities a fractal element can have.
pub type Capability {
  EmitEvents
  ReceiveEvents
  ProposeUI
  AcceptHITL
  DelegateToSubAgent
  PersistState
  StreamContent
}

/// Agent binding — connects a UI element to a backend agent.
pub type AgentBinding {
  AgentBinding(
    agent_id: String,
    run_id: Option(String),
    subscribed_topics: List(String),
  )
}

/// Fractal Agentic Element — the atomic unit of the Agentic UI.
/// Every UI element is a holon at a specific fractal layer.
pub type FractalElement {
  FractalElement(
    id: String,
    layer: FractalLayer,
    element_type: String,
    agent_binding: Option(AgentBinding),
    capabilities: List(Capability),
    stamp_controls: List(String),
  )
}

/// Boot phase for the 7-tier ignition sequence.
pub type BootPhase {
  Preflight
  Foundation
  Mesh
  Cognitive
  Application
  Homeostasis
  Swarm
}

/// Mesh operating mode.
pub type MeshMode {
  Standalone
  Clustered
  Federated
}

/// Boot configuration parameters.
pub type BootConfig {
  BootConfig(
    mode: MeshMode,
    timeout_ms: Int,
    max_retries: Int,
    patient_mode: Bool,
  )
}

/// Convert boot phase to string.
pub fn boot_phase_to_string(phase: BootPhase) -> String {
  case phase {
    Preflight -> "preflight"
    Foundation -> "foundation"
    Mesh -> "mesh"
    Cognitive -> "cognitive"
    Application -> "application"
    Homeostasis -> "homeostasis"
    Swarm -> "swarm"
  }
}

/// Convert mesh mode to string.
pub fn mesh_mode_to_string(mode: MeshMode) -> String {
  case mode {
    Standalone -> "standalone"
    Clustered -> "clustered"
    Federated -> "federated"
  }
}

/// Convert fractal layer to string.
pub fn layer_to_string(layer: FractalLayer) -> String {
  case layer {
    L0Constitutional -> "L0_CONSTITUTIONAL"
    L1AtomicDebug -> "L1_ATOMIC_DEBUG"
    L2Component -> "L2_COMPONENT"
    L3Transaction -> "L3_TRANSACTION"
    L4System -> "L4_SYSTEM"
    L5Cognitive -> "L5_COGNITIVE"
    L6Ecosystem -> "L6_ECOSYSTEM"
    L7Federation -> "L7_FEDERATION"
  }
}

/// Convert fractal layer to numeric level.
pub fn layer_level(layer: FractalLayer) -> Int {
  case layer {
    L0Constitutional -> 0
    L1AtomicDebug -> 1
    L2Component -> 2
    L3Transaction -> 3
    L4System -> 4
    L5Cognitive -> 5
    L6Ecosystem -> 6
    L7Federation -> 7
  }
}

/// Mathematical Integrity metrics (SC-GLM-UI-001).
/// Hs: Shannon Entropy, epsilon: Stability, Ds: Structural Divergence.
pub type MathematicalIntegrity {
  MathematicalIntegrity(hs: Float, epsilon: Float, ds: Float)
}

/// Evolution Vectors (V1-V4) for tracking code evolution.
pub type EvolutionVectors {
  EvolutionVectors(v1: Float, v2: Float, v3: Float, v4: Float)
}

/// NASA-STD-3000 Biomorphic Matrix state.
pub type BiomorphicMatrix {
  BiomorphicMatrix(levels: List(#(FractalLayer, HealthStatus)))
}

/// Homeostasis PID controls and thresholds.
pub type HomeostasisControls {
  HomeostasisControls(
    kp: Float,
    ki: Float,
    kd: Float,
    set_point: Float,
    current_value: Float,
    error: Float,
  )
}

/// Bicameral Two-Key Release Protocol sign-off state.
pub type BicameralSignOff {
  BicameralSignOff(
    key1_signed: Bool,
    key2_signed: Bool,
    authorized_by: Option(String),
  )
}

/// Time-to-Singularity estimation and confidence.
pub type SingularityEstimation {
  SingularityEstimation(
    time_to_singularity_ms: Int,
    confidence_interval: Float,
    critical_threshold_reached: Bool,
  )
}
