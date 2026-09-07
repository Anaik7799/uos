//// CLI for the global intelligence router: `gleam run -m uos_route_cli -- <command>`.
////
//// Commands:
////   decide <class> [budget.jsonl]   route decision for one operation class (R0..R6), with
////                                   live OpenRouter prices and a small built-in posterior
////                                   table; an optional budget ledger is read if given
////   tiers                           the default tier universe with live prices
////   budget init <path> <cap_usd>    create (or overwrite) a budget ledger at epoch 0
////   budget charge <path> <amount> <holder> <evidence_ref>
////                                   charge the ledger; refuses over cap or on epoch conflict
////   budget show <path>              print the ledger's current state
////   update <posteriors.json> <tier> <class> <pass|fail> <evidence_ref>
////                                   record one verified outcome and persist the posteriors

import argv
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import uos_swarm/openrouter_worker as ow
import uos_swarm/route

@external(erlang, "uos_openrouter_ffi", "https_get")
fn https_get(url: String, timeout_ms: Int) -> Result(#(Int, String), String)

@external(erlang, "uos_swarm_ffi", "file_read")
fn file_read(path: String) -> Result(String, String)

@external(erlang, "uos_swarm_ffi", "file_write")
fn file_write(path: String, content: String) -> Result(Nil, String)

pub fn main() {
  case argv.load().arguments {
    ["decide", class, ..rest] -> decide(class, rest)
    ["tiers"] -> tiers()
    ["budget", "init", path, cap] -> budget_init(path, cap)
    ["budget", "charge", path, amount, holder, evidence_ref] ->
      budget_charge(path, amount, holder, evidence_ref)
    ["budget", "show", path] -> budget_show(path)
    ["update", posteriors_path, tier, class, outcome, evidence_ref] ->
      update_cmd(posteriors_path, tier, class, outcome, evidence_ref)
    _ -> io.println(usage())
  }
}

fn usage() -> String {
  "usage: decide <class> [budget.jsonl] | tiers | budget init <path> <cap_usd> | budget charge <path> <amount> <holder> <evidence_ref> | budget show <path> | update <posteriors.json> <tier> <class> <pass|fail> <evidence_ref>"
}

fn parse_class(s: String) -> Result(route.OperationClass, String) {
  case string.uppercase(s) {
    "R0" -> Ok(route.R0Runtime)
    "R1" -> Ok(route.R1Verification)
    "R2" -> Ok(route.R2Docs)
    "R3" -> Ok(route.R3Advisory)
    "R4" -> Ok(route.R4Implementation)
    "R5" -> Ok(route.R5SovereignReview)
    "R6" -> Ok(route.R6DesignAuthority)
    _ -> Error("unknown class: " <> s <> " (expected R0..R6)")
  }
}

fn provider_id(p: route.Provider) -> String {
  case p {
    route.Deterministic -> "deterministic"
    route.OpenRouter -> "openrouter"
    route.Claude -> "claude"
    route.Codex -> "codex"
    route.Antigravity -> "antigravity"
  }
}

fn option_float(o: option.Option(Float)) -> String {
  case o {
    Some(f) -> float.to_string(f)
    None -> "unknown"
  }
}

fn bool_id(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

fn live_prices() -> List(#(String, Float, Float)) {
  case https_get(ow.models_url, 10_000) {
    Ok(#(200, body)) ->
      ow.decode_prices(body)
      |> result.unwrap([])
      |> list.map(fn(p) { #(p.id, p.prompt, p.completion) })
    _ -> []
  }
}

/// One verified sanitized review is already recorded for `R3Advisory`: deterministic
/// (by construction) and `openrouter/openai/gpt-4.1-nano` (the live nano review) are proven
/// with 3 verified trials at mean 0.8, which is exactly `theta(R3)`. Everything else is
/// unproven until `update` records a real outcome.
fn builtin_posteriors() -> List(route.Posterior) {
  [
    route.Posterior("deterministic", route.R3Advisory, 4.0, 1.0, 3),
    route.Posterior(
      "openrouter/openai/gpt-4.1-nano",
      route.R3Advisory,
      4.0,
      1.0,
      3,
    ),
  ]
}

fn decide(class_str: String, rest: List(String)) -> Nil {
  case parse_class(class_str) {
    Error(e) -> io.println("error: " <> e)
    Ok(class) -> {
      let tiers = route.default_tiers(live_prices())
      let budget = case rest {
        [path, ..] ->
          case route.read_budget(path) {
            Ok(b) -> Some(b)
            Error(_) -> None
          }
        [] -> None
      }
      let d =
        route.route(
          route.default_policy(),
          class,
          tiers,
          builtin_posteriors(),
          budget,
          400,
          200,
        )
      print_decision(d, class)
    }
  }
}

fn print_decision(d: route.Decision, class: route.OperationClass) -> Nil {
  case d {
    route.Route(tier, est, reason) ->
      io.println(
        route.class_label(class)
        <> " -> "
        <> tier.id
        <> " ("
        <> provider_id(tier.provider)
        <> ") est $"
        <> float.to_string(est)
        <> " | "
        <> reason,
      )
    route.Refuse(reason) ->
      io.println(route.class_label(class) <> " -> REFUSE: " <> reason)
  }
}

fn tiers() -> Nil {
  let all = route.default_tiers(live_prices())
  io.println("| id | provider | price_in | price_out | metered | paid |")
  io.println("|---|---|---|---|---|---|")
  list.each(all, fn(t) {
    io.println(
      "| "
      <> t.id
      <> " | "
      <> provider_id(t.provider)
      <> " | "
      <> option_float(t.price_in)
      <> " | "
      <> option_float(t.price_out)
      <> " | "
      <> bool_id(t.metered)
      <> " | "
      <> bool_id(t.paid)
      <> " |",
    )
  })
}

fn budget_init(path: String, cap_str: String) -> Nil {
  case float.parse(cap_str) {
    Error(_) -> io.println("error: bad cap_usd " <> cap_str)
    Ok(cap) ->
      case route.init_budget(path, cap, "cli") {
        Ok(b) ->
          io.println(
            "initialized " <> path <> " cap=" <> float.to_string(b.cap_usd),
          )
        Error(e) -> io.println("error: " <> e)
      }
  }
}

fn budget_charge(
  path: String,
  amount_str: String,
  holder: String,
  evidence_ref: String,
) -> Nil {
  case float.parse(amount_str) {
    Error(_) -> io.println("error: bad amount " <> amount_str)
    Ok(amount) ->
      case route.read_budget(path) {
        Error(e) -> io.println("error: " <> e)
        Ok(current) ->
          case route.charge(path, current, amount, holder, evidence_ref) {
            Ok(b) ->
              io.println(
                "charged: epoch="
                <> int.to_string(b.epoch)
                <> " spent="
                <> float.to_string(b.spent_usd)
                <> " cap="
                <> float.to_string(b.cap_usd),
              )
            Error(e) -> io.println("refused: " <> e)
          }
      }
  }
}

fn budget_show(path: String) -> Nil {
  case route.read_budget(path) {
    Ok(b) ->
      io.println(
        "cap="
        <> float.to_string(b.cap_usd)
        <> " spent="
        <> float.to_string(b.spent_usd)
        <> " epoch="
        <> int.to_string(b.epoch)
        <> " holder="
        <> b.holder,
      )
    Error(e) -> io.println("error: " <> e)
  }
}

fn parse_outcome(s: String) -> Result(Bool, String) {
  case s {
    "pass" -> Ok(True)
    "fail" -> Ok(False)
    _ -> Error("outcome must be pass|fail, got " <> s)
  }
}

fn lenient_float() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

fn posterior_decoder() -> decode.Decoder(route.Posterior) {
  use tier <- decode.field("tier", decode.string)
  use class_s <- decode.field("class", decode.string)
  use alpha <- decode.field("alpha", lenient_float())
  use beta <- decode.field("beta", lenient_float())
  use trials <- decode.field("trials", decode.int)
  case parse_class(class_s) {
    Ok(class) ->
      decode.success(route.Posterior(tier, class, alpha, beta, trials))
    Error(_) ->
      decode.failure(
        route.Posterior("", route.R0Runtime, 0.0, 0.0, 0),
        "OperationClass",
      )
  }
}

fn decode_posteriors(content: String) -> Result(List(route.Posterior), String) {
  json.parse(content, decode.list(posterior_decoder()))
  |> result.map_error(fn(e) { string.inspect(e) })
}

fn encode_posteriors(posteriors: List(route.Posterior)) -> String {
  json.array(posteriors, fn(p) {
    json.object([
      #("tier", json.string(p.tier)),
      #("class", json.string(route.class_label(p.class))),
      #("alpha", json.float(p.alpha)),
      #("beta", json.float(p.beta)),
      #("trials", json.int(p.trials)),
    ])
  })
  |> json.to_string
}

fn load_posteriors(path: String) -> List(route.Posterior) {
  case file_read(path) {
    Ok(content) ->
      decode_posteriors(content) |> result.unwrap(builtin_posteriors())
    Error(_) -> builtin_posteriors()
  }
}

fn save_posteriors(
  path: String,
  posteriors: List(route.Posterior),
) -> Result(Nil, String) {
  file_write(path, encode_posteriors(posteriors))
}

fn update_cmd(
  posteriors_path: String,
  tier: String,
  class_str: String,
  outcome: String,
  evidence_ref: String,
) -> Nil {
  case parse_class(class_str) {
    Error(e) -> io.println("error: " <> e)
    Ok(class) ->
      case parse_outcome(outcome) {
        Error(e) -> io.println("error: " <> e)
        Ok(verified_pass) -> {
          let current = load_posteriors(posteriors_path)
          let updated =
            route.update(current, tier, class, verified_pass, evidence_ref)
          case save_posteriors(posteriors_path, updated) {
            Ok(_) ->
              io.println(
                "updated " <> tier <> " / " <> route.class_label(class),
              )
            Error(e) -> io.println("error: " <> e)
          }
        }
      }
  }
}
