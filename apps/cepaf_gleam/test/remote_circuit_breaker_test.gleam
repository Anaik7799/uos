import cepaf_gleam/ai/remote_circuit_breaker.{
  RateLimitConfig, check_admission, current_time_seconds, new, record_failure,
  record_success,
}
import gleeunit/should

pub fn circuit_breaker_rate_and_budget_limits_test() {
  let cfg =
    RateLimitConfig(
      max_usd_milli_per_hour: 100,
      max_requests_per_window: 2,
      window_seconds: 60,
    )

  let cb0 = new(cfg)

  // 1st request admissible
  let assert Ok(cb1) = check_admission(cb0, 40)
  let cb2 = record_success(cb1, 40)

  // 2nd request admissible
  let assert Ok(cb3) = check_admission(cb2, 40)
  let cb4 = record_success(cb3, 40)

  // 3rd request in same window exceeds max_requests_per_window (2)
  check_admission(cb4, 10)
  |> should.equal(Error("request_rate_exceeded"))

  // Test budget exhaustion
  let cfg_budget =
    RateLimitConfig(
      max_usd_milli_per_hour: 50,
      max_requests_per_window: 10,
      window_seconds: 60,
    )
  let b_cb0 = new(cfg_budget)
  let assert Ok(b_cb1) = check_admission(b_cb0, 30)
  let b_cb2 = record_success(b_cb1, 30)

  // Next request would exceed $0.050 (30 + 25 = 55 > 50)
  check_admission(b_cb2, 25)
  |> should.equal(Error("hourly_budget_ceiling_exceeded"))

  // Test failure trip to Open
  let trip_cb =
    b_cb0
    |> record_failure
    |> record_failure
    |> record_failure
    |> record_failure
    |> record_failure

  check_admission(trip_cb, 5)
  |> should.equal(Error("circuit_breaker_open_budget_or_failure_limit"))
}
