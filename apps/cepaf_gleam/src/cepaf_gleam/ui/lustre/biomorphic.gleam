//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/lustre/biomorphic</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-BIO-EVO-001..007</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre MVU component for the Biomorphic page.
//// Displays bio/neuro/immune subsystem health, symbiosis index, and
//// the 7×8 biomorphic tensor (7 properties × 8 fractal layers).

import cepaf_gleam/symbiosis/tensor
import cepaf_gleam/symbiosis/types as symbiosis
import gleam/option.{type Option, None, Some}

pub type SubsystemHealth {
  SubsystemHealth(name: String, status: String, score: Float, detail: String)
}

pub type BiomorphicModel {
  BiomorphicModel(
    bio: SubsystemHealth,
    neuro: SubsystemHealth,
    immune: SubsystemHealth,
    overall_score: Float,
    mode: String,
    loading: Bool,
    error: Option(String),
    symbiosis: symbiosis.SymbiosisIndex,
    tensor: tensor.BiomorphicTensor,
  )
}

pub type BiomorphicMsg {
  HealthLoaded(
    bio: SubsystemHealth,
    neuro: SubsystemHealth,
    immune: SubsystemHealth,
    overall: Float,
    mode: String,
  )
  SubsystemUpdated(name: String, status: String, score: Float)
  SymbiosisRecorded(holon_a: String, holon_b: String, a: Float, b: Float)
  RefreshBiomorphic
  ErrorReceived(String)
}

pub fn init() -> BiomorphicModel {
  let sym = symbiosis.new()
    // Core subsystem relationships
    |> symbiosis.record("cortex", "rule_engine", 0.8, 0.7)
    |> symbiosis.record("zenoh", "otel", 0.9, 0.6)
    |> symbiosis.record("gleam_ui", "nif_bridge", 0.7, 0.5)
    |> symbiosis.record("sa_plan", "smriti_db", 0.9, 0.3)
    |> symbiosis.record("immune", "sentinel", 0.6, 0.8)
    |> symbiosis.record("dashboard", "websocket", 0.8, 0.4)
    |> symbiosis.record("guardian", "2oo3_voting", 0.5, 0.9)
    // Autonomous capability relationships
    |> symbiosis.record("heartbeat", "freshness", 0.9, 0.8)
    |> symbiosis.record("health_product", "tensor", 0.8, 0.7)
    |> symbiosis.record("rete_ul", "ooda", 0.9, 0.9)
    |> symbiosis.record("kalman", "drift_detector", 0.7, 0.8)
    |> symbiosis.record("fmea", "safety_kernel", 0.8, 0.9)
    |> symbiosis.record("zettelkasten", "cortex", 0.9, 0.7)
  BiomorphicModel(
    bio: SubsystemHealth(
      name: "Bio",
      status: "healthy",
      score: 1.0,
      detail: "Metabolic homeostasis nominal",
    ),
    neuro: SubsystemHealth(
      name: "Neuro",
      status: "healthy",
      score: 1.0,
      detail: "Cortex OODA cycle <30ms",
    ),
    immune: SubsystemHealth(
      name: "Immune",
      status: "healthy",
      score: 1.0,
      detail: "Sentinel active, 0 threats",
    ),
    overall_score: 1.0,
    mode: "normal",
    loading: True,
    error: None,
    symbiosis: sym,
    tensor: tensor.build(),
  )
}

pub fn update(model: BiomorphicModel, msg: BiomorphicMsg) -> BiomorphicModel {
  case msg {
    HealthLoaded(b, n, i, o, m) ->
      BiomorphicModel(
        ..model,
        bio: b,
        neuro: n,
        immune: i,
        overall_score: o,
        mode: m,
        loading: False,
        error: None,
      )
    SubsystemUpdated(name, status, score) ->
      case name {
        "bio" ->
          BiomorphicModel(
            ..model,
            bio: SubsystemHealth(..model.bio, status: status, score: score),
          )
        "neuro" ->
          BiomorphicModel(
            ..model,
            neuro: SubsystemHealth(..model.neuro, status: status, score: score),
          )
        "immune" ->
          BiomorphicModel(
            ..model,
            immune: SubsystemHealth(
              ..model.immune,
              status: status,
              score: score,
            ),
          )
        _ -> model
      }
    SymbiosisRecorded(holon_a, holon_b, a, b) ->
      BiomorphicModel(
        ..model,
        symbiosis: symbiosis.record(model.symbiosis, holon_a, holon_b, a, b),
      )
    RefreshBiomorphic ->
      BiomorphicModel(..model, loading: True, tensor: tensor.build())
    ErrorReceived(e) -> BiomorphicModel(..model, error: Some(e), loading: False)
  }
}

pub fn all_healthy(model: BiomorphicModel) -> Bool {
  model.bio.status == "healthy"
  && model.neuro.status == "healthy"
  && model.immune.status == "healthy"
}

pub fn tensor_coverage(model: BiomorphicModel) -> Float {
  model.tensor.coverage
}

pub fn symbiosis_healthy(model: BiomorphicModel) -> Bool {
  symbiosis.is_healthy(model.symbiosis)
}
