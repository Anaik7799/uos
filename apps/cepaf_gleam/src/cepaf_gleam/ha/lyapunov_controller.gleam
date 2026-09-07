//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/lyapunov_controller</module>
////     <fsharp-lineage>N/A — Pure Gleam Adaptive Lyapunov Damping Controller</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L3_TRANSACTION</layer>
////     <cross-layer-dependencies>
////       <dep layer="L0_CONSTITUTIONAL">cepaf_gleam/ha/lyapunov_proof</dep>
////     </cross-layer-dependencies>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-MATH-001, SC-CTRL-001, SC-JIDOKA-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="stability-feedback">Negative Lyapunov exponent maintains maximum concurrency; positive exponent throttles fail-closed</property>
////     <property name="bounded-concurrency">Concurrency limit strictly clamped within [min_concurrency, max_concurrency]</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/int

/// Operating mitigation state determined by Lyapunov stability exponent.
pub type MitigationState {
  NominalThroughput
  ThrottledBackpressure(throttle_ratio: Float)
  EmergencyHalt(violation_reason: String)
}

/// Adaptive Lyapunov Dynamic Damping Controller state.
pub type LyapunovController {
  LyapunovController(
    target_exponent: Float,
    current_exponent: Float,
    concurrency_limit: Int,
    min_concurrency: Int,
    max_concurrency: Int,
    publish_interval_ms: Int,
    damping_factor: Float,
    state: MitigationState,
  )
}

/// Initialize the Lyapunov Dynamic Damping Controller.
pub fn init_controller(
  min_concurrency: Int,
  max_concurrency: Int,
) -> LyapunovController {
  LyapunovController(
    target_exponent: -3.0,
    current_exponent: -3.0,
    concurrency_limit: max_concurrency,
    min_concurrency: min_concurrency,
    max_concurrency: max_concurrency,
    publish_interval_ms: 50,
    damping_factor: 0.5,
    state: NominalThroughput,
  )
}

/// Pure functional update of the controller based on a new measured Lyapunov exponent.
pub fn update_controller(
  ctrl: LyapunovController,
  measured_lambda: Float,
) -> LyapunovController {
  case measured_lambda <. -1.5 {
    // Case 1: Strictly Stable (lambda < -1.5)
    True ->
      LyapunovController(
        ..ctrl,
        current_exponent: measured_lambda,
        concurrency_limit: ctrl.max_concurrency,
        publish_interval_ms: 50,
        state: NominalThroughput,
      )

    // Not strictly stable -> check marginal vs unstable
    False ->
      case measured_lambda <=. 0.0 {
        // Case 2: Marginally Stable (-1.5 <= lambda <= 0.0) -> Proportional Damping
        True -> {
          let severity = float.absolute_value(measured_lambda) /. 1.5
          let throttle_ratio = float.max(0.2, severity)
          let dynamic_limit =
            int.max(
              ctrl.min_concurrency,
              float.round(int.to_float(ctrl.max_concurrency) *. throttle_ratio),
            )
          let backoff_interval =
            int.min(500, float.round(50.0 /. float.max(0.1, throttle_ratio)))

          LyapunovController(
            ..ctrl,
            current_exponent: measured_lambda,
            concurrency_limit: dynamic_limit,
            publish_interval_ms: backoff_interval,
            state: ThrottledBackpressure(throttle_ratio: throttle_ratio),
          )
        }

        // Case 3: Divergent / Unstable (lambda > 0.0) -> Fail-Closed Emergency Halt
        False ->
          LyapunovController(
            ..ctrl,
            current_exponent: measured_lambda,
            concurrency_limit: ctrl.min_concurrency,
            publish_interval_ms: 1000,
            state: EmergencyHalt(
              violation_reason: "Lyapunov exponent positive: lambda = "
              <> float.to_string(measured_lambda),
            ),
          )
      }
  }
}

/// Calculate adaptive batch size for task pull queues (Heijunka scheduling).
pub fn compute_batch_size(ctrl: LyapunovController) -> Int {
  case ctrl.state {
    NominalThroughput -> int.max(1, ctrl.concurrency_limit / 2)
    ThrottledBackpressure(_) -> 1
    EmergencyHalt(_) -> 0
  }
}
