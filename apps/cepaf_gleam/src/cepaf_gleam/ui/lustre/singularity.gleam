//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/lustre/singularity</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-SING-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre MVU component for the Singularity page.
//// Convergence estimator, capability timeline, safety boundary.

import gleam/option.{type Option, None, Some}

pub type CapabilityMetric {
  CapabilityMetric(name: String, score: Float, trend: String)
}

pub type SingularityModel {
  SingularityModel(
    convergence_pct: Float,
    safety_margin: Float,
    capability_score: Float,
    capabilities: List(CapabilityMetric),
    estimation_horizon: String,
    loading: Bool,
    error: Option(String),
  )
}

pub type SingularityMsg {
  EstimationLoaded(
    convergence: Float,
    safety: Float,
    capability: Float,
    caps: List(CapabilityMetric),
    horizon: String,
  )
  CapabilityUpdated(name: String, score: Float, trend: String)
  RefreshSingularity
  ErrorReceived(String)
}

pub fn init() -> SingularityModel {
  SingularityModel(
    convergence_pct: 0.0,
    safety_margin: 1.0,
    capability_score: 0.0,
    capabilities: [],
    estimation_horizon: "unknown",
    loading: True,
    error: None,
  )
}

pub fn update(model: SingularityModel, msg: SingularityMsg) -> SingularityModel {
  case msg {
    EstimationLoaded(c, s, cap, caps, h) ->
      SingularityModel(
        convergence_pct: c,
        safety_margin: s,
        capability_score: cap,
        capabilities: caps,
        estimation_horizon: h,
        loading: False,
        error: None,
      )
    CapabilityUpdated(name, score, trend) ->
      SingularityModel(
        ..model,
        capabilities: update_capability(model.capabilities, name, score, trend),
      )
    RefreshSingularity -> SingularityModel(..model, loading: True)
    ErrorReceived(e) ->
      SingularityModel(..model, error: Some(e), loading: False)
  }
}

fn update_capability(
  caps: List(CapabilityMetric),
  name: String,
  score: Float,
  trend: String,
) -> List(CapabilityMetric) {
  case caps {
    [] -> [CapabilityMetric(name: name, score: score, trend: trend)]
    [c, ..rest] ->
      case c.name == name {
        True -> [
          CapabilityMetric(name: name, score: score, trend: trend),
          ..rest
        ]
        False -> [c, ..update_capability(rest, name, score, trend)]
      }
  }
}

pub fn within_safety_boundary(model: SingularityModel) -> Bool {
  model.safety_margin >. 0.1
}
