//// ControlledAction adapter for `/voice-roll-call [mode=<m>]` (contract
//// 20261026-0115). Preview computes a roster of declared voice-pipeline states
//// with the pure `ha/voice_pipeline_state` constructors and queries; no
//// microphone, peer or biometric is read, so confidence is `declared`. Execute
//// records the computed roster as an exclusive-create receipt only. Grants no
//// authority and never counts a vote.

import cepaf_gleam/ha/voice_pipeline_state as voice
import cepaf_gleam/harness/files
import cepaf_gleam/ui/lustre/voice_pipeline
import cepaf_gleam/ui/wisp/voice_api
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import simplifile

pub opaque type Request {
  Request(mode: option.Option(voice.VoiceMode))
}

const literal_text = "/voice-roll-call"

const max_args = 256

const max_reply = 3500

const backend = "ha/voice_pipeline_state"

const usage = "usage: /voice-roll-call [mode=<always_on|push_to_talk|wake_word|disabled>]"

const all_modes = [
  voice.AlwaysOn,
  voice.PushToTalk,
  voice.WakeWord,
  voice.Disabled,
]

pub fn literal() -> String {
  literal_text
}

/// Pure: no audio, no peer, no filesystem.
pub fn parse(args: String) -> Result(Request, String) {
  let tokens =
    args
    |> string.split(" ")
    |> list.map(string.trim)
    |> list.filter(fn(t) { t != "" })
  case string.byte_size(args) <= max_args, tokens {
    True, [] -> Ok(Request(option.None))
    True, ["mode=" <> name] ->
      case list.find(all_modes, fn(m) { voice.mode_to_string(m) == name }) {
        Ok(m) -> Ok(Request(option.Some(m)))
        Error(_) -> Error(usage)
      }
    _, _ -> Error(usage)
  }
}

fn mode_text(r: Request) -> String {
  case r.mode {
    option.Some(m) -> voice.mode_to_string(m)
    option.None -> "*"
  }
}

pub fn effect_id(r: Request) -> String {
  files.digest("uos.telegram.action.voice_roll_call.v1|mode=" <> mode_text(r))
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

fn selected(r: Request) -> List(voice.VoiceMode) {
  case r.mode {
    option.Some(m) -> [m]
    option.None -> all_modes
  }
}

fn row(mode: voice.VoiceMode) -> json.Json {
  let state = voice.voice_new(mode)
  json.object([
    #("mode", json.string(voice.mode_to_string(mode))),
    #("session_id", json.string(state.session_id)),
    #("active", json.bool(voice.is_active(state))),
    #("health", json.float(voice.voice_health(state))),
    #("energy_threshold", json.float(state.energy_threshold)),
    #("samples_processed", json.int(state.samples_processed)),
    #("events", json.int(voice.event_count(state))),
  ])
}

fn roster_fields(r: Request) -> List(#(String, json.Json)) {
  [
    #("roster", json.array(selected(r), row)),
    #("pipeline", voice_api.status_json(voice_pipeline.init())),
    #("votes_counted", json.int(0)),
    #("backend", json.string(backend)),
    #("authority", json.string("NONE")),
  ]
}

fn head(status: String, r: Request) -> List(#(String, json.Json)) {
  [
    #("status", json.string(status)),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect_id(r))),
  ]
}

/// Read-only: declared pipeline states, not a live roll call.
pub fn preview(r: Request) -> String {
  reply(
    list.flatten([
      head("preview", r),
      [
        #("confidence", json.string("declared")),
        #(
          "effect",
          json.string("record computed roster receipt; no vote is collected"),
        ),
        #("mode_filter", json.string(mode_text(r))),
      ],
      roster_fields(r),
    ]),
  )
}

fn stored_decoder() -> decode.Decoder(String) {
  use effect <- decode.field("effect_id", decode.string)
  decode.success(effect)
}

fn duplicate(r: Request, dir: String) -> Result(String, String) {
  use raw <- result.try(files.read(dir, effect_id(r) <> ".json"))
  use stored <- result.try(
    json.parse(raw, stored_decoder())
    |> result.replace_error("receipt_unreadable"),
  )
  case stored == effect_id(r) {
    False -> Error("receipt_identity_mismatch")
    True ->
      Ok(
        reply(
          list.flatten([
            head("duplicate", r),
            [
              #("receipt_sha256", json.string(files.digest(raw))),
              #("authority", json.string("NONE")),
            ],
          ]),
        ),
      )
  }
}

/// Receipt-only and idempotent by `effect_id` (exclusive create).
pub fn execute(r: Request, evidence_dir: String) -> Result(String, String) {
  case simplifile.is_directory(evidence_dir) {
    Ok(True) -> record(r, evidence_dir)
    _ -> Error("evidence_dir_unavailable")
  }
}

fn record(r: Request, dir: String) -> Result(String, String) {
  let body =
    reply(
      list.flatten([
        head("executed", r),
        [
          #("confidence", json.string("declared")),
          #("mode_filter", json.string(mode_text(r))),
        ],
        roster_fields(r),
      ]),
    )
  let name = effect_id(r) <> ".json"
  case files.create(dir, name, body) {
    Ok(_) -> Ok(body)
    Error(reason) ->
      case simplifile.is_file(dir <> "/" <> name) {
        Ok(True) -> duplicate(r, dir)
        _ -> Error(reason)
      }
  }
}
