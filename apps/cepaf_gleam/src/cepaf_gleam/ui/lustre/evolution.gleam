//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/lustre/evolution</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-EVO-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre MVU component for the Evolution page.
//// Tracks Shannon entropy, morphogenic cycles, mutation rate, and fitness.

import gleam/option.{type Option, None, Some}

pub type EvolutionModel {
  EvolutionModel(
    entropy: Float,
    cycle_count: Int,
    mutation_rate: Float,
    fitness_score: Float,
    generation: Int,
    last_cycle: String,
    loading: Bool,
    error: Option(String),
  )
}

pub type EvolutionMsg {
  MetricsLoaded(
    entropy: Float,
    cycles: Int,
    mutation: Float,
    fitness: Float,
    gen: Int,
    timestamp: String,
  )
  CycleCompleted(new_entropy: Float, new_fitness: Float)
  RefreshEvolution
  ErrorReceived(String)
}

pub fn init() -> EvolutionModel {
  EvolutionModel(
    entropy: 0.0,
    cycle_count: 0,
    mutation_rate: 0.0,
    fitness_score: 0.0,
    generation: 0,
    last_cycle: "",
    loading: True,
    error: None,
  )
}

pub fn update(model: EvolutionModel, msg: EvolutionMsg) -> EvolutionModel {
  case msg {
    MetricsLoaded(h, c, m, f, g, ts) ->
      EvolutionModel(
        entropy: h,
        cycle_count: c,
        mutation_rate: m,
        fitness_score: f,
        generation: g,
        last_cycle: ts,
        loading: False,
        error: None,
      )
    CycleCompleted(h, f) ->
      EvolutionModel(
        ..model,
        entropy: h,
        fitness_score: f,
        cycle_count: model.cycle_count + 1,
        generation: model.generation + 1,
      )
    RefreshEvolution -> EvolutionModel(..model, loading: True)
    ErrorReceived(e) -> EvolutionModel(..model, error: Some(e), loading: False)
  }
}

pub fn entropy_healthy(model: EvolutionModel) -> Bool {
  model.entropy >=. 2.5
}
