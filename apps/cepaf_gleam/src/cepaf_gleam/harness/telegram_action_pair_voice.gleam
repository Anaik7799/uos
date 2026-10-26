//// ControlledAction adapter for `/pair-voice <peer>` (contract 20261026-0115).
//// Preview describes the planned pairing from the declared push-to-talk
//// pipeline state (`ha/voice_pipeline_state`, `ui/wisp/voice_api`). A pairing
//// needs a live peer voice session that cannot be bounded in development, so
//// `execute` returns `backend_unavailable:voice_pipeline_state` and writes
//// nothing. Grants no authority.

import cepaf_gleam/ha/voice_pipeline_state as voice
import cepaf_gleam/harness/files
import cepaf_gleam/ui/lustre/voice_pipeline
import cepaf_gleam/ui/wisp/voice_api
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub opaque type Request {
  Request(peer: String)
}

const literal_text = "/pair-voice"

const max_args = 256

const max_reply = 3500

const backend = "voice_pipeline_state"

const usage = "usage: /pair-voice <peer> (peer: lowercase letters, digits and hyphens, 1..32 chars, starts with a letter or digit)"

pub fn literal() -> String {
  literal_text
}

fn valid_peer(peer: String) -> Bool {
  let graphemes = string.to_graphemes(peer)
  string.byte_size(peer) >= 1
  && string.byte_size(peer) <= 32
  && list.all(graphemes, fn(c) {
    string.contains("abcdefghijklmnopqrstuvwxyz0123456789-", c)
  })
  && !string.starts_with(peer, "-")
}

/// Pure: no session, no audio, no filesystem.
pub fn parse(args: String) -> Result(Request, String) {
  let tokens =
    args
    |> string.split(" ")
    |> list.map(string.trim)
    |> list.filter(fn(t) { t != "" })
  case string.byte_size(args) <= max_args, tokens {
    True, [peer] ->
      case valid_peer(peer) {
        True -> Ok(Request(peer))
        False -> Error(usage)
      }
    _, _ -> Error(usage)
  }
}

pub fn effect_id(r: Request) -> String {
  files.digest("uos.telegram.action.pair_voice.v1|peer=" <> r.peer)
}

fn reply(fields: List(#(String, json.Json))) -> String {
  let text = json.object(fields) |> json.to_string
  case string.byte_size(text) <= max_reply {
    True -> text
    False ->
      json.object([
        #("status", json.string("denied")),
        #("literal", json.string(literal_text)),
        #("reason", json.string("reply_bound")),
      ])
      |> json.to_string
  }
}

/// Read-only: declared pipeline state, no peer is contacted.
pub fn preview(r: Request) -> String {
  let state = voice.voice_new(voice.PushToTalk)
  reply([
    #("status", json.string("preview")),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect_id(r))),
    #("confidence", json.string("declared")),
    #(
      "effect",
      json.string("would open one voice pairing session; nothing is opened"),
    ),
    #("peer", json.string(r.peer)),
    #("mode", json.string(voice.mode_to_string(state.mode))),
    #("pipeline_active", json.bool(voice.is_active(state))),
    #("pipeline_health", json.float(voice.voice_health(state))),
    #("pipeline_summary", json.string(voice.summary(state))),
    #("pipeline", voice_api.status_json(voice_pipeline.init())),
    #("backend", json.string("unavailable:" <> backend)),
    #("authority", json.string("NONE")),
  ])
}

/// Typed `backend_unavailable` reply for the service to relay.
pub fn unavailable_reply(r: Request) -> String {
  reply([
    #("status", json.string("backend_unavailable")),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect_id(r))),
    #("backend", json.string(backend)),
    #(
      "reason",
      json.string("pairing needs a live peer voice session; not boundable"),
    ),
    #("authority", json.string("NONE")),
  ])
}

/// Never opens a session and never writes.
pub fn execute(_r: Request, evidence_dir: String) -> Result(String, String) {
  use _ <- result.try(case simplifile.is_directory(evidence_dir) {
    Ok(True) -> Ok(Nil)
    _ -> Error("evidence_dir_unavailable")
  })
  Error("backend_unavailable:" <> backend)
}
