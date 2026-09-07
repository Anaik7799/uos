//// Bounded local CLI for parallel Claude/Codex/AGY session coordination.
//// Commands print JSON and use nonzero exit codes on refusal or storage error.
//// No command executes a deployment, shell payload, VCS mutation, or ACK on
//// another process's behalf. A caller supplies its own declared session ID.

import argv
import gleam/int
import gleam/io
import gleam/json
import gleam/result
import gleam/string
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
