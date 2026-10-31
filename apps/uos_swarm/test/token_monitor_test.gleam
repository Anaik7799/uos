import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import uos_swarm/coord
import uos_swarm/token_monitor as m
import uos_swarm/token_monitor_input

pub fn full_capacity_replay_and_new_id_test() {
  let rows =
    int.range(0, 4096, [], fn(acc, i) { [row(int.to_string(i)), ..acc] })
  let assert Ok(mon) = m.collect(rows)
  let assert Ok(replay) = m.record(mon, row("0"))
  m.summary(replay).unique_calls |> should.equal(4096)
  m.record(mon, row("new")) |> should.equal(Error("receipt_limit"))
}

pub fn all_immutable_receipt_fields_conflict_test() {
  let r = row("a")
  let assert Some(u) = r.usage
  let assert Ok(mon) = m.collect([r])
  [
    m.Receipt(..r, usage: None, reasoning_tokens: None),
    m.Receipt(..r, reasoning_tokens: None),
    m.Receipt(..r, estimated_nanodollars: None),
    m.Receipt(..r, usage: Some(coord.Usage(..u, agent: "other"))),
    m.Receipt(..r, usage: Some(coord.Usage(..u, model: "other"))),
    m.Receipt(..r, usage: Some(coord.Usage(..u, input_tokens: 11))),
    m.Receipt(..r, usage: Some(coord.Usage(..u, output_tokens: 21))),
    m.Receipt(..r, usage: Some(coord.Usage(..u, cache_read: 31))),
    m.Receipt(..r, usage: Some(coord.Usage(..u, cache_write: 41))),
    m.Receipt(..r, usage: Some(coord.Usage(..u, tool_uses: 2))),
    m.Receipt(..r, usage: Some(coord.Usage(..u, wall_ms: 101))),
    m.Receipt(..r, estimated_nanodollars: Some(1001)),
    m.Receipt(..r, reasoning_tokens: Some(6)),
    m.Receipt(..r, failed: True),
  ]
  |> list.each(fn(changed) {
    m.record(mon, changed) |> should.equal(Error("conflicting_receipt"))
  })
}

pub fn combined_counter_bound_test() {
  let assert Some(u) = row("a").usage
  m.collect([
    m.Receipt(
      ..row("a"),
      usage: Some(coord.Usage(..u, input_tokens: 1_000_000_000)),
    ),
  ])
  |> should.equal(Error("invalid_receipt"))
}

fn row(id: String) -> m.Receipt {
  m.Receipt(
    "openrouter",
    id,
    Some(coord.Usage("pi", "deepseek", 10, 20, 30, 40, 1, 100)),
    Some(5),
    Some(1000),
    False,
  )
}

pub fn disjoint_categories_reasoning_subset_test() {
  let assert Ok(mon) = m.collect([row("a")])
  m.total(m.summary(mon)) |> should.equal(100)
  m.summary(mon).known_calls |> should.equal(1)
}

pub fn replay_is_idempotent_test() {
  let assert Ok(mon) = m.collect([row("a"), row("a")])
  m.summary(mon).unique_calls |> should.equal(1)
  m.summary(mon).estimated_nanodollars |> should.equal(1000)
}

pub fn conflict_refuses_test() {
  m.collect([row("a"), m.Receipt(..row("a"), failed: True)])
  |> should.equal(Error("conflicting_receipt"))
}

pub fn unknown_is_not_zero_test() {
  let unknown = m.Receipt("claude", "missing", None, None, None, True)
  let assert Ok(mon) = m.collect([row("a"), unknown])
  let s = m.summary(mon)
  s.unknown_calls |> should.equal(1)
  s.failed_calls |> should.equal(1)
  s.unknown_cost_calls |> should.equal(1)
  m.decide(mon, m.Policy(1000, 10)) |> should.equal(Ok(m.HoldUnknownUsage))
}

pub fn boundary_limit_stops_test() {
  let assert Ok(mon) = m.collect([row("a")])
  m.decide(mon, m.Policy(100, 10)) |> should.equal(Ok(m.StopNewCalls))
  m.decide(mon, m.Policy(101, 10))
  |> should.equal(Ok(m.ContinueWithinObservedLimit))
  m.decide(mon, m.Policy(1000, 1)) |> should.equal(Ok(m.StopNewCalls))
  m.decide(mon, m.Policy(0, 10)) |> should.equal(Error("invalid_policy"))
}

pub fn invalid_counts_and_identity_refuse_test() {
  let assert Some(u) = row("a").usage
  [
    m.Receipt(..row("a"), usage: Some(coord.Usage(..u, input_tokens: -1))),
    m.Receipt(
      ..row("a"),
      usage: Some(coord.Usage(..u, input_tokens: 1_000_000_001)),
    ),
    m.Receipt(..row("a"), request_id: "contains secret spaces"),
    m.Receipt(..row("a"), reasoning_tokens: Some(21)),
    m.Receipt(..row("a"), estimated_nanodollars: Some(-1)),
  ]
  |> list.each(fn(r) {
    m.collect([r]) |> should.equal(Error("invalid_receipt"))
  })
}

pub fn independent_list_oracle_and_order_law_test() {
  // Reference interpretation is list unique-by-ID and direct scalar arithmetic.
  int.range(1, 65, [], fn(acc, i) { [i, ..acc] })
  |> list.each(fn(n) {
    let rows =
      int.range(1, n + 1, [], fn(acc, i) { [i, ..acc] })
      |> list.map(fn(i) { row(int.to_string(i)) })
    let assert Ok(forward) = m.collect(rows)
    let assert Ok(reverse) = m.collect(list.reverse(rows))
    let assert Ok(replayed) = m.collect(list.append(rows, rows))
    m.summary(forward) |> should.equal(m.summary(reverse))
    m.summary(forward) |> should.equal(m.summary(replayed))
    m.total(m.summary(forward)) |> should.equal(n * 100)
    m.summary(forward).estimated_nanodollars |> should.equal(n * 1000)
  })
}

pub fn cross_provider_same_id_distinct_test() {
  let assert Ok(mon) =
    m.collect([row("a"), m.Receipt(..row("a"), provider: "claude")])
  m.summary(mon).unique_calls |> should.equal(2)
}

pub fn oversized_snapshot_refused_test() {
  m.collect(list.repeat(row("a"), 4097)) |> should.equal(Error("receipt_limit"))
}

pub fn strict_json_refuses_duplicate_and_depth_test() {
  token_monitor_input.parse("{\"schema_version\":1,\"schema_version\":1}")
  |> should.equal(Error("invalid_bounded_unique_key_json"))
  let left = list.repeat("[", 17) |> list.fold("", fn(a, b) { a <> b })
  let right = list.repeat("]", 17) |> list.fold("", fn(a, b) { a <> b })
  token_monitor_input.parse("{\"x\":" <> left <> "0" <> right <> "}")
  |> should.equal(Error("invalid_bounded_unique_key_json"))
}

pub fn normalized_empty_snapshot_test() {
  let assert Ok(#(mon, p)) =
    token_monitor_input.parse(
      "{\"schema_version\":1,\"receipts\":[],\"max_tokens\":10,\"max_calls\":2}",
    )
  m.decide(mon, p) |> should.equal(Ok(m.ContinueWithinObservedLimit))
}
