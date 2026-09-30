import gleam/string
import gleeunit/should
import session_store_cli as cli
import simplifile
import uos_swarm/session_store as store
import uos_swarm/session_sync as sync

@external(erlang, "session_sync_ffi", "unique_id")
fn unique_id() -> String

@external(erlang, "session_store_test_ffi", "raw_exec")
fn raw_exec(path: String, sql: String) -> Result(Nil, String)

@external(erlang, "session_store_ffi", "open")
fn raw_open(path: String) -> Result(store.Conn, String)

@external(erlang, "session_store_ffi", "exec")
fn raw_script(conn: store.Conn, sql: String) -> Result(Int, String)

@external(erlang, "session_store_ffi", "close")
fn raw_close(conn: store.Conn) -> Result(Nil, String)

fn directory() -> String {
  let path = "/tmp/uos-store-verification-" <> unique_id()
  let assert Ok(_) = simplifile.create_directory_all(path)
  path
}

fn settled_bytes(path: String) -> BitArray {
  // esqlite close_v2 may defer final close until statement garbage collection.
  // Checkpoint the private writer before comparing the main database file.
  let assert Ok(_) = raw_exec(path, "PRAGMA wal_checkpoint(TRUNCATE);")
  let assert Ok(bytes) = simplifile.read_bits(path)
  bytes
}

fn same_bytes(path: String, before: BitArray) -> Nil {
  let assert Ok(after) = simplifile.read_bits(path)
  { after == before } |> should.be_true
}

fn populated(path: String, workspace: String) -> Nil {
  let assert Ok(opened) = store.open(path)
  let assert Ok(_) =
    store.append(
      opened,
      sync.Register("verification-fixture", "codex", workspace, "fixture", []),
      "verification-register",
    )
  let assert Ok(_) = store.close(opened)
  Nil
}

pub fn missing_path_is_refused_without_creation_test() {
  let path = directory() <> "/absent.sqlite3"
  let #(status, text) = cli.response(cli.run(["verify", path]))
  status |> should.equal(1)
  string.contains(text, "\"ok\":false") |> should.be_true
  simplifile.is_file(path) |> should.equal(Ok(False))
}

pub fn empty_file_is_not_initialized_test() {
  let path = directory() <> "/empty.sqlite3"
  let assert Ok(_) = simplifile.write(path, "")
  let #(status, _) = cli.response(cli.run(["verify", path]))
  status |> should.equal(1)
  simplifile.read(path) |> should.equal(Ok(""))
}

pub fn missing_trigger_is_reported_without_repair_test() {
  let dir = directory()
  let path = dir <> "/missing-trigger.sqlite3"
  populated(path, dir)
  let assert Ok(_) = raw_exec(path, "DROP TRIGGER events_no_delete;")
  let before = settled_bytes(path)
  let assert Error(cli.VerificationFailed(report)) = cli.run(["verify", path])
  report.ok |> should.be_false
  report.triggers_present |> should.be_false
  report.trigger_definitions_ok |> should.be_false
  same_bytes(path, before)
  let assert Ok(again) = store.verify_file(path)
  again.triggers_present |> should.be_false
}

pub fn same_named_weak_trigger_is_refused_test() {
  let dir = directory()
  let path = dir <> "/weak-trigger.sqlite3"
  populated(path, dir)
  let assert Ok(conn) = raw_open(path)
  let outcome =
    raw_script(
      conn,
      "DROP TRIGGER events_no_update; CREATE TRIGGER events_no_update BEFORE UPDATE ON events BEGIN SELECT 1; END;",
    )
  let assert Ok(_) = raw_close(conn)
  let assert Ok(_) = outcome
  let before = settled_bytes(path)
  let assert Error(cli.VerificationFailed(report)) = cli.run(["verify", path])
  report.triggers_present |> should.be_true
  report.trigger_definitions_ok |> should.be_false
  report.ok |> should.be_false
  same_bytes(path, before)
}

pub fn digest_failure_keeps_structured_report_and_failure_status_test() {
  let dir = directory()
  let path = dir <> "/tampered.sqlite3"
  populated(path, dir)
  let assert Ok(_) =
    raw_exec(
      path,
      "DROP TRIGGER events_no_update; UPDATE events SET body_json = body_json || ' ' WHERE sequence = 1;",
    )
  let outcome = cli.run(["verify", path])
  let assert Error(cli.VerificationFailed(report)) = outcome
  report.digest_ok |> should.be_false
  report.checked |> should.equal(1)
  let #(status, text) = cli.response(outcome)
  status |> should.equal(1)
  string.contains(text, "\"digest_ok\":false") |> should.be_true
  string.contains(text, "sha256 mismatch") |> should.be_true
}

pub fn valid_store_is_observed_without_byte_changes_test() {
  let dir = directory()
  let path = dir <> "/valid.sqlite3"
  populated(path, dir)
  let before = settled_bytes(path)
  let #(status, text) = cli.response(cli.run(["verify", path]))
  status |> should.equal(0)
  string.contains(text, "\"checked\":1") |> should.be_true
  same_bytes(path, before)
}

pub fn path_query_bytes_are_not_sqlite_uri_options_test() {
  let dir = directory()
  let path = dir <> "/literal?mode=rwc&cache=shared#%25.sqlite3"
  populated(path, dir)
  let assert Ok(report) = store.verify_file(path)
  report.ok |> should.be_true
  report.checked |> should.equal(1)
  simplifile.is_file(dir <> "/literal") |> should.equal(Ok(False))
}

pub fn incompatible_meta_is_not_repaired_test() {
  let dir = directory()
  let path = dir <> "/incompatible.sqlite3"
  populated(path, dir)
  let assert Ok(_) =
    raw_exec(
      path,
      "UPDATE meta SET value = 'incompatible' WHERE key = 'schema';",
    )
  let before = settled_bytes(path)
  let assert Error(store.SchemaError(_)) = store.verify_file(path)
  same_bytes(path, before)
}

pub fn invalid_inspection_paths_are_refused_test() {
  let assert Error(store.OpenError(_)) = store.verify_file(":memory:")
  let assert Error(store.OpenError(_)) = store.verify_file("relative.sqlite3")
  let assert Error(store.OpenError(_)) =
    store.verify_file("/tmp/null\u{0}suffix")
  Nil
}

pub fn main() {
  missing_path_is_refused_without_creation_test()
  empty_file_is_not_initialized_test()
  missing_trigger_is_reported_without_repair_test()
  same_named_weak_trigger_is_refused_test()
  digest_failure_keeps_structured_report_and_failure_status_test()
  valid_store_is_observed_without_byte_changes_test()
  path_query_bytes_are_not_sqlite_uri_options_test()
  incompatible_meta_is_not_repaired_test()
  invalid_inspection_paths_are_refused_test()
}
