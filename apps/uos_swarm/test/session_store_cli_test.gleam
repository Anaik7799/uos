import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import session_store_cli as cli
import simplifile
import uos_swarm/board
import uos_swarm/session_store as store
import uos_swarm/session_sync as sync

@external(erlang, "session_sync_ffi", "unique_id")
fn unique_id() -> String

@external(erlang, "session_store_test_ffi", "raw_exec")
fn raw_exec(path: String, sql: String) -> Result(Nil, String)

fn fixture_root() -> String {
  let root = "/tmp/uos-session-store-cli-tests/" <> unique_id()
  let assert Ok(_) = simplifile.create_directory_all(root)
  root
}

fn registered_store() -> String {
  let root = fixture_root()
  let db = root <> "/events.sqlite3"
  let assert Ok(opened) = store.open(db)
  let assert Ok(_) =
    store.append(
      opened,
      sync.Register("codex", "codex", root, "revision-a", []),
      "register",
    )
  let assert Ok(_) = store.close(opened)
  db
}

fn quoted(value: String) -> String {
  "'" <> string.replace(value, "'", "''") <> "'"
}

fn unregistered_event() -> sync.Event {
  sync.make_event(
    sync.empty(),
    sync.Heartbeat("ghost", "revision-a", []),
    "fixture",
    "host-a",
    "boot-a",
    100,
    1000,
  )
}

fn raw_insert_event(
  db: String,
  event: sync.Event,
  command: String,
  body: String,
) -> Result(Nil, String) {
  let values =
    [
      int.to_string(event.sequence),
      quoted(event.operation_id),
      quoted(event.host_id),
      quoted(event.boot_id),
      int.to_string(event.tick_us),
      int.to_string(event.utc_us),
      quoted(sync.operation(event.command)),
      quoted(sync.actor(event.command)),
      quoted(command),
      quoted(body),
      quoted(event.previous_digest),
      quoted(board.sha256_hex(body)),
      "1000",
    ]
    |> string.join(",")
  raw_exec(db, "INSERT INTO events VALUES (" <> values <> ")")
}

fn raw_insert(db: String, body: String) -> Result(Nil, String) {
  let event = unregistered_event()
  raw_insert_event(
    db,
    event,
    event.command |> sync.command_to_json |> json.to_string,
    body,
  )
}

pub fn raw_incomplete_registration_is_refused_before_poisoning_store_test() {
  let db = fixture_root() <> "/events.sqlite3"
  let assert Ok(opened) = store.open(db)
  let assert Ok(_) = store.close(opened)
  let event =
    sync.make_event(
      sync.empty(),
      sync.Register("ghost", "codex", "/tmp", "revision", []),
      "register-fixture",
      "host-a",
      "boot-a",
      100,
      1000,
    )
  let complete = event.command |> sync.command_to_json |> json.to_string
  let incomplete = "{\"operation\":\"register\",\"session\":\"ghost\"}"
  let body =
    sync.body_json_string(event) |> string.replace(complete, incomplete)
  raw_insert_event(db, event, incomplete, body)
  |> result.is_error
  |> should.be_true
  // Independent positive control: a complete registered event is accepted and
  // must then pass both digest and typed replay verification.
  let assert Ok(_) =
    raw_insert_event(db, event, complete, sync.body_json_string(event))
  let assert Ok(report) = cli.run(["verify", db])
  string.contains(report, "\"replay_ok\":true") |> should.be_true
}

fn injected_store(body: String) -> String {
  let db = fixture_root() <> "/events.sqlite3"
  let assert Ok(opened) = store.open(db)
  let assert Ok(_) = store.close(opened)
  // Model historical corruption or a privileged writer removing the entry
  // guard. Reopening restores the guard but must still reject existing damage.
  let assert Ok(_) = raw_exec(db, "DROP TRIGGER events_payload")
  let assert Ok(_) = raw_insert(db, body)
  db
}

pub fn raw_payload_and_unregistered_actor_are_refused_at_insert_test() {
  let body = sync.body_json_string(unregistered_event())
  ["{}", body, string.replace(body, "heartbeat", "ratify_cycle")]
  |> list.each(fn(invalid_body) {
    let db = fixture_root() <> "/events.sqlite3"
    let assert Ok(opened) = store.open(db)
    let assert Ok(_) = store.close(opened)
    raw_insert(db, invalid_body) |> result.is_error |> should.be_true
    let assert Ok(report) = cli.run(["verify", db])
    string.contains(report, "\"checked\":0") |> should.be_true
  })
}

pub fn empty_store_is_integrity_only_not_operational_readiness_test() {
  let db = fixture_root() <> "/events.sqlite3"
  let assert Ok(empty) = store.open(db)
  let assert Ok(_) = store.close(empty)
  let assert Ok(report) = cli.run(["verify", db])
  string.contains(report, "\"ok\":true") |> should.be_true
  string.contains(report, "\"nonempty\":false") |> should.be_true
  string.contains(report, "\"authority\":\"integrity_observation_only\"")
  |> should.be_true
}

pub fn canonical_registered_store_verifies_with_semantic_replay_test() {
  let assert Ok(report) = cli.run(["verify", registered_store()])
  string.contains(report, "\"ok\":true") |> should.be_true
  string.contains(report, "\"nonempty\":true") |> should.be_true
  string.contains(report, "\"replay_ok\":true") |> should.be_true
}

pub fn writable_database_paths_refuse_lexical_aliases_test() {
  let root = fixture_root()
  [root <> "/./events.sqlite3", root <> "//events.sqlite3", root <> "/../events.sqlite3"]
  |> list.each(fn(path) {
    let assert Error(error) = cli.run([path, "register", "codex", "codex", root, "revision", "-", "alias-register"])
    string.contains(cli.response(Error(error)).1, "aliases are refused") |> should.be_true
  })
  simplifile.is_file(root <> "/events.sqlite3") |> should.equal(Ok(False))
}

pub fn digest_failure_is_a_cli_error_not_success_test() {
  let db = registered_store()
  let assert Ok(_) =
    raw_exec(
      db,
      "DROP TRIGGER events_no_update; UPDATE events SET body_json = '{}' WHERE sequence = 1",
    )
  let assert Error(error) = cli.run(["verify", db])
  string.contains(cli.response(Error(error)).1, "sha256 mismatch") |> should.be_true
}

pub fn correct_digest_cannot_admit_an_unregistered_actor_test() {
  let event = unregistered_event()
  sync.replay(sync.event_string(event)) |> result.is_error |> should.be_true
  let db = injected_store(sync.body_json_string(event))
  let assert Ok(opened) = store.open(db)
  let assert Ok(report) = store.verify(opened)
  report.digest_ok |> should.be_true
  report.chain_ok |> should.be_true
  report.ok |> should.be_false
  let assert Ok(_) = store.close(opened)
  cli.run(["verify", db]) |> result.is_error |> should.be_true
}

pub fn correct_digest_cannot_admit_unknown_operations_or_malformed_events_test() {
  let body = sync.body_json_string(unregistered_event())
  ["{}", string.replace(body, "heartbeat", "ratify_cycle")]
  |> list.each(fn(invalid_body) {
    let db = injected_store(invalid_body)
    let assert Ok(opened) = store.open(db)
    let assert Ok(report) = store.verify(opened)
    report.digest_ok |> should.be_true
    report.ok |> should.be_false
    let assert Ok(_) = store.close(opened)
    cli.run(["verify", db]) |> result.is_error |> should.be_true
  })
}
