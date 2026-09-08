//// Test and real data selection shared by every homeostasis surface.
import cepaf_gleam/ha/multi_agent_quorum as quorum
import cepaf_gleam/ha/beam_metrics
import cepaf_gleam/ha/homeostasis_evolution_engine as engine
import cepaf_gleam/ha/physiological_homeostasis as physiology
import cepaf_gleam/ui/homeostasis_status as status
import gleam/int
import gleam/list
import gleam/result

pub type Mode { RealData TestData }
pub type Scenario { Nominal Disturbance Recovery MissingSource }
pub type Selection { Selection(mode: Mode, scenario: Scenario, cycle: Int) }
pub type Review { DeniedNoAuthority Preview(within_thresholds: Bool) }

/// A preview is not an execution permit. Raising valid thresholds is monotone
/// for a fixed simulated sample; real mode is denied regardless of thresholds.
pub fn review(selection: Selection, cpu_limit: Float, memory_limit: Float) -> Result(Review, String) {
  case cpu_limit >=. 0.0 && cpu_limit <=. 1.0 && memory_limit >=. 0.0 && memory_limit <=. 1.0 {
    False -> Error("Thresholds must be finite ratios in [0,1].")
    True -> case selection.mode {
      RealData -> Ok(DeniedNoAuthority)
      TestData -> case selection.scenario {
        MissingSource -> Error("No simulated observation is available.")
        Disturbance -> Ok(Preview(0.98 <=. cpu_limit && 0.95 <=. memory_limit))
        _ -> Ok(Preview(0.35 <=. cpu_limit && 0.45 <=. memory_limit))
      }
    }
  }
}

pub fn default() -> Selection { Selection(RealData, Nominal, 1) }

pub fn parse(query: List(#(String, String))) -> Result(Selection, String) {
  let mode = list.key_find(query, "mode") |> result.unwrap("real")
  let scenario = list.key_find(query, "scenario") |> result.unwrap("nominal")
  let cycle = list.key_find(query, "cycle") |> result.unwrap("1") |> int.parse()
  case mode, scenario, cycle {
    "real", _, Ok(n) if n >= 1 && n <= 30 -> Ok(default())
    "test", "nominal", Ok(n) if n >= 1 && n <= 30 -> Ok(Selection(TestData, Nominal, n))
    "test", "disturbance", Ok(n) if n >= 1 && n <= 30 -> Ok(Selection(TestData, Disturbance, n))
    "test", "recovery", Ok(n) if n >= 1 && n <= 30 -> Ok(Selection(TestData, Recovery, n))
    "test", "unavailable", Ok(n) if n >= 1 && n <= 30 -> Ok(Selection(TestData, MissingSource, n))
    _, _, _ -> Error("mode=real|test; scenario=nominal|disturbance|recovery|unavailable; cycle=1..30")
  }
}

pub fn mode_name(mode: Mode) -> String { case mode { RealData -> "real" TestData -> "test" } }
pub fn scenario_name(scenario: Scenario) -> String {
  case scenario { Nominal -> "nominal" Disturbance -> "disturbance" Recovery -> "recovery" MissingSource -> "unavailable" }
}
pub fn query(selection: Selection) -> String {
  "mode=" <> mode_name(selection.mode) <> "&scenario=" <> scenario_name(selection.scenario) <> "&cycle=" <> int.to_string(selection.cycle)
}

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn now_nanos() -> Int
pub fn now_us() -> Int { now_nanos() / 1000 }

/// Real mode observes existing BEAM counters. No unavailable sensor is fabricated.
/// Simulation time is a deterministic model coordinate, never an observed UTC time.
pub fn read(selection: Selection) -> #(status.Snapshot, Int) {
  let now = now_us()
  case selection.mode, selection.scenario {
    RealData, _ -> #(status.runtime_observation(beam_metrics.snapshot(), now), now)
    TestData, MissingSource -> #(status.unavailable(), now)
    TestData, scenario -> {
      let #(health, cpu, memory, latency, errors) = case scenario {
        Disturbance -> #(0.35, 98.0, 95.0, 350.0, 4.0)
        _ -> #(1.0, 35.0, 45.0, 20.0, 0.01)
      }
      let start_time = case scenario { Nominal -> selection.cycle * 10_000_000 + 5_000_000 _ -> 0 }
      let model_time = start_time + selection.cycle * 1_000_000
      let seed = engine.init_homeostasis_system(0)
      let seed = case scenario == Nominal {
        True -> cycles(selection.cycle) |> list.fold(seed, fn(s, n) { evolve_model(s, n) |> result.unwrap(s) })
        False -> seed
      }
      let model = cycles(selection.cycle) |> list.fold(seed, fn(state, tick) {
        let tick_health = case scenario == Recovery && tick <= 2 { True -> 0.35 False -> health }
        engine.ingest_telemetry(state, tick_health, 1.0, start_time + tick * 1_000_000)
      })
      let phys = physiology.update_physiological_telemetry(model.physiological, [
        #(physiology.CpuUtilization, cpu), #(physiology.MemoryUtilization, memory),
        #(physiology.RequestLatency, latency), #(physiology.ErrorRate, errors),
      ], 1.0, model_time)
      #(status.simulated(engine.HomeostasisSystemState(..model, physiological: phys)), now)
    }
  }
}

/// One deterministic model evolution, with explicit simulated ballots.
/// This function cannot contact agents, write the workspace or deploy code.
pub fn evolve_model(state: engine.HomeostasisSystemState, cycle: Int) -> Result(engine.HomeostasisSystemState, String) {
  let now = cycle * 10_000_000
  let stable = cycles(3) |> list.fold(state, fn(s, tick) {
    engine.ingest_telemetry(s, 1.0, 1.0, now + tick * 1_000_000)
  })
  let mutation = engine.EvolutionaryMutation("test-cycle-" <> int.to_string(cycle), "model-only", "Deterministic fixture evolution", 1.0, 0.0)
  use proposal <- result.try(engine.propose_evolution(stable, mutation, now + 4_000_000))
  let voted = [quorum.AgySovereign, quorum.ClaudeSovereign, quorum.CodexSovereign]
    |> list.fold(proposal, fn(p, member) {
      engine.vote_on_evolution(p, member, quorum.QuorumApprove, "SIMULATED vote", "fixture-only", now + 5_000_000)
    })
  engine.apply_ratified_evolution(stable, voted)
}

pub fn cycles(count: Int) -> List(Int) {
  list.repeat(Nil,int.clamp(count,0,30)) |> list.index_map(fn(_,index){index+1})
}
