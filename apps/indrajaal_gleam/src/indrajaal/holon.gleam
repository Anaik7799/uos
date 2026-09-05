import gleam/option.{type Option}

pub type HolonLifecycle {
  Discovered
  Classified
  Mapped
  Initialized
  Active
  Degraded
  Quarantined
  Terminated
}

pub type HolonCoord {
  HolonCoord(
    id: String,
    parent_id: Option(String),
    generation: Int,
    lease_token: String,
  )
}

pub type HolonCyclePhase {
  Observe
  Intent
  Decide
  Act
  Evidence
  Evolve
}

pub type HolonState {
  HolonState(
    coord: HolonCoord,
    lifecycle: HolonLifecycle,
    current_phase: HolonCyclePhase,
    health_score: Float,
  )
}

pub type HolonMessage {
  AdvancePhase(next_phase: HolonCyclePhase, generation: Int)
  ReportHealth(reply_with: fn(Float) -> Nil)
  FencingReject(reason: String)
}

pub fn new_holon(id: String, parent: Option(String)) -> HolonState {
  HolonState(
    coord: HolonCoord(
      id: id,
      parent_id: parent,
      generation: 1,
      lease_token: id <> "-gen-1",
    ),
    lifecycle: Initialized,
    current_phase: Observe,
    health_score: 1.0,
  )
}

pub fn step_cycle(state: HolonState, phase: HolonCyclePhase, gen: Int) -> Result(HolonState, String) {
  case gen == state.coord.generation {
    True -> {
      Ok(HolonState(
        ..state,
        lifecycle: Active,
        current_phase: phase,
      ))
    }
    False -> Error("FENCING_REJECT: Stale lease generation")
  }
}
