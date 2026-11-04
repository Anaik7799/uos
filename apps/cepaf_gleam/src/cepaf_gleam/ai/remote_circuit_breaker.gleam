pub type CircuitState {
  Closed
  HalfOpen
  Open
}

pub type RateLimitConfig {
  RateLimitConfig(
    max_usd_milli_per_hour: Int,
    max_requests_per_window: Int,
    window_seconds: Int,
  )
}

pub type CircuitBreaker {
  CircuitBreaker(
    config: RateLimitConfig,
    state: CircuitState,
    hourly_billed_usd_milli: Int,
    window_requests: Int,
    window_start_sec: Int,
    failure_count: Int,
  )
}

@external(erlang, "cepaf_gleam_time_ffi", "system_time_seconds")
pub fn current_time_seconds() -> Int

pub fn default_config() -> RateLimitConfig {
  RateLimitConfig(
    max_usd_milli_per_hour: 2000,
    // $2.00 / hour
    max_requests_per_window: 100,
    window_seconds: 300,
    // 5 minutes
  )
}

pub fn new(config: RateLimitConfig) -> CircuitBreaker {
  CircuitBreaker(
    config: config,
    state: Closed,
    hourly_billed_usd_milli: 0,
    window_requests: 0,
    window_start_sec: current_time_seconds(),
    failure_count: 0,
  )
}

pub fn check_admission(
  cb: CircuitBreaker,
  estimated_cost_usd_milli: Int,
) -> Result(CircuitBreaker, String) {
  case cb.state {
    Open -> Error("circuit_breaker_open_budget_or_failure_limit")
    _ -> {
      let now = current_time_seconds()
      let elapsed_sec = now - cb.window_start_sec

      let #(req_count, start_time) = case elapsed_sec >= cb.config.window_seconds {
        True -> #(0, now)
        False -> #(cb.window_requests, cb.window_start_sec)
      }

      case req_count >= cb.config.max_requests_per_window {
        True -> Error("request_rate_exceeded")
        False -> {
          case cb.hourly_billed_usd_milli + estimated_cost_usd_milli > cb.config.max_usd_milli_per_hour {
            True -> Error("hourly_budget_ceiling_exceeded")
            False -> {
              Ok(
                CircuitBreaker(
                  ..cb,
                  window_requests: req_count + 1,
                  window_start_sec: start_time,
                ),
              )
            }
          }
        }
      }
    }
  }
}

pub fn record_success(
  cb: CircuitBreaker,
  billed_cost_usd_milli: Int,
) -> CircuitBreaker {
  CircuitBreaker(
    ..cb,
    hourly_billed_usd_milli: cb.hourly_billed_usd_milli + billed_cost_usd_milli,
    failure_count: 0,
    state: Closed,
  )
}

pub fn record_failure(cb: CircuitBreaker) -> CircuitBreaker {
  let count = cb.failure_count + 1
  let next_state = case count >= 5 {
    True -> Open
    False -> cb.state
  }
  CircuitBreaker(..cb, failure_count: count, state: next_state)
}
