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

import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import gleam/uri
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

@external(erlang, "session_store_ffi", "open_existing")
fn ffi_open_existing(path: String) -> Result(Conn, String)

@external(erlang, "erlang", "binary_to_list")
fn ascii_charlist(text: String) -> List(Int)

@external(erlang, "esqlite3", "open")
fn ffi_open_uri(path: List(Int)) -> Result(Conn, Dynamic)

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
  Store(conn: Conn, path: String, generation: String)
}

/// A bounded, path- and request-bound critical section. The operation id is
/// diagnostic/replay context for the caller; durable idempotency remains the
/// caller's responsibility. SQLite serializes all such sections globally.
pub opaque type CriticalSection {
  CriticalSection(path_key: String, operation_id: String)
}

pub fn critical_section(
  path_key: String,
  operation_id: String,
) -> Result(CriticalSection, String) {
  let path_parts = string.split(path_key, "/")
  let path_valid =
    string.byte_size(path_key) > 0
    && string.byte_size(path_key) <= 512
    && !string.starts_with(path_key, "/")
    && !string.contains(path_key, "\\")
    && !string.contains(path_key, "\u{0}")
    && list.all(path_parts, fn(part) {
      part != "" && part != "." && part != ".."
    })
  let operation_valid =
    string.length(operation_id) > 0
    && string.length(operation_id) <= 128
    && list.all(string.to_graphemes(operation_id), fn(character) {
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:",
        character,
      )
    })
  case path_valid && operation_valid {
    True -> Ok(CriticalSection(path_key, operation_id))
    False -> Error("critical_section_binding_invalid")
  }
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
    replay_ok: Bool,
    triggers_present: Bool,
    trigger_definitions_ok: Bool,
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
    #("replay_ok", json.bool(report.replay_ok)),
    #("nonempty", json.bool(report.checked > 0)),
    #("authority", json.string("integrity_observation_only")),
    #("triggers_present", json.bool(report.triggers_present)),
    #("trigger_definitions_ok", json.bool(report.trigger_definitions_ok)),
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

-- `events_no_delete` alone does NOT make the table append-only: SQLite fires
-- DELETE triggers for the implicit delete of `INSERT OR REPLACE` only when
-- `PRAGMA recursive_triggers` is ON, and its default is OFF. A raw
-- `INSERT OR REPLACE` reusing an existing `operation_id` or `digest` would
-- therefore drop the historical row silently (measured on a scratch copy,
-- review wf_5f54e14c-28b). This BEFORE INSERT guard refuses any insert that
-- collides with a stored row, so the REPLACE never reaches its delete.
CREATE TRIGGER IF NOT EXISTS events_no_replace
BEFORE INSERT ON events
WHEN EXISTS (
  SELECT 1 FROM events
  WHERE sequence = NEW.sequence
     OR operation_id = NEW.operation_id
     OR digest = NEW.digest
)
BEGIN
  SELECT RAISE(ABORT, 'events are append-only: an insert may not reuse a stored sequence, operation_id or digest');
END;

-- Reject foreign payloads before they enter the append-only ledger. A chain
-- link alone does not prove a typed event, and an unregistered sender is not
-- made authoritative by supplying a correctly shaped digest. Full digest and
-- state-machine verification still belongs to the typed transactional writer.
CREATE TRIGGER IF NOT EXISTS events_payload
BEFORE INSERT ON events
WHEN COALESCE(CASE
  WHEN json_valid(NEW.body_json) AND json_valid(NEW.command_json) THEN
    json_extract(NEW.body_json, '$.schema') = '" <> sync.genesis <> "'
    AND json_type(NEW.body_json, '$.sequence') = 'integer'
    AND json_type(NEW.body_json, '$.tick_us') = 'integer'
    AND json_type(NEW.body_json, '$.utc_us') = 'integer'
    AND json_extract(NEW.body_json, '$.sequence') = NEW.sequence
    AND json_extract(NEW.body_json, '$.operation_id') = NEW.operation_id
    AND json_extract(NEW.body_json, '$.host_id') = NEW.host_id
    AND json_extract(NEW.body_json, '$.boot_id') = NEW.boot_id
    AND json_extract(NEW.body_json, '$.tick_us') = NEW.tick_us
    AND json_extract(NEW.body_json, '$.utc_us') = NEW.utc_us
    AND json_extract(NEW.body_json, '$.previous_digest') = NEW.previous_digest
    AND json_extract(NEW.command_json, '$.operation') = NEW.operation
    AND json_extract(NEW.command_json, '$.session') = NEW.actor
    AND json_type(NEW.command_json, '$.a') = 'text'
    AND json_type(NEW.command_json, '$.b') = 'text'
    AND json_type(NEW.command_json, '$.c') = 'text'
    AND json_type(NEW.command_json, '$.refs') = 'array'
    AND NOT EXISTS (SELECT 1 FROM json_each(NEW.command_json, '$.refs') WHERE type <> 'text')
    AND json_type(NEW.command_json, '$.epoch') = 'integer'
    AND json_type(NEW.command_json, '$.ttl_us') = 'integer'
    AND json(NEW.command_json) = json(json_extract(NEW.body_json, '$.command'))
    AND NEW.operation IN ('register','heartbeat','claim','renew','release','send','ack','retire')
    AND length(NEW.digest) = 64 AND NEW.digest NOT GLOB '*[^0-9a-f]*'
    AND ((NEW.operation = 'register'
      AND json_extract(NEW.command_json, '$.a') IN ('claude','codex','agy')
      AND substr(json_extract(NEW.command_json, '$.b'),1,1) = '/'
      AND NOT EXISTS (SELECT 1 FROM events WHERE actor=NEW.actor AND operation='register')) OR (
      NEW.operation <> 'register' AND (
      SELECT operation = 'register' FROM events
      WHERE actor = NEW.actor AND operation IN ('register','retire')
      ORDER BY sequence DESC LIMIT 1
    )))
  ELSE 0 END, 0) = 0
BEGIN
  SELECT RAISE(ABORT, 'events payload invalid: typed envelope, column binding and registered actor required');
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
pub fn verify_file(path: String) -> Result(VerifyReport, StoreError) {
  use _ <- result.try(
    case
      string.starts_with(path, "/")
      && !string.contains(path, "\u{0}")
      && string.byte_size(path) <= 1024
    {
      True -> Ok(Nil)
      False ->
        Error(OpenError("verification requires a bounded absolute file path"))
    },
  )
  use _ <- result.try(recovery_clear(path))
  use generation <- result.try(recovery_generation(path))
  let encoded =
    path
    |> string.split("/")
    |> list.map(uri.percent_encode)
    |> string.join("/")
  let sqlite_uri = "file://" <> encoded <> "?mode=ro&cache=private"
  use conn <- result.try(
    ffi_open_uri(ascii_charlist(sqlite_uri))
    |> result.map_error(fn(error) { OpenError(string.inspect(error)) }),
  )
  let opened = Store(conn, path, generation)
  let outcome = {
    use _ <- result.try(
      ffi_exec(conn, "BEGIN") |> result.map_error(StorageError),
    )
    use schema <- result.try(
      run(opened, "SELECT value FROM meta WHERE key = 'schema'", []),
    )
    use _ <- result.try(case schema {
      [[CellText(value)]] if value == sync.genesis -> Ok(Nil)
      _ -> Error(SchemaError("missing or incompatible meta.schema"))
    })
    use _ <- result.try(recovery_current(opened))
    verify(opened)
  }
  let closed = close(opened)
  case outcome {
    Error(error) -> Error(error)
    Ok(report) -> closed |> result.replace(report)
  }
}

/// Open (creating if absent) a SQLite store at `path`, apply the schema,
/// and verify `meta.schema == session_sync.genesis`. A freshly created
/// store gets its `meta` rows written here; an existing store is only read.
pub fn open(path: String) -> Result(Store, StoreError) {
  use _ <- result.try(recovery_clear(path))
  use generation <- result.try(recovery_generation(path))
  use conn <- result.try(ffi_open(path) |> result.map_error(OpenError))
  // Recheck after opening so a newly raised recovery hold cannot admit a writer.
  let store = Store(conn, path, generation)
  case recovery_current(store) {
    Error(reason) -> {
      let _ = ffi_close(conn)
      Error(reason)
    }
    Ok(_) -> initialize(store)
  }
}

/// Operational authority never initializes missing, truncated or empty history.
pub fn open_existing(path: String) -> Result(Store, StoreError) {
  use _ <- result.try(recovery_clear(path))
  use generation <- result.try(recovery_generation(path))
  use conn <- result.try(ffi_open_existing(path) |> result.map_error(OpenError))
  let store = Store(conn, path, generation)
  let checked = {
    use _ <- result.try(recovery_current(store))
    use metadata <- result.try(
      run(store, "SELECT value FROM meta WHERE key = 'schema'", []),
    )
    use _ <- result.try(case metadata {
      [[CellText(schema)]] if schema == sync.genesis -> Ok(Nil)
      _ -> Error(SchemaError("operational_coordinator_schema_mismatch"))
    })
    use report <- result.try(verify(store))
    use #(rows, _) <- result.try(head(store))
    use _ <- result.try(recovery_current(store))
    case report.ok && rows > 0 {
      True -> Ok(store)
      False ->
        Error(CorruptError(
          "operational_coordinator_requires_verified_nonempty_ledger",
        ))
    }
  }
  case checked {
    Ok(_) -> checked
    Error(_) -> {
      let _ = ffi_close(conn)
      checked
    }
  }
}

fn recovery_clear(path: String) -> Result(Nil, StoreError) {
  case simplifile.link_info(path <> ".recovery-lock") {
    Error(simplifile.Enoent) -> Ok(Nil)
    Ok(_) -> Error(RefusedError("coordinator_recovery_in_progress"))
    Error(_) -> Error(RefusedError("coordinator_recovery_lock_unknown"))
  }
}

fn recovery_generation(path: String) -> Result(String, StoreError) {
  let marker = path <> ".recovery-generation"
  case simplifile.link_info(marker) {
    Error(simplifile.Enoent) -> Ok("genesis")
    Ok(info) ->
      case
        simplifile.file_info_type(info) == simplifile.File
        && info.size > 0
        && info.size <= 256
      {
        True ->
          simplifile.read(marker)
          |> result.map_error(fn(_) {
            RefusedError("coordinator_generation_unreadable")
          })
        False -> Error(RefusedError("coordinator_generation_invalid"))
      }
    Error(_) -> Error(RefusedError("coordinator_generation_unknown"))
  }
}

fn recovery_current(store: Store) -> Result(Nil, StoreError) {
  use _ <- result.try(recovery_clear(store.path))
  use generation <- result.try(recovery_generation(store.path))
  case generation == store.generation {
    True -> Ok(Nil)
    False -> Error(RefusedError("coordinator_connection_generation_retired"))
  }
}

fn initialize(store: Store) -> Result(Store, StoreError) {
  let conn = store.conn
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
  let outcome = {
    use value <- result.try(body())
    use _ <- result.try(recovery_current(store))
    use _ <- result.try(commit(store))
    Ok(value)
  }
  case outcome {
    Ok(_) -> outcome
    Error(error) -> {
      let _ = rollback(store)
      Error(error)
    }
  }
}

/// Run a short external effect while this connection holds SQLite's writer
/// transaction. This globally serializes admitted writers; it is not a lock
/// against writers that bypass this store. The callback receives the already
/// replayed and clock-rebased state so it must not reopen/reenter the store.
/// If an external effect lands and COMMIT then fails, the result is uncertain
/// and the caller must reconcile its durable intent rather than retry.
pub fn with_critical_section(
  store: Store,
  section: CriticalSection,
  body: fn(sync.State, String, Int) -> Result(a, String),
) -> Result(a, StoreError) {
  use _ <- result.try(recovery_current(store))
  transactionally(store, fn() {
    use _ <- result.try(recovery_current(store))
    use journal_text <- result.try(reconstruct_journal(store))
    use state <- result.try(
      sync.replay(journal_text) |> result.map_error(CorruptError),
    )
    use #(host, boot, now, _utc) <- result.try(read_clock())
    use current <- result.try(
      sync.rebase_clock(state, host, boot, now)
      |> result.map_error(RefusedError),
    )
    let _binding = section.path_key <> "\u{0}" <> section.operation_id
    body(current, boot, now) |> result.map_error(RefusedError)
  })
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
  query: fn(sync.State, String, Int) -> Result(a, StoreError),
) -> Result(a, StoreError) {
  use _ <- result.try(recovery_current(store))
  use state <- result.try(replay(store))
  use #(host, boot, now, _utc) <- result.try(read_clock())
  use current <- result.try(
    sync.rebase_clock(state, host, boot, now) |> result.map_error(RefusedError),
  )
  use _ <- result.try(recovery_current(store))
  use value <- result.try(query(current, boot, now))
  use _ <- result.try(recovery_current(store))
  Ok(value)
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
  use _ <- result.try(recovery_current(store))
  use command <- result.try(
    sync.canonical_command(command) |> result.map_error(RefusedError),
  )
  transactionally(store, fn() {
    use _ <- result.try(recovery_current(store))
    append_locked(store, command, operation_id)
  })
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

/// Every failure row carries a typed check name beside its message, so the
/// report's per-check booleans are derived from the check name and never from
/// parsing text that embeds caller-supplied values such as an `operation_id`
/// (review wf_5f54e14c-28b: an id containing "sha256 mismatch" would otherwise
/// flip `digest_ok`).
fn add_if(
  failures: List(#(String, String)),
  condition: Bool,
  check: String,
  message: String,
) -> List(#(String, String)) {
  case condition {
    True -> [#(check, message), ..failures]
    False -> failures
  }
}

/// Independently recompute every chain link and every digest from stored
/// `body_json`, confirm the append-only triggers are installed, and confirm
/// every `operation_id` is unique. A tampered row (edited via a scratch
/// copy with the triggers dropped, or hand-built) is reported by exact
/// sequence and failed check rather than a generic refusal.
fn required_trigger_sql() -> List(String) {
  schema_sql()
  |> string.split("CREATE TRIGGER IF NOT EXISTS ")
  |> list.drop(1)
  |> list.map(fn(part) {
    let first = string.split(part, "\nEND;") |> list.first |> result.unwrap("")
    "CREATE TRIGGER " <> first <> "\nEND"
  })
}

pub fn events_payload_v1_sql() -> String {
  let triggers = required_trigger_sql()
  list.drop(triggers, 4) |> list.first |> result.unwrap("")
}

pub fn events_payload_v2_sql() -> String {
  string.replace(
    events_payload_v1_sql(),
    "IN ('claude','codex','agy')",
    "IN ('claude','codex','agy','service')",
  )
}

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
      "SELECT name, sql FROM sqlite_master WHERE type = 'trigger' AND name IN ('events_no_update', 'events_no_delete', 'events_chain', 'events_no_replace', 'events_payload')",
      [],
    ),
  )
  let triggers_present = list.length(trigger_rows) == 5
  let required_common = list.take(required_trigger_sql(), 4)
  let common_triggers_ok =
    list.all(required_common, fn(sql) {
      list.any(trigger_rows, fn(row) {
        case row {
          [CellText(_), CellText(actual)] -> actual == sql
          _ -> False
        }
      })
    })
  let payload_trigger_row =
    list.find(trigger_rows, fn(row) {
      case row {
        [CellText("events_payload"), CellText(_)] -> True
        _ -> False
      }
    })
  let payload_trigger_ok = case payload_trigger_row {
    Ok([CellText(_), CellText(actual)]) ->
      actual == events_payload_v1_sql() || actual == events_payload_v2_sql()
    _ -> False
  }
  let trigger_definitions_ok = common_triggers_ok && payload_trigger_ok
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
              "sequence",
              label
                <> ": expected sequence "
                <> int.to_string(expected_sequence + 1)
                <> ", found "
                <> int.to_string(sequence),
            )
            |> add_if(
              !chain_ok,
              "chain",
              label <> ": previous_digest does not match the prior row's digest",
            )
            |> add_if(
              !digest_ok,
              "digest",
              label
                <> ": stored digest does not recompute from body_json (sha256 mismatch)",
            )
            |> add_if(
              duplicate_op,
              "duplicate",
              label <> ": duplicate operation_id " <> operation_id,
            )
          #(sequence, digest, fails, set.insert(seen_ops, operation_id))
        }
        _ -> #(
          expected_sequence,
          expected_previous,
          [#("malformed", "malformed events row"), ..fails],
          seen_ops,
        )
      }
    })
  let failures = case triggers_present {
    True -> failures
    False -> [
      #(
        "triggers",
        "store guards are missing (events_no_update, events_no_delete, events_chain, events_no_replace, events_payload)",
      ),
      ..failures
    ]
  }
  let replay_result =
    list.try_map(rows, fn(row) {
      case row {
        [_, _, _, CellText(digest), CellText(body)] ->
          Ok(
            "{\"body\":"
            <> body
            <> ",\"digest\":"
            <> json.to_string(json.string(digest))
            <> "}",
          )
        _ -> Error("malformed events row")
      }
    })
    |> result.try(fn(lines) { sync.replay(string.join(lines, "\n")) })
  let failures = case replay_result {
    Ok(_) -> failures
    Error(reason) -> [
      #("replay", "typed replay failed: " <> reason),
      ..failures
    ]
  }
  let failures =
    failures
    |> add_if(
      !trigger_definitions_ok,
      "trigger_definitions",
      "append-only trigger definitions do not match this candidate's required schema",
    )
    |> list.reverse
  let failed = fn(check: String) {
    list.any(failures, fn(entry) { entry.0 == check })
  }
  Ok(VerifyReport(
    ok: list.is_empty(failures),
    checked: list.length(rows),
    sequence_ok: !failed("sequence") && !failed("malformed"),
    chain_ok: !failed("chain") && !failed("malformed"),
    digest_ok: !failed("digest") && !failed("malformed"),
    replay_ok: !failed("replay"),
    triggers_present: triggers_present,
    trigger_definitions_ok: trigger_definitions_ok,
    unique_operations: !failed("duplicate"),
    failures: list.map(failures, fn(entry) { entry.1 }),
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

/// Verified read-only snapshot for bounded observation workers. The caller must
/// isolate this operation with an OS deadline; SQLite limits alone are not a
/// whole-invocation deadline. No initialization, journal-mode change or writes.
pub fn observe_file(
  path: String,
  query: fn(sync.State, String, Int) -> Result(a, StoreError),
) -> Result(a, StoreError) {
  use _ <- result.try(
    case
      string.starts_with(path, "/")
      && !string.contains(path, "\u{0}")
      && string.byte_size(path) <= 1024
    {
      True -> Ok(Nil)
      False -> Error(OpenError("observation_path_invalid"))
    },
  )
  use info <- result.try(
    simplifile.link_info(path)
    |> result.replace_error(OpenError("observation_file_unavailable")),
  )
  use _ <- result.try(
    case
      simplifile.file_info_type(info) == simplifile.File
      && info.size > 0
      && info.size <= 67_108_864
    {
      True -> Ok(Nil)
      False -> Error(OpenError("observation_file_bound"))
    },
  )
  use _ <- result.try(recovery_clear(path))
  use generation <- result.try(recovery_generation(path))
  let encoded =
    path
    |> string.split("/")
    |> list.map(uri.percent_encode)
    |> string.join("/")
  use conn <- result.try(
    ffi_open_uri(ascii_charlist(
      "file://" <> encoded <> "?mode=ro&cache=private",
    ))
    |> result.replace_error(OpenError("observation_open_failed")),
  )
  let opened = Store(conn, path, generation)
  let outcome = {
    use _ <- result.try(
      ffi_exec(conn, "PRAGMA busy_timeout=200")
      |> result.map_error(StorageError),
    )
    use _ <- result.try(
      ffi_exec(conn, "PRAGMA query_only=ON") |> result.map_error(StorageError),
    )
    use _ <- result.try(
      ffi_exec(conn, "BEGIN") |> result.map_error(StorageError),
    )
    use schema <- result.try(
      run(opened, "SELECT value FROM meta WHERE key = 'schema'", []),
    )
    use _ <- result.try(case schema {
      [[CellText(value)]] if value == sync.genesis -> Ok(Nil)
      _ -> Error(SchemaError("observation_schema_mismatch"))
    })
    use sizes <- result.try(
      run(
        opened,
        "SELECT count(*), COALESCE(sum(length(CAST(body_json AS BLOB)) + length(CAST(command_json AS BLOB)) + length(digest)),0) FROM events",
        [],
      ),
    )
    use _ <- result.try(case sizes {
      [[CellInt(count), CellInt(bytes)]]
        if count > 0 && count <= 20_000 && bytes > 0 && bytes <= 16_777_216
      -> Ok(Nil)
      _ -> Error(RefusedError("observation_ledger_bound"))
    })
    use report <- result.try(verify(opened))
    use _ <- result.try(case report.ok && report.checked > 0 {
      True -> Ok(Nil)
      False -> Error(CorruptError("observation_integrity_refused"))
    })
    observe(opened, query)
  }
  let closed = close(opened)
  case outcome {
    Error(error) -> Error(error)
    Ok(value) -> closed |> result.replace(value)
  }
}

// ---------------------------------------------------------------------
// Service Provider Migration (v1 -> v2)
// ---------------------------------------------------------------------

/// Explicit staged migration from v1 trigger schema ('claude','codex','agy')
/// to v2 ('claude','codex','agy','service').
///
/// Preconditions:
/// 1. Recovery clear (no recovery in progress)
/// 2. Schema metadata matches genesis
/// 3. Store independently verifies (chain, sequence, digests, triggers)
/// 4. Current events_payload trigger matches events_payload_v1_sql() (or already v2)
///
/// Execution:
/// Transactionally drop v1 trigger and create v2 trigger under BEGIN IMMEDIATE.
///
/// Postconditions:
/// 1. Store independently verifies under v2
/// 2. Event count and head digest are byte-for-byte identical (no history mutation)
fn migration_require(ok: Bool, reason: String) -> Result(Nil, StoreError) {
  case ok {
    True -> Ok(Nil)
    False -> Error(RefusedError(reason))
  }
}

/// Development migration is confined to a fresh private staged candidate.
/// This function cannot migrate the operational coordinator or path aliases.
fn migration_stage_identity(
  path: String,
) -> Result(simplifile.FileInfo, StoreError) {
  use stage <- result.try(case string.split(path, "/") {
    ["", "tmp", "uos-telegram-provider-stage-" <> nonce, "coordinator.sqlite3"] -> {
      use _ <- result.try(migration_require(
        nonce != ""
          && string.byte_size(nonce) <= 128
          && list.all(string.to_graphemes(nonce), fn(c) {
          string.contains(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_",
            c,
          )
        }),
        "provider_migration_requires_private_stage",
      ))
      Ok("/tmp/uos-telegram-provider-stage-" <> nonce)
    }
    _ -> Error(RefusedError("provider_migration_requires_private_stage"))
  })
  use tmp <- result.try(
    simplifile.link_info("/tmp")
    |> result.map_error(fn(_) {
      RefusedError("provider_stage_parent_unavailable")
    }),
  )
  use owner <- result.try(
    simplifile.file_info("/proc/self")
    |> result.map_error(fn(_) {
      RefusedError("provider_stage_owner_unavailable")
    }),
  )
  use directory <- result.try(
    simplifile.link_info(stage)
    |> result.map_error(fn(_) {
      RefusedError("provider_stage_directory_unavailable")
    }),
  )
  use file <- result.try(
    simplifile.link_info(path)
    |> result.map_error(fn(_) {
      RefusedError("provider_stage_file_unavailable")
    }),
  )
  use _ <- result.try(migration_require(
    simplifile.file_info_type(tmp) == simplifile.Directory
      && tmp.user_id == 0
      && int.bitwise_and(tmp.mode, 0o1000) != 0
      && simplifile.file_info_type(directory) == simplifile.Directory
      && directory.user_id == owner.user_id
      && simplifile.file_info_permissions_octal(directory) == 0o700
      && simplifile.file_info_type(file) == simplifile.File
      && file.user_id == owner.user_id
      && simplifile.file_info_permissions_octal(file) == 0o600
      && file.nlinks == 1,
    "provider_stage_permissions_or_identity_invalid",
  ))
  Ok(file)
}

fn migration_identity_current(
  path: String,
  original: simplifile.FileInfo,
) -> Result(Nil, StoreError) {
  use current <- result.try(migration_stage_identity(path))
  migration_require(
    current.inode == original.inode && current.dev == original.dev,
    "provider_stage_identity_changed",
  )
}

fn migration_payload_sql(store: Store) -> Result(String, StoreError) {
  use rows <- result.try(
    run(
      store,
      "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'events_payload'",
      [],
    ),
  )
  case rows {
    [[CellText(sql)]] -> Ok(sql)
    _ -> Error(SchemaError("provider_stage_payload_trigger_missing"))
  }
}

pub fn migrate_to_service_provider(path: String) -> Result(Nil, StoreError) {
  use identity <- result.try(migration_stage_identity(path))
  use _ <- result.try(recovery_clear(path))
  use generation <- result.try(recovery_generation(path))
  use conn <- result.try(ffi_open_existing(path) |> result.map_error(OpenError))
  let store = Store(conn, path, generation)
  let outcome =
    transactionally(store, fn() {
      use _ <- result.try(migration_identity_current(path, identity))
      use _ <- result.try(recovery_current(store))
      use metadata <- result.try(
        run(store, "SELECT value FROM meta WHERE key = 'schema'", []),
      )
      use _ <- result.try(case metadata {
        [[CellText(schema)]] if schema == sync.genesis -> Ok(Nil)
        _ -> Error(SchemaError("operational_coordinator_schema_mismatch"))
      })
      use before <- result.try(verify(store))
      use _ <- result.try(migration_require(
        before.ok,
        "provider_stage_preverification_failed",
      ))
      use #(pre_count, pre_digest) <- result.try(head(store))
      use _ <- result.try(migration_require(
        pre_count > 0,
        "provider_stage_requires_verified_history",
      ))
      use pre_journal <- result.try(reconstruct_journal(store))
      use sql <- result.try(migration_payload_sql(store))
      use _ <- result.try(case sql == events_payload_v2_sql() {
        True -> Ok(Nil)
        False -> {
          use _ <- result.try(migration_require(
            sql == events_payload_v1_sql(),
            "provider_stage_unknown_payload_trigger",
          ))
          use _ <- result.try(
            ffi_exec(conn, "DROP TRIGGER events_payload;")
            |> result.map_error(SchemaError),
          )
          ffi_exec(conn, events_payload_v2_sql() <> ";")
          |> result.map(fn(_) { Nil })
          |> result.map_error(SchemaError)
        }
      })
      use after <- result.try(verify(store))
      use post_sql <- result.try(migration_payload_sql(store))
      use #(post_count, post_digest) <- result.try(head(store))
      use post_journal <- result.try(reconstruct_journal(store))
      use _ <- result.try(migration_require(
        after.ok
          && post_sql == events_payload_v2_sql()
          && pre_count == post_count
          && pre_digest == post_digest
          && pre_journal == post_journal,
        "provider_stage_postcondition_failed",
      ))
      use _ <- result.try(migration_identity_current(path, identity))
      // transactionally rechecks recovery generation/lock immediately before COMMIT.
      Ok(Nil)
    })
  let _ = ffi_close(conn)
  outcome
}
