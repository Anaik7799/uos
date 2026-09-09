import cepaf_gleam/ha/homeostasis_evolution_engine as h
import cepaf_gleam/ha/predictive_autoscaler as a
import gleam/int
import gleam/list
import gleeunit/should

fn stable() {
  h.init_homeostasis_system(0)
  |> h.ingest_telemetry(1.0, 1.0, 1000)
  |> h.ingest_telemetry(1.0, 1.0, 2000)
  |> h.ingest_telemetry(1.0, 1.0, 3000)
}

fn mutation(id) { h.EvolutionaryMutation(id, "fixture", "fixture", 1.0, 0.01) }
fn indices(n) { list.repeat(Nil, n) |> list.index_map(fn(_, i) { i + 1 }) }

pub fn pending_proposal_intake_is_bounded_test() {
  let full = indices(32) |> list.fold(stable(), fn(state, i) {
    let assert Ok(#(next, _)) = h.submit_evolution(state, mutation(int.to_string(i)), 4000)
    next
  })
  h.submit_evolution(full, mutation("overflow"), 4000) |> should.be_error()
  list.length(full.pending_proposals) |> should.equal(32)
}

pub fn fractional_refill_is_partition_invariant_test() {
  let initial = a.init_autoscaler(1, 10, 50.0, 100, 1, 0)
  let assert Ok(empty) = a.consume_tokens(initial, 100, 0)
  let whole = a.refill_tokens(empty.token_bucket, 1_000_000)
  let split = indices(10) |> list.fold(empty.token_bucket, fn(bucket, i) {
    a.refill_tokens(bucket, i * 100_000)
  })
  whole.available_tokens |> should.equal(1)
  split.available_tokens |> should.equal(1)
}

pub fn partial_token_is_not_issued_early_test() {
  let initial = a.init_autoscaler(1, 10, 50.0, 100, 1, 0)
  let assert Ok(empty) = a.consume_tokens(initial, 100, 0)
  a.refill_tokens(empty.token_bucket, 600_000).available_tokens |> should.equal(0)
}

pub fn queue_derivative_uses_elapsed_seconds_test() {
  let initial = a.init_autoscaler(10, 20, 50.0, 100, 1, 0)
  let observed = a.evaluate_scaling(initial, 20, 50.0, 10_000_000)
  observed.queue_derivative |> should.equal(2.0)
  observed.current_workers |> should.equal(10)
}

pub fn nonforward_queue_sample_preserves_state_test() {
  let initial = a.init_autoscaler(10, 20, 50.0, 100, 1, 0)
  let observed = a.evaluate_scaling(initial, 20, 50.0, 10_000_000)
  a.evaluate_scaling(observed, 200, 500.0, 10_000_000) |> should.equal(observed)
  a.evaluate_scaling(observed, 200, 500.0, 9_000_000) |> should.equal(observed)
}

pub fn invalid_worker_order_cannot_construct_unsafe_state_test() {
  let state = a.init_autoscaler(10, 2, 50.0, 100, 1, 0)
  { state.current_workers <= state.max_workers } |> should.be_true()
}

pub fn negative_worker_limit_cannot_construct_unsafe_state_test() {
  let state = a.init_autoscaler(-1, 2, 50.0, 100, 1, 0)
  { state.current_workers >= 0 } |> should.be_true()
}

pub fn negative_token_capacity_cannot_construct_unsafe_state_test() {
  let state = a.init_autoscaler(1, 2, 50.0, -1, 1, 0)
  { state.token_bucket.available_tokens >= 0 } |> should.be_true()
}

pub fn negative_refill_rate_cannot_construct_unsafe_state_test() {
  let state = a.init_autoscaler(1, 2, 50.0, 100, -1, 0)
  { state.token_bucket.refill_rate_per_sec >= 0 } |> should.be_true()
}

pub fn nonpositive_latency_cannot_construct_unsafe_state_test() {
  let state = a.init_autoscaler(1, 2, 0.0, 100, 1, 0)
  { state.target_latency_ms >. 0.0 } |> should.be_true()
}
