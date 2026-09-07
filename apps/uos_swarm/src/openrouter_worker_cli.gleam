//// CLI for the OpenRouter advisory worker: `gleam run -m openrouter_worker_cli -- <command>`.
////
//// Commands:
////   probe                       credential presence (never printed) and live price reachability
////   models                      allowlist with ceilings and live public prices
////   estimate <model> <max_tokens>  admission decision for the lease-invariant review
////   review-lease-invariant [model] [--paid] [out.json]
////                               run the one sanitized review; prints provider/model/usage/cost;
////                               writes the outcome JSON when a path is given

import argv
import gleam/float
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/openrouter_worker as w

@external(erlang, "uos_openrouter_ffi", "has_api_key")
fn has_api_key() -> Bool

@external(erlang, "uos_openrouter_ffi", "api_key")
fn api_key() -> Result(String, Nil)

@external(erlang, "uos_openrouter_ffi", "https_get")
fn https_get(url: String, timeout_ms: Int) -> Result(#(Int, String), String)

@external(erlang, "uos_openrouter_ffi", "https_post_json")
fn https_post_json(
  url: String,
  key: String,
  body: String,
  timeout_ms: Int,
) -> Result(#(Int, String), String)

@external(erlang, "uos_swarm_ffi", "system_time_us")
fn system_time_us() -> Int

@external(erlang, "uos_swarm_ffi", "file_write")
fn file_write(path: String, content: String) -> Result(Nil, String)

fn live_io() -> w.Io {
  w.Io(
    credential: fn() { option.from_result(api_key()) },
    fetch_prices: fn(t) { https_get(w.models_url, t) },
    post: fn(key, body, t) { https_post_json(w.chat_url, key, body, t) },
    now_ms: fn() { system_time_us() / 1000 },
  )
}

fn default_model() -> String {
  "google/gemma-4-31b-it:free"
}

pub fn main() {
  case argv.load().arguments {
    ["probe"] -> probe()
    ["models"] -> models()
    ["estimate", model, max_tokens] -> estimate(model, max_tokens)
    ["review-lease-invariant", ..rest] -> review(rest)
    _ ->
      io.println(
        "usage: probe | models | estimate <model> <max_tokens> | review-lease-invariant [model] [--paid] [out.json]",
      )
  }
}

fn probe() -> Nil {
  io.println(
    "credential: "
    <> case has_api_key() {
      True -> "present (OPENROUTER_API_KEY, not printed)"
      False -> "absent -> fail closed"
    },
  )
  case https_get(w.models_url, 10_000) {
    Ok(#(200, body)) ->
      case w.decode_prices(body) {
        Ok(ps) ->
          io.println(
            "live prices: " <> int.to_string(list.length(ps)) <> " models",
          )
        Error(e) -> io.println("live prices: " <> w.refusal_label(e))
      }
    Ok(#(code, _)) -> io.println("live prices: http " <> int.to_string(code))
    Error(e) -> io.println("live prices: " <> e)
  }
}

fn models() -> Nil {
  let live = case https_get(w.models_url, 10_000) {
    Ok(#(200, body)) -> w.decode_prices(body) |> result.unwrap([])
    _ -> []
  }
  io.println("| model | tier | ceiling prompt/completion (USD/token) | live |")
  io.println("|---|---|---|---|")
  list.each(w.allowlist(), fn(a) {
    let l = case list.find(live, fn(p) { p.id == a.id }) {
      Ok(p) ->
        float.to_string(p.prompt) <> " / " <> float.to_string(p.completion)
      Error(_) -> "unknown"
    }
    io.println(
      "| "
      <> a.id
      <> " | "
      <> case a.tier {
        w.Free -> "free"
        w.Paid -> "paid"
      }
      <> " | "
      <> float.to_string(a.prompt_ceiling)
      <> " / "
      <> float.to_string(a.completion_ceiling)
      <> " | "
      <> l
      <> " |",
    )
  })
}

fn estimate(model: String, max_tokens: String) -> Nil {
  let n = int.parse(max_tokens) |> result.unwrap(-1)
  let req = w.Request(..w.lease_invariant_review(model), max_tokens: n)
  let policy = w.allow_paid(w.default_policy())
  case https_get(w.models_url, 10_000) {
    Ok(#(200, body)) ->
      case w.decode_prices(body) |> result.try(w.admit(policy, _, req)) {
        Ok(a) ->
          io.println(
            "admitted: "
            <> a.model
            <> " prompt_tokens~"
            <> int.to_string(a.prompt_tokens_est)
            <> " max_tokens "
            <> int.to_string(a.max_tokens)
            <> " estimated USD "
            <> float.to_string(a.estimated_usd)
            <> " timeout "
            <> int.to_string(a.timeout_ms)
            <> " ms",
          )
        Error(e) -> io.println("refused: " <> w.refusal_label(e))
      }
    Ok(#(code, _)) -> io.println("refused: prices http " <> int.to_string(code))
    Error(e) -> io.println("refused: " <> e)
  }
}

fn review(args: List(String)) -> Nil {
  let paid = list.contains(args, "--paid")
  let rest = list.filter(args, fn(a) { a != "--paid" })
  let #(model, out) = case rest {
    [] -> #(default_model(), None)
    [m] -> #(m, None)
    [m, o, ..] -> #(m, Some(o))
  }
  let policy = case paid {
    True -> w.allow_paid(w.default_policy())
    False -> w.default_policy()
  }
  case w.run(policy, live_io(), w.lease_invariant_review(model)) {
    Ok(o) -> {
      io.println(
        "provider "
        <> o.reply.provider
        <> " | model "
        <> o.reply.model
        <> " | tokens "
        <> int.to_string(o.reply.prompt_tokens)
        <> "+"
        <> int.to_string(o.reply.completion_tokens)
        <> " | estimated USD "
        <> float.to_string(o.admitted.estimated_usd)
        <> " | actual USD "
        <> float.to_string(o.cost_usd)
        <> " | "
        <> int.to_string(o.elapsed_ms)
        <> " ms | finish "
        <> o.reply.finish_reason,
      )
      io.println("--- advice ---")
      io.println(o.reply.content)
      write_out(out, o)
    }
    Error(e) -> io.println("refused: " <> w.refusal_label(e))
  }
}

fn write_out(out: Option(String), o: w.Outcome) -> Nil {
  case out {
    Some(path) ->
      case file_write(path, json.to_string(w.outcome_json(o)) <> "\n") {
        Ok(_) -> io.println("outcome written: " <> path)
        Error(e) -> io.println("outcome not written: " <> e)
      }
    None -> Nil
  }
}

/// Exposed for tests: the advice text never carries the credential.
pub fn redact(text: String) -> String {
  string.replace(text, "sk-or-", "[redacted]")
}
