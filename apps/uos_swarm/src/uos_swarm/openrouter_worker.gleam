//// OpenRouter advisory worker: pure-Gleam policy around one bounded, credential-gated
//// chat completion. The worker is advisory only: it has no tools, no side effects, and
//// its output is a Report on the board or a printed advice text. Every network call goes
//// through injected I/O functions so the policy is unit-testable without a credential.
////
//// Policy (fail closed):
//// - exact-model allowlist with a price ceiling per model (USD per token);
//// - the live public price must be known and at or below the ceiling;
//// - free-only by default; paid models need an explicit opt-in;
//// - `max_tokens` <= 512 and estimated cost <= USD 0.02;
//// - timeout 30 s; no credential -> `MissingCredential` before any request is built;
//// - prompts must pass `sanitize_check` (no paths, source, fences or secrets).

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/route

pub const chat_url = "https://openrouter.ai/api/v1/chat/completions"

pub const models_url = "https://openrouter.ai/api/v1/models"

/// Hard ceilings of the policy (the request may ask for less, never more).
pub const max_tokens_ceiling = 512

pub const budget_usd_ceiling = 0.02

pub const timeout_ms = 30_000

pub type Tier {
  Free
  Paid
}

/// An allowlisted model with the highest price (USD per token) we accept for it.
pub type Allowed {
  Allowed(
    id: String,
    tier: Tier,
    prompt_ceiling: Float,
    completion_ceiling: Float,
  )
}

/// Exact model ids, checked against the live public price list before each call.
pub fn allowlist() -> List(Allowed) {
  [
    Allowed("openrouter/free", Free, 0.0, 0.0),
    Allowed("inclusionai/ling-3.0-flash-fin:free", Free, 0.0, 0.0),
    Allowed("google/gemma-4-31b-it:free", Free, 0.0, 0.0),
    Allowed("nvidia/nemotron-3.5-lightning:free", Free, 0.0, 0.0),
    Allowed("minimax/minimax-m3:free", Free, 0.0, 0.0),
    Allowed("thinkingmachines/inkling:free", Free, 0.0, 0.0),
    Allowed("google/gemini-2.5-flash-lite", Paid, 0.0000001, 0.0000004),
    Allowed("openai/gpt-4.1-nano", Paid, 0.0000001, 0.0000004),
    Allowed(
      "mistralai/mistral-small-3.2-24b-instruct",
      Paid,
      0.000000075,
      0.0000002,
    ),
    Allowed("anthropic/claude-haiku-4.5", Paid, 0.000001, 0.000005),
  ]
}

pub type Policy {
  Policy(max_tokens: Int, budget_usd: Float, timeout_ms: Int, free_only: Bool)
}

/// The default policy: free-only, 512 tokens, USD 0.02, 30 s.
pub fn default_policy() -> Policy {
  Policy(max_tokens_ceiling, budget_usd_ceiling, timeout_ms, True)
}

/// Explicit opt-in to paid allowlisted models; ceilings stay in force.
pub fn allow_paid(p: Policy) -> Policy {
  Policy(..p, free_only: False)
}

pub type Request {
  Request(model: String, system: String, user: String, max_tokens: Int)
}

/// Live price of a model from the public list (USD per prompt token, per completion token).
pub type Price {
  Price(id: String, prompt: Float, completion: Float)
}

pub type Refusal {
  NotAllowlisted(model: String)
  FreeOnly(model: String)
  TooManyTokens(asked: Int, ceiling: Int)
  PriceUnknown(model: String)
  PriceAboveCeiling(model: String, prompt: Float, completion: Float)
  OverBudget(estimated_usd: Float, budget_usd: Float)
  UnsanitizedPrompt(reason: String)
  MissingCredential
  Transport(reason: String)
  HttpStatus(code: Int, body_head: String)
  BadResponse(reason: String)
  RouteRefused(reason: String)
}

pub fn refusal_label(r: Refusal) -> String {
  case r {
    NotAllowlisted(m) -> "model not allowlisted: " <> m
    FreeOnly(m) -> "policy is free-only; paid model refused: " <> m
    TooManyTokens(a, c) ->
      "max_tokens " <> int.to_string(a) <> " > ceiling " <> int.to_string(c)
    PriceUnknown(m) -> "live price unknown for " <> m
    PriceAboveCeiling(m, p, c) ->
      "live price above ceiling for "
      <> m
      <> " (prompt "
      <> float.to_string(p)
      <> ", completion "
      <> float.to_string(c)
      <> ")"
    OverBudget(e, b) ->
      "estimated USD "
      <> float.to_string(e)
      <> " exceeds budget USD "
      <> float.to_string(b)
    UnsanitizedPrompt(why) -> "prompt refused: " <> why
    MissingCredential -> "no OPENROUTER_API_KEY in the approved environment"
    Transport(why) -> "transport: " <> why
    HttpStatus(code, head) -> "http " <> int.to_string(code) <> ": " <> head
    BadResponse(why) -> "bad response: " <> why
    RouteRefused(why) -> "route refused: " <> why
  }
}

/// What the policy admitted, with the numbers the decision was made on.
pub type Admitted {
  Admitted(
    model: String,
    tier: Tier,
    price: Price,
    prompt_tokens_est: Int,
    max_tokens: Int,
    estimated_usd: Float,
    timeout_ms: Int,
  )
}

/// Rough prompt token estimate: one token per four characters plus message overhead.
pub fn estimate_prompt_tokens(system: String, user: String) -> Int {
  { string.length(system) + string.length(user) } / 4 + 16
}

pub fn estimate_cost(
  price: Price,
  prompt_tokens: Int,
  max_tokens: Int,
) -> Float {
  int.to_float(prompt_tokens)
  *. price.prompt
  +. int.to_float(max_tokens)
  *. price.completion
}

const forbidden_fragments = [
  #("/home/", "filesystem path"),
  #("apps/", "repository path"),
  #(".gleam", "source file reference"),
  #(".erl", "source file reference"),
  #("```", "code fence"),
  #("import ", "source code"),
  #("sk-or-", "credential pattern"),
  #("OPENROUTER_API_KEY", "credential name"),
  #("UOS_BOARD_KEY", "credential name"),
  #("BEGIN ", "key material marker"),
  #("password", "secret word"),
]

/// Refuse prompts that could carry private source, paths, fences or secrets, or are too long.
pub fn sanitize_check(text: String) -> Result(Nil, Refusal) {
  case string.length(text) > 2000 {
    True -> Error(UnsanitizedPrompt("longer than 2000 characters"))
    False ->
      case
        list.find(forbidden_fragments, fn(f) { string.contains(text, f.0) })
      {
        Ok(#(_, why)) -> Error(UnsanitizedPrompt(why))
        Error(_) -> Ok(Nil)
      }
  }
}

fn find_allowed(model: String) -> Result(Allowed, Refusal) {
  allowlist()
  |> list.find(fn(a) { a.id == model })
  |> result.replace_error(NotAllowlisted(model))
}

fn find_price(prices: List(Price), model: String) -> Result(Price, Refusal) {
  prices
  |> list.find(fn(p) { p.id == model })
  |> result.replace_error(PriceUnknown(model))
}

/// The admission decision: allowlist, tier, token ceiling, live price ceiling, budget, prompt hygiene.
pub fn admit(
  policy: Policy,
  prices: List(Price),
  req: Request,
) -> Result(Admitted, Refusal) {
  use allowed <- result.try(find_allowed(req.model))
  use _ <- result.try(case policy.free_only, allowed.tier {
    True, Paid -> Error(FreeOnly(req.model))
    _, _ -> Ok(Nil)
  })
  let ceiling = int.min(policy.max_tokens, max_tokens_ceiling)
  use _ <- result.try(case req.max_tokens > ceiling || req.max_tokens < 1 {
    True -> Error(TooManyTokens(req.max_tokens, ceiling))
    False -> Ok(Nil)
  })
  use price <- result.try(find_price(prices, req.model))
  use _ <- result.try(case price.prompt <. 0.0 || price.completion <. 0.0 {
    True -> Error(PriceUnknown(req.model))
    False -> Ok(Nil)
  })
  use _ <- result.try(
    case
      price.prompt >. allowed.prompt_ceiling
      || price.completion >. allowed.completion_ceiling
    {
      True ->
        Error(PriceAboveCeiling(req.model, price.prompt, price.completion))
      False -> Ok(Nil)
    },
  )
  use _ <- result.try(sanitize_check(req.system))
  use _ <- result.try(sanitize_check(req.user))
  let prompt_tokens = estimate_prompt_tokens(req.system, req.user)
  let est = estimate_cost(price, prompt_tokens, req.max_tokens)
  let budget = float.min(policy.budget_usd, budget_usd_ceiling)
  case est >. budget {
    True -> Error(OverBudget(est, budget))
    False ->
      Ok(Admitted(
        req.model,
        allowed.tier,
        price,
        prompt_tokens,
        req.max_tokens,
        est,
        int.min(policy.timeout_ms, timeout_ms),
      ))
  }
}

/// OpenAI-compatible chat completion body: no tools, no streaming, deterministic.
pub fn request_json(req: Request) -> String {
  let provider = case string.ends_with(req.model, ":free") || req.model == "openrouter/free" {
    True -> [#("provider", json.object([
      #("zdr", json.bool(True)),
      #("max_price", json.object([
        #("prompt", json.float(0.0)),
        #("completion", json.float(0.0)),
        #("request", json.float(0.0)),
      ])),
    ])),
      // Short bounded advisory calls need a final answer within their token
      // allowance. Optional hidden reasoning must not consume the whole cap.
      #("reasoning", json.object([
        #("enabled", json.bool(False)),
        #("exclude", json.bool(True)),
      ])),
    ]
    False -> []
  }
  json.object(list.append([
    #("model", json.string(req.model)),
    #(
      "messages",
      json.array([#("system", req.system), #("user", req.user)], fn(m) {
        json.object([
          #("role", json.string(m.0)),
          #("content", json.string(m.1)),
        ])
      }),
    ),
    #("max_tokens", json.int(req.max_tokens)),
    #("temperature", json.float(0.0)),
    #("stream", json.bool(False)),
    #("usage", json.object([#("include", json.bool(True))])),
  ], provider))
  |> json.to_string
}

pub type Reply {
  Reply(
    model: String,
    provider: String,
    content: String,
    prompt_tokens: Int,
    completion_tokens: Int,
    total_tokens: Int,
    reported_cost_usd: Option(Float),
    finish_reason: String,
  )
}

fn number() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

fn reply_decoder() -> decode.Decoder(Reply) {
  use model <- decode.field("model", decode.string)
  use provider <- decode.optional_field("provider", "", decode.string)
  use choices <- decode.field(
    "choices",
    decode.list({
      use finish <- decode.optional_field("finish_reason", "", decode.string)
      use content <- decode.subfield(["message", "content"], decode.string)
      decode.success(#(content, finish))
    }),
  )
  use usage <- decode.field("usage", {
    use pt <- decode.field("prompt_tokens", decode.int)
    use ct <- decode.field("completion_tokens", decode.int)
    use tt <- decode.field("total_tokens", decode.int)
    use cost <- decode.optional_field("cost", None, decode.optional(number()))
    decode.success(#(pt, ct, tt, cost))
  })
  let #(prompt_tokens, completion_tokens, total_tokens, cost) = usage
  let #(content, finish) =
    list.first(choices) |> result.unwrap(#("", "no choices"))
  decode.success(Reply(
    model,
    provider,
    content,
    prompt_tokens,
    completion_tokens,
    total_tokens,
    cost,
    finish,
  ))
}

pub fn decode_reply(body: String) -> Result(Reply, Refusal) {
  use reply <- result.try(json.parse(body, reply_decoder())
    |> result.map_error(fn(_) { BadResponse("missing or invalid completion fields") }))
  let valid_cost = case reply.reported_cost_usd {
    Some(c) -> c >=. 0.0
    None -> True
  }
  case string.trim(reply.model) != "" && string.trim(reply.content) != ""
    && reply.prompt_tokens >= 0 && reply.completion_tokens > 0
    && reply.total_tokens == reply.prompt_tokens + reply.completion_tokens
    && valid_cost {
    True -> Ok(reply)
    False -> Error(BadResponse("empty completion or inconsistent usage"))
  }
}

fn price_string() -> decode.Decoder(Float) {
  decode.one_of(
    decode.string
      |> decode.map(fn(s) {
        case float.parse(s) {
          Ok(f) -> f
          Error(_) ->
            int.parse(s) |> result.map(int.to_float) |> result.unwrap(-1.0)
        }
      }),
    [number()],
  )
}

/// Decode the public model list into live prices (a negative price means unparseable).
pub fn decode_prices(body: String) -> Result(List(Price), Refusal) {
  let entry = {
    use id <- decode.field("id", decode.string)
    use prompt <- decode.subfield(["pricing", "prompt"], price_string())
    use completion <- decode.subfield(["pricing", "completion"], price_string())
    decode.success(Price(id, prompt, completion))
  }
  json.parse(body, decode.field("data", decode.list(entry), decode.success))
  |> result.map_error(fn(e) { BadResponse(string.inspect(e)) })
  |> result.map(fn(ps) { list.filter(ps, fn(p) { p.prompt >=. 0.0 && p.completion >=. 0.0 }) })
}

/// Cost from measured usage at the admitted price; the provider's own figure wins when present.
pub fn actual_cost(reply: Reply, price: Price) -> Float {
  case reply.reported_cost_usd {
    Some(c) -> c
    None ->
      int.to_float(reply.prompt_tokens)
      *. price.prompt
      +. int.to_float(reply.completion_tokens)
      *. price.completion
  }
}

pub type Outcome {
  Outcome(admitted: Admitted, reply: Reply, cost_usd: Float, elapsed_ms: Int)
}

/// Injected I/O so the policy runs identically in tests and live.
pub type Io {
  Io(
    credential: fn() -> Option(String),
    fetch_prices: fn(Int) -> Result(#(Int, String), String),
    post: fn(String, String, Int) -> Result(#(Int, String), String),
    now_ms: fn() -> Int,
  )
}

/// Run one advisory completion under the policy. Order matters: the credential is checked
/// first so a missing key never causes a network round trip; then live prices; then admission.
pub fn run(policy: Policy, io: Io, req: Request) -> Result(Outcome, Refusal) {
  use key <- result.try(case io.credential() {
    Some(k) -> Ok(k)
    None -> Error(MissingCredential)
  })
  let t = int.min(policy.timeout_ms, timeout_ms)
  use prices <- result.try(case io.fetch_prices(t) {
    Ok(#(200, body)) -> decode_prices(body)
    Ok(#(code, body)) -> Error(HttpStatus(code, string.slice(body, 0, 120)))
    Error(e) -> Error(Transport(e))
  })
  use admitted <- result.try(admit(policy, prices, req))
  let started = io.now_ms()
  use #(code, body) <- result.try(
    io.post(key, request_json(req), admitted.timeout_ms)
    |> result.map_error(Transport),
  )
  let elapsed = io.now_ms() - started
  use _ <- result.try(case code {
    200 -> Ok(Nil)
    c -> Error(HttpStatus(c, string.slice(body, 0, 120)))
  })
  use reply <- result.try(decode_reply(body))
  Ok(Outcome(admitted, reply, actual_cost(reply, admitted.price), elapsed))
}

/// `run` gated by the global intelligence router (`uos_swarm/route`): first asks
/// `route.route` for class `R3Advisory` with the tier universe built from the same live
/// prices this call will use, so a route-level refusal (unproven tier, paid without a
/// budget, etc.) is caught before any network round trip; a `Refuse` becomes
/// `Error(RouteRefused(reason))`. When `route.route` admits a tier, this falls through to
/// the unchanged `run`, whose own `admit` remains the authoritative allowlist/price/budget
/// check for the actual dispatch. A paid decision out of `route.route` is only possible
/// when the caller's `route_policy`/`budget` satisfy rule (d) in `uos_swarm/route`.
pub fn run_routed(
  policy: Policy,
  route_policy: route.Policy,
  io: Io,
  req: Request,
  posteriors: List(route.Posterior),
  budget: Option(route.Budget),
) -> Result(Outcome, Refusal) {
  let t = int.min(policy.timeout_ms, timeout_ms)
  use prices <- result.try(case io.fetch_prices(t) {
    Ok(#(200, body)) -> decode_prices(body)
    Ok(#(code, body)) -> Error(HttpStatus(code, string.slice(body, 0, 120)))
    Error(e) -> Error(Transport(e))
  })
  let live_prices = list.map(prices, fn(p) { #(p.id, p.prompt, p.completion) })
  let tiers = route.default_tiers(live_prices)
  let est_out = req.max_tokens
  let est_in = estimate_prompt_tokens(req.system, req.user)
  case
    route.route(
      route_policy,
      route.R3Advisory,
      tiers,
      posteriors,
      budget,
      est_in,
      est_out,
    )
  {
    route.Refuse(reason) -> Error(RouteRefused(reason))
    route.Route(_, _, _) -> run(policy, io, req)
  }
}

/// The one sanitized review this slice runs: a fencing-token lease invariant, stated
/// abstractly. No source, paths, identifiers or prompts from the repository are included.
pub fn lease_invariant_review(model: String) -> Request {
  Request(
    model,
    "You are a careful distributed-systems reviewer. Answer in at most 200 words, as a numbered list.",
    "Design under review: each resource has at most one live lease; lease epochs are strictly increasing per resource; a renewal with a stale epoch, or after expiry, must be refused; a freshly started service must seed its epochs from the durable log before granting anything; every mutation of the resource must carry the epoch and be refused when the epoch is not the current one. List the three most likely ways this invariant is violated in practice and one concrete test for each.",
    384,
  )
}

/// Board payload for a Report about an advisory outcome (no advice body, no secrets).
pub fn report_payload(
  o: Outcome,
  advice_ref: String,
) -> List(#(String, String)) {
  [
    #("provider", o.reply.provider),
    #("model", o.reply.model),
    #("tier", case o.admitted.tier {
      Free -> "free"
      Paid -> "paid"
    }),
    #("prompt_tokens", int.to_string(o.reply.prompt_tokens)),
    #("completion_tokens", int.to_string(o.reply.completion_tokens)),
    #("estimated_usd", float.to_string(o.admitted.estimated_usd)),
    #("actual_usd", float.to_string(o.cost_usd)),
    #("elapsed_ms", int.to_string(o.elapsed_ms)),
    #("finish_reason", o.reply.finish_reason),
    #("advice_ref", advice_ref),
    #("role", "advisory only; no tools; no side effects"),
  ]
}

pub fn outcome_json(o: Outcome) -> Json {
  json.object([
    #("model", json.string(o.reply.model)),
    #("provider", json.string(o.reply.provider)),
    #(
      "tier",
      json.string(case o.admitted.tier {
        Free -> "free"
        Paid -> "paid"
      }),
    ),
    #("prompt_tokens", json.int(o.reply.prompt_tokens)),
    #("completion_tokens", json.int(o.reply.completion_tokens)),
    #("total_tokens", json.int(o.reply.total_tokens)),
    #("estimated_usd", json.float(o.admitted.estimated_usd)),
    #("actual_usd", json.float(o.cost_usd)),
    #("reported_cost_usd", case o.reply.reported_cost_usd {
      Some(c) -> json.float(c)
      None -> json.null()
    }),
    #("elapsed_ms", json.int(o.elapsed_ms)),
    #("finish_reason", json.string(o.reply.finish_reason)),
    #("timeout_ms", json.int(o.admitted.timeout_ms)),
    #("max_tokens", json.int(o.admitted.max_tokens)),
    #("advice", json.string(o.reply.content)),
  ])
}
