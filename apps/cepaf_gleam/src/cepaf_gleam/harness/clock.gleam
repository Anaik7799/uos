//// Gleam policy over observed OTP/chrony primitives. Source-reference age,
//// sample-delivery elapsed time and inter-sample continuity are distinct.

import gleam/bit_array
import gleam/int
import gleam/json
import gleam/result
import gleam/string
import gleam/list
import uos_swarm/clock_contract as contract
import uos_swarm/clock_guard

type Unit {
  Microsecond
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: Unit) -> Int

@external(erlang, "cepaf_gleam_ffi", "nanos_to_iso8601")
fn iso8601(nanos: Int) -> String

// A chrony reference timestamps the last accepted network synchronization,
// not this freshly captured receipt. Normal host polling exceeds 120 seconds
// (observed reference age 595 seconds at 2026-09-09T05:47:25Z). The finite
// development policy allows one hour of reference age only while offset and
// uncertainty remain bounded. This is not a production clock admission.
pub const reference_max_age_us = 3_600_000_000

pub const sample_max_delivery_us = 3_000_000

pub const policy = contract.Policy(
  max_offset_us: 2_000_000,
  max_uncertainty_us: 500_000,
  max_evidence_age_us: sample_max_delivery_us,
  max_clock_step_us: 2_000_000,
  max_future_us: 0,
)

pub fn reference_and_delivery_valid(
  captured_utc_us: Int,
  reference_utc_us: Int,
  delivery_us: Int,
) -> Bool {
  delivery_us >= 0 && delivery_us <= sample_max_delivery_us
  && reference_utc_us <= captured_utc_us
  && captured_utc_us - reference_utc_us <= reference_max_age_us
}

pub type Observation {
  Observation(
    sample: clock_guard.Sample,
    delivery_us: Int,
    reference_utc_us: Int,
  )
}

@external(erlang, "session_store_ffi", "clock")
fn host_clock() -> Result(#(String, String, Int, Int), String)

@external(erlang, "ecology_capability_ffi", "run_bounded")
fn run_bounded(
  path: String,
  args: List(String),
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

fn reading() -> Result(contract.Reading, String) {
  use raw <- result.try(host_clock())
  Ok(contract.Reading(contract.Domain(raw.0, raw.1), raw.3, raw.2))
}

pub fn observe() -> Result(Observation, String) {
  let start = monotonic_time(Microsecond)
  use captured <- result.try(reading())
  use output <- result.try(
    case run_bounded("/usr/bin/chronyc", ["-c", "tracking"], 2000) {
      Ok(#(0, bytes)) ->
        bit_array.to_string(bytes) |> result.map_error(fn(_) { "clock_utf8" })
      _ -> Error("bounded_clock_sampler_failed")
    },
  )
  use #(reference, offset, uncertainty, source) <- result.try(
    clock_guard.parse_tracking(output),
  )
  use current <- result.try(reading())
  let sample =
    clock_guard.Sample(
      contract.Evidence(captured, source, True, offset, uncertainty, 0),
      current,
    )
  let elapsed = monotonic_time(Microsecond) - start
  case reference_and_delivery_valid(captured.utc_us, reference, elapsed) {
    False -> Error("clock_sample_delivery_expired")
    True -> {
      use _ <- result.try(
        contract.validate(
          sample.evidence,
          sample.observed,
          policy,
        )
        |> result.map_error(contract.failure_label),
      )
      Ok(Observation(sample, elapsed, reference))
    }
  }
}

pub fn utc(observation: Observation) -> String {
  iso8601(observation.sample.observed.utc_us * 1000)
}

pub fn canonical_utc(observation: Observation) -> String {
  case utc(observation) |> string.split(".") |> list.first {
    Ok(whole) -> whole <> "Z"
    Error(_) -> ""
  }
}

pub fn continuity(
  before: Observation,
  after: Observation,
) -> Result(Nil, String) {
  contract.continuity(before.sample.observed, after.sample.observed, policy)
  |> result.map_error(contract.failure_label)
}

pub fn to_json(value: Observation) -> json.Json {
  let sample = value.sample
  json.object([
    #("utc", json.string(utc(value))),
    #("utc_us", json.string(int.to_string(sample.observed.utc_us))),
    #("boot_us", json.string(int.to_string(sample.observed.boot_us))),
    #("host_id", json.string(sample.observed.domain.host_id)),
    #("boot_id", json.string(sample.observed.domain.boot_id)),
    #("offset_us", json.int(sample.evidence.offset_us)),
    #("uncertainty_us", json.int(sample.evidence.uncertainty_us)),
    #(
      "reference_age_us",
      json.int(sample.observed.utc_us - value.reference_utc_us),
    ),
    #(
      "receipt_age_us",
      json.int(sample.observed.boot_us - sample.evidence.reading.boot_us),
    ),
    #("delivery_us", json.int(value.delivery_us)),
    #("source", json.string(sample.evidence.source_ref)),
    #("reference_max_age_us", json.int(reference_max_age_us)),
    #("sample_max_delivery_us", json.int(sample_max_delivery_us)),
    #("authority", json.string("OBSERVATION_ONLY")),
  ])
}
