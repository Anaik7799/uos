//// SC-HIVE-TIME-001. Physical time and Lamport order are different domains.
//// Clocks ≙ (fresh bounded UTC evidence, monotonic continuity, causal counter).
//// This pure observer never sets a host clock or grants action authority.
//// tick(n) = n+1; receive(n,r) = max(n,r)+1. Persist the counter across restarts.

import gleam/int
import gleam/result
import gleam/string

pub type Domain {
  Domain(host_id: String, boot_id: String)
}

pub type Reading {
  Reading(domain: Domain, utc_us: Int, boot_us: Int)
}

pub type Evidence {
  Evidence(
    reading: Reading,
    source_ref: String,
    synchronized: Bool,
    offset_us: Int,
    uncertainty_us: Int,
    counter_floor: Int,
  )
}

pub type Policy {
  Policy(
    max_offset_us: Int,
    max_uncertainty_us: Int,
    max_evidence_age_us: Int,
    max_clock_step_us: Int,
    max_future_us: Int,
  )
}

pub const strict_policy = Policy(2_000_000, 500_000, 120_000_000, 2_000_000, 0)

// Interoperable JSON integer range. Exhaustion requires explicit epoch migration,
// never wraparound, silent reset, or conversion to floating point.
pub const max_counter = 9_007_199_254_740_991

pub type Failure {
  InvalidPolicy
  InvalidReading
  MissingEvidence
  Unsynchronized
  ClockDomainChanged
  FutureEvidence
  StaleEvidence
  ExcessiveOffset
  ExcessiveUncertainty
  PhysicalTimeRegressed
  PhysicalMonotonicDivergence
  InvalidCounter
  CounterExhausted
  CounterBelowDurableFloor
  CausalOrderViolation
  FutureEvent
}

pub fn failure_label(failure: Failure) -> String {
  case failure {
    InvalidPolicy -> "invalid_clock_policy"
    InvalidReading -> "invalid_clock_reading"
    MissingEvidence -> "missing_clock_evidence"
    Unsynchronized -> "ntp_unsynchronized"
    ClockDomainChanged -> "host_or_boot_changed"
    FutureEvidence -> "clock_evidence_is_from_the_future"
    StaleEvidence -> "clock_evidence_expired"
    ExcessiveOffset -> "ntp_offset_exceeds_bound"
    ExcessiveUncertainty -> "ntp_uncertainty_exceeds_bound"
    PhysicalTimeRegressed -> "wall_clock_regressed"
    PhysicalMonotonicDivergence -> "wall_and_monotonic_elapsed_times_diverged"
    InvalidCounter -> "invalid_lamport_counter"
    CounterExhausted -> "lamport_counter_exhausted"
    CounterBelowDurableFloor -> "lamport_counter_below_durable_floor"
    CausalOrderViolation -> "lamport_order_violates_causal_link"
    FutureEvent -> "event_ahead_of_observed_utc_bound"
  }
}

fn valid_reading(reading: Reading) -> Bool {
  string.trim(reading.domain.host_id) != ""
  && string.trim(reading.domain.boot_id) != ""
  && reading.utc_us >= 0
  && reading.boot_us >= 0
}

fn valid_policy(policy: Policy) -> Bool {
  policy.max_offset_us >= 0
  && policy.max_uncertainty_us >= 0
  && policy.max_evidence_age_us > 0
  && policy.max_clock_step_us >= 0
  && policy.max_future_us >= 0
}

fn magnitude(value: Int) -> Int {
  case value < 0 {
    True -> 0 - value
    False -> value
  }
}

pub fn continuity(
  earlier: Reading,
  later: Reading,
  policy: Policy,
) -> Result(Nil, Failure) {
  case valid_policy(policy), valid_reading(earlier) && valid_reading(later) {
    False, _ -> Error(InvalidPolicy)
    _, False -> Error(InvalidReading)
    True, True ->
      case earlier.domain == later.domain {
        False -> Error(ClockDomainChanged)
        True ->
          case later.boot_us < earlier.boot_us {
            True -> Error(FutureEvidence)
            False ->
              case later.utc_us < earlier.utc_us {
                True -> Error(PhysicalTimeRegressed)
                False ->
                  case
                    magnitude(
                      { later.utc_us - earlier.utc_us }
                      - { later.boot_us - earlier.boot_us },
                    )
                    > policy.max_clock_step_us
                  {
                    True -> Error(PhysicalMonotonicDivergence)
                    False -> Ok(Nil)
                  }
              }
          }
      }
  }
}

pub fn validate(
  evidence: Evidence,
  current: Reading,
  policy: Policy,
) -> Result(Nil, Failure) {
  use _ <- result.try(continuity(evidence.reading, current, policy))
  case string.trim(evidence.source_ref) == "" {
    True -> Error(MissingEvidence)
    False ->
      case evidence.synchronized {
        False -> Error(Unsynchronized)
        True ->
          case
            current.boot_us - evidence.reading.boot_us
            > policy.max_evidence_age_us
          {
            True -> Error(StaleEvidence)
            False ->
              case magnitude(evidence.offset_us) > policy.max_offset_us {
                True -> Error(ExcessiveOffset)
                False ->
                  case
                    evidence.uncertainty_us < 0
                    || evidence.uncertainty_us > policy.max_uncertainty_us
                  {
                    True -> Error(ExcessiveUncertainty)
                    False ->
                      case
                        evidence.counter_floor < 0
                        || evidence.counter_floor > max_counter
                      {
                        True -> Error(InvalidCounter)
                        False -> Ok(Nil)
                      }
                  }
              }
          }
      }
  }
}

pub fn tick(counter: Int) -> Result(Int, Failure) {
  case counter < 0 || counter > max_counter {
    True -> Error(InvalidCounter)
    False ->
      case counter == max_counter {
        True -> Error(CounterExhausted)
        False -> Ok(counter + 1)
      }
  }
}

pub fn receive(local: Int, remote: Int) -> Result(Int, Failure) {
  case local < 0 || remote < 0 || local > max_counter || remote > max_counter {
    True -> Error(InvalidCounter)
    False -> tick(int.max(local, remote))
  }
}

/// Check a restored durable counter before a timestamped local event is emitted.
/// Evidence.counter_floor must come from the coordinator's durable journal,
/// not a remote message or a model report.
pub fn checked_tick(
  local: Int,
  evidence: Evidence,
  current: Reading,
  policy: Policy,
) -> Result(Int, Failure) {
  use _ <- result.try(validate(evidence, current, policy))
  case local < evidence.counter_floor {
    True -> Error(CounterBelowDurableFloor)
    False -> tick(local)
  }
}

/// These counters are comparable because there is an explicit causal edge.
/// Equal or reversed counters on unrelated events are not evidence of a fault.
pub fn causal_edge(parent: Int, child: Int) -> Result(Nil, Failure) {
  case parent < 0 || child < 0 || parent > max_counter || child > max_counter {
    True -> Error(InvalidCounter)
    False ->
      case child > parent {
        True -> Ok(Nil)
        False -> Error(CausalOrderViolation)
      }
  }
}

pub fn event_time(
  utc_us: Int,
  current: Reading,
  evidence: Evidence,
  policy: Policy,
) -> Result(Nil, Failure) {
  use _ <- result.try(validate(evidence, current, policy))
  case utc_us < 0 {
    True -> Error(InvalidReading)
    False ->
      case
        utc_us > current.utc_us + evidence.uncertainty_us + policy.max_future_us
      {
        True -> Error(FutureEvent)
        False -> Ok(Nil)
      }
  }
}
