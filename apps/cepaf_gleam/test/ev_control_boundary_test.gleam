import cepaf_gleam/ha/homeostasis_evolution_engine as h
import cepaf_gleam/ha/multi_agent_quorum as q
import cepaf_gleam/ha/physiological_homeostasis.{CpuUtilization}
import cepaf_gleam/ha/predictive_autoscaler as a
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleeunit/should

fn stable() {
  h.init_homeostasis_system(1000)
  |> h.ingest_telemetry(1.0, 1.0, 2000)
  |> h.ingest_telemetry(1.0, 1.0, 3000)
  |> h.ingest_telemetry(1.0, 1.0, 4000)
}

fn mutation(id) {
  h.EvolutionaryMutation(id, "bounded-test", "fixture", 1.0, 0.01)
}

fn ratify(proposal) {
  proposal
  |> h.vote_on_evolution(q.AgySovereign, q.QuorumApprove, "fixture", "a", 4200)
  |> h.vote_on_evolution(
    q.ClaudeSovereign,
    q.QuorumApprove,
    "fixture",
    "c",
    4300,
  )
  |> h.vote_on_evolution(
    q.CodexSovereign,
    q.QuorumApprove,
    "fixture",
    "x",
    4400,
  )
}

fn ratify_registered(state, proposal) {
  let assert Ok(#(state, proposal)) =
    h.cast_registered_vote(
      state,
      proposal,
      q.AgySovereign,
      q.QuorumApprove,
      "fixture",
      "a",
      4200,
    )
  let assert Ok(#(state, proposal)) =
    h.cast_registered_vote(
      state,
      proposal,
      q.ClaudeSovereign,
      q.QuorumApprove,
      "fixture",
      "c",
      4300,
    )
  let assert Ok(pair) =
    h.cast_registered_vote(
      state,
      proposal,
      q.CodexSovereign,
      q.QuorumApprove,
      "fixture",
      "x",
      4400,
    )
  pair
}

pub fn outsider_cannot_ratify_test() {
  let b = q.create_ballot("p", "fixture", q.TwoOfThreeSovereign, 1000)
  let voted =
    b
    |> q.cast_ballot_vote(
      q.PeerSovereign("outsider-1"),
      q.QuorumApprove,
      "",
      "",
      1100,
    )
    |> q.cast_ballot_vote(
      q.PeerSovereign("outsider-2"),
      q.QuorumApprove,
      "",
      "",
      1200,
    )
  voted.verdict |> should.not_equal(q.VerdictRatified(2, 2))
  voted.votes |> should.equal([])
}

pub fn named_peer_cannot_impersonate_sovereign_test() {
  let b = q.create_ballot("p", "fixture", q.TwoOfThreeSovereign, 1000)
  let voted =
    q.cast_ballot_vote(b, q.PeerSovereign("AGY"), q.QuorumApprove, "", "", 1100)
  voted.votes |> should.equal([])
}

pub fn byzantine_fault_is_terminal_test() {
  let fault =
    q.create_ballot("p", "fixture", q.TwoOfThreeSovereign, 1000)
    |> q.cast_ballot_vote(q.AgySovereign, q.QuorumApprove, "", "a", 1100)
    |> q.cast_ballot_vote(q.AgySovereign, q.QuorumReject, "", "b", 1200)
  q.cast_ballot_vote(fault, q.ClaudeSovereign, q.QuorumApprove, "", "c", 1300)
  |> should.equal(fault)
}

pub fn negative_debit_is_rejected_test() {
  let assert Ok(state) = a.init_autoscaler(1, 2, 50.0, 100, 10, 1000)
  a.consume_tokens(state, -1, 1000)
  |> should.equal(Error(a.InvalidTokenAmount(-1)))
}

pub fn intervention_after_ratification_blocks_apply_test() {
  let state = stable()
  let assert Ok(#(state, p)) =
    h.submit_evolution(state, mutation("intervention"), 4100)
  let #(state, p) = ratify_registered(state, p)
  let unstable = h.ingest_telemetry(state, 0.5, 1.0, 4500)
  h.apply_ratified_evolution(unstable, p) |> should.be_error()
}

pub fn physiology_after_ratification_blocks_apply_test() {
  let state = stable()
  let assert Ok(#(state, p)) =
    h.submit_evolution(state, mutation("physiology"), 4100)
  let #(state, p) = ratify_registered(state, p)
  let stressed =
    h.ingest_physiological_telemetry(
      state,
      [#(CpuUtilization, 98.0)],
      1.0,
      4500,
    )
  h.apply_ratified_evolution(stressed, p) |> should.be_error()
}

pub fn ratified_replay_is_rejected_test() {
  let state = stable()
  let assert Ok(#(state, p)) =
    h.submit_evolution(state, mutation("replay"), 4100)
  let #(state, proposal) = ratify_registered(state, p)
  let assert Ok(evolved) = h.apply_ratified_evolution(state, proposal)
  h.apply_ratified_evolution(evolved, proposal)
  |> should.equal(Error(h.EvolutionAlreadyApplied("replay")))
}

pub fn forged_verdict_without_votes_is_rejected_test() {
  let state = stable()
  let assert Ok(#(state, p)) =
    h.submit_evolution(state, mutation("forged"), 4100)
  let forged =
    h.EvolutionProposal(
      ..p,
      ballot: q.QuorumBallot(..p.ballot, verdict: q.VerdictRatified(3, 3)),
    )
  h.apply_ratified_evolution(state, forged)
  |> should.equal(Error(h.EvolutionProposalMismatch("forged")))
}

pub fn mismatched_mutation_is_rejected_test() {
  let state = stable()
  let assert Ok(#(state, p)) =
    h.submit_evolution(state, mutation("original"), 4100)
  let #(state, p) = ratify_registered(state, p)
  let forged = h.EvolutionProposal(..p, mutation: mutation("injected"))
  h.apply_ratified_evolution(state, forged) |> should.be_error()
}

pub fn skipped_generation_is_rejected_test() {
  let state = stable()
  let assert Ok(#(state, p)) =
    h.submit_evolution(state, mutation("generation"), 4100)
  let #(state, p) = ratify_registered(state, p)
  h.apply_ratified_evolution(state, h.EvolutionProposal(..p, generation: 9))
  |> should.equal(Error(h.EvolutionGenerationMismatch(1, 9)))
}

pub fn stale_generation_cannot_regress_state_test() {
  let assert Ok(#(state, old)) =
    h.submit_evolution(stable(), mutation("old"), 4100)
  let #(state, old) = ratify_registered(state, old)
  let assert Ok(#(state, current)) =
    h.submit_evolution(state, mutation("current"), 4100)
  let #(state, current) = ratify_registered(state, current)
  let assert Ok(evolved) = h.apply_ratified_evolution(state, current)
  h.apply_ratified_evolution(evolved, old)
  |> should.equal(Error(h.EvolutionGenerationMismatch(2, 1)))
  evolved.generation |> should.equal(1)
  list.map(evolved.ratified_evolutions, fn(m) { m.mutation_id })
  |> should.equal(["current"])
}

pub fn token_debits_conserve_available_and_consumed_test() {
  let assert Ok(state) = a.init_autoscaler(1, 2, 50.0, 100, 10, 1000)
  list.each([#(0, 100), #(1, 99), #(99, 1), #(100, 0)], fn(pair) {
    let assert Ok(next) = a.consume_tokens(state, pair.0, 1000)
    next.token_bucket.available_tokens |> should.equal(pair.1)
    next.total_tokens_consumed |> should.equal(pair.0)
  })
  a.consume_tokens(state, 101, 1000)
  |> should.equal(Error(a.TokenBudgetExhausted(101, 100)))
}

pub fn unconfigured_bft_roster_fails_closed_test() {
  let b = q.create_ballot("p", "fixture", q.ByzantineFaultTolerant(2), 1000)
  let voted =
    q.cast_ballot_vote(b, q.AgySovereign, q.QuorumApprove, "", "a", 1100)
  voted.verdict
  |> should.equal(q.VerdictByzantineFault(
    "POLICY",
    "Unsupported sovereign roster",
  ))
  voted.votes |> should.equal([])
}

fn start_stable_actor() {
  let assert Ok(started) = h.start_actor(1000)
  actor.send(started.data, h.IngestHealthObservation(1.0, 1.0, 2000))
  actor.send(started.data, h.IngestHealthObservation(1.0, 1.0, 3000))
  actor.send(started.data, h.IngestHealthObservation(1.0, 1.0, 4000))
  started
}

fn actor_vote(subject, proposal, voter, vote) {
  actor.call(subject, 1000, fn(reply) {
    h.CastQuorumVote(proposal, voter, vote, "fixture", "test", 4200, reply)
  })
}

fn actor_submit(subject, id) {
  let assert Ok(p) =
    actor.call(subject, 1000, fn(reply) {
      h.SubmitMutationProposal(mutation(id), 4100, reply)
    })
  p
}

fn actor_apply(subject, proposal) {
  actor.call(subject, 1000, fn(reply) {
    h.ApplyMutationEvolution(proposal, reply)
  })
}

fn stop_actor(started: actor.Started(process.Subject(h.HomeostasisActorMsg))) {
  process.unlink(started.pid)
  process.kill(started.pid)
}

pub fn actor_rejects_forged_votes_and_stale_vote_snapshot_test() {
  let started = start_stable_actor()
  let subject = started.data
  let p = actor_submit(subject, "actor-owned")
  let forged_apply = actor_apply(subject, ratify(p))
  let assert Ok(p1) = actor_vote(subject, p, q.AgySovereign, q.QuorumApprove)
  let stale_vote = actor_vote(subject, p, q.ClaudeSovereign, q.QuorumApprove)
  let observed = actor.call(subject, 1000, h.GetHomeostasisState)
  stop_actor(started)
  forged_apply
  |> should.equal(Error(h.EvolutionProposalMismatch("actor-owned")))
  stale_vote |> should.equal(Error(h.EvolutionProposalMismatch("actor-owned")))
  observed.pending_proposals |> should.equal([p1])
  observed.ratified_evolutions |> should.equal([])
}

pub fn actor_intervention_and_replay_preserve_owned_state_test() {
  let started = start_stable_actor()
  let subject = started.data
  let p = actor_submit(subject, "actor-cycle")
  let assert Ok(p) = actor_vote(subject, p, q.AgySovereign, q.QuorumApprove)
  let assert Ok(p) = actor_vote(subject, p, q.ClaudeSovereign, q.QuorumApprove)
  let assert Ok(p) = actor_vote(subject, p, q.CodexSovereign, q.QuorumApprove)
  actor.send(subject, h.IngestHealthObservation(0.5, 1.0, 4500))
  let stopped = actor_apply(subject, p)
  let stopped_state = actor.call(subject, 1000, h.GetHomeostasisState)
  actor.send(subject, h.IngestHealthObservation(1.0, 1.0, 5000))
  actor.send(subject, h.IngestHealthObservation(1.0, 1.0, 6000))
  actor.send(subject, h.IngestHealthObservation(1.0, 1.0, 7000))
  let applied = actor_apply(subject, p)
  let replay = actor_apply(subject, p)
  let observed = actor.call(subject, 1000, h.GetHomeostasisState)
  stop_actor(started)
  stopped
  |> should.equal(
    Error(h.EvolutionNotReady("Current phase does not permit evolution")),
  )
  stopped_state.generation |> should.equal(0)
  let assert Ok(evolved) = applied
  evolved.generation |> should.equal(1)
  replay |> should.equal(Error(h.EvolutionAlreadyApplied("actor-cycle")))
  observed |> should.equal(evolved)
  list.length(observed.ratified_evolutions) |> should.equal(1)
}

pub fn actor_byzantine_fault_cannot_be_overwritten_test() {
  let started = start_stable_actor()
  let subject = started.data
  let p = actor_submit(subject, "actor-fault")
  let assert Ok(p) = actor_vote(subject, p, q.AgySovereign, q.QuorumApprove)
  let assert Ok(fault) = actor_vote(subject, p, q.AgySovereign, q.QuorumReject)
  let assert Ok(after_vote) =
    actor_vote(subject, fault, q.ClaudeSovereign, q.QuorumApprove)
  let rejected = actor_apply(subject, after_vote)
  let observed = actor.call(subject, 1000, h.GetHomeostasisState)
  stop_actor(started)
  after_vote |> should.equal(fault)
  rejected |> should.equal(Error(h.EvolutionNotRatified(fault.ballot.verdict)))
  observed.generation |> should.equal(0)
}

pub fn actor_rejects_unsubmitted_proposal_test() {
  let assert Ok(p) = h.propose_evolution(stable(), mutation("foreign"), 4100)
  let assert Ok(started) = h.start_actor(1000)
  let subject = started.data
  actor.send(subject, h.IngestHealthObservation(1.0, 1.0, 2000))
  actor.send(subject, h.IngestHealthObservation(1.0, 1.0, 3000))
  actor.send(subject, h.IngestHealthObservation(1.0, 1.0, 4000))
  let result =
    actor.call(subject, 1000, fn(reply) {
      h.ApplyMutationEvolution(ratify(p), reply)
    })
  let observed = actor.call(subject, 1000, h.GetHomeostasisState)
  // Shut down the isolated test actor before asserting the boundary.
  process.unlink(started.pid)
  process.kill(started.pid)
  result |> should.be_error()
  observed.generation |> should.equal(0)
  observed.ratified_evolutions |> should.equal([])
}
