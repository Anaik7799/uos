//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/chaos/apoptosis</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ULTRA-001, SC-SIL4-007</stamp-controls></compliance>
//// </c3i-module>
////
//// Continuous Stochastic Apoptosis — mathematically derived container lifespans.

import gleam/float
import gleam/int
import gleam/list

pub type ApoptosisConfig {
  ApoptosisConfig(
    mean_lifespan_hours: Float,
    variance_hours: Float,
    min_lifespan_hours: Float,
    max_concurrent_deaths: Int,
    excluded: List(String),
  )
}

pub type ContainerLifespan {
  ContainerLifespan(
    container: String,
    born_at: Int,
    scheduled_death: Int,
    actual_death: Int,
    resurrections: Int,
    is_alive: Bool,
  )
}

pub type ApoptosisState {
  ApoptosisState(
    config: ApoptosisConfig,
    lifespans: List(ContainerLifespan),
    total_deaths: Int,
    total_resurrections: Int,
    mean_recovery_ms: Int,
  )
}

/// Default config: 72h median, excluded db-prod + zenoh-router
pub fn default_config() -> ApoptosisConfig {
  ApoptosisConfig(
    mean_lifespan_hours: 72.0,
    variance_hours: 24.0,
    min_lifespan_hours: 1.0,
    max_concurrent_deaths: 1,
    excluded: ["indrajaal-db-prod", "zenoh-router"],
  )
}

pub fn init() -> ApoptosisState {
  ApoptosisState(
    config: default_config(),
    lifespans: [],
    total_deaths: 0,
    total_resurrections: 0,
    mean_recovery_ms: 0,
  )
}

/// Register a container with its birth time
pub fn register(
  state: ApoptosisState,
  container: String,
  born_at: Int,
) -> ApoptosisState {
  let lifespan_ms =
    float.truncate(state.config.mean_lifespan_hours *. 3600.0 *. 1000.0)
  let lifespan =
    ContainerLifespan(
      container: container,
      born_at: born_at,
      scheduled_death: born_at + lifespan_ms,
      actual_death: 0,
      resurrections: 0,
      is_alive: True,
    )
  ApoptosisState(..state, lifespans: [lifespan, ..state.lifespans])
}

/// Check which containers should die at the given timestamp
pub fn due_for_death(state: ApoptosisState, now: Int) -> List(String) {
  state.lifespans
  |> list.filter(fn(l) {
    l.is_alive
    && now >= l.scheduled_death
    && !list.contains(state.config.excluded, l.container)
  })
  |> list.take(state.config.max_concurrent_deaths)
  |> list.map(fn(l) { l.container })
}

/// Record a container death
pub fn record_death(
  state: ApoptosisState,
  container: String,
  death_time: Int,
) -> ApoptosisState {
  let updated =
    list.map(state.lifespans, fn(l) {
      case l.container == container {
        True ->
          ContainerLifespan(..l, actual_death: death_time, is_alive: False)
        False -> l
      }
    })
  ApoptosisState(
    ..state,
    lifespans: updated,
    total_deaths: state.total_deaths + 1,
  )
}

/// Record a resurrection (container restarted after death)
pub fn record_resurrection(
  state: ApoptosisState,
  container: String,
  rebirth_time: Int,
) -> ApoptosisState {
  let lifespan_ms =
    float.truncate(state.config.mean_lifespan_hours *. 3600.0 *. 1000.0)
  let updated =
    list.map(state.lifespans, fn(l) {
      case l.container == container && !l.is_alive {
        True ->
          ContainerLifespan(
            ..l,
            born_at: rebirth_time,
            scheduled_death: rebirth_time + lifespan_ms,
            is_alive: True,
            resurrections: l.resurrections + 1,
          )
        False -> l
      }
    })
  ApoptosisState(
    ..state,
    lifespans: updated,
    total_resurrections: state.total_resurrections + 1,
  )
}

/// Anti-fragility metric: MTTR under stress should be < MTTR calm
pub fn anti_fragility_score(state: ApoptosisState) -> Float {
  case state.total_resurrections > 0 {
    True -> int.to_float(state.mean_recovery_ms) /. 30_000.0
    False -> 1.0
  }
}
