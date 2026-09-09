// Tests for Predictive Autoscaler & Token Flow Optimizer (EV-106)
// STAMP: SC-SIL6-001, SC-LYAPUNOV-001, SC-MUDA-001

import cepaf_gleam/ha/predictive_autoscaler.{
  ScaleDown, ScaleHold, ScaleUp, consume_tokens, evaluate_scaling,
  init_autoscaler, refill_tokens,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn init_autoscaler_test() {
  let a = init_autoscaler(2, 10, 50.0, 1000, 100, 1000)
  a.current_workers |> should.equal(2)
  a.min_workers |> should.equal(2)
  a.max_workers |> should.equal(10)
  a.token_bucket.capacity |> should.equal(1000)
  a.token_bucket.available_tokens |> should.equal(1000)
}

pub fn token_consumption_and_refill_test() {
  let a0 = init_autoscaler(2, 10, 50.0, 1000, 100, 1000)
  let res1 = consume_tokens(a0, 400, 1000)
  case res1 {
    Ok(a1) -> {
      a1.token_bucket.available_tokens |> should.equal(600)
      a1.total_tokens_consumed |> should.equal(400)

      // Test refill after 2 seconds (2,000,000 us * 100 tokens/sec = 200 tokens)
      let bucket_refilled = refill_tokens(a1.token_bucket, 1000 + 2_000_000)
      bucket_refilled.available_tokens |> should.equal(800)
    }
    Error(_) -> panic as "Expected token consumption to succeed"
  }
}

pub fn token_exhaustion_test() {
  let a0 = init_autoscaler(2, 10, 50.0, 100, 10, 1000)
  let res = consume_tokens(a0, 500, 1000)
  case res {
    Ok(_) -> panic as "Expected error due to token exhaustion"
    Error(error) ->
      error
      |> should.equal(predictive_autoscaler.TokenBudgetExhausted(500, 100))
  }
}

pub fn scale_up_on_queue_spike_test() {
  let a0 = init_autoscaler(2, 10, 50.0, 1000, 100, 1000)

  // Pass cooldown time (10s + 1us = 10_000_001 us)
  let now = 1000 + 10_000_001
  let a1 = evaluate_scaling(a0, 25, 120.0, now)

  a1.current_workers |> should.equal(4)
  case a1.last_scale_action {
    ScaleUp(delta, _) -> delta |> should.equal(2)
    _ -> panic as "Expected ScaleUp action"
  }
  should.be_true(a1.lyapunov_exponent >. 0.0)
}

pub fn cooldown_inhibits_scaling_test() {
  let a0 = init_autoscaler(2, 10, 50.0, 1000, 100, 1000)

  // Attempt scale during cooldown (only 1s passed)
  let now = 1000 + 1_000_000
  let a1 = evaluate_scaling(a0, 30, 150.0, now)

  a1.current_workers |> should.equal(2)
  case a1.last_scale_action {
    ScaleHold(_) -> Nil
    _ -> panic as "Expected ScaleHold during cooldown"
  }
}

pub fn scale_down_on_idle_queue_test() {
  let a0 = init_autoscaler(2, 10, 50.0, 1000, 100, 1000)
  // Manually put workers to 6
  let a_scaled = evaluate_scaling(a0, 40, 150.0, 1000 + 10_000_001)
  let a_scaled_more = evaluate_scaling(a_scaled, 45, 160.0, 1000 + 20_000_002)

  // Now idle queue and low latency after cooldown
  let now = 1000 + 30_000_003
  let a_idle = evaluate_scaling(a_scaled_more, 1, 15.0, now)

  case a_idle.last_scale_action {
    ScaleDown(delta, _) -> delta |> should.equal(1)
    _ -> panic as "Expected ScaleDown action"
  }
  should.be_true(a_idle.lyapunov_exponent <. 0.0)
}
