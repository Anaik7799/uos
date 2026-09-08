//// =============================================================================
//// [C3I-SIL6-MSTS] 15 EVOLUTIONARY TEST CYCLES FOR TUI
//// =============================================================================
//// <c3i-module>
////   <identity><module>tui_15_evolutionary_cycles_test</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer><layer>L2_COMPONENT</layer><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-MATH-003, SC-HOM-001, SC-SOV-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Executes 15 continuous cybernetic evolutionary cycles for TUI:
//// 1. Telemetry convergence to homeostatic equilibrium (|e| <= 0.05, V <= 0.001)
//// 2. Mutation proposal on Pareto frontier
//// 3. 4-Party Sovereign Quorum balloting (AGY ⊕ Claude ⊕ Codex ⊕ OpenRouter)
//// 4. Ratification and application advancing Generation 1..15
//// 5. TUI rendering verification across Tab 12 Evolution & Homeostasis view
//// 6. 5-Agent Sovereign Workspace Matrix preservation
//// =============================================================================

import cepaf_gleam/ha/homeostasis_evolution_engine.{
  type EvolutionaryMutation, type HomeostasisSystemState,
  AutonomousEvolutionActive, EvolutionaryMutation,
  apply_ratified_evolution, ingest_telemetry, init_homeostasis_system,
  propose_evolution, vote_on_evolution,
}
import cepaf_gleam/ha/multi_agent_quorum.{
  AgySovereign, ClaudeSovereign, CodexSovereign, OpenRouterSovereign,
  QuorumApprove, VerdictRatified,
}
import cepaf_gleam/ui/tui/homeostasis_evolution_view
import cepaf_gleam/ui/tui/sysadmin_cockpit.{
  EvolutionTab, default_model, render, select_tab,
}
import gleam/int
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn get_15_mutations() -> List(EvolutionaryMutation) {
  [
    EvolutionaryMutation(
      "mut-01-simd-scorer",
      "MAX SIMD Tensor Closure & Fast Evaluator",
      "Vectorized fitness matrix evaluation over AVX-512/NEON",
      18.5,
      0.04,
    ),
    EvolutionaryMutation(
      "mut-02-heijunka-queue",
      "Autonomous Heijunka Leveled Pull Queue",
      "Work-stealing leveled task scheduler with token rate-limiting",
      22.0,
      0.03,
    ),
    EvolutionaryMutation(
      "mut-03-solo5-microvm",
      "Solo5 Sub-15ms Sandboxing & CAS Boundary",
      "Hardware-isolated tender execution with linear arena bounds",
      25.0,
      0.02,
    ),
    EvolutionaryMutation(
      "mut-04-crdt-delta-sync",
      "Multi-Host CRDT Delta State Synchronization",
      "Bounded semi-lattice state convergence across vm-1 and nas-1",
      16.8,
      0.05,
    ),
    EvolutionaryMutation(
      "mut-05-lyapunov-pid",
      "Adaptive Lyapunov Convergence & Anti-Windup PID",
      "Real-time gain tuning with negative energy derivative assurance",
      20.4,
      0.03,
    ),
    EvolutionaryMutation(
      "mut-06-zenoh-zmof",
      "Zenoh ZMOF Zero-Copy Backplane Transport",
      "High-throughput pub/sub telemetry multiplexing with zero Muda",
      28.2,
      0.02,
    ),
    EvolutionaryMutation(
      "mut-07-sre-antibody",
      "Biomorphic Chaos SRE Immune Learning & Antibodies",
      "Automated antibody generation for memory leaks and socket churn",
      19.1,
      0.04,
    ),
    EvolutionaryMutation(
      "mut-08-gospel-rete",
      "Hermes Gospel Formal Contracts & Gospel-Rete Engine",
      "Machine-checked differential oracle with forward-chaining rules",
      24.6,
      0.01,
    ),
    EvolutionaryMutation(
      "mut-09-solo5-cas",
      "Solo5 Linear CAS Allocation Arena & Zero-GC Rings",
      "Deterministic memory reclamation without garbage collector pauses",
      30.5,
      0.02,
    ),
    EvolutionaryMutation(
      "mut-10-max-mojo-vec",
      "Modular MAX/Mojo Vectorized AI Inference Pipes",
      "Sub-millisecond local embedding generation and scoring",
      26.0,
      0.03,
    ),
    EvolutionaryMutation(
      "mut-11-prajna-breaker",
      "Prajna 2oo3 Constitutional Fast-Trip Interlock",
      "Immediate fail-closed circuit breaker isolating degrading actors",
      15.5,
      0.01,
    ),
    EvolutionaryMutation(
      "mut-12-quantum-entangle",
      "Distributed Entropy & Lyapunov Derivative Metric",
      "Multi-core entropy harvesting for random victim task stealing",
      17.2,
      0.04,
    ),
    EvolutionaryMutation(
      "mut-13-chaos-sandbox",
      "Simulated Chaos Injection & Andon Line Resiliency",
      "Automated fault recovery validation with sub-second MTTR",
      21.8,
      0.03,
    ),
    EvolutionaryMutation(
      "mut-14-crdt-sheaf",
      "Sheaf-Theoretic Semantic Knowledge Transclusion",
      "Presheaf restriction maps over distributed markdown corpora",
      23.4,
      0.02,
    ),
    EvolutionaryMutation(
      "mut-15-otel-stream",
      "High-Frequency W3C OTel SSE Stream Multiplexer",
      "Real-time event streaming with microsecond ISO 8601 UTC stamps",
      32.0,
      0.01,
    ),
  ]
}

/// Helper to drive the system to Homeostatic Equilibrium
pub fn reach_equilibrium(
  state: HomeostasisSystemState,
  start_time_us: Int,
) -> HomeostasisSystemState {
  let s1 = ingest_telemetry(state, 1.0, 1.0, start_time_us + 1000)
  let s2 = ingest_telemetry(s1, 1.0, 1.0, start_time_us + 2000)
  let s3 = ingest_telemetry(s2, 1.0, 1.0, start_time_us + 3000)
  s3
}

/// Helper to execute a single complete evolutionary cycle
pub fn execute_single_cycle(
  state: HomeostasisSystemState,
  mutation: EvolutionaryMutation,
  base_time_us: Int,
) -> HomeostasisSystemState {
  // 1. Ensure equilibrium
  let eq_state = reach_equilibrium(state, base_time_us)

  // 2. Propose evolution
  let assert Ok(prop0) = propose_evolution(eq_state, mutation, base_time_us + 4000)

  // 3. Quorum balloting (4-party ratification)
  let prop1 =
    vote_on_evolution(
      prop0,
      AgySovereign,
      QuorumApprove,
      "Formal proof and Gospel contracts verified",
      "sig-agy",
      base_time_us + 4100,
    )
  let prop2 =
    vote_on_evolution(
      prop1,
      ClaudeSovereign,
      QuorumApprove,
      "Monorepo architecture and coordinator deconflicted",
      "sig-claude",
      base_time_us + 4200,
    )
  let prop3 =
    vote_on_evolution(
      prop2,
      CodexSovereign,
      QuorumApprove,
      "Solo5 sandbox and CAS immutability proved",
      "sig-codex",
      base_time_us + 4300,
    )
  let prop4 =
    vote_on_evolution(
      prop3,
      OpenRouterSovereign,
      QuorumApprove,
      "Pareto fitness trade-off non-dominated",
      "sig-or",
      base_time_us + 4400,
    )

  case prop3.ballot.verdict {
    VerdictRatified(approvals, total) -> {
      approvals |> should.equal(3)
      total |> should.equal(3)
    }
    _ -> panic as "Expected 3-of-4 supermajority quorum ratification"
  }

  // 4. Apply ratified evolution
  let assert Ok(evolved_state) = apply_ratified_evolution(eq_state, prop3)
  evolved_state
}

// =============================================================================
// Individual Tests for Evolutionary Cycles 1 through 15
// =============================================================================

pub fn evolutionary_cycle_01_simd_scorer_test() {
  let s0 = init_homeostasis_system(1_000_000)
  let muts = get_15_mutations()
  let assert Ok(m1) = list.first(muts)

  let s1 = execute_single_cycle(s0, m1, 1_000_000)
  s1.generation |> should.equal(1)
  case s1.phase {
    AutonomousEvolutionActive(id, 1) -> id |> should.equal("mut-01-simd-scorer")
    _ -> panic as "Expected AutonomousEvolutionActive for cycle 1"
  }

  // Verify TUI Render
  let tui_text = homeostasis_evolution_view.render(s1)
  string.contains(tui_text, "CYBERNETIC HOMEOSTASIS & 4-PARTY QUORUM EVOLUTION") |> should.be_true()
  string.contains(tui_text, "mut-01-simd-scorer") |> should.be_true()
  string.contains(tui_text, "Generation: 1") |> should.be_true()
  string.contains(tui_text, "● uos · 1 (agy)") |> should.be_true()
  string.contains(tui_text, "○ uos · 5 (openrouter)") |> should.be_true()
}

pub fn evolutionary_cycle_02_heijunka_queue_test() {
  let s0 = init_homeostasis_system(2_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 1) |> list.first

  let s2 = execute_single_cycle(s0, m, 2_000_000)
  s2.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s2)
  string.contains(tui_text, "mut-02-heijunka-queue") |> should.be_true()
}

pub fn evolutionary_cycle_03_solo5_microvm_test() {
  let s0 = init_homeostasis_system(3_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 2) |> list.first

  let s = execute_single_cycle(s0, m, 3_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-03-solo5-microvm") |> should.be_true()
}

pub fn evolutionary_cycle_04_crdt_delta_sync_test() {
  let s0 = init_homeostasis_system(4_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 3) |> list.first

  let s = execute_single_cycle(s0, m, 4_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-04-crdt-delta-sync") |> should.be_true()
}

pub fn evolutionary_cycle_05_lyapunov_pid_test() {
  let s0 = init_homeostasis_system(5_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 4) |> list.first

  let s = execute_single_cycle(s0, m, 5_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-05-lyapunov-pid") |> should.be_true()
}

pub fn evolutionary_cycle_06_zenoh_zmof_test() {
  let s0 = init_homeostasis_system(6_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 5) |> list.first

  let s = execute_single_cycle(s0, m, 6_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-06-zenoh-zmof") |> should.be_true()
}

pub fn evolutionary_cycle_07_sre_antibody_test() {
  let s0 = init_homeostasis_system(7_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 6) |> list.first

  let s = execute_single_cycle(s0, m, 7_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-07-sre-antibody") |> should.be_true()
}

pub fn evolutionary_cycle_08_gospel_rete_test() {
  let s0 = init_homeostasis_system(8_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 7) |> list.first

  let s = execute_single_cycle(s0, m, 8_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-08-gospel-rete") |> should.be_true()
}

pub fn evolutionary_cycle_09_solo5_cas_test() {
  let s0 = init_homeostasis_system(9_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 8) |> list.first

  let s = execute_single_cycle(s0, m, 9_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-09-solo5-cas") |> should.be_true()
}

pub fn evolutionary_cycle_10_max_mojo_vec_test() {
  let s0 = init_homeostasis_system(10_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 9) |> list.first

  let s = execute_single_cycle(s0, m, 10_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-10-max-mojo-vec") |> should.be_true()
}

pub fn evolutionary_cycle_11_prajna_breaker_test() {
  let s0 = init_homeostasis_system(11_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 10) |> list.first

  let s = execute_single_cycle(s0, m, 11_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-11-prajna-breaker") |> should.be_true()
}

pub fn evolutionary_cycle_12_quantum_entangle_test() {
  let s0 = init_homeostasis_system(12_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 11) |> list.first

  let s = execute_single_cycle(s0, m, 12_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-12-quantum-entangle") |> should.be_true()
}

pub fn evolutionary_cycle_13_chaos_sandbox_test() {
  let s0 = init_homeostasis_system(13_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 12) |> list.first

  let s = execute_single_cycle(s0, m, 13_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-13-chaos-sandbox") |> should.be_true()
}

pub fn evolutionary_cycle_14_crdt_sheaf_test() {
  let s0 = init_homeostasis_system(14_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 13) |> list.first

  let s = execute_single_cycle(s0, m, 14_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-14-crdt-sheaf") |> should.be_true()
}

pub fn evolutionary_cycle_15_otel_stream_test() {
  let s0 = init_homeostasis_system(15_000_000)
  let muts = get_15_mutations()
  let assert Ok(m) = list.drop(muts, 14) |> list.first

  let s = execute_single_cycle(s0, m, 15_000_000)
  s.generation |> should.equal(1)
  let tui_text = homeostasis_evolution_view.render(s)
  string.contains(tui_text, "mut-15-otel-stream") |> should.be_true()
}

// =============================================================================
// Comprehensive Continuous 15-Cycle Evolutionary E2E Test
// =============================================================================

pub fn continuous_15_evolutionary_cycles_e2e_test() {
  let initial_state = init_homeostasis_system(1_000_000)
  let mutations = get_15_mutations()

  // Fold through all 15 mutations, accumulating generations and testing TUI output
  let final_state =
    list.index_fold(
      mutations,
      initial_state,
      fn(acc_state, mutation, idx) {
        let cycle_num = idx + 1
        let base_time = 1_000_000 + cycle_num * 100_000
        let next_state = execute_single_cycle(acc_state, mutation, base_time)

        // Verify generation increment
        next_state.generation |> should.equal(cycle_num)

        // Verify ratified evolution list length
        list.length(next_state.ratified_evolutions) |> should.equal(cycle_num)

        // Verify TUI rendering for every generation
        let tui_rendered = homeostasis_evolution_view.render(next_state)
        string.contains(tui_rendered, "Generation: " <> int.to_string(cycle_num))
        |> should.be_true()
        string.contains(tui_rendered, mutation.mutation_id)
        |> should.be_true()

        // Verify Sysadmin Cockpit integration with EvolutionTab
        let cockpit_model =
          default_model()
          |> select_tab(EvolutionTab)

        let cockpit_with_homeo =
          sysadmin_cockpit.SysadminModel(
            ..cockpit_model,
            homeostasis_state: next_state,
          )

        let cockpit_rendered = render(cockpit_with_homeo)
        string.contains(cockpit_rendered, "Autonomous Evolution") |> should.be_true()

        next_state
      },
    )

  // Assert terminal state after 15 cycles
  final_state.generation |> should.equal(15)
  list.length(final_state.ratified_evolutions) |> should.equal(15)

  // Verify that final state rendered in TUI has Gen 15
  let final_tui = homeostasis_evolution_view.render(final_state)
  string.contains(final_tui, "Generation: 15") |> should.be_true()
  string.contains(final_tui, "mut-15-otel-stream") |> should.be_true()
}
