//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/prajna/circuit_breaker</module>
////   <fsharp-lineage>Cepaf.Prajna.CircuitBreaker</fsharp-lineage></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology></c3i-module>

pub type BreakerState {
  BreakerClosed
  BreakerOpen(opened_at: Int)
  BreakerHalfOpen
}

pub type Breaker {
  Breaker(
    name: String,
    state: BreakerState,
    failure_count: Int,
    success_count: Int,
    failure_threshold: Int,
    success_threshold: Int,
    reset_timeout_ms: Int,
  )
}

pub fn create(
  name: String,
  failure_threshold: Int,
  success_threshold: Int,
  reset_timeout_ms: Int,
) -> Breaker {
  Breaker(
    name: name,
    state: BreakerClosed,
    failure_count: 0,
    success_count: 0,
    failure_threshold: failure_threshold,
    success_threshold: success_threshold,
    reset_timeout_ms: reset_timeout_ms,
  )
}

pub fn record_failure(breaker: Breaker, now_ms: Int) -> Breaker {
  let new_count = breaker.failure_count + 1
  case new_count >= breaker.failure_threshold {
    True ->
      Breaker(
        ..breaker,
        state: BreakerOpen(now_ms),
        failure_count: new_count,
        success_count: 0,
      )
    False -> Breaker(..breaker, failure_count: new_count)
  }
}

pub fn record_success(breaker: Breaker) -> Breaker {
  case breaker.state {
    BreakerHalfOpen -> {
      let new_count = breaker.success_count + 1
      case new_count >= breaker.success_threshold {
        True ->
          Breaker(
            ..breaker,
            state: BreakerClosed,
            failure_count: 0,
            success_count: 0,
          )
        False -> Breaker(..breaker, success_count: new_count)
      }
    }
    _ -> Breaker(..breaker, success_count: breaker.success_count + 1)
  }
}

pub fn should_attempt_reset(breaker: Breaker, now_ms: Int) -> Bool {
  case breaker.state {
    BreakerOpen(opened_at) -> now_ms - opened_at >= breaker.reset_timeout_ms
    _ -> False
  }
}

pub fn attempt_half_open(breaker: Breaker, now_ms: Int) -> Breaker {
  case should_attempt_reset(breaker, now_ms) {
    True -> Breaker(..breaker, state: BreakerHalfOpen, success_count: 0)
    False -> breaker
  }
}

pub fn is_allowed(breaker: Breaker) -> Bool {
  case breaker.state {
    BreakerClosed -> True
    BreakerHalfOpen -> True
    BreakerOpen(_) -> False
  }
}
