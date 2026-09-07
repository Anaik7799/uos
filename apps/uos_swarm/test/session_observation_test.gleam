import gleam/list
import gleam/string
import gleeunit/should
import uos_swarm/session_observation as observation
import uos_swarm/session_sync as sync

fn history() -> String {
  let register =
    sync.Register(
      "actor-1",
      "codex",
      "/home/an/NAS-setup/uos",
      "revision-1",
      [],
    )
  let e1 =
    sync.make_event(
      sync.empty(),
      register,
      "register-1",
      "host",
      "boot-1",
      100,
      100,
    )
  let line1 = sync.event_string(e1)
  let assert Ok(s1) = sync.replay(line1)
  let e2 =
    sync.make_event(
      s1,
      sync.Heartbeat("actor-1", "revision-2", []),
      "beat-2",
      "host",
      "boot-2",
      10,
      200,
    )
  let two = line1 <> "\n" <> sync.event_string(e2)
  let assert Ok(s2) = sync.replay(two)
  let e3 =
    sync.make_event(
      s2,
      sync.Claim("actor-1", "task:projection", 1_000_000),
      "claim-3",
      "host",
      "boot-2",
      11,
      201,
    )
  two <> "\n" <> sync.event_string(e3)
}

pub fn historical_candidate_and_boot_transition_preserved_test() {
  let assert Ok(rows) = observation.project(history(), "journal-1")
  list.map(rows, fn(row) { #(row.local_sequence, row.candidate_ref) })
  |> should.equal([#(1, "revision-1"), #(2, "revision-2"), #(3, "revision-2")])
  let assert [first, second, third] = rows
  first.host_boot_id |> should.equal("host:boot-1")
  second.host_boot_id |> should.equal("host:boot-2")
  third.resource_ref |> should.equal("task:projection")
  third.epoch |> should.equal(1)
}

pub fn corrupt_journal_emits_no_observations_test() {
  observation.project(
    string.replace(history(), "revision-1", "forged"),
    "journal-1",
  )
  |> should.be_error
  observation.project(history() <> "\n{", "journal-1") |> should.be_error
}

pub fn source_namespaces_and_payload_hashes_are_bound_test() {
  let assert Ok([first, ..]) = observation.project(history(), "journal-1")
  let assert Ok([other, ..]) = observation.project(history(), "journal-2")
  should.be_false(first.event_id == other.event_id)
  should.be_false(
    observation.payload_hash(first) == observation.payload_hash(other),
  )
  should.be_false(
    observation.payload_hash(first)
    == observation.payload_hash(observation.Observation(..first, epoch: 9)),
  )
  string.length(observation.payload_hash(first)) |> should.equal(64)
}

pub fn empty_or_invalid_source_is_not_invented_evidence_test() {
  observation.project("", "journal-1") |> should.equal(Ok([]))
  observation.project(history(), "") |> should.be_error
}
