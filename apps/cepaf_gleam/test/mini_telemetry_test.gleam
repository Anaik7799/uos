import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/mini_runtime
import cepaf_gleam/telegram/mini_telemetry as collector
import cepaf_gleam/telegram/mini_telemetry_state as state
import cepaf_gleam/telegram/types
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import mini_test_vectors as vectors

@external(erlang, "mini_telemetry_test_ffi", "kill_collector")
fn kill_collector() -> Nil

@external(erlang, "mini_telemetry_test_ffi", "wait_collector")
fn wait_collector() -> Nil

const epoch = "abcdefabcdefabcdefabcdefabcdefab"

const trace = "abcdefabcdefabcdefabcdefabcdefac"

const span = "abcdefabcdefabcd"

fn initial() {
  state.new(epoch, -1_000_000, 2000) |> should.be_ok
}

fn ticket_start(s: state.State, id: String, now: Int) {
  let assert Ok(#(next, Some(ticket))) =
    state.begin(s, types.MiniPlanning, id, span, now, 2000)
  #(next, ticket)
}

fn id(n: Int) -> String {
  "abcdefabcdefabcdefabcdefabcdef"
  <> case n < 16 {
    True -> "0"
    False -> ""
  }
  <> { int.to_base_string(n, 16) |> should.be_ok |> string.lowercase }
}

import gleam/string

pub fn epoch_and_identifier_refusal_test() {
  state.new("", 0, 2000) |> should.be_error
  state.new(epoch, 0, 0) |> should.be_error
  state.new(string.repeat("0", 32), 0, 2000) |> should.be_error
  state.begin(initial(), types.MiniPlanning, "bad", span, 0, 2000)
  |> should.be_error
  state.begin(
    initial(),
    types.MiniPlanning,
    trace,
    string.repeat("0", 16),
    0,
    2000,
  )
  |> should.be_error
}

pub fn span_lifecycle_and_clock_test() {
  let #(s, t) = ticket_start(initial(), trace, -900_000)
  state.snapshot(s).active |> should.equal(1)
  let s = state.finish(s, t, state.Observed, -850_000) |> should.be_ok
  state.snapshot(s).completed |> should.equal(1)
  let assert [observed] = state.snapshot(s).recent
  observed.duration_us |> should.equal(50_000)
  observed.started_at |> should.equal(2000)
  observed.trace_id |> should.equal(trace)
  state.finish(s, t, state.Observed, -840_000) |> should.be_error
  state.prune(s, -860_000) |> should.be_error
  state.begin(s, types.MiniPlanning, trace, span, 0, 2000) |> should.be_error
}

pub fn expired_capacity_is_reusable_test() {
  let s =
    list.fold(numbers(128), initial(), fn(s, n) {
      let #(next, _) = ticket_start(s, id(n), 0)
      next
    })
  state.snapshot(s).active |> should.equal(128)
  let assert Ok(#(s, None)) =
    state.begin(s, types.MiniPlanning, id(129), span, 1, 2000)
  state.snapshot(s).dropped |> should.equal(1)
  state.prune(s, 29_999_999)
  |> should.be_ok
  |> state.snapshot
  |> fn(s) { s.active }
  |> should.equal(128)
  let assert Ok(#(s, Some(_))) =
    state.begin(s, types.MiniPlanning, id(129), span, 30_000_000, 2030)
  state.snapshot(s).active |> should.equal(1)
  state.snapshot(s).expired |> should.equal(128)
}

pub fn retention_keeps_newest_twenty_test() {
  let s =
    list.fold(numbers(25), initial(), fn(s, n) {
      let #(s, t) = ticket_start(s, id(n), n * 100)
      state.finish(s, t, state.Unavailable, n * 100 + 10) |> should.be_ok
    })
  let snapshot = state.snapshot(s)
  snapshot.completed |> should.equal(25)
  snapshot.active |> should.equal(0)
  list.length(snapshot.recent) |> should.equal(20)
  let assert [first, ..] = snapshot.recent
  first.trace_id |> should.equal(id(25))
  let assert Ok(last) = list.last(snapshot.recent)
  last.trace_id |> should.equal(id(6))
}

pub fn epoch_change_rejects_stale_completion_test() {
  let #(_, ticket) = ticket_start(initial(), trace, 0)
  let next =
    state.new("bbcdefabcdefabcdefabcdefabcdefab", 0, 2000) |> should.be_ok
  state.finish(next, ticket, state.Observed, 10) |> should.be_error
}

pub fn safe_counter_saturation_test() {
  state.increment(state.counter_limit - 1, 1)
  |> should.equal(#(state.counter_limit, True))
  state.increment(state.counter_limit, 1)
  |> should.equal(#(state.counter_limit, True))
  state.increment(0, 128) |> should.equal(#(128, False))
}

fn success() -> api.Observation {
  api.Observed(2000, "test", dict.new())
}

fn stop(pid: process.Pid) {
  process.unlink(pid)
  process.kill(pid)
  process.sleep(30)
}

pub fn supervised_collection_auth_exception_and_self_exclusion_test() {
  let started = collector.start() |> should.be_ok
  let first = collector.read() |> should.be_ok
  collector.with_span(types.MiniPlanning, success) |> should.equal(success())
  let snapshot = collector.read() |> should.be_ok
  snapshot.completed |> should.equal(1)
  snapshot.active |> should.equal(0)
  let assert [s] = snapshot.recent
  string.byte_size(s.trace_id) |> should.equal(32)
  string.byte_size(s.span_id) |> should.equal(16)
  { s.duration_us >= 0 } |> should.be_true
  let assert api.Observed(_, _, fields) = collector.observe()
  dict.get(fields, "Scope")
  |> should.be_ok
  |> string.contains("No fleet")
  |> should.be_true
  let config =
    api.configuration(
      "synthetic-mini-test-token",
      [api.AllowedIdentity(42, None)],
      300,
    )
    |> should.be_ok
  let body = fn(data) {
    json.object([
      #("init_data", json.string(data)),
      #("path", json.string("/mini-app/telemetry")),
    ])
    |> json.to_string
  }
  api.authorize(body(vectors.wrong_user), config, 1000) |> should.be_error
  let read = api.authorize(body(vectors.valid), config, 1000) |> should.be_ok
  let _ = mini_runtime.observe(read)
  collector.read() |> should.be_ok |> fn(s) { s.completed } |> should.equal(1)
  collector.with_span(types.MiniPlanning, fn() { panic as "private exception" })
  |> should.equal(api.Unavailable("backend_exception"))
  collector.with_span(types.MiniZenohBrowser, fn() { api.Forbidden })
  |> should.equal(api.Forbidden)
  collector.read() |> should.be_ok |> fn(s) { s.completed } |> should.equal(3)
  kill_collector()
  wait_collector()
  let restarted = collector.read() |> should.be_ok
  { restarted.epoch != first.epoch } |> should.be_true
  restarted.completed |> should.equal(0)
  stop(started.pid)
  collector.read() |> should.be_error
  collector.with_span(types.MiniPlanning, success) |> should.equal(success())
}

pub fn supervisor_budget_exhaustion_does_not_kill_caller_test() {
  let started = collector.start() |> should.be_ok
  list.each([1, 2, 3], fn(_) {
    kill_collector()
    wait_collector()
  })
  kill_collector()
  process.sleep(50)
  collector.read() |> should.be_error
  process.is_alive(started.pid) |> should.be_true
  collector.with_span(types.MiniPlanning, success) |> should.equal(success())
  collector.observe() |> should.equal(api.Unavailable("telemetry_unavailable"))
  stop(started.pid)
}

fn numbers(n: Int) -> List(Int) {
  case n <= 0 {
    True -> []
    False -> list.append(numbers(n - 1), [n])
  }
}
