//// Telegram /rewind adapter (controlled-action contract, wave 3).
//// Backend: cepaf_gleam/planning/sa_plan_simulator.simulate_temporal_replay, a pure
//// event-sourced replay. The history it replays is a fixed, declared reference history
//// (1 start + 64 scheduled/completed activity pairs); no live store, workflow or
//// conversation is read, so every reply is labelled "simulated". preview describes the
//// rewind window (the last n events dropped and the replay state hashes before/after).
//// execute records a receipt only; it never mutates any store. Grants no authority.

import cepaf_gleam/harness/files
import cepaf_gleam/planning/sa_plan_simulator as sim
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

const max_args_bytes = 256

const max_reply_bytes = 3500

const max_rewind = 64

const backend = "cepaf_gleam/planning/sa_plan_simulator.simulate_temporal_replay"

pub type Request {
  Request(count: Int)
}

pub fn literal() -> String {
  "/rewind"
}

const usage = "Usage: /rewind <n> (ASCII integer 1-64 events to rewind in the simulated reference history)."

pub fn parse(args: String) -> Result(Request, String) {
  let text = string.trim(args)
  case
    string.byte_size(args) <= max_args_bytes
    && text != ""
    && string.byte_size(text) <= 2
    && !string.starts_with(text, "0")
    && list.all(string.to_graphemes(text), fn(c) {
      string.contains("0123456789", c)
    })
  {
    False -> Error(usage)
    True ->
      case int.parse(text) {
        Ok(n) if n >= 1 && n <= max_rewind -> Ok(Request(n))
        _ -> Error(usage)
      }
  }
}

pub fn effect_id(r: Request) -> String {
  files.digest("/rewind\n" <> int.to_string(r.count))
}

fn indices() -> List(Int) {
  int.range(from: 1, to: max_rewind + 1, with: [], run: list.prepend)
  |> list.reverse
}

fn history() -> List(sim.SimWorkflowEvent) {
  [
    sim.WfStart("telegram-rewind-reference", 0),
    ..list.flat_map(indices(), fn(i) {
      let id = "act-" <> int.to_string(i)
      [
        sim.WfActivityScheduled(id, i * 2),
        sim.WfActivityCompleted(id, "h" <> int.to_string(i), i * 2 + 1),
      ]
    })
  ]
}

fn replay_digest(events: List(sim.SimWorkflowEvent)) -> String {
  case sim.simulate_temporal_replay(events) {
    Ok(state) -> files.digest(state)
    Error(_) -> "replay_failed"
  }
}

fn bounded(status: String, effect: String, r: Request) -> String {
  let events = history()
  let total = list.length(events)
  let kept = list.take(events, total - r.count)
  let text =
    json.object([
      #("literal", json.string(literal())),
      #("status", json.string(status)),
      #("confidence", json.string("simulated")),
      #("effect_id", json.string(effect_id(r))),
      #("effect", json.string(effect)),
      #("backend", json.string(backend)),
      #("request", json.object([#("count", json.int(r.count))])),
      #(
        "window",
        json.object([
          #("total_events", json.int(total)),
          #("kept_events", json.int(list.length(kept))),
          #("dropped_events", json.int(r.count)),
          #("first_dropped_index", json.int(total - r.count)),
        ]),
      ),
      #("replay_before_sha256", json.string(replay_digest(events))),
      #("replay_after_sha256", json.string(replay_digest(kept))),
      #(
        "history",
        json.string("declared reference history; no live store read"),
      ),
      #("store_mutations", json.int(0)),
    ])
    |> json.to_string
  case string.byte_size(text) <= max_reply_bytes {
    True -> text
    False ->
      "{\"literal\":\"/rewind\",\"status\":\"denied\",\"reason\":\"reply_bound\"}"
  }
}

pub fn preview(r: Request) -> String {
  bounded("preview", "none", r)
}

fn check_dir(dir: String) -> Result(Nil, String) {
  case string.starts_with(dir, "/") && string.byte_size(dir) <= 1024 {
    False -> Error("evidence_dir_required")
    True ->
      case simplifile.link_info(dir) {
        Ok(info) ->
          case simplifile.file_info_type(info) {
            simplifile.Directory -> Ok(Nil)
            _ -> Error("evidence_dir_unavailable")
          }
        Error(_) -> Error("evidence_dir_unavailable")
      }
  }
}

fn duplicate(r: Request, stored: String) -> String {
  json.object([
    #("literal", json.string(literal())),
    #("status", json.string("duplicate")),
    #("effect_id", json.string(effect_id(r))),
    #("receipt_sha256", json.string(files.digest(stored))),
  ])
  |> json.to_string
}

pub fn execute(r: Request, evidence_dir: String) -> Result(String, String) {
  use _ <- result.try(check_dir(evidence_dir))
  let name = effect_id(r) <> ".json"
  case files.read(evidence_dir, name) {
    Ok(stored) -> Ok(duplicate(r, stored))
    Error(_) -> {
      let receipt = bounded("executed", "receipt_only", r)
      case string.contains(receipt, "\"reply_bound\"") {
        True -> Error("reply_bound")
        False ->
          case files.create(evidence_dir, name, receipt) {
            Ok(_) -> Ok(receipt)
            Error(reason) ->
              case files.read(evidence_dir, name) {
                Ok(stored) -> Ok(duplicate(r, stored))
                Error(_) -> Error(reason)
              }
          }
      }
    }
  }
}
