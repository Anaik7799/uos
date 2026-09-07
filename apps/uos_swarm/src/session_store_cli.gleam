//// SQLite-backed CLI for parallel Claude/Codex/AGY session coordination:
//// the same verbs and JSON receipts as session_sync_cli, mirrored onto
//// uos_swarm/session_store. The first argument to every mirrored verb is
//// the absolute path of the `.sqlite3` store (opened, used, closed once
//// per invocation — this CLI holds no long-lived connection). Commands
//// print JSON and use nonzero exit codes on refusal or storage error,
//// exactly like the file CLI.

import argv
import gleam/int
import gleam/io
import gleam/json
import gleam/result
import gleam/string
import uos_swarm/board
import uos_swarm/session_store as store
import uos_swarm/session_sync as sync

@external(erlang, "session_store_ffi", "halt")
fn halt(status: Int) -> Nil

fn refs(value: String) -> List(String) {
  case value {
    "-" -> []
    _ -> string.split(value, ",")
  }
}

fn number(value: String) -> Result(Int, String) {
  int.parse(value) |> result.replace_error("expected an integer")
}

fn respond(outcome: Result(String, String)) -> Nil {
  case outcome {
    Ok(text) -> io.println(text)
    Error(error) -> {
      io.println(
        json.to_string(
          json.object([
            #("ok", json.bool(False)),
            #("error", json.string(error)),
          ]),
        ),
      )
      halt(1)
    }
  }
}

/// Open `db`, run `f` against the store, close it, and fold both the open
/// and the body's own error into the one `Result(String, String)` shape
/// every command returns. The store is always closed, even on failure.
fn with_store(
  db: String,
  f: fn(store.Store) -> Result(String, store.StoreError),
) -> Result(String, String) {
  use opened <- result.try(
    store.open(db) |> result.map_error(store.error_to_string),
  )
  let outcome = f(opened)
  let _ = store.close(opened)
  outcome |> result.map_error(store.error_to_string)
}

fn execute(
  db: String,
  command: sync.Command,
  op: String,
) -> Result(String, String) {
  with_store(db, fn(opened) {
    store.append(opened, command, op)
    |> result.map(fn(outcome) {
      let #(receipt, duplicate) = outcome
      json.to_string(sync.receipt_json(receipt, duplicate))
    })
  })
}

pub fn run(args: List(String)) -> Result(String, String) {
  case args {
    ["schema"] -> Ok(store.schema_sql())
    ["verify", db] ->
      with_store(db, fn(opened) {
        store.verify(opened)
        |> result.map(fn(report) {
          json.to_string(store.verify_report_json(report))
        })
      })
    ["migrate", events_dir, db] ->
      with_store(db, fn(opened) {
        store.migrate_from_journal(events_dir, opened)
        |> result.map(fn(count) {
          json.to_string(
            json.object([
              #("ok", json.bool(True)),
              #("migrated_events", json.int(count)),
              #("events_dir", json.string(events_dir)),
              #("db", json.string(db)),
            ]),
          )
        })
      })
    ["export", db, out_root] ->
      with_store(db, fn(opened) {
        store.export(opened, out_root)
        |> result.map(fn(count) {
          json.to_string(
            json.object([
              #("ok", json.bool(True)),
              #("exported_events", json.int(count)),
              #("out_root", json.string(out_root)),
            ]),
          )
        })
      })
    [db, "register", s, provider, workspace, revision, metadata, op] ->
      execute(
        db,
        sync.Register(s, provider, workspace, revision, refs(metadata)),
        op,
      )
    [db, "heartbeat", s, revision, metadata, op] ->
      execute(db, sync.Heartbeat(s, revision, refs(metadata)), op)
    [db, "claim", s, resource, ttl, op] -> {
      use seconds <- result.try(number(ttl))
      execute(db, sync.Claim(s, resource, seconds * 1_000_000), op)
    }
    [db, "renew", s, resource, epoch, ttl, op] -> {
      use epoch <- result.try(number(epoch))
      use seconds <- result.try(number(ttl))
      execute(db, sync.Renew(s, resource, epoch, seconds * 1_000_000), op)
    }
    [db, "release", s, resource, epoch, op] -> {
      use epoch <- result.try(number(epoch))
      execute(db, sync.Release(s, resource, epoch), op)
    }
    [db, "send", s, to, kind, text, metadata, op] -> {
      use kind <- result.try(board.kind_from_label(kind))
      execute(db, sync.Send(s, to, kind, text, refs(metadata)), op)
    }
    [db, "ack", s, message_id, op] -> execute(db, sync.Ack(s, message_id), op)
    [db, "retire", s, op] -> execute(db, sync.Retire(s), op)
    [db, "status"] ->
      with_store(db, fn(opened) {
        store.observe(opened, fn(state, boot, now) {
          Ok(sync.status_json(state, boot, now))
        })
        |> result.map(json.to_string)
      })
    [db, "inbox", s] ->
      with_store(db, fn(opened) {
        store.observe(opened, fn(state, _boot, _now) {
          Ok(sync.inbox_json(state, s))
        })
        |> result.map(json.to_string)
      })
    [db, "check", s, resource, epoch] -> {
      use epoch <- result.try(number(epoch))
      use resource <- result.try(sync.canonical_resource(resource))
      with_store(db, fn(opened) {
        store.observe(opened, fn(state, boot, now) {
          use _ <- result.try(
            sync.check(state, s, resource, epoch, boot, now)
            |> result.map_error(store.RefusedError),
          )
          Ok(
            json.object([
              #("ok", json.bool(True)),
              #("resource", json.string(resource)),
              #("holder", json.string(s)),
              #("epoch", json.int(epoch)),
              #("checked_boot_us", json.int(now)),
              #(
                "scope",
                json.string("cooperative fence observation; no action executed"),
              ),
            ]),
          )
        })
        |> result.map(json.to_string)
      })
    }
    [db, "journal"] -> with_store(db, fn(opened) { store.journal(opened) })
    _ -> Error(usage())
  }
}

pub fn usage() -> String {
  "gleam run -m session_store_cli -- <absolute_sqlite3_path> <command> ...\n"
  <> "register <session> <claude|codex|agy> <workspace> <revision> <refs_csv|-> <op_id>\n"
  <> "heartbeat <session> <revision> <refs_csv|-> <op_id>\n"
  <> "claim <session> <task:id|workspace:path|integration/main|runtime:service> <ttl_seconds> <op_id>\n"
  <> "renew <session> <resource> <epoch> <ttl_seconds> <op_id>\n"
  <> "release <session> <resource> <epoch> <op_id>\n"
  <> "send <from> <to|broadcast> <Report|Progress|Question|Answer|Andon> <text> <refs_csv|-> <op_id>\n"
  <> "inbox <session> | ack <session> <message_id> <op_id> | retire <session> <op_id>\n"
  <> "status | check <session> <resource> <epoch> | journal\n"
  <> "\n"
  <> "gleam run -m session_store_cli -- verify <absolute_sqlite3_path>\n"
  <> "gleam run -m session_store_cli -- migrate <events_dir> <absolute_sqlite3_path>\n"
  <> "gleam run -m session_store_cli -- export <absolute_sqlite3_path> <out_root>\n"
  <> "gleam run -m session_store_cli -- schema\n"
  <> "\n"
  <> "SQLite store, journal_mode=WAL, busy_timeout=30s. ACKs are self-reported;\n"
  <> "leases require executor fencing. Retry uncertain mutations with their\n"
  <> "original op_id: duplicate operation_ids return the original receipt.\n"
  <> "The events table is append-only by trigger; never edit rows directly."
}

pub fn main() -> Nil {
  let args = argv.load().arguments
  case args {
    ["--help"] | ["help"] | [] -> io.println(usage())
    _ -> respond(run(args))
  }
}
