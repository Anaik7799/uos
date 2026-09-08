//// apps/cepaf_gleam/src/cepaf_gleam/intent/denotational.gleam
//// Denotational Intent Monadic Functor and Lattice Semantics (Pure Gleam)
//// Contract Reference: SC-DENOTATIONAL-INTENT-001, SC-INTENT-ATLAS-001

import gleam/list

pub type LatticeState {
  LatticeState(
    version: Int,
    trace_coords: List(Float),
    active_containers: List(String),
    zenoh_topics: List(String),
    is_bottom: Bool,
    error_reason: String,
  )
}

pub type Intent {
  Intent(
    authority: String,
    target_drive_serial: String,
    criticality: String,
    guardian_approved: Bool,
    delta_coord: Float,
    add_containers: List(String),
    add_topics: List(String),
  )
}

pub const hard_denied_system_os_serial = "25503L801736"
pub const admitted_ev_ceiling = 93

pub fn bottom(reason: String) -> LatticeState {
  LatticeState(
    version: 0,
    trace_coords: [],
    active_containers: [],
    zenoh_topics: [],
    is_bottom: True,
    error_reason: reason,
  )
}

pub fn initial_state() -> LatticeState {
  let initial_coords = list.repeat(1.0, 13)
  LatticeState(
    version: 1,
    trace_coords: initial_coords,
    active_containers: ["c3i-core-broker", "c3i-sentinel"],
    zenoh_topics: ["indrajaal/l0/const/**", "indrajaal/otel/spans/**"],
    is_bottom: False,
    error_reason: "",
  )
}

/// Denotational evaluation [[ I ]] : Sigma -> Sigma U {bot}
pub fn evaluate(intent: Intent, state: LatticeState) -> LatticeState {
  case state.is_bottom {
    True -> state
    False -> {
      case intent.authority == "sa-plan" {
        False -> bottom("UNAUTHORIZED_AUTHORITY_NOT_SA_PLAN")
        True -> {
          case intent.target_drive_serial == hard_denied_system_os_serial {
            True -> bottom("ROOT_OS_DRIVE_MUTATION_HARD_DENIED")
            False -> {
              case intent.criticality == "DAL-A" && !intent.guardian_approved {
                True -> bottom("GUARDIAN_APPROVAL_MANDATORY_FOR_DAL_A")
                False -> {
                  let next_coords = list.map(state.trace_coords, fn(c) { c +. intent.delta_coord })
                  let next_containers = list.append(state.active_containers, intent.add_containers)
                  let next_topics = list.append(state.zenoh_topics, intent.add_topics)
                  LatticeState(
                    version: state.version + 1,
                    trace_coords: next_coords,
                    active_containers: next_containers,
                    zenoh_topics: next_topics,
                    is_bottom: False,
                    error_reason: "",
                  )
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Evaluates an intent with provenance ceiling check (Psi-7, SC-PROVENANCE-001).
pub fn evaluate_with_provenance(
  intent: Intent,
  state: LatticeState,
  ev_cycle: Int,
) -> LatticeState {
  case ev_cycle > admitted_ev_ceiling {
    True -> bottom("UNADMITTED_EV_CYCLE_ABOVE_CEILING_93")
    False -> evaluate(intent, state)
  }
}

/// Monadic unit: pure(s)
pub fn pure(state: LatticeState) -> LatticeState {
  state
}

/// Monadic bind: s >>= f
pub fn bind(state: LatticeState, f: fn(LatticeState) -> LatticeState) -> LatticeState {
  case state.is_bottom {
    True -> state
    False -> f(state)
  }
}

/// Monadic map: f <$> s
pub fn map(state: LatticeState, f: fn(LatticeState) -> LatticeState) -> LatticeState {
  bind(state, f)
}

/// Monotonic partial order: s1 <= s2
pub fn state_leq(s1: LatticeState, s2: LatticeState) -> Bool {
  case s1.is_bottom {
    True -> True
    False -> {
      case s2.is_bottom {
        True -> False
        False -> {
          s1.version <= s2.version
        }
      }
    }
  }
}
