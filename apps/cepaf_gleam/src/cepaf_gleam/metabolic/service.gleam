// STAMP: SC-METABOLIC-002, SC-FUNC-001
// AOR: AOR-METABOLIC-002
// Criticality: Level 1 (CRITICAL) - Foundation
//
// This module implements the metabolic scaling algorithms.

import cepaf_gleam/metabolic/domain.{type MetabolicState}
import cepaf_gleam/zenoh/client.{type Session}
import gleam/float

/// Calculates the metabolic set-point based on energy availability and CPU load.
/// Ported from F# `calculateMetabolicSetPoint`.
pub fn calculate_metabolic_set_point(energy: Float, cpu_load: Float) -> Float {
  let base_rate = energy *. 0.8

  case cpu_load >. 0.95 {
    True -> base_rate *. 0.5
    False -> base_rate
  }
}

/// Updates a metabolic state with a new set-point.
pub fn update_set_point(state: MetabolicState) -> MetabolicState {
  let new_rate =
    calculate_metabolic_set_point(100.0, state.cpu_usage_percent /. 100.0)
  domain.MetabolicState(..state, metabolic_rate: new_rate)
}

/// Publishes the metabolic rate to the Zenoh mesh.
pub fn publish_metabolic_rate(
  session: Session,
  rate: Float,
) -> Result(Nil, String) {
  let payload = float.to_string(rate)
  client.put(session, "indrajaal/metabolism/setpoint", payload)
}
