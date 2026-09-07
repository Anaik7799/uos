import cepaf_gleam/ha/homeostasis_evolution_engine.{
  AutonomousEvolutionActive, Converging, EvolutionaryMutation,
  HomeostaticEquilibrium, InstabilityIntervention, apply_ratified_evolution,
  default_pid_config, get_quorum_members, ingest_telemetry,
  init_homeostasis_system, propose_evolution, step_homeostasis,
  vote_on_evolution,
}
import cepaf_gleam/ha/multi_agent_quorum.{
  AgySovereign, ClaudeSovereign, CodexSovereign, OpenRouterSovereign,
  QuorumApprove, QuorumReject, VerdictPending, VerdictRatified,
  sovereign_to_string,
}
import cepaf_gleam/ha/physiological_homeostasis.{CpuUtilization}
import gleam/list
import gleam/otp/actor
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn four_party_quorum_members_test() {
  let members = get_quorum_members()
  list.length(members) |> should.equal(4)
  list.contains(members, AgySovereign) |> should.equal(True)
  list.contains(members, ClaudeSovereign) |> should.equal(True)
  list.contains(members, CodexSovereign) |> should.equal(True)
  list.contains(members, OpenRouterSovereign) |> should.equal(True)

  sovereign_to_string(OpenRouterSovereign) |> should.equal("OPENROUTER")
}

pub fn pid_homeostasis_convergence_test() {
  let cfg = default_pid_config()
  let m0 = homeostasis_evolution_engine.initial_metrics(1000)
  m0.error |> should.equal(0.15)

  // Step towards setpoint 1.0 with measured health 0.98
  let m1 = step_homeostasis(m0, 0.98, 1.0, cfg, 2000)
  // error drops from 0.15 to 0.02
  { m1.error <. 0.05 } |> should.equal(True)
  m1.stable |> should.equal(True)
  // Lyapunov function V = 0.5 * e^2 is tiny
  { m1.lyapunov_v <. 0.001 } |> should.equal(True)
}

pub fn equilibrium_transition_test() {
  let s0 = init_homeostasis_system(1000)
  case s0.phase {
    Converging(..) -> True |> should.equal(True)
    _ -> panic as "Expected initial state to be Converging"
  }

  // Supply 3 consecutive ticks of nominal health 1.0 (error = 0.0)
  let s1 = ingest_telemetry(s0, 1.0, 1.0, 2000)
  s1.consecutive_stable_ticks |> should.equal(1)

  let s2 = ingest_telemetry(s1, 1.0, 1.0, 3000)
  s2.consecutive_stable_ticks |> should.equal(2)

  let s3 = ingest_telemetry(s2, 1.0, 1.0, 4000)
  s3.consecutive_stable_ticks |> should.equal(3)

  case s3.phase {
    HomeostaticEquilibrium(cycles, _) -> cycles |> should.equal(3)
    _ -> panic as "Expected HomeostaticEquilibrium after 3 consecutive stable ticks"
  }
}

pub fn propose_evolution_blocked_before_homeostasis_test() {
  let s0 = init_homeostasis_system(1000)
  let mut =
    EvolutionaryMutation(
      mutation_id: "mut-01",
      target_capability: "SIMD Tensor Cache",
      description: "Expand L1 cache lines",
      expected_gain_pct: 18.5,
      risk_score: 0.05,
    )

  // Proposing while still converging must fail closed
  case propose_evolution(s0, mut, 1500) {
    Error(_msg) -> {
      // Must state that system is converging
      True |> should.equal(True)
    }
    Ok(_) -> panic as "Expected self-evolution proposal to be blocked before homeostasis"
  }
}

pub fn three_of_four_evolution_ratification_test() {
  // Reach equilibrium first
  let s0 = init_homeostasis_system(1000)
  let s1 = ingest_telemetry(s0, 1.0, 1.0, 2000)
  let s2 = ingest_telemetry(s1, 1.0, 1.0, 3000)
  let s3 = ingest_telemetry(s2, 1.0, 1.0, 4000)

  let mut =
    EvolutionaryMutation(
      mutation_id: "mut-fast-ooda",
      target_capability: "Autonomous Fast OODA Expansion",
      description: "Ratify Solo5 sub-15ms sandboxing into active mesh",
      expected_gain_pct: 25.0,
      risk_score: 0.02,
    )

  let assert Ok(prop0) = propose_evolution(s3, mut, 4100)
  prop0.ballot.total_eligible |> should.equal(4)
  prop0.ballot.required_approvals |> should.equal(3)
  prop0.ballot.verdict |> should.equal(VerdictPending)

  // Vote 1: AGY Approves
  let prop1 = vote_on_evolution(prop0, AgySovereign, QuorumApprove, "Lean 4 proofs verified", "sha-agy", 4200)
  prop1.ballot.verdict |> should.equal(VerdictPending)

  // Vote 2: Claude Approves
  let prop2 = vote_on_evolution(prop1, ClaudeSovereign, QuorumApprove, "Architecture deconflicted", "sha-claude", 4300)
  prop2.ballot.verdict |> should.equal(VerdictPending)

  // Vote 3: OpenRouter Approves (via local free-tier router)
  let prop3 = vote_on_evolution(prop2, OpenRouterSovereign, QuorumApprove, "Cross-model heuristic verified", "sha-or", 4400)
  case prop3.ballot.verdict {
    VerdictRatified(approvals, total) -> {
      approvals |> should.equal(3)
      total |> should.equal(3)
    }
    _ -> panic as "Expected 3-of-4 quorum to ratify proposal"
  }

  // Apply ratified evolution
  let assert Ok(evolved_state) = apply_ratified_evolution(s3, prop3)
  evolved_state.generation |> should.equal(1)
  case evolved_state.phase {
    AutonomousEvolutionActive(id, gen) -> {
      id |> should.equal("mut-fast-ooda")
      gen |> should.equal(1)
    }
    _ -> panic as "Expected phase to be AutonomousEvolutionActive"
  }
}

pub fn instability_intervention_test() {
  let s0 = init_homeostasis_system(1000)
  // Sudden health drop to 0.70 (error 0.30 > 0.20 threshold)
  let s1 = ingest_telemetry(s0, 0.70, 1.0, 2000)
  case s1.phase {
    InstabilityIntervention(_reason) -> {
      // Andon stop active
      True |> should.equal(True)
    }
    _ -> panic as "Expected InstabilityIntervention on critical divergence"
  }
}

pub fn three_of_four_evolution_rejection_test() {
  let s0 = init_homeostasis_system(1000)
  let s1 = ingest_telemetry(s0, 1.0, 1.0, 2000)
  let s2 = ingest_telemetry(s1, 1.0, 1.0, 3000)
  let s3 = ingest_telemetry(s2, 1.0, 1.0, 4000)

  let mut =
    EvolutionaryMutation(
      mutation_id: "mut-untested",
      target_capability: "Untested Dependency",
      description: "Proposed change without formal proof",
      expected_gain_pct: 5.0,
      risk_score: 0.85,
    )

  let assert Ok(prop0) = propose_evolution(s3, mut, 4100)

  // 2 Rejections out of 4 makes 3 approvals impossible
  let prop1 = vote_on_evolution(prop0, AgySovereign, QuorumReject, "Formal proof absent", "sha-agy", 4200)
  let prop2 = vote_on_evolution(prop1, ClaudeSovereign, QuorumReject, "Violates Zero-Muda", "sha-claude", 4300)

  case prop2.ballot.verdict {
    multi_agent_quorum.VerdictRejected(rejections, total) -> {
      rejections |> should.equal(2)
      total |> should.equal(2)
    }
    _ -> panic as "Expected proposal to be rejected"
  }

  case apply_ratified_evolution(s3, prop2) {
    Error(_) -> True |> should.equal(True)
    Ok(_) -> panic as "Rejected evolution must not be applied"
  }
}

pub fn homeostasis_actor_lifecycle_test() {
  let assert Ok(started) = homeostasis_evolution_engine.start_actor(1000)
  let subj = started.data

  // Send 3 observations of health 1.0 (driving towards homeostasis)
  actor.send(subj, homeostasis_evolution_engine.IngestHealthObservation(1.0, 1.0, 2000))
  actor.send(subj, homeostasis_evolution_engine.IngestHealthObservation(1.0, 1.0, 3000))
  actor.send(subj, homeostasis_evolution_engine.IngestHealthObservation(1.0, 1.0, 4000))

  // Query state
  let s3 = actor.call(subj, 1000, homeostasis_evolution_engine.GetHomeostasisState)
  case s3.phase {
    HomeostaticEquilibrium(cycles, _) -> cycles |> should.equal(3)
    _ -> panic as "Expected HomeostaticEquilibrium in actor"
  }

  // Submit mutation proposal
  let mut =
    EvolutionaryMutation(
      mutation_id: "mut-actor-01",
      target_capability: "Dynamic Swarm Router",
      description: "Auto-tune buffer sizes based on Lyapunov trends",
      expected_gain_pct: 15.0,
      risk_score: 0.01,
    )

  let assert Ok(prop0) =
    actor.call(
      subj,
      1000,
      fn(reply) { homeostasis_evolution_engine.SubmitMutationProposal(mut, 4100, reply) },
    )

  // Cast 3 approvals (AGY, Claude, OpenRouter)
  let prop1 =
    actor.call(
      subj,
      1000,
      fn(reply) {
        homeostasis_evolution_engine.CastQuorumVote(
          prop0,
          AgySovereign,
          QuorumApprove,
          "Energy verified",
          "sha-a",
          4200,
          reply,
        )
      },
    )

  let prop2 =
    actor.call(
      subj,
      1000,
      fn(reply) {
        homeostasis_evolution_engine.CastQuorumVote(
          prop1,
          ClaudeSovereign,
          QuorumApprove,
          "Zero-Muda verified",
          "sha-c",
          4300,
          reply,
        )
      },
    )

  let prop3 =
    actor.call(
      subj,
      1000,
      fn(reply) {
        homeostasis_evolution_engine.CastQuorumVote(
          prop2,
          OpenRouterSovereign,
          QuorumApprove,
          "Consensus complete",
          "sha-or",
          4400,
          reply,
        )
      },
    )

  // Apply ratified mutation
  let assert Ok(evolved) =
    actor.call(
      subj,
      1000,
      fn(reply) { homeostasis_evolution_engine.ApplyMutationEvolution(prop3, reply) },
    )

  evolved.generation |> should.equal(1)
  case evolved.phase {
    AutonomousEvolutionActive(id, gen) -> {
      id |> should.equal("mut-actor-01")
      gen |> should.equal(1)
    }
    _ -> panic as "Expected AutonomousEvolutionActive after applying mutation"
  }
}

pub fn physiological_homeostasis_gating_test() {
  let s0 = init_homeostasis_system(1000)
  // Bring PID to equilibrium
  let s1 = ingest_telemetry(s0, 1.0, 1.0, 2000)
  let s2 = ingest_telemetry(s1, 1.0, 1.0, 3000)
  let s3 = ingest_telemetry(s2, 1.0, 1.0, 4000)

  // Ingest critical physiological stress (CPU at 98%)
  let s4 =
    homeostasis_evolution_engine.ingest_physiological_telemetry(
      s3,
      [#(CpuUtilization, 98.0)],
      1.0,
      5000,
    )

  // System should fail closed into InstabilityIntervention Andon stop
  case s4.phase {
    InstabilityIntervention(_) -> True |> should.equal(True)
    _ -> panic as "Expected InstabilityIntervention on critical physiological stress"
  }

  // Evolutionary proposal must be blocked
  let mut =
    EvolutionaryMutation(
      mutation_id: "mut-blocked-by-phys",
      target_capability: "Speculative Engine",
      description: "Should fail closed",
      expected_gain_pct: 10.0,
      risk_score: 0.1,
    )

  case propose_evolution(s4, mut, 5100) {
    Error(_) -> True |> should.equal(True)
    Ok(_) -> panic as "Expected propose_evolution to fail closed under critical stress"
  }
}

