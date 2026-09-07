//// Bounded local CLI for parallel Claude/Codex/AGY session coordination.
//// Commands print JSON and use nonzero exit codes on refusal or storage error.
//// No command executes a deployment, shell payload, VCS mutation, or ACK on
//// another process's behalf. A caller supplies its own declared session ID.

import argv
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile
import uos_swarm/board
import uos_swarm/session_sync as sync

@external(erlang, "session_sync_ffi", "halt")
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

pub fn run(args: List(String)) -> Result(String, String) {
  case args {
    [root, "register", s, provider, workspace, revision, metadata, op] ->
      sync.execute(
        root,
        sync.Register(s, provider, workspace, revision, refs(metadata)),
        op,
      )
    [root, "heartbeat", s, revision, metadata, op] ->
      sync.execute(root, sync.Heartbeat(s, revision, refs(metadata)), op)
    [root, "claim", s, resource, ttl, op] -> {
      use seconds <- result.try(number(ttl))
      sync.execute(root, sync.Claim(s, resource, seconds * 1_000_000), op)
    }
    [root, "renew", s, resource, epoch, ttl, op] -> {
      use epoch <- result.try(number(epoch))
      use seconds <- result.try(number(ttl))
      sync.execute(
        root,
        sync.Renew(s, resource, epoch, seconds * 1_000_000),
        op,
      )
    }
    [root, "release", s, resource, epoch, op] -> {
      use epoch <- result.try(number(epoch))
      sync.execute(root, sync.Release(s, resource, epoch), op)
    }
    [root, "send", s, to, kind, text, metadata, op] -> {
      use kind <- result.try(board.kind_from_label(kind))
      sync.execute(root, sync.Send(s, to, kind, text, refs(metadata)), op)
    }
    [root, "ack", s, message_id, op] ->
      sync.execute(root, sync.Ack(s, message_id), op)
    [root, "retire", s, op] -> sync.execute(root, sync.Retire(s), op)
    [root, "status"] ->
      sync.observe(root, fn(state, boot, now) {
        Ok(sync.status_json(state, boot, now))
      })
    [root, "inbox", s] ->
      sync.observe(root, fn(state, _, _) { Ok(sync.inbox_json(state, s)) })
    [root, "check", s, resource, epoch] -> {
      use epoch <- result.try(number(epoch))
      use resource <- result.try(sync.canonical_resource(resource))
      sync.observe(root, fn(state, boot, now) {
        use _ <- result.try(sync.check(state, s, resource, epoch, boot, now))
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
    }
    [root, "journal"] -> sync.read_journal(root)
    [root, "resign", out_root] -> resign_into(root, out_root)
    [root, "compact", out_root] -> compact_into(root, out_root)
    [root, "recover-lock"] -> {
      use message <- result.try(sync.recover_lock(root))
      Ok(
        json.to_string(
          json.object([
            #("ok", json.bool(True)),
            #("result", json.string(message)),
          ]),
        ),
      )
    }
    _ -> Error(usage())
  }
}

/// `resign <root> <out_root>`: rebuild the journal under `root` with this
/// module's canonical byte form and digests (see `session_sync.resign`) and
/// write it as a fresh `events/` directory under `out_root`, which must not
/// already contain an `events/` directory. The source journal is never
/// modified; swapping directories is a separate, recorded operator step.
fn resign_into(root: String, out_root: String) -> Result(String, String) {
  use journal <- result.try(sync.read_journal(root))
  use events <- result.try(sync.resign(journal))
  let dir = out_root <> "/events"
  use _ <- result.try(case simplifile.is_directory(dir) {
    Ok(True) -> Error("refusing to write: " <> dir <> " already exists")
    _ -> Ok(Nil)
  })
  use _ <- result.try(
    simplifile.create_directory_all(dir)
    |> result.map_error(fn(e) {
      "cannot create " <> dir <> ": " <> string.inspect(e)
    }),
  )
  let _ = simplifile.set_permissions_octal(out_root, 0o700)
  let _ = simplifile.set_permissions_octal(dir, 0o700)
  use last <- result.try(
    list.try_fold(events, "", fn(_, event) {
      let name = string.pad_start(int.to_string(event.sequence), 10, "0")
      let path = dir <> "/" <> name <> ".json"
      use _ <- result.try(
        simplifile.write(path, sync.event_string(event))
        |> result.map_error(fn(e) {
          "cannot write " <> path <> ": " <> string.inspect(e)
        }),
      )
      let _ = simplifile.set_permissions_octal(path, 0o600)
      Ok(event.digest)
    }),
  )
  Ok(
    json.to_string(
      json.object([
        #("ok", json.bool(True)),
        #("resigned_events", json.int(list.length(events))),
        #("out_root", json.string(out_root)),
        #("last_digest", json.string(last)),
      ]),
    ),
  )
}

/// Read an event directory that `session_sync_ffi:read_events/1` would refuse.
///
/// The storage reader demands a contiguous `events/NNNNNNNNNN.json` run and
/// fails with "journal gap or unexpected file" otherwise — correct for every
/// normal path, and exactly the state compaction exists to repair (invalid
/// events removed leave a gap). This lenient reader is used ONLY by `compact`:
/// it takes the `*.json` files in name order and concatenates them, leaving
/// every validity judgement to `session_sync.compact`.
fn read_damaged_journal(root: String) -> Result(String, String) {
  let dir = root <> "/events"
  use names <- result.try(
    simplifile.read_directory(dir)
    |> result.map_error(fn(e) {
      "cannot read " <> dir <> ": " <> string.inspect(e)
    }),
  )
  let lines =
    names
    |> list.filter(string.ends_with(_, ".json"))
    |> list.sort(string.compare)
    |> list.map(fn(name) {
      case simplifile.read(dir <> "/" <> name) {
        Ok(text) -> string.trim(text)
        Error(_) -> ""
      }
    })
    |> list.filter(fn(line) { line != "" })
  case lines {
    [] -> Error("no readable events under " <> dir)
    _ -> Ok(string.join(lines, "\n"))
  }
}

/// `compact <root> <out_root>`: rebuild the SURVIVING events of the journal
/// under `root` into a fresh `events/` directory under `out_root`, closing the
/// sequence gaps left by quarantining invalid events (see
/// `session_sync.compact`). Events the coordinator would refuse in their new
/// context are not written; they are listed in the receipt as `orphaned` with
/// their original sequence and the refusal, so the caller can quarantine them
/// as evidence. The source journal is never modified.
fn compact_into(root: String, out_root: String) -> Result(String, String) {
  use journal <- result.try(read_damaged_journal(root))
  use #(events, orphaned) <- result.try(sync.compact(journal))
  let dir = out_root <> "/events"
  use _ <- result.try(case simplifile.is_directory(dir) {
    Ok(True) -> Error("refusing to write: " <> dir <> " already exists")
    _ -> Ok(Nil)
  })
  use _ <- result.try(
    simplifile.create_directory_all(dir)
    |> result.map_error(fn(e) {
      "cannot create " <> dir <> ": " <> string.inspect(e)
    }),
  )
  let _ = simplifile.set_permissions_octal(out_root, 0o700)
  let _ = simplifile.set_permissions_octal(dir, 0o700)
  use last <- result.try(
    list.try_fold(events, "", fn(_, event) {
      let name = string.pad_start(int.to_string(event.sequence), 10, "0")
      let path = dir <> "/" <> name <> ".json"
      use _ <- result.try(
        simplifile.write(path, sync.event_string(event))
        |> result.map_error(fn(e) {
          "cannot write " <> path <> ": " <> string.inspect(e)
        }),
      )
      let _ = simplifile.set_permissions_octal(path, 0o600)
      Ok(event.digest)
    }),
  )
  Ok(
    json.to_string(
      json.object([
        #("ok", json.bool(True)),
        #("compacted_events", json.int(list.length(events))),
        #(
          "orphaned",
          json.array(orphaned, fn(entry) {
            json.object([
              #("original_sequence", json.int(entry.0)),
              #("reason", json.string(entry.1)),
            ])
          }),
        ),
        #("out_root", json.string(out_root)),
        #("last_digest", json.string(last)),
      ]),
    ),
  )
}

pub fn usage() -> String {
  "gleam run -m session_sync_cli -- <absolute_state_directory> <command> ...\n"
  <> "register <session> <claude|codex|agy> <workspace> <revision> <refs_csv|-> <op_id>\n"
  <> "heartbeat <session> <revision> <refs_csv|-> <op_id>\n"
  <> "claim <session> <task:id|workspace:path|integration/main|runtime:service> <ttl_seconds> <op_id>\n"
  <> "renew <session> <resource> <epoch> <ttl_seconds> <op_id>\n"
  <> "release <session> <resource> <epoch> <op_id>\n"
  <> "send <from> <to|broadcast> <Report|Progress|Question|Answer|Andon> <text> <refs_csv|-> <op_id>\n"
  <> "inbox <session> | ack <session> <message_id> <op_id> | retire <session> <op_id>\n"
  <> "status | check <session> <resource> <epoch> | journal | recover-lock\n"
  <> "Private mode 0700 local Linux storage. ACKs are self-reported; leases require executor fencing.\n"
  <> "Retry uncertain mutations with their original op_id. Never regenerate or edit event files."
}

pub fn main() -> Nil {
  let args = argv.load().arguments
  case args {
    ["--help"] | ["help"] | [] -> io.println(usage())
    _ -> respond(run(args))
  }
}
