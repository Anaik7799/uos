//// =============================================================================
//// [UOS-HA-15-CYCLES-RUNNER] 15 CONTINUOUS EVOLUTIONARY CYCLES RUNNER
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/ha/fifteen_cycles_runner</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL..L9_SOVEREIGNTY</layer>
////     <topology>High-Assurance Continuous Evolutionary Engine for Generations 1..15</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-HA-001, SC-SOV-001, SC-POODAVR-001, SC-CHECKLIST-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/fpp/fifteen_evolutionary_cycles.{
  type SystemEvolutionCycle, get_15_system_evolutionary_cycles,
}
import cepaf_gleam/ha/homeostasis_evolution_engine.{
  type HomeostasisSystemState, EvolutionaryMutation, apply_ratified_evolution,
  ingest_telemetry, init_homeostasis_system, submit_evolution,
  cast_registered_vote, evolution_error_to_string,
}
import cepaf_gleam/ha/multi_agent_quorum.{
  AgySovereign, ClaudeSovereign, CodexSovereign, OpenRouterSovereign,
  QuorumApprove, VerdictRatified,
}
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/result
import gleam/list
import gleam/string

pub type CycleExecutionReceipt {
  CycleExecutionReceipt(
    cycle_num: Int,
    ev_tag: String,
    title: String,
    generation_prior: Int,
    generation_posterior: Int,
    lyapunov_energy_prior: Float,
    lyapunov_energy_posterior: Float,
    quorum_ratified: Bool,
    receipt_sha256: String,
    aspects_evolved: List(Int),
  )
}

/// Drive the homeostasis engine to equilibrium by ingesting nominal telemetry.
pub fn stabilize_to_equilibrium(
  state: HomeostasisSystemState,
  base_time_us: Int,
) -> HomeostasisSystemState {
  let s1 = ingest_telemetry(state, 1.0, 1.0, base_time_us + 1000)
  let s2 = ingest_telemetry(s1, 1.0, 1.0, base_time_us + 2000)
  let s3 = ingest_telemetry(s2, 1.0, 1.0, base_time_us + 3000)
  s3
}

/// Executes a single evolutionary cycle through equilibrium, proposal, 4-party quorum, and ratification.
pub fn execute_cycle(
  state: HomeostasisSystemState,
  cycle: SystemEvolutionCycle,
  base_time_us: Int,
) -> Result(#(CycleExecutionReceipt, HomeostasisSystemState), String) {
  // 1. Telemetry convergence to homeostatic equilibrium
  let eq_state = stabilize_to_equilibrium(state, base_time_us)

  // 2. Formulate evolutionary mutation from cycle specification
  let mutation =
    EvolutionaryMutation(
      mutation_id: "mut-"
        <> cycle.ev_tag
        <> "-"
        <> int.to_string(cycle.cycle_num),
      target_capability: cycle.title,
      description: cycle.focus,
      expected_gain_pct: cycle.expected_gain_pct,
      risk_score: cycle.risk_score,
    )

  // 3. Propose evolution on the Pareto frontier
  case submit_evolution(eq_state, mutation, base_time_us + 4000) {
    Error(err) -> Error("ProposalFailed: " <> evolution_error_to_string(err))
    Ok(submitted) -> {
      // Pure simulation: these model votes are not observed sovereign approvals.
      use voted <- result.try(
        [AgySovereign, ClaudeSovereign, CodexSovereign, OpenRouterSovereign]
        |> list.try_fold(submitted, fn(pair, member) {
          cast_registered_vote(pair.0, pair.1, member, QuorumApprove,
            "SIMULATED model vote", "simulation-only", base_time_us + 4400)
        })
        |> result.map_error(evolution_error_to_string),
      )
      let p4 = voted.1

      // 5. Verify quorum ratification
      case p4.ballot.verdict {
        VerdictRatified(_approvals, _total) -> {
          let gen_prior = eq_state.generation
          let lyap_prior = eq_state.metrics.lyapunov_v

          // 6. Apply ratified mutation advancing generation
          case apply_ratified_evolution(voted.0, p4) {
            Error(err) -> Error("EvolutionApplyFailed: " <> evolution_error_to_string(err))
            Ok(next_state) -> {
              let gen_posterior = next_state.generation
              let lyap_posterior = next_state.metrics.lyapunov_v

              // 7. Cryptographic SHA-256 execution receipt
              let raw_receipt =
                "cycle:"
                <> int.to_string(cycle.cycle_num)
                <> ":tag:"
                <> cycle.ev_tag
                <> ":gen:"
                <> int.to_string(gen_posterior)
                <> ":focus:"
                <> cycle.focus

              let receipt_hash =
                crypto.hash(crypto.Sha256, <<raw_receipt:utf8>>)
                |> bit_array.base16_encode
                |> string.lowercase

              let receipt =
                CycleExecutionReceipt(
                  cycle_num: cycle.cycle_num,
                  ev_tag: cycle.ev_tag,
                  title: cycle.title,
                  generation_prior: gen_prior,
                  generation_posterior: gen_posterior,
                  lyapunov_energy_prior: lyap_prior,
                  lyapunov_energy_posterior: lyap_posterior,
                  quorum_ratified: True,
                  receipt_sha256: receipt_hash,
                  aspects_evolved: cycle.target_aspect_ids,
                )

              Ok(#(receipt, next_state))
            }
          }
        }
        _ -> Error("QuorumNotRatified for " <> cycle.ev_tag)
      }
    }
  }
}

/// Executes all 15 continuous evolutionary cycles sequentially.
/// Advances the system from Generation 0 through Generation 15.
pub fn run_all_15_cycles(
  now_us: Int,
) -> Result(#(List(CycleExecutionReceipt), HomeostasisSystemState), String) {
  let init_st = init_homeostasis_system(now_us)
  let cycles = get_15_system_evolutionary_cycles()

  list.try_fold(cycles, #([], init_st), fn(acc, cycle) {
    let #(receipts, current_st) = acc
    let cycle_time_us = now_us + cycle.cycle_num * 10_000
    case execute_cycle(current_st, cycle, cycle_time_us) {
      Error(err) -> Error(err)
      Ok(#(new_receipt, next_st)) -> {
        Ok(#(list.append(receipts, [new_receipt]), next_st))
      }
    }
  })
}
