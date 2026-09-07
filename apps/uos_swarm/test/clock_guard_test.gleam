import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import uos_swarm/board
import uos_swarm/board_reader
import uos_swarm/clock_contract as clock
import uos_swarm/clock_guard as guard

const host = "nas-1"

const boot = "boot-a"

fn message() -> board.Message {
  board.seal(
    board.Draft(
      board.Agent("codex", "L2", "declared-model"),
      "broadcast",
      board.Report,
      [#("tenant_id", "tenant-a")],
      board.no_semantics,
      board.Causality(None, []),
      None,
      None,
    ),
    "hive-a",
    1_000_000,
    7,
    "aaaaaaaaaaaaaaaa",
    board.genesis_digest,
  )
}

fn sample(utc: Int, mono: Int) -> guard.Sample {
  let reading = clock.Reading(clock.Domain(host, boot), utc, mono)
  guard.Sample(
    clock.Evidence(reading, "chronyc:-c-tracking", True, 8, 900, 4),
    reading,
  )
}

pub fn healthy_sample_and_board_advance_floor_test() {
  let event =
    guard.CausalEvent(
      "m2",
      "codex",
      clock.Domain(host, boot),
      1_000_000,
      7,
      Some(6),
      1_000_000,
    )
  let state =
    guard.audit(
      guard.new(guard.strict_config(), 4),
      Ok(sample(1_000_000, 1_000_000)),
      Ok(guard.BoardSnapshot([event], [#("codex", 999_999)])),
    )
  state.lamport_floor |> should.equal(7)
  state.last_faults |> should.equal([])
}

pub fn discontinuity_boot_future_causality_and_stale_actor_fail_test() {
  let initial =
    guard.audit(
      guard.new(guard.strict_config(), 0),
      Ok(sample(2_000_000, 2_000_000)),
      Ok(guard.BoardSnapshot([], [])),
    )
  let later_reading = clock.Reading(clock.Domain(host, "boot-b"), 3_000_000, 1)
  let later =
    guard.Sample(
      clock.Evidence(later_reading, "chronyc:-c-tracking", True, 0, 1, 0),
      later_reading,
    )
  let bad =
    guard.CausalEvent(
      "bad",
      "claude",
      clock.Domain(host, boot),
      9_000_000,
      5,
      Some(5),
      4_000_000,
    )
  let state =
    guard.audit(
      initial,
      Ok(later),
      Ok(guard.BoardSnapshot([bad], [#("claude", -200_000_000)])),
    )
  list.is_empty(state.last_faults) |> should.equal(False)
  state.last_faults
  |> list.map(guard.fault_label)
  |> list.contains("boot_changed")
  |> should.equal(True)
  state.last_faults
  |> list.map(guard.fault_label)
  |> list.contains("lamport_order_violates_causal_link")
  |> should.equal(True)
  state.last_faults
  |> list.map(guard.fault_label)
  |> list.contains("stale_actor")
  |> should.equal(True)
}

pub fn unknown_inputs_never_report_green_and_reloads_preserve_floor_test() {
  let state =
    guard.audit(
      guard.new(guard.strict_config(), 42),
      Error("ntp unknown"),
      Error("board unknown"),
    )
  state.last_faults |> should.equal([guard.SampleUnavailable("ntp unknown")])
  let assert Ok(reloaded) =
    guard.reload(state, guard.Config(1, 50, 1, 1, clock.strict_policy))
  reloaded.lamport_floor |> should.equal(42)
  guard.reload(state, guard.Config(2, 50, 1, 1, clock.strict_policy))
  |> should.be_error
}

pub fn unchanged_faults_are_coalesced_and_ring_is_bounded_test() {
  let once =
    guard.audit(
      guard.new(guard.Config(1, 50, 1, 1, clock.strict_policy), 0),
      Error("missing"),
      Ok(guard.BoardSnapshot([], [])),
    )
  let twice =
    guard.audit(once, Error("missing"), Ok(guard.BoardSnapshot([], [])))
  twice.reports |> list.length |> should.equal(1)
}

pub fn bounded_reader_drives_nonempty_snapshot_and_floor_is_durable_test() {
  let m = message()
  let assert Ok(input) = board_reader.from_jsonl(board.to_string(m))
  let snapshot = guard.from_board_input(input, ["codex"])
  snapshot.events |> list.length |> should.equal(1)
  snapshot.actor_last_seen |> should.equal([#("codex", 1_000_000)])

  let path = "/tmp/uos-clock-floor-" <> m.id
  guard.store_floor(path, 77) |> should.be_ok
  guard.load_floor(path) |> should.equal(Ok(77))
  let assert Ok(reloaded) =
    guard.reload(guard.new(guard.strict_config(), 77), guard.strict_config())
  reloaded.lamport_floor |> should.equal(77)
}

pub fn captured_chrony_fourteen_field_fixture_has_correct_units_test() {
  let fixture =
    "B97DBE7A,185.125.190.122,3,1788771094.828469440,0.000268486,-0.000264731,0.000807282,-3.739,-0.007,0.224,0.030454356,0.000914232,1030.6,Normal"
  let assert Ok(#(reference_us, offset_us, uncertainty_us, _)) =
    guard.parse_tracking(fixture)
  reference_us |> should.equal(1_788_771_094_828_469)
  offset_us |> should.equal(268)
  uncertainty_us |> should.equal(16_142)
  guard.parse_tracking(fixture <> ",extra") |> should.be_error
}

pub fn durable_directory_probe_reports_missing_directory_test() {
  guard.verify_durable_directory("/tmp/uos-clock-guard-missing-directory")
  |> should.be_error
  guard.verify_durable_directory("/tmp") |> should.be_ok
}
