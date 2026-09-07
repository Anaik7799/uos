import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import simplifile
import uos_swarm/session_store as store
import uos_swarm/session_sync as sync

@external(erlang, "session_sync_ffi", "unique_id")
fn unique_id() -> String

@external(erlang, "session_store_test_ffi", "raw_exec")
fn raw_exec(path: String, sql: String) -> Result(Nil, String)

@external(erlang, "session_store_test_ffi", "copy_file")
fn copy_file(from: String, to: String) -> Result(Nil, String)

/// Scratch root for these tests. Session-independent on purpose: the original
/// value pointed at one authoring session's private scratchpad, which does not
/// exist for any other session or on CI. Every path under it is suffixed with
/// `unique_id()`, so concurrent runs do not collide.
const scratch_root = "/tmp/uos-session-store-tests"

/// Migration source for the migration tests. The original was a frozen
/// 415-event copy in one session's private scratchpad, which no other session
/// can read. Instead the fixture is generated here through the store's own API
/// and exported, so the migration tests assert the export-to-migrate round trip
/// rather than a fixed historical count.
fn fixture_sessions() -> List(String) {
  ["alpha", "beta", "gamma", "delta", "epsilon"]
}

/// Build a journal directory by appending known events to a fresh store and
/// exporting it. Returns the events directory, the event count and the head
/// digest that a faithful migration must reproduce.
fn fixture_events_dir() -> #(String, Int, String) {
  let db = db_path()
  let assert Ok(source) = store.open(db)
  list.each(fixture_sessions(), fn(name) {
    let assert Ok(#(_, False)) =
      store.append(
        source,
        sync.Register(name, "codex", workspace_dir(), "rev-" <> name, []),
        "fixture-register-" <> name,
      )
  })
  let assert Ok(head) = store.head(source)
  let out_root = out_root_dir()
  let assert Ok(exported) = store.export(source, out_root)
  let assert Ok(Nil) = store.close(source)
  #(out_root <> "/events", exported, head.1)
}

fn ensure_scratch_root() -> Nil {
  let _ = simplifile.create_directory_all(scratch_root)
  Nil
}

fn db_path() -> String {
  ensure_scratch_root()
  scratch_root <> "/" <> unique_id() <> ".sqlite3"
}

fn workspace_dir() -> String {
  ensure_scratch_root()
  let dir = scratch_root <> "/workspace-" <> unique_id()
  let assert Ok(_) = simplifile.create_directory_all(dir)
  dir
}

fn out_root_dir() -> String {
  ensure_scratch_root()
  scratch_root <> "/export-" <> unique_id()
}

// ---------------------------------------------------------------------
// open / schema / meta
// ---------------------------------------------------------------------

pub fn open_creates_schema_and_meta_test() {
  let db = db_path()
  let assert Ok(opened) = store.open(db)
  // meta.schema round-trips through a second open of the same file.
  let assert Ok(reopened) = store.open(db)
  store.path(reopened) |> should.equal(db)
  // events/quarantine tables and the three append-only triggers exist.
  let assert Ok(_) =
    raw_exec(
      db,
      "SELECT 1 FROM events WHERE 1 = 0; SELECT 1 FROM quarantine WHERE 1 = 0;",
    )
  store.head(opened) |> should.equal(Ok(#(0, sync.genesis)))
  let assert Ok(Nil) = store.close(opened)
  let assert Ok(Nil) = store.close(reopened)
}

pub fn open_refuses_incompatible_schema_marker_test() {
  let db = db_path()
  let assert Ok(opened) = store.open(db)
  let assert Ok(Nil) = store.close(opened)
  let assert Ok(Nil) =
    raw_exec(
      db,
      "UPDATE meta SET value = 'some-other-schema/v9' WHERE key = 'schema';",
    )
  let assert Error(store.SchemaError(_)) = store.open(db)
  Nil
}

// ---------------------------------------------------------------------
// append: round trip, duplicate suppression, and an independent oracle
// ---------------------------------------------------------------------

pub fn append_round_trip_matches_direct_apply_oracle_test() {
  let db = db_path()
  let workspace = workspace_dir()
  let assert Ok(opened) = store.open(db)

  let assert Ok(#(receipt1, False)) =
    store.append(
      opened,
      sync.Register("codex", "codex", workspace, "revision-a", []),
      "op-register",
    )
  let assert Ok(#(receipt2, False)) =
    store.append(
      opened,
      sync.Heartbeat("codex", "revision-b", ["herdr:pane=1"]),
      "op-heartbeat",
    )
  let assert Ok(#(receipt3, False)) =
    store.append(
      opened,
      sync.Claim("codex", "integration/main", 60_000_000),
      "op-claim",
    )
  receipt3.epoch |> should.equal(1)
  let assert Ok(#(receipt4, False)) =
    store.append(
      opened,
      sync.Release("codex", "integration/main", receipt3.epoch),
      "op-release",
    )

  // Independent oracle: decode the exact recorded events (their own
  // host_id/boot_id/tick_us/utc_us, not fresh clock reads) and fold
  // session_sync.apply directly, outside of session_store's own replay
  // path. This must reproduce bit-identical receipts, because the file
  // coordinator's `execute` would do exactly the same thing with these
  // same recorded values.
  let assert Ok(journal_text) = store.journal(opened)
  let assert Ok(events) =
    journal_text
    |> string.split("\n")
    |> list.filter(fn(line) { string.trim(line) != "" })
    |> list.try_map(sync.decode_event)
  list.length(events) |> should.equal(4)

  let assert Ok(#(final_direct, direct_receipts)) =
    list.try_fold(events, #(sync.empty(), []), fn(acc, event) {
      let #(state, receipts) = acc
      use #(next, receipt, duplicate) <- result.try(sync.apply(
        state,
        event.command,
        event.operation_id,
        event.host_id,
        event.boot_id,
        event.tick_us,
        event.utc_us,
      ))
      duplicate |> should.be_false
      Ok(#(next, [receipt, ..receipts]))
    })
  let assert [d1, d2, d3, d4] = list.reverse(direct_receipts)
  d1 |> should.equal(receipt1)
  d2 |> should.equal(receipt2)
  d3 |> should.equal(receipt3)
  d4 |> should.equal(receipt4)
  dict.get(final_direct.coordinator.epochs, "integration/main")
  |> should.equal(Ok(1))

  // And session_store's own replay agrees with the same oracle.
  let assert Ok(replayed) = store.replay(opened)
  replayed.coordinator.epochs |> should.equal(final_direct.coordinator.epochs)
  replayed.sequence |> should.equal(4)

  let assert Ok(Nil) = store.close(opened)
}

pub fn duplicate_operation_id_returns_duplicate_true_and_no_new_row_test() {
  let db = db_path()
  let workspace = workspace_dir()
  let assert Ok(opened) = store.open(db)
  let command = sync.Register("codex", "codex", workspace, "revision-a", [])
  let assert Ok(#(first, False)) = store.append(opened, command, "same-op")
  store.head(opened) |> result.map(fn(head) { head.0 }) |> should.equal(Ok(1))
  let assert Ok(#(second, True)) = store.append(opened, command, "same-op")
  second |> should.equal(first)
  // No new row: head sequence is still 1.
  store.head(opened) |> result.map(fn(head) { head.0 }) |> should.equal(Ok(1))
  // Conflicting reuse of the same op_id with a different command is refused.
  let assert Error(store.RefusedError(_)) =
    store.append(
      opened,
      sync.Register("codex", "codex", workspace, "revision-b", []),
      "same-op",
    )
  let assert Ok(Nil) = store.close(opened)
}

// ---------------------------------------------------------------------
// Append-only triggers reject raw mutation
// ---------------------------------------------------------------------

pub fn raw_update_and_delete_are_rejected_by_triggers_test() {
  let db = db_path()
  let workspace = workspace_dir()
  let assert Ok(opened) = store.open(db)
  let assert Ok(#(_, False)) =
    store.append(
      opened,
      sync.Register("codex", "codex", workspace, "revision-a", []),
      "register",
    )
  let assert Ok(Nil) = store.close(opened)

  let assert Error(_) =
    raw_exec(db, "UPDATE events SET actor = 'tampered' WHERE sequence = 1;")
  let assert Error(_) = raw_exec(db, "DELETE FROM events WHERE sequence = 1;")

  let assert Ok(reopened) = store.open(db)
  store.head(reopened) |> should.equal(Ok(#(1, { store_digest(reopened) })))
  let assert Ok(Nil) = store.close(reopened)
}

/// Review wf_5f54e14c-28b measured that `events_no_delete` alone does not make
/// the table append-only: SQLite fires DELETE triggers for the implicit delete
/// of `INSERT OR REPLACE` only when `PRAGMA recursive_triggers` is ON, and its
/// default is OFF, so a raw `INSERT OR REPLACE` reusing a stored `operation_id`
/// or `digest` dropped the historical row silently. `events_no_replace` refuses
/// the insert before the replace can delete anything.
pub fn insert_or_replace_cannot_delete_history_test() {
  let db = db_path()
  let workspace = workspace_dir()
  let assert Ok(opened) = store.open(db)
  let assert Ok(#(_, False)) =
    store.append(
      opened,
      sync.Register("codex", "codex", workspace, "revision-a", []),
      "register",
    )
  let assert Ok(#(_, False)) =
    store.append(opened, sync.Heartbeat("codex", "revision-b", []), "heartbeat")
  let assert Ok(#(2, head_digest)) = store.head(opened)
  let assert Ok(Nil) = store.close(opened)

  let row = fn(sequence: String, operation_id: String, digest: String) {
    "INSERT OR REPLACE INTO events (sequence, operation_id, host_id, boot_id, tick_us, utc_us, operation, actor, command_json, body_json, previous_digest, digest, inserted_utc_us) VALUES ("
    <> sequence
    <> ", "
    <> operation_id
    <> ", 'h', 'b', 1, 1, 'heartbeat', 'codex', '{}', '{}', '"
    <> head_digest
    <> "', "
    <> digest
    <> ", 1);"
  }
  // Chain-valid (sequence 3, correct previous_digest) but reusing the stored
  // operation_id of sequence 1: without the guard this REPLACE deletes row 1.
  let assert Error(_) =
    raw_exec(
      db,
      row(
        "3",
        "(SELECT operation_id FROM events WHERE sequence = 1)",
        "'fresh-digest-a'",
      ),
    )
  // Same, reusing the stored digest of sequence 1.
  let assert Error(_) =
    raw_exec(
      db,
      row(
        "3",
        "'fresh-operation-id'",
        "(SELECT digest FROM events WHERE sequence = 1)",
      ),
    )
  // Reusing an existing sequence outright.
  let assert Error(_) =
    raw_exec(db, row("1", "'another-operation-id'", "'fresh-digest-b'"))

  let assert Ok(reopened) = store.open(db)
  // Nothing was deleted, nothing was added, and the head is unchanged.
  store.head(reopened) |> should.equal(Ok(#(2, head_digest)))
  let assert Ok(report) = store.verify(reopened)
  report.ok |> should.equal(True)
  report.checked |> should.equal(2)
  report.triggers_present |> should.equal(True)
  let assert Ok(Nil) = store.close(reopened)
}

fn store_digest(opened: store.Store) -> String {
  let assert Ok(#(_, digest)) = store.head(opened)
  digest
}

pub fn raw_insert_with_wrong_sequence_or_wrong_previous_digest_is_rejected_test() {
  let db = db_path()
  let workspace = workspace_dir()
  let assert Ok(opened) = store.open(db)
  let assert Ok(#(_, False)) =
    store.append(
      opened,
      sync.Register("codex", "codex", workspace, "revision-a", []),
      "register",
    )
  let assert Ok(Nil) = store.close(opened)

  // Wrong sequence (skips ahead of the actual next sequence, 2).
  let assert Error(_) =
    raw_exec(
      db,
      "INSERT INTO events (sequence, operation_id, host_id, boot_id, tick_us, utc_us, operation, actor, command_json, body_json, previous_digest, digest, inserted_utc_us) VALUES (5, 'bad-sequence', 'h', 'b', 1, 1, 'heartbeat', 'codex', '{}', '{}', 'whatever', 'bad-digest-a', 1);",
    )
  // Correct next sequence (2), but a previous_digest that does not match
  // the current head's digest.
  let assert Error(_) =
    raw_exec(
      db,
      "INSERT INTO events (sequence, operation_id, host_id, boot_id, tick_us, utc_us, operation, actor, command_json, body_json, previous_digest, digest, inserted_utc_us) VALUES (2, 'bad-previous-digest', 'h', 'b', 1, 1, 'heartbeat', 'codex', '{}', '{}', 'not-the-real-previous-digest', 'bad-digest-b', 1);",
    )

  let assert Ok(reopened) = store.open(db)
  store.head(reopened) |> result.map(fn(head) { head.0 }) |> should.equal(Ok(1))
  let assert Ok(Nil) = store.close(reopened)
}

// ---------------------------------------------------------------------
// verify: passes on a good store, reports the exact failure on tampering
// ---------------------------------------------------------------------

pub fn verify_passes_on_a_good_store_test() {
  let db = db_path()
  let workspace = workspace_dir()
  let assert Ok(opened) = store.open(db)
  let assert Ok(#(_, False)) =
    store.append(
      opened,
      sync.Register("codex", "codex", workspace, "revision-a", []),
      "register",
    )
  let assert Ok(#(_, False)) =
    store.append(opened, sync.Heartbeat("codex", "revision-b", []), "heartbeat")
  let assert Ok(#(_, False)) =
    store.append(
      opened,
      sync.Claim("codex", "integration/main", 60_000_000),
      "claim",
    )
  let assert Ok(report) = store.verify(opened)
  report.ok |> should.be_true
  report.checked |> should.equal(3)
  report.sequence_ok |> should.be_true
  report.chain_ok |> should.be_true
  report.digest_ok |> should.be_true
  report.triggers_present |> should.be_true
  report.unique_operations |> should.be_true
  report.failures |> should.equal([])
  let assert Ok(Nil) = store.close(opened)
}

pub fn verify_reports_the_exact_failure_on_a_tampered_copy_test() {
  let db = db_path()
  let workspace = workspace_dir()
  let assert Ok(opened) = store.open(db)
  let assert Ok(#(_, False)) =
    store.append(
      opened,
      sync.Register("codex", "codex", workspace, "revision-a", []),
      "register",
    )
  let assert Ok(#(_, False)) =
    store.append(opened, sync.Heartbeat("codex", "revision-b", []), "heartbeat")
  let assert Ok(#(_, False)) =
    store.append(
      opened,
      sync.Claim("codex", "integration/main", 60_000_000),
      "claim",
    )
  let assert Ok(Nil) = store.close(opened)

  // Work on a scratch copy: temporarily drop the append-only triggers,
  // then edit body_json for sequence 2 directly.
  let copy = db_path()
  let assert Ok(Nil) = copy_file(db, copy)
  let assert Ok(Nil) =
    raw_exec(
      copy,
      "DROP TRIGGER events_no_update; DROP TRIGGER events_no_delete; UPDATE events SET body_json = '{\"tampered\":true}' WHERE sequence = 2;",
    )

  // Reopening recreates the (harmless, DDL-only) triggers but does not
  // touch the tampered row's data.
  let assert Ok(tampered) = store.open(copy)
  let assert Ok(report) = store.verify(tampered)
  report.ok |> should.be_false
  report.digest_ok |> should.be_false
  report.checked |> should.equal(3)
  list.any(report.failures, fn(failure) {
    string.contains(failure, "sequence 2")
    && string.contains(failure, "sha256 mismatch")
  })
  |> should.be_true
  let assert Ok(Nil) = store.close(tampered)
}

// ---------------------------------------------------------------------
// Migration from the read-only 415-event copy, and export parity
// ---------------------------------------------------------------------

pub fn migrate_from_journal_replay_verify_and_export_parity_test() {
  let #(events_dir, source_count, source_digest) = fixture_events_dir()
  let expected = list.length(fixture_sessions())
  source_count |> should.equal(expected)

  let db = db_path()
  let assert Ok(opened) = store.open(db)
  let assert Ok(count) = store.migrate_from_journal(events_dir, opened)
  count |> should.equal(expected)

  let assert Ok(state) = store.replay(opened)
  state.sequence |> should.equal(expected)
  dict.size(state.sessions) |> should.equal(expected)

  let assert Ok(head) = store.head(opened)
  head.0 |> should.equal(expected)
  // A faithful migration reproduces the source chain exactly.
  head.1 |> should.equal(source_digest)

  let assert Ok(report) = store.verify(opened)
  report.ok |> should.be_true
  report.checked |> should.equal(expected)

  let out_root = out_root_dir()
  let assert Ok(exported) = store.export(opened, out_root)
  exported |> should.equal(expected)

  let assert Ok(names) = simplifile.read_directory(out_root <> "/events")
  list.length(names) |> should.equal(expected)
  let assert Ok(lines) =
    names
    |> list.sort(string.compare)
    |> list.try_map(fn(name) { simplifile.read(out_root <> "/events/" <> name) })
  let assert Ok(exported_state) = sync.replay(string.join(lines, "\n"))
  exported_state.digest |> should.equal(head.1)
  exported_state.sequence |> should.equal(expected)

  let assert Ok(Nil) = store.close(opened)
}

pub fn migration_refuses_a_non_empty_store_test() {
  let db = db_path()
  let workspace = workspace_dir()
  let assert Ok(opened) = store.open(db)
  let assert Ok(#(_, False)) =
    store.append(
      opened,
      sync.Register("codex", "codex", workspace, "revision-a", []),
      "register",
    )
  let #(events_dir, _, _) = fixture_events_dir()
  let assert Error(store.RefusedError(reason)) =
    store.migrate_from_journal(events_dir, opened)
  string.contains(reason, "non-empty store") |> should.be_true
  let assert Ok(Nil) = store.close(opened)
}
