//// ControlledAction adapter for `/eco-schedule` (contract 20261026-0115).
//// Preview computes a LEVELED (heijunka) schedule proposal from declared
//// budget/queue parameters using the pure `ecology/daily_budget` admission
//// functions; nothing is read from live state, so confidence is `simulated`.
//// Execute records the proposal as an exclusive-create receipt only: no job is
//// enqueued, no model is called and no spend is reserved. Grants no authority.

import cepaf_gleam/ecology/daily_budget as budget
import cepaf_gleam/harness/files
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub opaque type Request {
  Request(model: String, jobs: Int, max_tokens: Int, input_bytes: Int)
}

const literal_text = "/eco-schedule"

const max_args = 256

const max_reply = 3500

const backend = "ecology/daily_budget"

const default_model = "google/gemma-4-31b-it"

const default_jobs = 24

const default_max_tokens = 512

const default_input_bytes = 2048

const max_jobs = 1000

const slots = 24

const usage = "usage: /eco-schedule [model=<provider model>] [jobs=1..1000] [max_tokens=1..4096] [input_bytes=1..16384]"

pub fn literal() -> String {
  literal_text
}

fn digits_only(text: String) -> Bool {
  string.byte_size(text) >= 1
  && string.byte_size(text) <= 5
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("0123456789", c)
  })
}

fn bounded(text: String, low: Int, high: Int) -> Result(Int, Nil) {
  case digits_only(text) {
    False -> Error(Nil)
    True ->
      case int.parse(text) {
        Ok(n) if n >= low && n <= high -> Ok(n)
        _ -> Error(Nil)
      }
  }
}

fn pairs(tokens: List(String)) -> Result(List(#(String, String)), Nil) {
  use found <- result.try(
    list.try_map(tokens, fn(t) { string.split_once(t, "=") }),
  )
  let keys = list.map(found, fn(p) { p.0 })
  case list.length(list.unique(keys)) == list.length(keys) {
    True -> Ok(found)
    False -> Error(Nil)
  }
}

fn lookup(
  found: List(#(String, String)),
  key: String,
  default: a,
  convert: fn(String) -> Result(a, Nil),
) -> Result(a, Nil) {
  case list.key_find(found, key) {
    Error(_) -> Ok(default)
    Ok(value) -> convert(value)
  }
}

/// Pure: no ledger, no filesystem.
pub fn parse(args: String) -> Result(Request, String) {
  let tokens =
    args
    |> string.split(" ")
    |> list.map(string.trim)
    |> list.filter(fn(t) { t != "" })
  let parsed = {
    use found <- result.try(pairs(tokens))
    let known = ["model", "jobs", "max_tokens", "input_bytes"]
    case list.all(found, fn(p) { list.contains(known, p.0) }) {
      False -> Error(Nil)
      True -> {
        use model <- result.try(
          lookup(found, "model", default_model, fn(m) {
            case budget.provider_ceiling(m) {
              Ok(_) -> Ok(m)
              Error(_) -> Error(Nil)
            }
          }),
        )
        use jobs <- result.try(
          lookup(found, "jobs", default_jobs, bounded(_, 1, max_jobs)),
        )
        use max_tokens <- result.try(
          lookup(found, "max_tokens", default_max_tokens, bounded(_, 1, 4096)),
        )
        use input_bytes <- result.try(
          lookup(found, "input_bytes", default_input_bytes, bounded(
            _,
            1,
            16_384,
          )),
        )
        Ok(Request(model, jobs, max_tokens, input_bytes))
      }
    }
  }
  case string.byte_size(args) <= max_args, parsed {
    True, Ok(r) -> Ok(r)
    _, _ -> Error(usage)
  }
}

pub fn effect_id(r: Request) -> String {
  files.digest(
    "uos.telegram.action.eco_schedule.v1|model="
    <> r.model
    <> "|jobs="
    <> int.to_string(r.jobs)
    <> "|max_tokens="
    <> int.to_string(r.max_tokens)
    <> "|input_bytes="
    <> int.to_string(r.input_bytes),
  )
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

/// Level `scheduled` jobs over the day's slots: slot sizes differ by at most one.
fn level(scheduled: Int) -> List(Int) {
  let base = scheduled / slots
  let extra = scheduled % slots
  list.repeat(0, slots)
  |> list.index_map(fn(_, i) {
    case i < extra {
      True -> base + 1
      False -> base
    }
  })
}

fn proposal(r: Request) -> Result(List(#(String, json.Json)), String) {
  use ceiling <- result.try(budget.provider_ceiling(r.model))
  let input = string.repeat("x", r.input_bytes)
  use reservation <- result.try(budget.admit(
    "eco-schedule-proposal",
    r.model,
    r.max_tokens,
    input,
    input,
    ceiling,
  ))
  let worst = budget.worst_case_nanodollars(reservation)
  let per_day = budget.daily_limit_nanodollars / worst
  let scheduled = int.min(r.jobs, per_day)
  Ok([
    #("model", json.string(r.model)),
    #("jobs_requested", json.int(r.jobs)),
    #("max_tokens", json.int(r.max_tokens)),
    #("input_bytes", json.int(r.input_bytes)),
    #("worst_case_nanodollars_per_job", json.int(worst)),
    #("daily_limit_nanodollars", json.int(budget.daily_limit_nanodollars)),
    #("max_jobs_per_day", json.int(per_day)),
    #("jobs_scheduled", json.int(scheduled)),
    #("jobs_deferred", json.int(r.jobs - scheduled)),
    #("hourly_slots", json.array(level(scheduled), json.int)),
    #("backend", json.string(backend)),
    #("authority", json.string("NONE")),
  ])
}

fn denied(r: Request, reason: String) -> String {
  reply([
    #("status", json.string("denied")),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect_id(r))),
    #("reason", json.string(reason)),
    #("authority", json.string("NONE")),
  ])
}

fn head(status: String, r: Request) -> List(#(String, json.Json)) {
  [
    #("status", json.string(status)),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect_id(r))),
  ]
}

/// Read-only: the schedule is simulated from declared parameters.
pub fn preview(r: Request) -> String {
  case proposal(r) {
    Error(reason) -> denied(r, reason)
    Ok(fields) ->
      reply(
        list.flatten([
          head("preview", r),
          [
            #("confidence", json.string("simulated")),
            #(
              "effect",
              json.string(
                "record leveled schedule proposal receipt; no job is enqueued",
              ),
            ),
          ],
          fields,
        ]),
      )
  }
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
  use fields <- result.try(proposal(r))
  let body =
    reply(
      list.flatten([
        head("executed", r),
        [#("confidence", json.string("simulated"))],
        fields,
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
