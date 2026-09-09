//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/homeostasis_evolution_engine</module>
////     <fsharp-lineage>Pure Gleam Cybernetic Homeostasis & Quorum Evolution Engine</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L2_HEALTH</layer>
////     <layer>L5_COGNITIVE</layer>
////     <layer>L7_FEDERATION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-SIL6-001, SC-SOV-001, SC-MUDA-001, SC-JIDOKA-001, SC-HA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// CYBERNETIC SWARM HOMEOSTASIS & 4-PARTY QUORUM EVOLUTION ENGINE
//// সমस्थितिरेव गतिः — Homeostasis itself is the foundation of evolution.
////
//// Regulates system state toward homeostatic equilibrium via closed-loop PID &
//// Lyapunov stability damping. Once homeostasis is established, empowers the
//// 4-party sovereign quorum (AGY ⊕ Claude ⊕ Codex ⊕ OpenRouter) to evaluate,
//// ratify, and dispatch autonomous self-evolution cycles with fail-closed Andon stops.

import cepaf_gleam/ha/multi_agent_quorum.{
  type QuorumBallot, type SovereignAgent, AgySovereign, ClaudeSovereign,
  CodexSovereign, OpenRouterSovereign, ThreeOfFourSovereign, VerdictRatified,
  cast_ballot_vote, create_ballot,
}
import cepaf_gleam/ha/pareto_fitness_evaluator.{type CandidateEvaluation}
import cepaf_gleam/ha/physiological_homeostasis.{
  type PhysiologicalState, type PhysiologicalVariable,
}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result

// ---------------------------------------------------------------------------
// 1. Cybernetic PID & Lyapunov Homeostasis State
// ---------------------------------------------------------------------------

pub type HomeostasisPidConfig {
  HomeostasisPidConfig(
    kp: Float,
    ki: Float,
    kd: Float,
    setpoint: Float,
    integral_clamp: Float,
  )
}

pub fn default_pid_config() -> HomeostasisPidConfig {
  HomeostasisPidConfig(
    kp: 1.2,
    ki: 0.15,
    kd: 0.08,
    setpoint: 1.0,
    integral_clamp: 2.0,
  )
}

pub type HomeostasisMetrics {
  HomeostasisMetrics(
    measured_health: Float,
    error: Float,
    integral: Float,
    derivative: Float,
    control_output: Float,
    lyapunov_v: Float,
    lyapunov_dot_v: Float,
    stable: Bool,
    timestamp_us: Int,
  )
}

/// Compute one cybernetic PID & Lyapunov step toward homeostasis.
pub fn step_homeostasis(
  prev: HomeostasisMetrics,
  measured_health: Float,
  dt_seconds: Float,
  config: HomeostasisPidConfig,
  now_us: Int,
) -> HomeostasisMetrics {
  let dt = case dt_seconds <=. 0.0 {
    True -> 0.001
    False -> dt_seconds
  }

  let error = config.setpoint -. measured_health
  let raw_integral = prev.integral +. { error *. dt }
  let integral = case raw_integral >. config.integral_clamp {
    True -> config.integral_clamp
    False ->
      case raw_integral <. -0.0 -. config.integral_clamp {
        True -> -0.0 -. config.integral_clamp
        False -> raw_integral
      }
  }

  let derivative = { error -. prev.error } /. dt
  let p_term = config.kp *. error
  let i_term = config.ki *. integral
  let d_term = config.kd *. derivative
  let control_output = p_term +. i_term +. d_term

  // Lyapunov candidate function V(e) = 0.5 * e^2
  let lyapunov_v = 0.5 *. error *. error
  // dV/dt = e * de/dt
  let lyapunov_dot_v = error *. derivative
  // Stability condition: error is damped or zero
  let is_stable =
    lyapunov_dot_v <=. 0.0001 || float.absolute_value(error) <=. 0.05

  HomeostasisMetrics(
    measured_health: measured_health,
    error: error,
    integral: integral,
    derivative: derivative,
    control_output: control_output,
    lyapunov_v: lyapunov_v,
    lyapunov_dot_v: lyapunov_dot_v,
    stable: is_stable,
    timestamp_us: now_us,
  )
}

pub fn initial_metrics(now_us: Int) -> HomeostasisMetrics {
  HomeostasisMetrics(
    measured_health: 0.85,
    error: 0.15,
    integral: 0.0,
    derivative: 0.0,
    control_output: 0.0,
    lyapunov_v: 0.01125,
    lyapunov_dot_v: 0.0,
    stable: True,
    timestamp_us: now_us,
  )
}

// ---------------------------------------------------------------------------
// 2. Homeostasis Phases & Self-Evolution Readiness
// ---------------------------------------------------------------------------

pub type HomeostasisPhase {
  Converging(current_error: Float, lyapunov_v: Float)
  HomeostaticEquilibrium(consecutive_cycles: Int, mean_error: Float)
  AutonomousEvolutionActive(active_cycle: String, generation: Int)
  InstabilityIntervention(violation: String)
}

pub type EvolutionaryMutation {
  EvolutionaryMutation(
    mutation_id: String,
    target_capability: String,
    description: String,
    expected_gain_pct: Float,
    risk_score: Float,
  )
}

pub type EvolutionProposal {
  EvolutionProposal(
    proposal_id: String,
    mutation: EvolutionaryMutation,
    ballot: QuorumBallot,
    generation: Int,
    created_at_us: Int,
    proposal_sequence: Int,
  )
}

pub type HomeostasisSystemState {
  HomeostasisSystemState(
    pid_config: HomeostasisPidConfig,
    metrics: HomeostasisMetrics,
    physiological: PhysiologicalState,
    pareto_candidates: List(CandidateEvaluation),
    phase: HomeostasisPhase,
    consecutive_stable_ticks: Int,
    generation: Int,
    ratified_evolutions: List(EvolutionaryMutation),
    pending_proposals: List(EvolutionProposal),
    last_proposal_sequence: Int,
  )
}

pub fn init_homeostasis_system(now_us: Int) -> HomeostasisSystemState {
  HomeostasisSystemState(
    pid_config: default_pid_config(),
    metrics: initial_metrics(now_us),
    physiological: physiological_homeostasis.initial_physiological_state(now_us),
    pareto_candidates: pareto_fitness_evaluator.default_evolution_candidates(),
    phase: Converging(0.15, 0.01125),
    consecutive_stable_ticks: 0,
    generation: 0,
    ratified_evolutions: [],
    pending_proposals: [],
    last_proposal_sequence: 0,
  )
}

/// Ingest telemetry observation and advance homeostasis cybernetics.
pub fn ingest_telemetry(
  state: HomeostasisSystemState,
  measured_health: Float,
  dt_seconds: Float,
  now_us: Int,
) -> HomeostasisSystemState {
  let updated_metrics =
    step_homeostasis(
      state.metrics,
      measured_health,
      dt_seconds,
      state.pid_config,
      now_us,
    )

  let abs_err = float.absolute_value(updated_metrics.error)
  let is_in_band = abs_err <=. 0.05 && updated_metrics.stable

  let new_ticks = case is_in_band {
    True -> state.consecutive_stable_ticks + 1
    False -> 0
  }

  // Phase transition logic
  let new_phase = case True {
    _ if abs_err >. 0.2 || !state.physiological.is_homeostatic ->
      InstabilityIntervention(
        "Critical divergence from homeostasis (error > 0.20 or physiological stress)",
      )
    _ if new_ticks >= 3 ->
      case state.phase {
        AutonomousEvolutionActive(cycle, gen) ->
          AutonomousEvolutionActive(cycle, gen)
        _ ->
          HomeostaticEquilibrium(
            consecutive_cycles: new_ticks,
            mean_error: abs_err,
          )
      }
    _ ->
      Converging(
        current_error: updated_metrics.error,
        lyapunov_v: updated_metrics.lyapunov_v,
      )
  }

  HomeostasisSystemState(
    ..state,
    metrics: updated_metrics,
    phase: new_phase,
    consecutive_stable_ticks: new_ticks,
  )
}

/// Ingest multi-variable physiological telemetry (CPU, memory, latency, error rate).
pub fn ingest_physiological_telemetry(
  state: HomeostasisSystemState,
  measurements: List(#(PhysiologicalVariable, Float)),
  dt_seconds: Float,
  now_us: Int,
) -> HomeostasisSystemState {
  let updated_phys =
    physiological_homeostasis.update_physiological_telemetry(
      state.physiological,
      measurements,
      dt_seconds,
      now_us,
    )
  let next_state = HomeostasisSystemState(..state, physiological: updated_phys)
  case updated_phys.is_homeostatic {
    False ->
      HomeostasisSystemState(
        ..next_state,
        phase: InstabilityIntervention(
          "Physiological stress exceeded safe boundary: "
          <> float.to_string(updated_phys.composite_stress),
        ),
      )
    True -> next_state
  }
}

/// Update the evolutionary Pareto fitness candidate landscape.
pub fn update_pareto_candidates(
  state: HomeostasisSystemState,
  candidates: List(CandidateEvaluation),
) -> HomeostasisSystemState {
  let frontier = pareto_fitness_evaluator.compute_pareto_frontier(candidates)
  HomeostasisSystemState(..state, pareto_candidates: frontier)
}

// ---------------------------------------------------------------------------
// 3. 4-Party Sovereign Quorum Evolution Dispatch
// ---------------------------------------------------------------------------

/// Create an Evolution Proposal evaluated by the 4-Party Sovereign Quorum.
/// Fails closed if the system has not yet reached Homeostatic Equilibrium or if physiological stress is high.
/// This pure preview is not registered; submit_evolution owns that transition.
pub fn propose_evolution(
  state: HomeostasisSystemState,
  mutation: EvolutionaryMutation,
  now_us: Int,
) -> Result(EvolutionProposal, String) {
  case state.phase {
    HomeostaticEquilibrium(..) | AutonomousEvolutionActive(..) -> {
      case state.physiological.is_homeostatic {
        False ->
          Error(
            "Cannot initiate self-evolution: physiological stress ("
            <> float.to_string(state.physiological.composite_stress)
            <> ") is critical",
          )
        True -> {
          // 4-Party Quorum: AGY, Claude, Codex, OpenRouter
          let ballot =
            create_ballot(
              mutation.mutation_id,
              "Autonomous Evolution: " <> mutation.target_capability,
              ThreeOfFourSovereign,
              now_us,
            )

          Ok(EvolutionProposal(
            proposal_id: mutation.mutation_id,
            mutation: mutation,
            ballot: ballot,
            generation: state.generation + 1,
            created_at_us: now_us,
            proposal_sequence: state.last_proposal_sequence + 1,
          ))
        }
      }
    }
    Converging(err, _) ->
      Error(
        "Cannot initiate self-evolution: system converging toward homeostasis (error="
        <> float.to_string(err)
        <> ")",
      )
    InstabilityIntervention(reason) ->
      Error(
        "Cannot initiate self-evolution: Andon stop triggered ("
        <> reason
        <> ")",
      )
  }
}

/// Cast a vote from one of the 4 sovereign agents.
/// This is a pure preview; use cast_registered_vote to advance owned state.
pub fn vote_on_evolution(
  proposal: EvolutionProposal,
  agent: SovereignAgent,
  vote: multi_agent_quorum.QuorumVote,
  rationale: String,
  digest: String,
  now_us: Int,
) -> EvolutionProposal {
  let updated_ballot =
    cast_ballot_vote(proposal.ballot, agent, vote, rationale, digest, now_us)

  EvolutionProposal(..proposal, ballot: updated_ballot)
}

pub type EvolutionError {
  EvolutionCapacityReached(limit: Int)
  EvolutionNotTerminal(proposal_id: String)
  EvolutionNotReady(reason: String)
  EvolutionAlreadyApplied(proposal_id: String)
  EvolutionGenerationMismatch(expected: Int, supplied: Int)
  EvolutionUnknownProposal(proposal_id: String)
  EvolutionProposalMismatch(proposal_id: String)
  EvolutionNotRatified(verdict: multi_agent_quorum.QuorumVerdict)
}

pub fn evolution_error_to_string(error: EvolutionError) -> String {
  case error {
    EvolutionCapacityReached(limit) ->
      "Pending evolution capacity reached: " <> int.to_string(limit)
    EvolutionNotTerminal(id) ->
      "Cannot retire a pending evolution ballot: " <> id
    EvolutionNotReady(reason) -> reason
    EvolutionAlreadyApplied(id) -> "Evolution already applied: " <> id
    EvolutionGenerationMismatch(expected, supplied) ->
      "Evolution generation mismatch: expected "
      <> int.to_string(expected)
      <> ", supplied "
      <> int.to_string(supplied)
    EvolutionUnknownProposal(id) -> "Unknown evolution proposal: " <> id
    EvolutionProposalMismatch(id) ->
      "Evolution proposal differs from registered state: " <> id
    EvolutionNotRatified(_) -> "Evolution proposal is not ratified"
  }
}

/// Register a proposal in the owned state. Pure propose_evolution previews carry
/// no application authority. This model does not authenticate remote voters.
pub fn submit_evolution(
  state: HomeostasisSystemState,
  mutation: EvolutionaryMutation,
  now_us: Int,
) -> Result(#(HomeostasisSystemState, EvolutionProposal), EvolutionError) {
  use _ <- result.try(case list.length(state.pending_proposals) >= 32 {
    True -> Error(EvolutionCapacityReached(32))
    False -> Ok(Nil)
  })
  case
    list.any(state.ratified_evolutions, fn(m) {
      m.mutation_id == mutation.mutation_id
    })
  {
    True -> Error(EvolutionAlreadyApplied(mutation.mutation_id))
    False -> {
      case
        list.any(state.pending_proposals, fn(p) {
          p.proposal_id == mutation.mutation_id
        })
      {
        True -> Error(EvolutionProposalMismatch(mutation.mutation_id))
        False -> {
          use proposal <- result.try(
            propose_evolution(state, mutation, now_us)
            |> result.map_error(EvolutionNotReady),
          )
          Ok(#(
            HomeostasisSystemState(
              ..state,
              last_proposal_sequence: proposal.proposal_sequence,
              pending_proposals: [proposal, ..state.pending_proposals],
            ),
            proposal,
          ))
        }
      }
    }
  }
}

fn registered_proposal(
  state: HomeostasisSystemState,
  proposal: EvolutionProposal,
) -> Result(Nil, EvolutionError) {
  case
    list.find(state.pending_proposals, fn(p) {
      p.proposal_id == proposal.proposal_id
    })
  {
    Error(_) -> Error(EvolutionUnknownProposal(proposal.proposal_id))
    Ok(stored) if stored != proposal ->
      Error(EvolutionProposalMismatch(proposal.proposal_id))
    Ok(_) -> Ok(Nil)
  }
}

/// Vote only on the exact currently registered proposal; stale or substituted
/// snapshots cannot overwrite earlier votes or resurrect a terminal ballot.
pub fn cast_registered_vote(
  state: HomeostasisSystemState,
  proposal: EvolutionProposal,
  agent: SovereignAgent,
  vote: multi_agent_quorum.QuorumVote,
  rationale: String,
  digest: String,
  now_us: Int,
) -> Result(#(HomeostasisSystemState, EvolutionProposal), EvolutionError) {
  use _ <- result.try(registered_proposal(state, proposal))
  let updated =
    vote_on_evolution(proposal, agent, vote, rationale, digest, now_us)
  let proposals =
    list.map(state.pending_proposals, fn(p) {
      case p.proposal_id == proposal.proposal_id {
        True -> updated
        False -> p
      }
    })
  Ok(#(HomeostasisSystemState(..state, pending_proposals: proposals), updated))
}

/// Retire an exact terminal proposal, freeing an intake slot. A monotonic
/// sequence distinguishes a later submission even if all its other fields
/// match; retired snapshots cannot regain membership through resubmission.
pub fn retire_terminal_proposal(
  state: HomeostasisSystemState,
  proposal: EvolutionProposal,
) -> Result(HomeostasisSystemState, EvolutionError) {
  use _ <- result.try(registered_proposal(state, proposal))
  case proposal.ballot.verdict {
    multi_agent_quorum.VerdictPending ->
      Error(EvolutionNotTerminal(proposal.proposal_id))
    _ ->
      Ok(
        HomeostasisSystemState(
          ..state,
          pending_proposals: list.filter(state.pending_proposals, fn(p) {
            p.proposal_sequence != proposal.proposal_sequence
          }),
        ),
      )
  }
}

/// Revalidate live control state and exact owned proposal before application.
pub fn apply_ratified_evolution(
  state: HomeostasisSystemState,
  proposal: EvolutionProposal,
) -> Result(HomeostasisSystemState, EvolutionError) {
  use _ <- result.try(case state.phase {
    HomeostaticEquilibrium(..) | AutonomousEvolutionActive(..) -> {
      case
        state.physiological.is_homeostatic
        && state.metrics.stable
        && float.absolute_value(state.metrics.error) <=. 0.05
        && state.consecutive_stable_ticks >= 3
      {
        True -> Ok(Nil)
        False ->
          Error(EvolutionNotReady(
            "Current physiology or health is outside equilibrium",
          ))
      }
    }
    _ -> Error(EvolutionNotReady("Current phase does not permit evolution"))
  })
  use _ <- result.try(
    case
      list.any(state.ratified_evolutions, fn(m) {
        m.mutation_id == proposal.proposal_id
      })
    {
      True -> Error(EvolutionAlreadyApplied(proposal.proposal_id))
      False -> Ok(Nil)
    },
  )
  use _ <- result.try(case proposal.generation == state.generation + 1 {
    True -> Ok(Nil)
    False ->
      Error(EvolutionGenerationMismatch(
        state.generation + 1,
        proposal.generation,
      ))
  })
  use _ <- result.try(registered_proposal(state, proposal))
  case proposal.ballot.verdict {
    VerdictRatified(_approvals, _total) -> {
      let updated_evolutions = [proposal.mutation, ..state.ratified_evolutions]
      Ok(
        HomeostasisSystemState(
          ..state,
          phase: AutonomousEvolutionActive(
            proposal.mutation.mutation_id,
            proposal.generation,
          ),
          generation: proposal.generation,
          ratified_evolutions: updated_evolutions,
          pending_proposals: [],
        ),
      )
    }
    verdict -> Error(EvolutionNotRatified(verdict))
  }
}

/// Return all 4 sovereign agent members of the Homeostasis Evolution Quorum.
pub fn get_quorum_members() -> List(SovereignAgent) {
  [AgySovereign, ClaudeSovereign, CodexSovereign, OpenRouterSovereign]
}

// ---------------------------------------------------------------------------
// 4. OTP Actor & Supervision Interface
// ---------------------------------------------------------------------------

pub type HomeostasisActorMsg {
  IngestHealthObservation(measured: Float, dt_seconds: Float, now_us: Int)
  SubmitMutationProposal(
    mutation: EvolutionaryMutation,
    now_us: Int,
    reply_to: Subject(Result(EvolutionProposal, EvolutionError)),
  )
  CastQuorumVote(
    proposal: EvolutionProposal,
    agent: SovereignAgent,
    vote: multi_agent_quorum.QuorumVote,
    rationale: String,
    digest: String,
    now_us: Int,
    reply_to: Subject(Result(EvolutionProposal, EvolutionError)),
  )
  ApplyMutationEvolution(
    proposal: EvolutionProposal,
    reply_to: Subject(Result(HomeostasisSystemState, EvolutionError)),
  )
  RetireMutationProposal(
    proposal: EvolutionProposal,
    reply_to: Subject(Result(HomeostasisSystemState, EvolutionError)),
  )
  IngestPhysiological(
    measurements: List(#(PhysiologicalVariable, Float)),
    dt_seconds: Float,
    now_us: Int,
  )
  UpdateCandidates(candidates: List(CandidateEvaluation))
  GetHomeostasisState(reply_to: Subject(HomeostasisSystemState))
}

pub fn handle_actor_message(
  state: HomeostasisSystemState,
  msg: HomeostasisActorMsg,
) -> actor.Next(HomeostasisSystemState, HomeostasisActorMsg) {
  case msg {
    IngestHealthObservation(measured, dt_seconds, now_us) -> {
      let next_state = ingest_telemetry(state, measured, dt_seconds, now_us)
      actor.continue(next_state)
    }

    IngestPhysiological(measurements, dt_seconds, now_us) -> {
      let next_state =
        ingest_physiological_telemetry(state, measurements, dt_seconds, now_us)
      actor.continue(next_state)
    }

    UpdateCandidates(candidates) -> {
      let next_state = update_pareto_candidates(state, candidates)
      actor.continue(next_state)
    }

    SubmitMutationProposal(mutation, now_us, reply_to) -> {
      case submit_evolution(state, mutation, now_us) {
        Ok(#(next, proposal)) -> {
          process.send(reply_to, Ok(proposal))
          actor.continue(next)
        }
        Error(err) -> {
          process.send(reply_to, Error(err))
          actor.continue(state)
        }
      }
    }

    CastQuorumVote(proposal, agent, vote, rationale, digest, now_us, reply_to) -> {
      case
        cast_registered_vote(
          state,
          proposal,
          agent,
          vote,
          rationale,
          digest,
          now_us,
        )
      {
        Ok(#(next, updated)) -> {
          process.send(reply_to, Ok(updated))
          actor.continue(next)
        }
        Error(err) -> {
          process.send(reply_to, Error(err))
          actor.continue(state)
        }
      }
    }

    ApplyMutationEvolution(proposal, reply_to) -> {
      case apply_ratified_evolution(state, proposal) {
        Ok(next_state) -> {
          process.send(reply_to, Ok(next_state))
          actor.continue(next_state)
        }
        Error(err) -> {
          process.send(reply_to, Error(err))
          actor.continue(state)
        }
      }
    }

    RetireMutationProposal(proposal, reply_to) -> {
      case retire_terminal_proposal(state, proposal) {
        Ok(next_state) -> {
          process.send(reply_to, Ok(next_state))
          actor.continue(next_state)
        }
        Error(err) -> {
          process.send(reply_to, Error(err))
          actor.continue(state)
        }
      }
    }

    GetHomeostasisState(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
  }
}

/// Start an active BEAM actor running the Homeostasis Evolution Engine.
pub fn start_actor(
  now_us: Int,
) -> Result(actor.Started(Subject(HomeostasisActorMsg)), actor.StartError) {
  actor.new(init_homeostasis_system(now_us))
  |> actor.on_message(handle_actor_message)
  |> actor.start()
}

/// Supervised child specification for the OTP supervision tree.
pub fn supervised(
  now_us: Int,
) -> supervision.ChildSpecification(Subject(HomeostasisActorMsg)) {
  supervision.worker(fn() { start_actor(now_us) })
  |> supervision.restart(supervision.Permanent)
}
