//// C02 observation projection. This is not a command, task completion, or grant.
//// Validate the complete immutable journal before projecting any row; use one
//// linear pass to retain the candidate revision that was current at each event.

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import uos_swarm/board
import uos_swarm/session_sync as sync

pub type Observation {
  Observation(
    source_journal_ref: String,
    host_boot_id: String,
    event_id: String,
    local_sequence: Int,
    session_ref: String,
    resource_ref: String,
    epoch: Int,
    candidate_ref: String,
  )
}

type EventRef {
  EventRef(
    sequence: Int,
    operation_id: String,
    host: String,
    boot: String,
    digest: String,
  )
}

fn event_ref() -> decode.Decoder(EventRef) {
  use sequence <- decode.subfield(["body", "sequence"], decode.int)
  use operation <- decode.subfield(["body", "operation_id"], decode.string)
  use host <- decode.subfield(["body", "host_id"], decode.string)
  use boot <- decode.subfield(["body", "boot_id"], decode.string)
  use digest <- decode.field("digest", decode.string)
  decode.success(EventRef(sequence, operation, host, boot, digest))
}

fn fields(o: Observation) -> List(#(String, json.Json)) {
  [
    #("source_journal_ref", json.string(o.source_journal_ref)),
    #("host_boot_id", json.string(o.host_boot_id)),
    #("event_id", json.string(o.event_id)),
    #("local_sequence", json.int(o.local_sequence)),
    #("session_ref", json.string(o.session_ref)),
    #("resource_ref", json.string(o.resource_ref)),
    #("epoch", json.int(o.epoch)),
    #("candidate_ref", json.string(o.candidate_ref)),
  ]
}

pub fn payload_hash(o: Observation) -> String {
  fields(o) |> json.object |> json.to_string |> board.sha256_hex
}

pub fn encode(o: Observation) -> String {
  json.to_string(
    json.object(
      list.append(fields(o), [#("payload_hash", json.string(payload_hash(o)))]),
    ),
  )
}

pub fn project(
  journal: String,
  source_journal_ref: String,
) -> Result(List(Observation), String) {
  case
    string.trim(source_journal_ref) == ""
    || string.byte_size(source_journal_ref) > 512
    || string.byte_size(journal) > 16_777_216
  {
    True -> Error("invalid source reference or journal size limit")
    False -> {
      use state <- result.try(sync.replay(journal))
      let lines =
        string.split(journal, "\n")
        |> list.filter(fn(line) { string.trim(line) != "" })
      use #(rows, _) <- result.try(
        list.try_fold(lines, #([], dict.new()), fn(acc, line) {
          let #(rows, candidates) = acc
          use e <- result.try(
            json.parse(line, event_ref())
            |> result.replace_error("invalid event reference"),
          )
          use seen <- result.try(
            dict.get(state.seen, e.operation_id)
            |> result.replace_error("event receipt absent"),
          )
          let actor = sync.actor(seen.command)
          let candidates = case seen.command {
            sync.Register(_, _, _, revision, _)
            | sync.Heartbeat(_, revision, _) ->
              dict.insert(candidates, actor, revision)
            _ -> candidates
          }
          use candidate <- result.try(
            dict.get(candidates, actor)
            |> result.replace_error("event candidate absent"),
          )
          let resource = case seen.command {
            sync.Claim(_, resource, _)
            | sync.Renew(_, resource, _, _)
            | sync.Release(_, resource, _) -> resource
            _ -> "session:" <> actor
          }
          let row =
            Observation(
              source_journal_ref,
              e.host <> ":" <> e.boot,
              board.sha256_hex(source_journal_ref <> ":" <> e.digest),
              e.sequence,
              actor,
              resource,
              seen.receipt.epoch,
              candidate,
            )
          Ok(#([row, ..rows], candidates))
        }),
      )
      Ok(list.reverse(rows))
    }
  }
}

pub fn export(
  root: String,
  source_journal_ref: String,
) -> Result(String, String) {
  use journal <- result.try(sync.read_journal(root))
  use rows <- result.try(project(journal, source_journal_ref))
  Ok(rows |> list.map(encode) |> string.join("\n"))
}
