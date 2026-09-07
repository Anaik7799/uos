import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import prng
import uos_swarm/board
import uos_swarm/board_insights as insights
import uos_swarm/board_reader as reader
import uos_swarm/clock_contract as clock

const trace = "1234567890abcdef1234567890abcdef"

const now = 1_000_000_000

fn query() -> insights.Query {
  insights.Query(
    insights.Scope("hive-a", "tenant-a", False),
    now,
    100,
    1000,
    10,
  )
}

fn message(
  n: Int,
  kind: board.Kind,
  attrs: List(#(String, String)),
) -> board.Message {
  board.seal(
    board.Draft(
      board.Agent("worker-a", "L3", "declared-model"),
      "broadcast",
      kind,
      list.append(
        [#("tenant_id", "tenant-a"), #("candidate_ref", "rev-a")],
        attrs,
      ),
      board.no_semantics,
      board.Causality(None, []),
      Some(trace),
      None,
    ),
    "hive-a",
    now - 100 + n,
    n,
    int.to_string(n + 1) |> string.pad_start(16, "a"),
    board.genesis_digest,
  )
}

fn sample(m: board.Message) -> insights.Sample {
  insights.Sample(
    "sample-a",
    "test:structured-log",
    "hive-a",
    "tenant-a",
    m.trace_id,
    m.span_id,
    Some(m.id),
    Some("rev-a"),
    "test-service",
    now - 1,
    insights.StructuredLog,
    insights.Info,
  )
}

fn clock_sample() -> #(clock.Evidence, clock.Reading) {
  let reading = clock.Reading(clock.Domain("test-host", "boot-a"), now, 123_000)
  #(clock.Evidence(reading, "test:ntp", True, 0, 1, 0), reading)
}

fn codes(report: insights.Report) -> List(String) {
  list.map(report.findings, fn(f) { f.code })
}

pub fn exact_repeats_and_permutations_preserve_messages_test() {
  let a = message(1, board.Report, [#("task", "a")])
  let b = message(2, board.Report, [#("task", "b")])
  let assert Ok(first) = insights.analyse([a, b, a], [], query(), None)
  let assert Ok(second) = insights.analyse([b, a, a], [], query(), None)
  first |> should.equal(second)
  first.duplicate_count |> should.equal(1)
  first.messages |> should.equal([b, a])
}

pub fn conflicting_duplicate_quarantines_all_versions_test() {
  let a = message(1, board.Report, [#("task", "a")])
  let b = message(1, board.Report, [#("task", "b")])
  a.id |> should.equal(b.id)
  let assert Ok(report) = insights.analyse([a, b], [], query(), None)
  report.messages |> should.equal([])
  report.rejected_count |> should.equal(2)
  codes(report) |> list.contains("quarantined_identity") |> should.be_true
}

pub fn foreign_scope_and_unbound_legacy_are_not_discovered_test() {
  let a = message(1, board.Report, [])
  let foreign = board.Message(..a, swarm: "hive-b")
  let unbound = board.Message(..a, payload: [])
  let assert Ok(report) =
    insights.analyse(
      [foreign, unbound],
      [insights.Sample(..sample(a), tenant_id: "tenant-b")],
      query(),
      None,
    )
  report.messages |> should.equal([])
  report.agents |> should.equal([])
  report.samples |> should.equal([])
}

pub fn report_activity_never_substitutes_for_heartbeat_test() {
  let assert Ok(report) =
    insights.analyse(
      [message(1, board.Report, [])],
      [],
      query(),
      Some(clock_sample()),
    )
  let assert [agent] = report.agents
  agent.heartbeat_fresh |> should.be_false
  let assert Ok(beat) =
    insights.analyse(
      [message(1, board.Heartbeat, [])],
      [],
      query(),
      Some(clock_sample()),
    )
  let assert [agent] = beat.agents
  agent.heartbeat_fresh |> should.be_true
  let assert Ok(no_ntp) =
    insights.analyse([message(1, board.Heartbeat, [])], [], query(), None)
  let assert [agent] = no_ntp.agents
  agent.heartbeat_fresh |> should.be_false
}

pub fn future_evidence_and_expired_heartbeat_fail_test() {
  let future = message(110, board.Heartbeat, [])
  let assert Ok(report) =
    insights.analyse([future], [], query(), Some(clock_sample()))
  report.agents |> should.equal([])
  codes(report) |> list.contains("future_message") |> should.be_true
  let assert Ok(old) =
    insights.analyse(
      [message(1, board.Heartbeat, [])],
      [],
      insights.Query(..query(), ttl_us: 1),
      Some(clock_sample()),
    )
  let assert [agent] = old.agents
  agent.heartbeat_fresh |> should.be_false
}

pub fn explicit_causality_requires_increasing_lamport_test() {
  let parent = message(5, board.Report, [])
  let child = message(4, board.Report, [])
  let child =
    board.Message(..child, causality: board.Causality(Some(parent.id), []))
  insights.causal_findings([parent, child])
  |> list.map(fn(f) { f.code })
  |> should.equal(["lamport_causality_violation"])
  insights.causal_findings([parent, message(4, board.Report, [])])
  |> should.equal([])
  insights.causal_findings([child])
  |> list.map(fn(f) { f.code })
  |> should.equal(["missing_causal_parent"])
}

pub fn telemetry_joins_require_scope_trace_message_and_candidate_test() {
  let m = message(1, board.Report, [])
  let s = sample(m)
  let invalid = [
    insights.Sample(..s, tenant_id: "tenant-b"),
    insights.Sample(..s, id: "other-revision", candidate_ref: Some("rev-b")),
    insights.Sample(..s, id: "other-message", message_id: Some("other")),
    insights.Sample(
      ..s,
      id: "other-trace",
      trace_id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
  ]
  let assert Ok(report) = insights.analyse([m], [s, ..invalid], query(), None)
  list.length(report.correlations) |> should.equal(1)
  let assert [link] = report.correlations
  link.match_kind |> should.equal("explicit_message_and_trace")
  report.samples
  |> list.any(fn(s) { s.signal == insights.CollectorAccepted })
  |> should.be_false
}

pub fn duplicate_telemetry_is_not_double_counted_or_promoted_test() {
  let m = message(1, board.Report, [])
  let s = sample(m)
  let assert Ok(report) = insights.analyse([m], [s, s], query(), None)
  list.length(report.samples) |> should.equal(1)
  let assert Ok(conflict) =
    insights.analyse(
      [m],
      [s, insights.Sample(..s, signal: insights.BackendVisible)],
      query(),
      None,
    )
  conflict.samples |> should.equal([])
}

pub fn reader_counts_malformed_and_preserves_conflicts_test() {
  let m = message(1, board.Report, [])
  let rows = board.to_string(m) <> "\n{invalid}\n" <> board.to_string(m)
  let assert Ok(input) = reader.from_jsonl(rows)
  input.malformed_count |> should.equal(1)
  list.length(input.events) |> should.equal(2)
  let object_wire =
    json.to_string(
      json.array(
        [
          json.object([#("value", board.to_json(m))]),
          json.object([#("value", json.string(board.to_string(m)))]),
        ],
        fn(x) { x },
      ),
    )
  let assert Ok(wire) = reader.from_zenoh(object_wire)
  wire.events
  |> list.map(fn(event) {
    #(
      event.id,
      event.digest,
      board.digest_ok(event),
      insights.attribute(event, "tenant_id"),
    )
  })
  |> should.equal([
    #(m.id, m.digest, True, Some("tenant-a")),
    #(m.id, m.digest, True, Some("tenant-a")),
  ])
  wire.malformed_count |> should.equal(0)
}

pub fn unknown_kind_is_rejected_and_terminal_controls_escaped_test() {
  let m = message(1, board.Report, [#("note", "\u{001b}[2J")])
  let bad =
    board.to_string(m)
    |> string.replace("\"kind\":\"Report\"", "\"kind\":\"invented\"")
  let assert Ok(input) = reader.from_jsonl(bad)
  input.malformed_count |> should.equal(1)
  let assert Ok(report) = insights.analyse([m], [], query(), None)
  insights.to_text(report) |> string.contains("\u{001b}") |> should.be_false
}

pub fn generated_set_observer_matches_independent_oracle_test() {
  prng.range(1, 80)
  |> list.each(fn(seed) {
    let a = message({ seed * 13 } % 80 + 1, board.Report, [])
    let b = message({ seed * 7 } % 80 + 1, board.Report, [])
    let input = [a, b, a, b]
    let oracle =
      input
      |> list.map(fn(m) { m.id })
      |> list.unique
      |> list.sort(string.compare)
    let assert Ok(report) =
      insights.analyse(input, [], insights.Query(..query(), limit: 100), None)
    report.messages
    |> list.map(fn(m) { m.id })
    |> list.sort(string.compare)
    |> should.equal(oracle)
  })
}
