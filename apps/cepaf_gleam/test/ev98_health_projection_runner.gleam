import cepaf_gleam/crdt/delta_state.{type LWWRegister, new_lww_register}
import cepaf_gleam/crdt/health_bridge.{type NodeHealthTelemetry, NodeHealthTelemetry, merge_health_maps}
import gleam/int
import gleam/io
import gleam/list

// The OCaml verifier consumes this complete, line-delimited projection. It
// executes the landed Gleam merge rather than copying its ordering branch.
type Input {
  Input(sample: Int, logical: Int, writer_rank: Int, payload: Int)
}

fn writer(rank: Int) -> String { "w" <> int.to_string(rank) }

fn register(node: String, input: Input) {
  let Input(sample, logical, rank, payload) = input
  let telemetry =
    NodeHealthTelemetry(
      node: node,
      health_score: 0.0,
      lyapunov_exponent: 0.0,
      is_stable: True,
      breaker_state: int.to_string(payload),
      sample_epoch_us: sample,
    )
  new_lww_register(telemetry, logical, writer(rank))
}

fn quoted(value: String) -> String {
  "\"" <> value <> "\""
}

fn input_json(input: Input) -> String {
  let Input(sample, logical, rank, payload) = input
  "{\"sample\":"
  <> int.to_string(sample)
  <> ",\"logical\":"
  <> int.to_string(logical)
  <> ",\"writer\":"
  <> quoted(writer(rank))
  <> ",\"payload\":"
  <> int.to_string(payload)
  <> "}"
}

fn winner_json(value: LWWRegister(NodeHealthTelemetry)) -> String {
  "{\"sample\":"
  <> int.to_string(value.value.sample_epoch_us)
  <> ",\"logical\":"
  <> int.to_string(value.timestamp_us)
  <> ",\"writer\":"
  <> quoted(value.writer)
  <> ",\"payload\":"
  <> value.value.breaker_state
  <> "}"
}

fn well_formed(left: Input, right: Input) -> Bool {
  let Input(ls, ll, lw, lp) = left
  let Input(rs, rl, rw, rp) = right
  ls != rs || ll != rl || lw != rw || lp == rp
}

fn emit_pair(left: Input, right: Input) {
  let merged =
    merge_health_maps([#("target", register("target", left))], [
      #("target", register("target", right)),
    ])
  let assert [#(_, winner)] = merged
  io.println(
    "{\"kind\":\"pair\",\"node\":\"target\",\"left\":"
    <> input_json(left)
    <> ",\"right\":"
    <> input_json(right)
    <> ",\"winner\":"
    <> winner_json(winner)
    <> "}",
  )
}

fn emit_pairs(left: Input, inputs: List(Input)) {
  inputs
  |> list.each(fn(right) {
    case well_formed(left, right) {
      True -> emit_pair(left, right)
      False -> Nil
    }
  })
}

fn records() -> List(Input) {
  [0, 1, 2]
  |> list.flat_map(fn(sample) {
    [0, 1, 2]
    |> list.flat_map(fn(logical) {
      [0, 1, 2]
      |> list.flat_map(fn(writer_rank) {
        [Input(sample, logical, writer_rank, 0), Input(sample, logical, writer_rank, 1)]
      })
    })
  })
}

fn emit_malformed_collision() {
  let zero = Input(1, 1, 1, 0)
  let one = Input(1, 1, 1, 1)
  let assert [#(_, forward)] = merge_health_maps([#("target", register("target", zero))], [#("target", register("target", one))])
  let assert [#(_, reverse)] = merge_health_maps([#("target", register("target", one))], [#("target", register("target", zero))])
  io.println("{\"kind\":\"malformed_collision\",\"forward\":" <> winner_json(forward) <> ",\"reverse\":" <> winner_json(reverse) <> "}")
}

fn emit_raw_map_order() {
  let value = Input(0, 0, 0, 0)
  let assert [#(forward_first, _), #(forward_second, _)] = merge_health_maps([#("a", register("a", value))], [#("b", register("b", value))])
  let assert [#(reverse_first, _), #(reverse_second, _)] = merge_health_maps([#("b", register("b", value))], [#("a", register("a", value))])
  io.println("{\"kind\":\"raw_map_order\",\"forward\":[" <> quoted(forward_first) <> "," <> quoted(forward_second) <> "],\"reverse\":[" <> quoted(reverse_first) <> "," <> quoted(reverse_second) <> "],\"canonical\":[\"a\",\"b\"]}")
}

pub fn main() {
  let inputs = records()
  io.println("{\"kind\":\"header\",\"records\":54,\"well_formed_pairs\":2862}")
  inputs |> list.each(fn(left) { emit_pairs(left, inputs) })
  emit_malformed_collision()
  emit_raw_map_order()
}
