//// Telegram /bisect adapter (controlled-action contract, wave 3).
//// A pure bisection PLAN over the ordinal interval (good, bad] derived from two hex ids
//// read as numbers, plus an optional step cap (<= 64). No VCS call is made; every
//// outcome in the plan is simulated (each probe assumed "bad"). execute records the plan
//// as a receipt with an exclusive create. Grants no authority.

import cepaf_gleam/harness/files
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

const max_args_bytes = 256

const max_reply_bytes = 3500

const max_steps = 64

const default_steps = 8

pub type Request {
  Request(good: Int, bad: Int, width: Int, steps: Int)
}

pub fn literal() -> String {
  "/bisect"
}

const usage = "Usage: /bisect <good-hex> <bad-hex> [steps 1-64] (4-12 lowercase hex digits each; bad must be greater than good)."

fn hex(s: String) -> Result(Int, Nil) {
  let n = string.byte_size(s)
  case
    n >= 4
    && n <= 12
    && list.all(string.to_graphemes(s), fn(c) {
      string.contains("0123456789abcdef", c)
    })
  {
    True -> int.base_parse(s, 16)
    False -> Error(Nil)
  }
}

fn steps_of(s: String) -> Result(Int, Nil) {
  case
    s != ""
    && string.byte_size(s) <= 2
    && !string.starts_with(s, "0")
    && list.all(string.to_graphemes(s), fn(c) {
      string.contains("0123456789", c)
    })
  {
    False -> Error(Nil)
    True ->
      case int.parse(s) {
        Ok(v) if v >= 1 && v <= max_steps -> Ok(v)
        _ -> Error(Nil)
      }
  }
}

pub fn parse(args: String) -> Result(Request, String) {
  case string.byte_size(args) <= max_args_bytes {
    False -> Error(usage)
    True -> {
      let words =
        string.split(string.trim(args), " ")
        |> list.filter(fn(w) { w != "" })
      case words {
        [g, b] -> build(g, b, Ok(default_steps))
        [g, b, s] -> build(g, b, steps_of(s))
        _ -> Error(usage)
      }
    }
  }
}

fn build(
  g: String,
  b: String,
  steps: Result(Int, Nil),
) -> Result(Request, String) {
  case hex(g), hex(b), steps {
    Ok(good), Ok(bad), Ok(s) if bad > good ->
      Ok(Request(good, bad, string.byte_size(b), s))
    _, _, _ -> Error(usage)
  }
}

pub fn effect_id(r: Request) -> String {
  files.digest(
    "/bisect\n"
    <> int.to_string(r.good)
    <> "\n"
    <> int.to_string(r.bad)
    <> "\n"
    <> int.to_string(r.width)
    <> "\n"
    <> int.to_string(r.steps),
  )
}

fn show(n: Int, width: Int) -> String {
  string.pad_start(int.to_base16(n) |> string.lowercase, width, "0")
}

/// Smallest k with 2^k >= size (size >= 1).
fn probes_needed(size: Int, k: Int) -> Int {
  case size <= 1 {
    True -> k
    False -> probes_needed({ size + 1 } / 2, k + 1)
  }
}

/// Deterministic probe sequence: midpoint of (lo, hi], then assume the probe is bad.
fn plan(lo: Int, hi: Int, left: Int, acc: List(Int)) -> List(Int) {
  case left <= 0 || hi - lo <= 1 {
    True -> list.reverse(acc)
    False -> {
      let mid = lo + { hi - lo } / 2
      plan(lo, mid, left - 1, [mid, ..acc])
    }
  }
}

fn body(r: Request) -> List(#(String, json.Json)) {
  let size = r.bad - r.good
  let probes = plan(r.good, r.bad, r.steps, [])
  let next = case probes {
    [first, ..] -> json.string(show(first, r.width))
    [] -> json.string(show(r.bad, r.width))
  }
  [
    #("literal", json.string(literal())),
    #("confidence", json.string("simulated")),
    #("effect_id", json.string(effect_id(r))),
    #(
      "request",
      json.object([
        #("good", json.string(show(r.good, r.width))),
        #("bad", json.string(show(r.bad, r.width))),
        #("steps", json.int(r.steps)),
      ]),
    ),
    #("candidates", json.int(size)),
    #("probes_needed", json.int(probes_needed(size, 0))),
    #("next_probe", next),
    #(
      "plan",
      json.array(list.map(probes, fn(p) { show(p, r.width) }), json.string),
    ),
    #("assumed_outcome", json.string("every probe bad (simulated)")),
    #("vcs_calls", json.int(0)),
  ]
}

fn bounded(status: String, effect: String, r: Request) -> String {
  let text =
    json.object(
      list.append(body(r), [
        #("status", json.string(status)),
        #("effect", json.string(effect)),
      ]),
    )
    |> json.to_string
  case string.byte_size(text) <= max_reply_bytes {
    True -> text
    False ->
      "{\"literal\":\"/bisect\",\"status\":\"denied\",\"reason\":\"reply_bound\"}"
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
