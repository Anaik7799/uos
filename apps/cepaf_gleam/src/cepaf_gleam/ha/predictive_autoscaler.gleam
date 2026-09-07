//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/predictive_autoscaler</module>
////     <fsharp-lineage>N/A — Pure Gleam Lyapunov-Windowed Predictive Autoscaler & Token Flow Optimizer</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L2_HEALTH</layer>
////     <layer>L4_SYSTEM</layer>
////     <layer>L5_COGNITIVE</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-SIL6-001, SC-LYAPUNOV-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/int

/// Scaling action recommended by the predictive engine.
pub type ScalingAction {
  ScaleUp(delta: Int, rationale: String)
  ScaleDown(delta: Int, rationale: String)
  ScaleHold(rationale: String)
}

/// Token bucket budget descriptor.
pub type TokenBucket {
  TokenBucket(
    capacity: Int,
    available_tokens: Int,
    refill_rate_per_sec: Int,
    last_refill_us: Int,
  )
}

/// Autoscaler State Model.
pub type AutoscalerState {
  AutoscalerState(
    current_workers: Int,
    min_workers: Int,
    max_workers: Int,
    queue_depth: Int,
    prev_queue_depth: Int,
    queue_derivative: Float,
    token_bucket: TokenBucket,
    total_tokens_consumed: Int,
    lyapunov_exponent: Float,
    target_latency_ms: Float,
    observed_latency_ms: Float,
    last_scale_action: ScalingAction,
    last_scale_timestamp_us: Int,
    cooldown_period_us: Int,
  )
}

/// Initialize the predictive autoscaler.
pub fn init_autoscaler(
  min_workers: Int,
  max_workers: Int,
  target_latency_ms: Float,
  token_capacity: Int,
  refill_rate: Int,
  now_us: Int,
) -> AutoscalerState {
  let bucket =
    TokenBucket(
      capacity: token_capacity,
      available_tokens: token_capacity,
      refill_rate_per_sec: refill_rate,
      last_refill_us: now_us,
    )

  AutoscalerState(
    current_workers: min_workers,
    min_workers: min_workers,
    max_workers: max_workers,
    queue_depth: 0,
    prev_queue_depth: 0,
    queue_derivative: 0.0,
    token_bucket: bucket,
    total_tokens_consumed: 0,
    lyapunov_exponent: -2.5,
    target_latency_ms: target_latency_ms,
    observed_latency_ms: target_latency_ms,
    last_scale_action: ScaleHold("Initial state"),
    last_scale_timestamp_us: now_us,
    cooldown_period_us: 10_000_000,
    // 10 seconds cooldown
  )
}

/// Refill tokens based on elapsed microsecond time delta.
pub fn refill_tokens(bucket: TokenBucket, now_us: Int) -> TokenBucket {
  let elapsed_us = now_us - bucket.last_refill_us
  case elapsed_us <= 0 {
    True -> bucket
    False -> {
      let elapsed_sec = int.to_float(elapsed_us) /. 1_000_000.0
      let added_tokens =
        float.round(elapsed_sec *. int.to_float(bucket.refill_rate_per_sec))
      let new_tokens = int.min(bucket.capacity, bucket.available_tokens + added_tokens)
      TokenBucket(..bucket, available_tokens: new_tokens, last_refill_us: now_us)
    }
  }
}

/// Consume tokens from the bucket if available.
pub fn consume_tokens(
  state: AutoscalerState,
  tokens: Int,
  now_us: Int,
) -> Result(AutoscalerState, String) {
  let bucket = refill_tokens(state.token_bucket, now_us)
  case bucket.available_tokens >= tokens {
    True -> {
      let updated_bucket =
        TokenBucket(..bucket, available_tokens: bucket.available_tokens - tokens)
      Ok(
        AutoscalerState(
          ..state,
          token_bucket: updated_bucket,
          total_tokens_consumed: state.total_tokens_consumed + tokens,
        ),
      )
    }
    False ->
      Error(
        "Token budget exhausted: requested "
        <> int.to_string(tokens)
        <> ", available "
        <> int.to_string(bucket.available_tokens),
      )
  }
}

/// Evaluate predictive scaling based on queue depth, rate of change d(Q)/dt, and Lyapunov stability.
pub fn evaluate_scaling(
  state: AutoscalerState,
  new_queue_depth: Int,
  new_latency_ms: Float,
  now_us: Int,
) -> AutoscalerState {
  let bucket = refill_tokens(state.token_bucket, now_us)
  let delta_q = int.to_float(new_queue_depth - state.queue_depth)
  let dq_dt = delta_q

  // Compute Lyapunov stability: lambda = ln(|latency / target|)
  let ratio = new_latency_ms /. state.target_latency_ms
  let lyapunov = case ratio >. 1.0 {
    True -> { ratio -. 1.0 } *. 2.0
    False -> 0.0 -. { { 1.0 -. ratio } *. 2.0 }
  }

  let in_cooldown = now_us - state.last_scale_timestamp_us < state.cooldown_period_us

  let #(new_workers, action, action_ts) = case in_cooldown {
    True -> #(state.current_workers, ScaleHold("In cooldown period"), state.last_scale_timestamp_us)
    False -> {
      // Scale UP trigger: high queue, positive derivative, or diverging Lyapunov
      case new_queue_depth > state.current_workers * 5 || dq_dt >. 2.0 || lyapunov >. 0.5 {
        True -> {
          let target = int.min(state.max_workers, state.current_workers + 2)
          let delta = target - state.current_workers
          case delta > 0 {
            True -> #(
              target,
              ScaleUp(delta, "Queue pressure d(Q)/dt > 2.0 or Lyapunov > 0.5"),
              now_us,
            )
            False -> #(state.current_workers, ScaleHold("At maximum capacity"), state.last_scale_timestamp_us)
          }
        }
        False -> {
          // Scale DOWN trigger: low queue, non-positive derivative, negative Lyapunov
          case new_queue_depth < state.current_workers && dq_dt <=. 0.0 && lyapunov <. -1.0 {
            True -> {
              let target = int.max(state.min_workers, state.current_workers - 1)
              let delta = state.current_workers - target
              case delta > 0 {
                True -> #(
                  target,
                  ScaleDown(delta, "Low queue depth and stable negative Lyapunov"),
                  now_us,
                )
                False -> #(state.current_workers, ScaleHold("At minimum capacity"), state.last_scale_timestamp_us)
              }
            }
            False -> #(state.current_workers, ScaleHold("Workload within target envelope"), state.last_scale_timestamp_us)
          }
        }
      }
    }
  }

  AutoscalerState(
    ..state,
    current_workers: new_workers,
    prev_queue_depth: state.queue_depth,
    queue_depth: new_queue_depth,
    queue_derivative: dq_dt,
    token_bucket: bucket,
    lyapunov_exponent: lyapunov,
    observed_latency_ms: new_latency_ms,
    last_scale_action: action,
    last_scale_timestamp_us: action_ts,
  )
}
