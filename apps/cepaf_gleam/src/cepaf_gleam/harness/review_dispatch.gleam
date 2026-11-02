//// Existing successor effect interpreter adapter, not a second controller.
//// Authorizing this tool requires a whole-grant-reviewed optional delegation.

import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/review_completion as c
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/json_guard
import gleam/json
import gleam/list
import gleam/result

@external(erlang, "pi_review_io", "reserve")
fn reserve(request: String) -> Result(String, String)

@external(erlang, "pi_review_io", "ready")
pub fn readiness() -> Result(Nil, String)

@external(erlang, "pi_review_io", "invoke")
fn invoke(
  root: String,
  runtime: String,
  body: String,
) -> Result(c.Exchange, String)

fn text(v: value.Value, k: String) -> Result(String, String) {
  use x <- result.try(value.get(v, k))
  case x {
    value.Text(s) -> Ok(s)
    _ -> Error("review_field:" <> k)
  }
}

fn closed(v: value.Value, keys: List(String)) -> Result(Nil, String) {
  case v {
    value.Object(fs) ->
      a.require(
        list.length(fs) == list.length(keys)
          && list.all(fs, fn(p) { list.contains(keys, p.0) }),
        "review_closed_fields",
      )
    _ -> Error("review_closed_fields")
  }
}

pub fn backend(name: String) -> Result(c.Backend, String) {
  case name {
    "pi" -> Ok(c.PiOpenRouterArgon)
    "claude" -> Ok(c.Claude)
    "agy" -> Ok(c.Agy)
    "codex" -> Ok(c.Codex)
    _ -> Error("review_backend")
  }
}

/// Same logical review remains the same paid ID after worker/grant/attempt
/// replacement. Changed prompt/backend under it cannot reserve a second row.
pub fn logical_call_id(plan: String, task: String, intent: String) -> String {
  "agent-review:" <> files.digest(plan <> "\u{0}" <> task <> "\u{0}" <> intent)
}

/// Pure request admission plus SOURCE readiness gate; no grant, budget,
/// credential or process IO can precede a successful result from this function.
pub fn prepare_available(
  chosen: c.Backend,
  id: String,
  prompt: String,
  tokens: Int,
) -> Result(c.Prepared, String) {
  use prepared <- result.try(c.prepare(chosen, id, prompt, tokens))
  use _ <- result.try(readiness())
  Ok(prepared)
}

fn entitlement(e: a.Execution) -> Result(String, String) {
  use _ <- result.try(a.check(e.grant))
  use bytes <- result.try(files.read(dev.root, e.grant.path))
  use _ <- result.try(a.require(
    files.digest(bytes) == e.grant.digest,
    "grant_changed",
  ))
  use doc <- result.try(
    json_guard.native_inspect(bytes, 32)
    |> result.map_error(fn(_) { "review_grant_json" }),
  )
  use grant <- result.try(value.get(doc, "completion_review"))
  use _ <- result.try(
    closed(grant, [
      "backends",
      "targets",
      "max_request_nanodollars",
      "max_output_tokens",
      "runtime",
    ]),
  )
  use _ <- result.try(a.require(
    value.get(grant, "backends")
      == Ok(value.Array([value.Text("pi_openrouter_argon")]))
      && value.get(grant, "max_request_nanodollars")
      == Ok(value.Integer(19_999_999))
      && value.get(grant, "max_output_tokens") == Ok(value.Integer(512))
      && list.contains(e.scope.allowed_clients, "pi"),
    "review_not_delegated",
  ))
  use targets <- result.try(value.get(grant, "targets"))
  use _ <- result.try(case targets {
    value.Array(xs) ->
      a.require(
        xs != []
          && list.length(xs) <= 32
          && list.any(xs, fn(x) {
          value.get(x, "plan") == Ok(value.Text(e.scope.plan))
          && value.get(x, "task") == Ok(value.Text(e.scope.task))
        }),
        "review_target_scope",
      )
    _ -> Error("review_target_scope")
  })
  use runtime <- result.try(value.get(grant, "runtime"))
  use _ <- result.try(
    closed(runtime, ["node_sha256", "worker_sha256", "sdk_sha256"]),
  )
  use _ <- result.try(
    list.try_each(["node_sha256", "worker_sha256", "sdk_sha256"], fn(k) {
      use hash <- result.try(text(runtime, k))
      a.require(a.digest_valid(hash), "review_runtime_pin")
    }),
  )
  Ok(json.to_string(value.encode(runtime)))
}

/// Runs INSIDE operations.effect's durable intent/replay/unknown stop line.
/// No effect is attempted for unavailable backends or missing reviewed grant.
pub fn perform(e: a.Execution, args: value.Value) -> Result(String, String) {
  use intent <- result.try(text(args, "intent_id"))
  use name <- result.try(text(args, "backend"))
  use prompt <- result.try(text(args, "prompt"))
  use tokens <- result.try(
    text(args, "max_tokens") |> result.try(c.token_count),
  )
  use chosen <- result.try(backend(name))
  // Attempt/grant changes cannot create a fresh paid request namespace.
  let id = logical_call_id(e.binding.plan, e.binding.task, intent)
  use prepared <- result.try(prepare_available(chosen, id, prompt, tokens))
  use runtime <- result.try(entitlement(e))
  use root <- result.try(a.source_root(e.grant))
  let io =
    c.Io(
      authorize: fn() {
        use _ <- result.try(entitlement(e))
        a.fence(e, 35_000) |> result.map(fn(_) { Nil })
      },
      reserve: reserve,
      invoke: fn(body) { invoke(root, runtime, body) },
    )
  c.execute(prepared, io)
}

pub fn availability_json() -> json.Json {
  json.object([
    #("pi", json.string("PREPARATION_ONLY_TRANSPORT_UNAVAILABLE")),
    #("claude", json.string("UNAVAILABLE_EXISTING_ADAPTER_NOT_INTEGRATED")),
    #("agy", json.string("UNAVAILABLE_EXISTING_ADAPTER_NOT_INTEGRATED")),
    #("codex", json.string("UNAVAILABLE_EXISTING_ADAPTER_NOT_INTEGRATED")),
    #("agentic_tool_loop", json.bool(False)),
    #("live_completion_verified", json.bool(False)),
    #("capability", json.string("BOUNDED_COMPLETION_ADVICE_ONLY")),
    #(
      "economy",
      json.object([
        #("max_output_tokens", json.int(512)),
        #("request_cost_strictly_below_nanodollars", json.int(20_000_000)),
        #("daily_reserved_limit_nanodollars", json.int(10_000_000_000)),
        #("canonical_retained_per_call_nanodollars", json.int(250_000_000)),
        #("actual_provider_cost", json.null()),
        #("price_basis", json.string("PINNED_CEILING_NOT_LIVE_QUOTE")),
        #(
          "preference",
          json.string("EXISTING_LOCAL_DETERMINISTIC_CHECKS_FIRST"),
        ),
      ]),
    ),
    #(
      "blocking",
      json.array(
        [
          "FIXED_CLEAN_LAUNCH_ENVIRONMENT", "POST_CATALOG_GLEAM_FENCE",
          "VERIFIED_TRANSITIVE_SDK_RUNTIME_CLOSURE",
          "CURRENT_ZDR_PRICE_ELIGIBILITY",
        ],
        json.string,
      ),
    ),
  ])
}
