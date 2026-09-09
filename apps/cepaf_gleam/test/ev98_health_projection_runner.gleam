import cepaf_gleam/crdt/delta_state.{new_lww_register}
import cepaf_gleam/crdt/health_bridge.{NodeHealthTelemetry, merge_health_maps}
import gleam/int
import gleam/io
import gleam/list

type Projection {
  Projection(
    label: String,
    left_sample: Int,
    left_logical: Int,
    left_writer: String,
    left_payload: Int,
    right_sample: Int,
    right_logical: Int,
    right_writer: String,
    right_payload: Int,
  )
}

fn register(sample, logical, writer, payload) {
  let telemetry =
    NodeHealthTelemetry(
      node: "target",
      health_score: 0.0,
      lyapunov_exponent: 0.0,
      is_stable: True,
      breaker_state: int.to_string(payload),
      sample_epoch_us: sample,
    )
  new_lww_register(telemetry, logical, writer)
}

fn quoted(value: String) -> String {
  "\"" <> value <> "\""
}

fn emit(projection: Projection) {
  let Projection(label, ls, ll, lw, lp, rs, rl, rw, rp) = projection
  let merged =
    merge_health_maps([#("target", register(ls, ll, lw, lp))], [
      #("target", register(rs, rl, rw, rp)),
    ])
  let assert [#(_, winner)] = merged
  io.println(
    "{\"label\":"
    <> quoted(label)
    <> ",\"winner\":{\"sample\":"
    <> int.to_string(winner.value.sample_epoch_us)
    <> ",\"logical\":"
    <> int.to_string(winner.timestamp_us)
    <> ",\"writer\":"
    <> quoted(winner.writer)
    <> ",\"payload\":"
    <> quoted(winner.value.breaker_state)
    <> "}}",
  )
}

pub fn main() {
  [
    Projection("sample_dominates", 2, 0, "a", 0, 1, 2, "z", 1),
    Projection("logical_tiebreak", 1, 2, "a", 0, 1, 1, "z", 1),
    Projection("writer_tiebreak", 1, 1, "z", 0, 1, 1, "a", 1),
    Projection("exact_replay", 1, 1, "a", 0, 1, 1, "a", 0),
  ]
  |> list.each(emit)
}
