import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import uos_swarm/board
import uos_swarm/board_reader
import uos_swarm/clock_contract as clock
import uos_swarm/clock_guard as guard

const host = "nas-1"

const boot = "boot-a"

fn message_with_payload(payload: List(#(String, String))) -> board.Message {
  board.seal(
    board.Draft(
      board.Agent("codex", "L2", "declared-model"),
      "broadcast",
      board.Report,
      payload,
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

fn message() -> board.Message {
  message_with_payload([#("tenant_id", "tenant-a")])
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
      Ok(
        guard.BoardSnapshot([event], [
          guard.ActorObservation("codex", Some("codex"), Some(event)),
        ]),
      ),
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
      Ok(
        guard.BoardSnapshot([bad], [
          guard.ActorObservation("claude", Some("claude"), None),
        ]),
      ),
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
  let assert [current] = twice.reports
  current.sequence |> should.equal(2)
  current.fault_count |> should.equal(1)
}

pub fn first_healthy_report_exists_and_unchanged_health_stays_fresh_test() {
  let first =
    guard.audit(
      guard.new(guard.strict_config(), 0),
      Ok(sample(1_000_000, 1_000_000)),
      Ok(guard.BoardSnapshot([], [])),
    )
  let assert [initial] = first.reports
  initial.sequence |> should.equal(1)
  initial.fault_count |> should.equal(0)

  let second =
    guard.audit(
      first,
      Ok(sample(2_000_000, 2_000_000)),
      Ok(guard.BoardSnapshot([], [])),
    )
  let assert [current] = second.reports
  current.sequence |> should.equal(2)
  let assert Some(reading) = current.observed
  reading.utc_us |> should.equal(2_000_000)
}

fn stale_actors(remaining: Int) -> List(guard.ActorObservation) {
  case remaining <= 0 {
    True -> []
    False -> [
      guard.ActorObservation(
        "session-" <> int.to_string(remaining),
        Some("actor-" <> int.to_string(remaining)),
        None,
      ),
      ..stale_actors(remaining - 1)
    ]
  }
}

pub fn current_health_reports_total_and_omitted_fault_counts_test() {
  let state =
    guard.audit(
      guard.new(guard.strict_config(), 0),
      Ok(sample(200_000_000, 200_000_000)),
      Ok(guard.BoardSnapshot([], stale_actors(70))),
    )
  let assert [current] = state.reports
  current.fault_count |> should.equal(70)
  current.faults |> list.length |> should.equal(64)
  current.faults_omitted |> should.equal(6)
}

pub fn bounded_reader_drives_nonempty_snapshot_and_floor_is_durable_test() {
  let m = message()
  let assert Ok(input) = board_reader.from_jsonl(board.to_string(m))
  let snapshot = guard.from_board_input(input, ["codex"])
  snapshot.events |> list.length |> should.equal(1)
  let assert [actor] = snapshot.actor_last_seen
  actor.session_id |> should.equal("codex")
  actor.board_actor |> should.equal(Some("codex"))
  let assert Some(latest) = actor.latest
  latest.utc_us |> should.equal(1_000_000)

  let path = "/tmp/uos-clock-floor-" <> m.id
  guard.store_floor(path, 77) |> should.be_ok
  guard.load_floor(path) |> should.equal(Ok(77))
  let assert Ok(reloaded) =
    guard.reload(guard.new(guard.strict_config(), 77), guard.strict_config())
  reloaded.lamport_floor |> should.equal(77)
}

pub fn same_host_boot_provenance_supports_freshness_test() {
  let m =
    message_with_payload([
      #("host", host),
      #("boot_id", boot),
      #("boot_us", "999000"),
    ])
  let assert Ok(input) = board_reader.from_jsonl(board.to_string(m))
  let snapshot =
    guard.from_board_input_bound(input, [
      guard.expected_actor("session-codex", ["board:codex"]),
    ])
  let state =
    guard.audit(
      guard.new(guard.strict_config(), 0),
      Ok(sample(1_000_000, 1_000_000)),
      Ok(snapshot),
    )
  state.last_faults |> should.equal([])
}

pub fn missing_provenance_and_unbound_session_remain_unknown_test() {
  let m = message()
  let assert Ok(input) = board_reader.from_jsonl(board.to_string(m))
  let snapshot =
    guard.from_board_input_bound(input, [
      guard.expected_actor("session-codex", ["board:codex"]),
      guard.expected_actor("session-unbound", []),
    ])
  let state =
    guard.audit(
      guard.new(guard.strict_config(), 0),
      Ok(sample(1_000_000, 1_000_000)),
      Ok(snapshot),
    )
  let labels = list.map(state.last_faults, guard.fault_label)
  labels |> list.contains("event_clock_domain_unknown") |> should.equal(True)
  labels |> list.contains("actor_freshness_unknown") |> should.equal(True)
  labels |> list.contains("actor_binding_unknown") |> should.equal(True)
}

pub fn foreign_clock_never_uses_local_boot_or_ntp_as_freshness_proof_test() {
  let m =
    message_with_payload([
      #("host", "vm-1"),
      #("boot_id", "remote-boot"),
      #("boot_us", "999999999"),
    ])
  let assert Ok(input) = board_reader.from_jsonl(board.to_string(m))
  let snapshot =
    guard.from_board_input_bound(input, [
      guard.expected_actor("session-codex", ["board:codex"]),
    ])
  let state =
    guard.audit(
      guard.new(guard.strict_config(), 0),
      Ok(sample(1_000_000, 1_000_000)),
      Ok(snapshot),
    )
  let labels = list.map(state.last_faults, guard.fault_label)
  labels |> list.contains("foreign_clock_unverified") |> should.equal(True)
  labels |> list.contains("actor_freshness_unknown") |> should.equal(True)
  labels |> list.contains("event_observed_in_future") |> should.equal(False)
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
