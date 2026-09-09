import cepaf_gleam/ha/homeostasis_evolution_engine as h
import cepaf_gleam/ha/multi_agent_quorum as q
import cepaf_gleam/ha/predictive_autoscaler as a
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleeunit/should

fn stable() {
  h.init_homeostasis_system(0)
  |> h.ingest_telemetry(1.0, 1.0, 1000)
  |> h.ingest_telemetry(1.0, 1.0, 2000)
  |> h.ingest_telemetry(1.0, 1.0, 3000)
}

fn mutation(id) {
  h.EvolutionaryMutation(id, "fixture", "fixture", 1.0, 0.01)
}

fn indices(n) {
  list.repeat(Nil, n) |> list.index_map(fn(_, i) { i + 1 })
}

pub fn pending_proposal_intake_is_bounded_test() {
  let full =
    indices(32)
    |> list.fold(stable(), fn(state, i) {
      let assert Ok(#(next, _)) =
        h.submit_evolution(state, mutation(int.to_string(i)), 4000)
      next
    })
  h.submit_evolution(full, mutation("overflow"), 4000)
  |> should.equal(Error(h.EvolutionCapacityReached(32)))
  list.length(full.pending_proposals) |> should.equal(32)
}

pub fn fractional_refill_is_partition_invariant_test() {
  let assert Ok(initial) = a.init_autoscaler(1, 10, 50.0, 100, 1, 0)
  let assert Ok(empty) = a.consume_tokens(initial, 100, 0)
  let whole = a.refill_tokens(empty.token_bucket, 1_000_000)
  let split =
    indices(10)
    |> list.fold(empty.token_bucket, fn(bucket, i) {
      a.refill_tokens(bucket, i * 100_000)
    })
  whole.available_tokens |> should.equal(1)
  split.available_tokens |> should.equal(1)
}

pub fn partial_token_is_not_issued_early_test() {
  let assert Ok(initial) = a.init_autoscaler(1, 10, 50.0, 100, 1, 0)
  let assert Ok(empty) = a.consume_tokens(initial, 100, 0)
  a.refill_tokens(empty.token_bucket, 600_000).available_tokens
  |> should.equal(0)
}

pub fn queue_derivative_uses_elapsed_seconds_test() {
  let assert Ok(initial) = a.init_autoscaler(10, 20, 50.0, 100, 1, 0)
  let observed = a.evaluate_scaling(initial, 20, 50.0, 10_000_000)
  observed.queue_derivative |> should.equal(2.0)
  observed.current_workers |> should.equal(10)
}

pub fn nonforward_queue_sample_preserves_state_test() {
  let assert Ok(initial) = a.init_autoscaler(10, 20, 50.0, 100, 1, 0)
  let observed = a.evaluate_scaling(initial, 20, 50.0, 10_000_000)
  a.evaluate_scaling(observed, 200, 500.0, 10_000_000) |> should.equal(observed)
  a.evaluate_scaling(observed, 200, 500.0, 9_000_000) |> should.equal(observed)
}

pub fn invalid_worker_order_cannot_construct_unsafe_state_test() {
  a.init_autoscaler(10, 2, 50.0, 100, 1, 0)
  |> should.equal(Error(a.InvalidWorkerLimits(10, 2)))
}

pub fn negative_worker_limit_cannot_construct_unsafe_state_test() {
  a.init_autoscaler(-1, 2, 50.0, 100, 1, 0)
  |> should.equal(Error(a.InvalidWorkerLimits(-1, 2)))
}

pub fn negative_token_capacity_cannot_construct_unsafe_state_test() {
  a.init_autoscaler(1, 2, 50.0, -1, 1, 0)
  |> should.equal(Error(a.InvalidTokenLimits(-1, 1)))
}

pub fn negative_refill_rate_cannot_construct_unsafe_state_test() {
  a.init_autoscaler(1, 2, 50.0, 100, -1, 0)
  |> should.equal(Error(a.InvalidTokenLimits(100, -1)))
}

pub fn nonpositive_latency_cannot_construct_unsafe_state_test() {
  a.init_autoscaler(1, 2, 0.0, 100, 1, 0)
  |> should.equal(Error(a.InvalidTargetLatency(0.0)))
}

fn ratify(state, proposal) {
  let assert Ok(#(state, proposal)) =
    h.cast_registered_vote(
      state,
      proposal,
      q.AgySovereign,
      q.QuorumApprove,
      "fixture",
      "a",
      4100,
    )
  let assert Ok(#(state, proposal)) =
    h.cast_registered_vote(
      state,
      proposal,
      q.ClaudeSovereign,
      q.QuorumApprove,
      "fixture",
      "c",
      4200,
    )
  let assert Ok(pair) =
    h.cast_registered_vote(
      state,
      proposal,
      q.CodexSovereign,
      q.QuorumApprove,
      "fixture",
      "x",
      4300,
    )
  pair
}

pub fn retired_ratified_snapshot_cannot_regain_authority_test() {
  let assert Ok(#(state, original)) =
    h.submit_evolution(stable(), mutation("same"), 4000)
  let #(state, original) = ratify(state, original)
  let assert Ok(retired) = h.retire_terminal_proposal(state, original)
  retired.pending_proposals |> should.equal([])
  h.apply_ratified_evolution(retired, original)
  |> should.equal(Error(h.EvolutionUnknownProposal("same")))
  let assert Ok(#(state, replacement)) =
    h.submit_evolution(retired, mutation("same"), 4000)
  let #(state, replacement) = ratify(state, replacement)
  replacement.proposal_sequence |> should.equal(2)
  h.apply_ratified_evolution(state, original)
  |> should.equal(Error(h.EvolutionProposalMismatch("same")))
  h.cast_registered_vote(
    state,
    original,
    q.OpenRouterSovereign,
    q.QuorumApprove,
    "fixture",
    "o",
    4500,
  )
  |> should.equal(Error(h.EvolutionProposalMismatch("same")))
  let assert Ok(evolved) = h.apply_ratified_evolution(state, replacement)
  evolved.generation |> should.equal(1)
  list.length(evolved.ratified_evolutions) |> should.equal(1)
}

pub fn pending_ballot_cannot_be_retired_test() {
  let assert Ok(#(state, proposal)) =
    h.submit_evolution(stable(), mutation("pending"), 4000)
  h.retire_terminal_proposal(state, proposal)
  |> should.equal(Error(h.EvolutionNotTerminal("pending")))
}

pub fn actor_terminal_retirement_frees_exactly_one_slot_test() {
  let assert Ok(started) = h.start_actor(0)
  let subject = started.data
  actor.send(subject, h.IngestHealthObservation(1.0, 1.0, 1000))
  actor.send(subject, h.IngestHealthObservation(1.0, 1.0, 2000))
  actor.send(subject, h.IngestHealthObservation(1.0, 1.0, 3000))
  let proposals =
    indices(32)
    |> list.map(fn(i) {
      let assert Ok(proposal) =
        actor.call(subject, 1000, fn(reply) {
          h.SubmitMutationProposal(mutation(int.to_string(i)), 4000, reply)
        })
      proposal
    })
  let overflow =
    actor.call(subject, 1000, fn(reply) {
      h.SubmitMutationProposal(mutation("overflow"), 4000, reply)
    })
  let assert Ok(p) = list.first(proposals)
  let refused_retirement =
    actor.call(subject, 1000, fn(reply) { h.RetireMutationProposal(p, reply) })
  let assert Ok(p) =
    actor.call(subject, 1000, fn(reply) {
      h.CastQuorumVote(
        p,
        q.AgySovereign,
        q.QuorumReject,
        "fixture",
        "a",
        4100,
        reply,
      )
    })
  let assert Ok(p) =
    actor.call(subject, 1000, fn(reply) {
      h.CastQuorumVote(
        p,
        q.ClaudeSovereign,
        q.QuorumReject,
        "fixture",
        "c",
        4200,
        reply,
      )
    })
  let retired =
    actor.call(subject, 1000, fn(reply) { h.RetireMutationProposal(p, reply) })
  let replaced =
    actor.call(subject, 1000, fn(reply) {
      h.SubmitMutationProposal(mutation("overflow"), 4000, reply)
    })
  let repeated_retirement =
    actor.call(subject, 1000, fn(reply) { h.RetireMutationProposal(p, reply) })
  let observed = actor.call(subject, 1000, h.GetHomeostasisState)
  process.unlink(started.pid)
  process.kill(started.pid)
  overflow |> should.equal(Error(h.EvolutionCapacityReached(32)))
  refused_retirement |> should.equal(Error(h.EvolutionNotTerminal("1")))
  let assert Ok(retired_state) = retired
  list.length(retired_state.pending_proposals) |> should.equal(31)
  let assert Ok(replacement) = replaced
  replacement.proposal_sequence |> should.equal(33)
  repeated_retirement |> should.equal(Error(h.EvolutionUnknownProposal("1")))
  list.length(observed.pending_proposals) |> should.equal(32)
  observed.generation |> should.equal(0)
}

pub fn refill_partitions_conserve_fraction_and_saturation_test() {
  let assert Ok(initial) = a.init_autoscaler(0, 0, 1.0, 3, 7, 0)
  let assert Ok(empty) = a.consume_tokens(initial, 3, 0)
  list.each([100_000, 400_000, 800_000], fn(end_time) {
    let whole = a.refill_tokens(empty.token_bucket, end_time)
    let split =
      indices(100)
      |> list.fold(empty.token_bucket, fn(bucket, i) {
        a.refill_tokens(bucket, i * end_time / 100)
      })
    split |> should.equal(whole)
  })
  let full = a.refill_tokens(empty.token_bucket, 500_000)
  full.available_tokens |> should.equal(3)
  full.refill_remainder |> should.equal(0)
  a.refill_tokens(full, 499_000) |> should.equal(full)
}

pub fn derivative_tracks_observation_time_independently_of_refill_test() {
  let assert Ok(initial) = a.init_autoscaler(10, 20, 50.0, 100, 1, 0)
  let assert Ok(refilled) = a.consume_tokens(initial, 0, 9_000_000)
  let first = a.evaluate_scaling(refilled, 20, 50.0, 10_000_000)
  let second = a.evaluate_scaling(first, 24, 50.0, 12_000_000)
  first.queue_derivative |> should.equal(2.0)
  second.queue_derivative |> should.equal(2.0)
  second.current_workers |> should.equal(10)
}
