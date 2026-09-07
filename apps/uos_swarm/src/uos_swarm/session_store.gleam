//// SQLite-backed replacement for the file-journal coordinator's storage,
//// implementing exactly the same policy (uos_swarm/session_sync) over a
//// robust, typed SQLite protocol instead of one-JSON-file-per-event.
////
//// Design decisions (operator directive: "use a database like json for
//// sqlite, ignore digest, do the migration, replace with correct digest,
//// create robust api and protocol for all sqlite operations"):
////
//// - Writers never supply `sequence`, `digest`, or `previous_digest`; those
////   are always derived by `session_sync.make_event` from state replayed
////   from this store's own rows, exactly as the file coordinator derives
////   them from its own journal. "Ignore digest" from a migration source
////   means: the source journal's stored digests are not trusted and are
////   never copied in; `migrate_from_journal` recomputes every digest from
////   genesis via `session_sync.resign` before a single row is inserted.
//// - `events` is an append-only ledger enforced by SQL triggers, not just
////   Gleam-side discipline: `events_no_update`/`events_no_delete` reject any
////   raw UPDATE/DELETE, and `events_chain` rejects any INSERT whose
////   `sequence`/`previous_digest` do not extend the current chain by
////   exactly one link. Triggers reject a broken *chain*; they cannot detect
////   a *tampered* row whose digest was recomputed to match altered content
////   after a chain-preserving edit is entered through this module's own
////   `append`/`migrate_from_journal` paths — that class of tampering is
////   caught only by `verify`, which independently recomputes every digest
////   from its stored `body_json`.
//// - Every operation is a typed, parameterized SQLite statement (via the
////   `Cell` wire type and `session_store_ffi`); no query is ever built by
////   string-interpolating caller-controlled data.
////
//// Cost note: `append` and `migrate_from_journal`'s duplicate-refusal path
//// replay the full stored chain on every call (`reconstruct_journal` reads
//// every row, then `session_sync.replay` folds `session_sync.apply` over
//// each one). This is the same algorithm the file coordinator's `execute`
//// runs over its own journal file and is documented there as acceptable at
//// this store's expected size (a few thousand events per coordination
//// root); a future revision could instead persist snapshots and replay
//// only the suffix, but that optimization is out of scope here.
////
//// STAMP: SC-TUI-COORD-001; SC-FPP-INTENT-001; SC-DB-001. #fractal-l2
//// #fractal-l3 #zero-muda

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import simplifile
import uos_swarm/board
import uos_swarm/session_sync as sync

// ---------------------------------------------------------------------
// FFI surface
// ---------------------------------------------------------------------

/// Opaque handle onto an esqlite3 connection. Never constructed or
/// pattern-matched outside `session_store_ffi`'s FFI boundary.
pub type Conn

/// The one wire type crossing the Gleam/Erlang boundary for both bound
/// parameters and returned row values, matching `session_store_ffi`'s
/// `{cell_text, binary()} | {cell_int, integer()} | cell_null` shape.
pub type Cell {
  CellText(String)
  CellInt(Int)
  CellNull
}

@external(erlang, "session_store_ffi", "open")
fn ffi_open(path: String) -> Result(Conn, String)

@external(erlang, "session_store_ffi", "exec")
fn ffi_exec(conn: Conn, sql: String) -> Result(Int, String)

@external(erlang, "session_store_ffi", "query")
fn ffi_query(
  conn: Conn,
  sql: String,
  params: List(Cell),
) -> Result(List(List(Cell)), String)

@external(erlang, "session_store_ffi", "begin_immediate")
fn ffi_begin(conn: Conn) -> Result(Int, String)

@external(erlang, "session_store_ffi", "commit")
fn ffi_commit(conn: Conn) -> Result(Int, String)

@external(erlang, "session_store_ffi", "rollback")
fn ffi_rollback(conn: Conn) -> Result(Int, String)

@external(erlang, "session_store_ffi", "close")
fn ffi_close(conn: Conn) -> Result(Nil, String)

@external(erlang, "session_store_ffi", "clock")
fn ffi_clock() -> Result(#(String, String, Int, Int), String)

// ---------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------

pub opaque type Store {
  Store(conn: Conn, path: String)
}

pub fn path(store: Store) -> String {
  store.path
}

/// Typed store error. Every public operation returns `Result(_, StoreError)`
/// rather than a bare string, so callers can branch on the failure class
/// (a schema mismatch is not the same situation as a busy database file).
pub type StoreError {
  /// `esqlite3:open` failed, or a PRAGMA could not be applied.
  OpenError(String)
  /// The store exists but its `meta.schema` does not match
  /// `session_sync.genesis`, or the schema DDL itself could not be applied.
  SchemaError(String)
  /// A SQL statement failed (busy, constraint violation, I/O error, ...).
  StorageError(String)
  /// The requested operation was refused by policy: a command failed
  /// `session_sync.apply`/`canonical_command`, or a precondition such as
  /// "migration requires an empty store" was not met.
  RefusedError(String)
  /// Stored data does not decode into a well-formed `session_sync.Event`,
  /// or fails to fold under `session_sync.replay`.
  CorruptError(String)
}

pub fn error_to_string(error: StoreError) -> String {
  case error {
    OpenError(message) -> "open: " <> message
    SchemaError(message) -> "schema: " <> message
    StorageError(message) -> "storage: " <> message
    RefusedError(message) -> "refused: " <> message
    CorruptError(message) -> "corrupt: " <> message
  }
}

/// The result of independently recomputing every chain link and digest
/// from stored bytes. `ok` is `True` only when `failures` is empty; each
/// failure names the exact sequence and check that did not hold, so a
/// tampered store reports precisely what changed instead of a bare refusal.
pub type VerifyReport {
  VerifyReport(
    ok: Bool,
    checked: Int,
    sequence_ok: Bool,
    chain_ok: Bool,
    digest_ok: Bool,
    triggers_present: Bool,
    unique_operations: Bool,
    failures: List(String),
  )
}

pub fn verify_report_json(report: VerifyReport) -> Json {
  json.object([
    #("ok", json.bool(report.ok)),
    #("checked", json.int(report.checked)),
    #("sequence_ok", json.bool(report.sequence_ok)),
    #("chain_ok", json.bool(report.chain_ok)),
    #("digest_ok", json.bool(report.digest_ok)),
    #("triggers_present", json.bool(report.triggers_present)),
    #("unique_operations", json.bool(report.unique_operations)),
    #("failures", json.array(report.failures, json.string)),
  ])
}

// ---------------------------------------------------------------------
// Schema
// ---------------------------------------------------------------------

/// The complete schema DDL, applied idempotently (`IF NOT EXISTS`
/// throughout) by `open`. Exposed publicly so `schema` CLI/tooling can print
/// it without opening a database, and so tests can assert on it directly.
pub fn schema_sql() -> String {
  "
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS events (
  sequence INTEGER PRIMARY KEY CHECK (sequence > 0),
  operation_id TEXT NOT NULL UNIQUE,
  host_id TEXT NOT NULL,
  boot_id TEXT NOT NULL,
  tick_us INTEGER NOT NULL,
  utc_us INTEGER NOT NULL,
  operation TEXT NOT NULL,
  actor TEXT NOT NULL,
  command_json TEXT NOT NULL,
  body_json TEXT NOT NULL,
  previous_digest TEXT NOT NULL,
  digest TEXT NOT NULL UNIQUE,
  inserted_utc_us INTEGER NOT NULL
);

CREATE TRIGGER IF NOT EXISTS events_no_update
BEFORE UPDATE ON events
BEGIN
  SELECT RAISE(ABORT, 'events are append-only');
END;

CREATE TRIGGER IF NOT EXISTS events_no_delete
BEFORE DELETE ON events
BEGIN
  SELECT RAISE(ABORT, 'events are append-only');
END;

CREATE TRIGGER IF NOT EXISTS events_chain
BEFORE INSERT ON events
WHEN NOT (
  NEW.sequence = (SELECT COALESCE(MAX(sequence), 0) + 1 FROM events)
  AND NEW.previous_digest = COALESCE(
        (SELECT digest FROM events WHERE sequence = NEW.sequence - 1),
        '" <> sync.genesis <> "'
      )
)
BEGIN
  SELECT RAISE(ABORT, 'events chain violated: sequence or previous_digest does not extend the current head');
END;

CREATE TABLE IF NOT EXISTS quarantine (
  id INTEGER PRIMARY KEY,
  raw TEXT NOT NULL,
  reason TEXT NOT NULL,
  recorded_utc_us INTEGER NOT NULL
);
"
}

/// Open (creating if absent) a SQLite store at `path`, apply the schema,
/// and verify `meta.schema == session_sync.genesis`. A freshly created
/// store gets its `meta` rows written here; an existing store is only read.
pub fn open(path: String) -> Result(Store, StoreError) {
  use conn <- result.try(ffi_open(path) |> result.map_error(OpenError))
  let store = Store(conn, path)
  use _ <- result.try(
    ffi_exec(conn, schema_sql()) |> result.map_error(SchemaError),
  )
  use rows <- result.try(
    run(store, "SELECT value FROM meta WHERE key = 'schema'", []),
  )
  case rows {
    [] -> {
      use #(_, _, _, utc) <- result.try(read_clock())
      use _ <- result.try(
        run(store, "INSERT INTO meta (key, value) VALUES ('schema', ?)", [
          CellText(sync.genesis),
        ]),
      )
      use _ <- result.try(
        run(
          store,
          "INSERT INTO meta (key, value) VALUES ('created_utc_us', ?)",
          [CellText(int.to_string(utc))],
        ),
      )
      Ok(store)
    }
    [[CellText(schema)]] ->
      case schema == sync.genesis {
        True -> Ok(store)
        False ->
          Error(SchemaError(
            "meta.schema mismatch: store has "
            <> schema
            <> ", this build expects "
            <> sync.genesis,
          ))
      }
    _ -> Error(SchemaError("malformed meta row for key 'schema'"))
  }
}

pub fn close(store: Store) -> Result(Nil, StoreError) {
  ffi_close(store.conn) |> result.map_error(StorageError)
}

// ---------------------------------------------------------------------
// Low-level typed SQL helpers
// ---------------------------------------------------------------------

fn run(
  store: Store,
  sql: String,
  params: List(Cell),
) -> Result(List(List(Cell)), StoreError) {
  ffi_query(store.conn, sql, params) |> result.map_error(StorageError)
}

fn begin(store: Store) -> Result(Nil, StoreError) {
  ffi_begin(store.conn)
  |> result.map_error(StorageError)
  |> result.map(fn(_) { Nil })
}

fn commit(store: Store) -> Result(Nil, StoreError) {
  ffi_commit(store.conn)
  |> result.map_error(StorageError)
  |> result.map(fn(_) { Nil })
}

fn rollback(store: Store) -> Result(Nil, StoreError) {
  ffi_rollback(store.conn)
  |> result.map_error(StorageError)
  |> result.map(fn(_) { Nil })
}

fn read_clock() -> Result(#(String, String, Int, Int), StoreError) {
  ffi_clock() |> result.map_error(StorageError)
}

/// Run `body` inside `BEGIN IMMEDIATE ... COMMIT`, rolling back on any
/// error and propagating that error (the rollback's own outcome, if it
/// also fails, is best-effort and does not shadow the original error).
fn transactionally(
  store: Store,
  body: fn() -> Result(a, StoreError),
) -> Result(a, StoreError) {
  use _ <- result.try(begin(store))
  case body() {
    Ok(value) -> {
      use _ <- result.try(commit(store))
      Ok(value)
    }
    Error(error) -> {
      let _ = rollback(store)
      Error(error)
    }
  }
}

// ---------------------------------------------------------------------
// Journal reconstruction
// ---------------------------------------------------------------------

/// Rebuild the canonical newline-joined journal text from stored rows, in
/// the exact byte form `session_sync.event_string` would produce for each
/// event: `body_json` is stored pre-encoded (see `session_sync.body_json_string`)
/// and is spliced back in verbatim rather than re-serialized, so this can
/// never introduce byte drift relative to what the digest was computed
/// over.
fn reconstruct_journal(store: Store) -> Result(String, StoreError) {
  use rows <- result.try(
    run(store, "SELECT body_json, digest FROM events ORDER BY sequence ASC", []),
  )
  use lines <- result.try(
    list.try_map(rows, fn(row) {
      case row {
        [CellText(body), CellText(digest)] ->
          Ok("{\"body\":" <> body <> ",\"digest\":\"" <> digest <> "\"}")
        _ ->
          Error(CorruptError(
            "malformed events row while reconstructing journal",
          ))
      }
    }),
  )
  Ok(string.join(lines, "\n"))
}

fn all_events(store: Store) -> Result(List(sync.Event), StoreError) {
  use rows <- result.try(
    run(store, "SELECT body_json, digest FROM events ORDER BY sequence ASC", []),
  )
  list.try_map(rows, fn(row) {
    case row {
      [CellText(body), CellText(digest)] -> {
        let line = "{\"body\":" <> body <> ",\"digest\":\"" <> digest <> "\"}"
        sync.decode_event(line) |> result.map_error(CorruptError)
      }
      _ -> Error(CorruptError("malformed events row"))
    }
  })
}

/// `#(sequence, digest)` of the current chain head, or
/// `#(0, session_sync.genesis)` for an empty store.
pub fn head(store: Store) -> Result(#(Int, String), StoreError) {
  use rows <- result.try(
    run(
      store,
      "SELECT sequence, digest FROM events ORDER BY sequence DESC LIMIT 1",
      [],
    ),
  )
  case rows {
    [] -> Ok(#(0, sync.genesis))
    [[CellInt(sequence), CellText(digest)]] -> Ok(#(sequence, digest))
    _ -> Error(CorruptError("malformed head row"))
  }
}

/// Fold `session_sync.replay` over the reconstructed journal. See the
/// module doc comment for the O(n) replay cost this implies.
pub fn replay(store: Store) -> Result(sync.State, StoreError) {
  use journal <- result.try(reconstruct_journal(store))
  sync.replay(journal) |> result.map_error(CorruptError)
}

/// Replay to a fresh `session_sync.State`, then normalize it against the
/// current host/boot/tick with `session_sync.rebase_clock`, mirroring the
/// file coordinator's `observe`. `query` receives that normalized state
/// plus the current `(boot, now)` pair used to normalize it.
pub fn observe(
  store: Store,
  query: fn(sync.State, String, Int) -> Result(Json, StoreError),
) -> Result(Json, StoreError) {
  use state <- result.try(replay(store))
  use #(host, boot, now, _utc) <- result.try(read_clock())
  use current <- result.try(
    sync.rebase_clock(state, host, boot, now) |> result.map_error(RefusedError),
  )
  query(current, boot, now)
}

/// The canonical journal lines, one event per line, in the exact byte
/// form the file coordinator's `journal` command prints.
pub fn journal(store: Store) -> Result(String, StoreError) {
  reconstruct_journal(store)
}

// ---------------------------------------------------------------------
// Append (the write path)
// ---------------------------------------------------------------------

/// Append `command` under `operation_id`, exactly reproducing the file
/// coordinator's semantics: `BEGIN IMMEDIATE`; replay the current chain;
/// build the event with `session_sync.make_event` using this store's own
/// clock (sequence, digest and previous_digest are never caller-supplied);
/// `session_sync.apply`; on success `INSERT` the row; `COMMIT`. A duplicate
/// `operation_id` (same command replayed) returns the original receipt with
/// `duplicate: True` and inserts no new row, matching
/// `session_sync.apply`'s idempotency contract.
pub fn append(
  store: Store,
  command: sync.Command,
  operation_id: String,
) -> Result(#(sync.Receipt, Bool), StoreError) {
  use command <- result.try(
    sync.canonical_command(command) |> result.map_error(RefusedError),
  )
  transactionally(store, fn() { append_locked(store, command, operation_id) })
}

fn append_locked(
  store: Store,
  command: sync.Command,
  operation_id: String,
) -> Result(#(sync.Receipt, Bool), StoreError) {
  use journal_text <- result.try(reconstruct_journal(store))
  use state <- result.try(
    sync.replay(journal_text) |> result.map_error(CorruptError),
  )
  use #(host, boot, tick, utc) <- result.try(read_clock())
  use #(_, receipt, duplicate) <- result.try(
    sync.apply(state, command, operation_id, host, boot, tick, utc)
    |> result.map_error(RefusedError),
  )
  case duplicate {
    True -> Ok(#(receipt, True))
    False -> {
      let event =
        sync.make_event(state, command, operation_id, host, boot, tick, utc)
      use _ <- result.try(insert_event(store, event, utc))
      Ok(#(receipt, False))
    }
  }
}

fn insert_event(
  store: Store,
  event: sync.Event,
  inserted_utc: Int,
) -> Result(Nil, StoreError) {
  let body_json = sync.body_json_string(event)
  let command_json = json.to_string(sync.command_to_json(event.command))
  let sql =
    "INSERT INTO events (
      sequence, operation_id, host_id, boot_id, tick_us, utc_us,
      operation, actor, command_json, body_json, previous_digest, digest,
      inserted_utc_us
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  let params = [
    CellInt(event.sequence),
    CellText(event.operation_id),
    CellText(event.host_id),
    CellText(event.boot_id),
    CellInt(event.tick_us),
    CellInt(event.utc_us),
    CellText(sync.operation(event.command)),
    CellText(sync.actor(event.command)),
    CellText(command_json),
    CellText(body_json),
    CellText(event.previous_digest),
    CellText(event.digest),
    CellInt(inserted_utc),
  ]
  use _ <- result.try(run(store, sql, params))
  Ok(Nil)
}

// ---------------------------------------------------------------------
// Verify
// ---------------------------------------------------------------------

fn add_if(failures: List(String), condition: Bool, message: String) {
  case condition {
    True -> [message, ..failures]
    False -> failures
  }
}

/// Independently recompute every chain link and every digest from stored
/// `body_json`, confirm the append-only triggers are installed, and confirm
/// every `operation_id` is unique. A tampered row (edited via a scratch
/// copy with the triggers dropped, or hand-built) is reported by exact
/// sequence and failed check rather than a generic refusal.
pub fn verify(store: Store) -> Result(VerifyReport, StoreError) {
  use rows <- result.try(
    run(
      store,
      "SELECT sequence, operation_id, previous_digest, digest, body_json FROM events ORDER BY sequence ASC",
      [],
    ),
  )
  use trigger_rows <- result.try(
    run(
      store,
      "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name IN ('events_no_update', 'events_no_delete', 'events_chain')",
      [],
    ),
  )
  let triggers_present = list.length(trigger_rows) == 3
  let #(_, _, failures, _) =
    list.fold(rows, #(0, sync.genesis, [], set.new()), fn(acc, row) {
      let #(expected_sequence, expected_previous, fails, seen_ops) = acc
      case row {
        [
          CellInt(sequence),
          CellText(operation_id),
          CellText(previous_digest),
          CellText(digest),
          CellText(body),
        ] -> {
          let sequence_ok = sequence == expected_sequence + 1
          let chain_ok = previous_digest == expected_previous
          let recomputed = board.sha256_hex(body)
          let digest_ok = recomputed == digest
          let duplicate_op = set.contains(seen_ops, operation_id)
          let label = "sequence " <> int.to_string(sequence)
          let fails =
            fails
            |> add_if(
              !sequence_ok,
              label
                <> ": expected sequence "
                <> int.to_string(expected_sequence + 1)
                <> ", found "
                <> int.to_string(sequence),
            )
            |> add_if(
              !chain_ok,
              label <> ": previous_digest does not match the prior row's digest",
            )
            |> add_if(
              !digest_ok,
              label
                <> ": stored digest does not recompute from body_json (sha256 mismatch)",
            )
            |> add_if(
              duplicate_op,
              label <> ": duplicate operation_id " <> operation_id,
            )
          #(sequence, digest, fails, set.insert(seen_ops, operation_id))
        }
        _ -> #(
          expected_sequence,
          expected_previous,
          ["malformed events row", ..fails],
          seen_ops,
        )
      }
    })
  let failures = case triggers_present {
    True -> failures
    False -> [
      "append-only triggers are missing (events_no_update, events_no_delete, events_chain)",
      ..failures
    ]
  }
  let failures = list.reverse(failures)
  Ok(VerifyReport(
    ok: list.is_empty(failures),
    checked: list.length(rows),
    sequence_ok: !list.any(failures, string.contains(_, "expected sequence")),
    chain_ok: !list.any(failures, string.contains(
      _,
      "previous_digest does not match",
    )),
    digest_ok: !list.any(failures, string.contains(_, "sha256 mismatch")),
    triggers_present: triggers_present,
    unique_operations: !list.any(failures, string.contains(
      _,
      "duplicate operation_id",
    )),
    failures: failures,
  ))
}

// ---------------------------------------------------------------------
// Migration from the file journal
// ---------------------------------------------------------------------

/// Read the file journal under `events_dir` (one canonical event per
/// `NNNNNNNNNN.json` file, as `session_sync_ffi`/`session_store_cli resign`
/// produce it), run `session_sync.resign` to recompute every digest from
/// genesis over the unchanged command content — this is the operator's
/// "ignore digest ... replace with correct digest" — then insert the
/// resulting canonical events in one transaction. Refuses if this store is
/// not empty. Unlike `append`, this does not require `events_dir` to be a
/// full session_sync_ffi-managed root (mode 0700, transaction lock, ...):
/// it only lists and reads `*.json` files, since the migration source may
/// be a read-only evidence copy rather than a live coordination root.
pub fn migrate_from_journal(
  events_dir: String,
  store: Store,
) -> Result(Int, StoreError) {
  use current_head <- result.try(head(store))
  use _ <- result.try(case current_head {
    #(0, _) -> Ok(Nil)
    #(sequence, _) ->
      Error(RefusedError(
        "migrate_from_journal refuses a non-empty store (head sequence "
        <> int.to_string(sequence)
        <> ")",
      ))
  })
  use journal_text <- result.try(read_journal_files(events_dir))
  use events <- result.try(
    sync.resign(journal_text) |> result.map_error(RefusedError),
  )
  transactionally(store, fn() {
    use _ <- result.try(
      list.try_each(events, fn(event) {
        insert_event(store, event, event.utc_us)
      }),
    )
    Ok(list.length(events))
  })
}

fn read_journal_files(events_dir: String) -> Result(String, StoreError) {
  use names <- result.try(
    simplifile.read_directory(events_dir)
    |> result.map_error(fn(error) {
      StorageError(
        "cannot list " <> events_dir <> ": " <> string.inspect(error),
      )
    }),
  )
  let files =
    names
    |> list.filter(fn(name) { string.ends_with(name, ".json") })
    |> list.sort(string.compare)
  use lines <- result.try(
    list.try_map(files, fn(name) {
      simplifile.read(events_dir <> "/" <> name)
      |> result.map_error(fn(error) {
        StorageError("cannot read " <> name <> ": " <> string.inspect(error))
      })
    }),
  )
  Ok(string.join(lines, "\n"))
}

// ---------------------------------------------------------------------
// Export (rollback path: SQLite store back to the file form)
// ---------------------------------------------------------------------

/// Write every stored event back out as one file per event under
/// `out_root/events/`, using the exact same names and byte form as the
/// file coordinator (`session_sync.event_string`, `NNNNNNNNNN.json`,
/// mode 0600 files under a mode 0700 directory). Refuses if `out_root/events`
/// already exists, so an export can never silently merge into or overwrite
/// another journal.
pub fn export(store: Store, out_root: String) -> Result(Int, StoreError) {
  use events <- result.try(all_events(store))
  let dir = out_root <> "/events"
  let already_exists = case simplifile.is_directory(dir) {
    Ok(exists) -> exists
    Error(_) -> False
  }
  use _ <- result.try(case already_exists {
    True ->
      Error(RefusedError("refusing to write: " <> dir <> " already exists"))
    False -> Ok(Nil)
  })
  use _ <- result.try(
    simplifile.create_directory_all(dir)
    |> result.map_error(fn(error) {
      StorageError("cannot create " <> dir <> ": " <> string.inspect(error))
    }),
  )
  let _ = simplifile.set_permissions_octal(out_root, 0o700)
  let _ = simplifile.set_permissions_octal(dir, 0o700)
  use _ <- result.try(
    list.try_each(events, fn(event) {
      let name = string.pad_start(int.to_string(event.sequence), 10, "0")
      let path = dir <> "/" <> name <> ".json"
      use _ <- result.try(
        simplifile.write(path, sync.event_string(event))
        |> result.map_error(fn(error) {
          StorageError("cannot write " <> path <> ": " <> string.inspect(error))
        }),
      )
      let _ = simplifile.set_permissions_octal(path, 0o600)
      Ok(Nil)
    }),
  )
  Ok(list.length(events))
}

// ---------------------------------------------------------------------
// Quarantine
// ---------------------------------------------------------------------

/// Record a raw line that could not be admitted as a canonical event
/// (malformed JSON, a digest that did not recompute, a chain gap) alongside
/// the reason it was refused. Quarantine rows are pure evidence: nothing
/// reads them back into `replay`/`apply`, and they carry no chain of their
/// own.
pub fn quarantine(
  store: Store,
  raw_line: String,
  reason: String,
) -> Result(Nil, StoreError) {
  use #(_, _, _, utc) <- result.try(read_clock())
  use _ <- result.try(
    run(
      store,
      "INSERT INTO quarantine (raw, reason, recorded_utc_us) VALUES (?, ?, ?)",
      [CellText(raw_line), CellText(reason), CellInt(utc)],
    ),
  )
  Ok(Nil)
}
