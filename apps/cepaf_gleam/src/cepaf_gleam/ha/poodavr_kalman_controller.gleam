// =============================================================================
// poodavr_kalman_controller.gleam — 7-Stage POODAVR Cybernetic Closed-Loop Controller
// STAMP: SC-POODAVR-002, SC-MATH-001, SC-SIL6-001, SC-JIDOKA-001
// Codex Astra Sovereign Cybernetic Engine: Kalman State Estimation + Lyapunov Guard
// =============================================================================


pub type KalmanState {
  KalmanState(
    estimate: Float,
    covariance: Float,
    process_noise: Float,
    measurement_noise: Float,
  )
}

pub type ControllerState {
  ControllerState(
    cycle_id: String,
    kalman: KalmanState,
    setpoint: Float,
    last_energy: Float,
    control_action: Float,
    is_stable: Bool,
    andon_halt: Bool,
    stage_history: List(String),
  )
}

pub type PoodavrVerdict {
  ControllerNominal(
    cycle_id: String,
    filtered_estimate: Float,
    energy: Float,
    action: Float,
  )
  ControllerAndonHalt(
    cycle_id: String,
    stage_failed: String,
    reason: String,
    code: Int,
  )
}

pub fn new_kalman(q: Float, r: Float, initial_x: Float, initial_p: Float) -> KalmanState {
  KalmanState(
    estimate: initial_x,
    covariance: initial_p,
    process_noise: q,
    measurement_noise: r,
  )
}

pub fn new_controller(
  cycle_id: String,
  setpoint: Float,
  initial_estimate: Float,
) -> ControllerState {
  let kalman = new_kalman(0.01, 0.1, initial_estimate, 1.0)
  let initial_error = initial_estimate -. setpoint
  let initial_energy = initial_error *. initial_error
  ControllerState(
    cycle_id: cycle_id,
    kalman: kalman,
    setpoint: setpoint,
    last_energy: initial_energy,
    control_action: 0.0,
    is_stable: True,
    andon_halt: False,
    stage_history: [],
  )
}

/// Stage 1: Predict — Kalman Time Update (Prior Projection)
pub fn stage_predict(state: ControllerState) -> ControllerState {
  case state.andon_halt {
    True -> state
    False -> {
      let prior_p = state.kalman.covariance +. state.kalman.process_noise
      let updated_kalman = KalmanState(..state.kalman, covariance: prior_p)
      ControllerState(
        ..state,
        kalman: updated_kalman,
        stage_history: ["Predict", ..state.stage_history],
      )
    }
  }
}

/// Stage 2: Observe — Receive Noisy Measurement z
pub fn stage_observe(state: ControllerState, measurement: Float) -> #(ControllerState, Float) {
  case state.andon_halt {
    True -> #(state, 0.0)
    False -> {
      let next_state =
        ControllerState(
          ..state,
          stage_history: ["Observe", ..state.stage_history],
        )
      #(next_state, measurement)
    }
  }
}

/// Stage 3: Orient — Kalman Measurement Innovation and Posterior Update
pub fn stage_orient(state: ControllerState, measurement: Float) -> ControllerState {
  case state.andon_halt {
    True -> state
    False -> {
      let prior_x = state.kalman.estimate
      let prior_p = state.kalman.covariance
      let r = state.kalman.measurement_noise

      // S = P + R
      let s = prior_p +. r
      // K = P / S
      let k = case s >. 0.0000001 {
        True -> prior_p /. s
        False -> 0.0
      }

      // Innovation y = z - x
      let y = measurement -. prior_x
      let posterior_x = prior_x +. { k *. y }
      let posterior_p = { 1.0 -. k } *. prior_p

      let updated_kalman =
        KalmanState(..state.kalman, estimate: posterior_x, covariance: posterior_p)

      ControllerState(
        ..state,
        kalman: updated_kalman,
        stage_history: ["Orient", ..state.stage_history],
      )
    }
  }
}

/// Stage 4: Decide — Compute Cybernetic Proportional Control Action u = -Kp * (x - x*)
pub fn stage_decide(state: ControllerState, kp: Float) -> ControllerState {
  case state.andon_halt {
    True -> state
    False -> {
      let error = state.kalman.estimate -. state.setpoint
      let action = 0.0 -. { kp *. error }
      ControllerState(
        ..state,
        control_action: action,
        stage_history: ["Decide", ..state.stage_history],
      )
    }
  }
}

/// Stage 5: Act — Apply Actuation Output
pub fn stage_act(state: ControllerState) -> ControllerState {
  case state.andon_halt {
    True -> state
    False -> {
      ControllerState(
        ..state,
        stage_history: ["Act", ..state.stage_history],
      )
    }
  }
}

/// Stage 6: Verify — Evaluate Lyapunov Candidate V(x) = (x - x*)^2 and Energy Trend dV/dt <= 0
pub fn stage_verify(state: ControllerState, max_divergence_allowed: Float) -> ControllerState {
  case state.andon_halt {
    True -> state
    False -> {
      let err = state.kalman.estimate -. state.setpoint
      let current_energy = err *. err
      let delta_energy = current_energy -. state.last_energy

      // If energy grew beyond allowable threshold, system is diverging -> Andon Halt!
      case delta_energy >. max_divergence_allowed {
        True -> {
          ControllerState(
            ..state,
            last_energy: current_energy,
            is_stable: False,
            andon_halt: True,
            stage_history: ["Verify:DivergenceHalt", ..state.stage_history],
          )
        }
        False -> {
          ControllerState(
            ..state,
            last_energy: current_energy,
            is_stable: True,
            stage_history: ["Verify:Passed", ..state.stage_history],
          )
        }
      }
    }
  }
}

/// Stage 7: Reflect — Record Epistemic Learning and Check Verdict
pub fn stage_reflect(state: ControllerState) -> PoodavrVerdict {
  case state.andon_halt {
    True ->
      ControllerAndonHalt(
        cycle_id: state.cycle_id,
        stage_failed: "Verify",
        reason: "Lyapunov energy diverged: dV/dt > 0 violation",
        code: -32002,
      )
    False ->
      ControllerNominal(
        cycle_id: state.cycle_id,
        filtered_estimate: state.kalman.estimate,
        energy: state.last_energy,
        action: state.control_action,
      )
  }
}

/// Runs a complete 7-stage POODAVR closed-loop step with Kalman filtering and Lyapunov verification.
pub fn execute_full_poodavr_cycle(
  state: ControllerState,
  measurement: Float,
  kp: Float,
  max_divergence_allowed: Float,
) -> #(ControllerState, PoodavrVerdict) {
  let s1 = stage_predict(state)
  let #(s2, m) = stage_observe(s1, measurement)
  let s3 = stage_orient(s2, m)
  let s4 = stage_decide(s3, kp)
  let s5 = stage_act(s4)
  let s6 = stage_verify(s5, max_divergence_allowed)
  let verdict = stage_reflect(s6)
  #(s6, verdict)
}
