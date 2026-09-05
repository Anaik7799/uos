import cepaf_gleam/ui/domain.{
  type BicameralSignOff, type BiomorphicMatrix, type EvolutionVectors,
  type HomeostasisControls, type MathematicalIntegrity,
  type SingularityEstimation, BicameralSignOff, BiomorphicMatrix,
  EvolutionVectors, HomeostasisControls, MathematicalIntegrity,
  SingularityEstimation,
}
import gleam/option.{None}

/// Lustre component for Prajna Operator plane (SC-GLM-UI-001).
/// Manages holon count, threat level, cockpit mode, and circuit state.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
pub type PrajnaModel {
  PrajnaModel(
    holon_count: Int,
    threat_level: String,
    cockpit_mode: String,
    circuit_state: String,
    messages_routed: Int,
    integrity: MathematicalIntegrity,
    vectors: EvolutionVectors,
    matrix: BiomorphicMatrix,
    homeostasis: HomeostasisControls,
    release: BicameralSignOff,
    singularity: SingularityEstimation,
  )
}

pub type PrajnaMsg {
  HolonCreated
  ThreatChanged(String)
  ModeChanged(String)
  CircuitChanged(String)
  IntegrityUpdated(MathematicalIntegrity)
  VectorsUpdated(EvolutionVectors)
  MatrixUpdated(BiomorphicMatrix)
  HomeostasisUpdated(HomeostasisControls)
  ReleaseUpdated(BicameralSignOff)
  SingularityUpdated(SingularityEstimation)
  RefreshPrajna
}

pub fn init() -> PrajnaModel {
  PrajnaModel(
    holon_count: 0,
    threat_level: "nominal",
    cockpit_mode: "dark",
    circuit_state: "closed",
    messages_routed: 0,
    integrity: MathematicalIntegrity(hs: 0.0, epsilon: 0.0, ds: 0.0),
    vectors: EvolutionVectors(v1: 0.0, v2: 0.0, v3: 0.0, v4: 0.0),
    matrix: BiomorphicMatrix(levels: []),
    homeostasis: HomeostasisControls(
      kp: 0.0,
      ki: 0.0,
      kd: 0.0,
      set_point: 0.0,
      current_value: 0.0,
      error: 0.0,
    ),
    release: BicameralSignOff(
      key1_signed: False,
      key2_signed: False,
      authorized_by: None,
    ),
    singularity: SingularityEstimation(
      time_to_singularity_ms: 0,
      confidence_interval: 0.0,
      critical_threshold_reached: False,
    ),
  )
}

pub fn update(model: PrajnaModel, msg: PrajnaMsg) -> PrajnaModel {
  case msg {
    HolonCreated -> PrajnaModel(..model, holon_count: model.holon_count + 1)
    ThreatChanged(level) -> PrajnaModel(..model, threat_level: level)
    ModeChanged(mode) -> PrajnaModel(..model, cockpit_mode: mode)
    CircuitChanged(state) -> PrajnaModel(..model, circuit_state: state)
    IntegrityUpdated(integrity) -> PrajnaModel(..model, integrity: integrity)
    VectorsUpdated(vectors) -> PrajnaModel(..model, vectors: vectors)
    MatrixUpdated(matrix) -> PrajnaModel(..model, matrix: matrix)
    HomeostasisUpdated(homeostasis) ->
      PrajnaModel(..model, homeostasis: homeostasis)
    ReleaseUpdated(release) -> PrajnaModel(..model, release: release)
    SingularityUpdated(singularity) ->
      PrajnaModel(..model, singularity: singularity)
    RefreshPrajna -> model
  }
}

pub fn is_emergency(model: PrajnaModel) -> Bool {
  model.threat_level == "critical" || model.circuit_state == "open"
}

pub fn active_holons(model: PrajnaModel) -> Int {
  model.holon_count
}
