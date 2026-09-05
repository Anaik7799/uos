//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/lustre/homeostasis</module></identity>
////   <fractal-topology><layer>L2_COMPONENT</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-MATH-003</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre MVU component for the Homeostasis page.
//// Displays PID controller state: setpoint, actual, error, control output.

import gleam/option.{type Option, None, Some}

pub type PidState {
  PidState(
    setpoint: Float,
    actual: Float,
    error: Float,
    output: Float,
    kp: Float,
    ki: Float,
    kd: Float,
    integral: Float,
  )
}

pub type HomeostasisModel {
  HomeostasisModel(
    pid: PidState,
    stable: Bool,
    convergence_pct: Float,
    sample_count: Int,
    loading: Bool,
    error: Option(String),
  )
}

pub type HomeostasisMsg {
  PidLoaded(pid: PidState, stable: Bool, convergence: Float, samples: Int)
  PidUpdated(actual: Float, error: Float, output: Float)
  RefreshHomeostasis
  ErrorReceived(String)
}

pub fn init() -> HomeostasisModel {
  HomeostasisModel(
    pid: PidState(
      setpoint: 1.0,
      actual: 0.0,
      error: 1.0,
      output: 0.0,
      kp: 1.0,
      ki: 0.1,
      kd: 0.05,
      integral: 0.0,
    ),
    stable: False,
    convergence_pct: 0.0,
    sample_count: 0,
    loading: True,
    error: None,
  )
}

pub fn update(model: HomeostasisModel, msg: HomeostasisMsg) -> HomeostasisModel {
  case msg {
    PidLoaded(p, s, c, n) ->
      HomeostasisModel(
        pid: p,
        stable: s,
        convergence_pct: c,
        sample_count: n,
        loading: False,
        error: None,
      )
    PidUpdated(a, e, o) ->
      HomeostasisModel(
        ..model,
        pid: PidState(..model.pid, actual: a, error: e, output: o),
        sample_count: model.sample_count + 1,
      )
    RefreshHomeostasis -> HomeostasisModel(..model, loading: True)
    ErrorReceived(e) ->
      HomeostasisModel(..model, error: Some(e), loading: False)
  }
}
