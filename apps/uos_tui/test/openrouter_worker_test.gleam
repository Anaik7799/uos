import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import uos_tui/openrouter_worker as w

fn prices() -> List(w.Price) {
  [
    w.Price("google/gemma-4-31b-it:free", 0.0, 0.0),
    w.Price("openai/gpt-4.1-nano", 0.0000001, 0.0000004),
    w.Price("anthropic/claude-haiku-4.5", 0.000001, 0.000005),
    w.Price("openai/gpt-5", 0.00001, 0.0001),
  ]
}

fn req(model: String) -> w.Request {
  w.lease_invariant_review(model)
}

pub fn free_model_is_admitted_under_default_policy_test() {
  let assert Ok(a) =
    w.admit(w.default_policy(), prices(), req("google/gemma-4-31b-it:free"))
  a.tier |> should.equal(w.Free)
  a.estimated_usd |> should.equal(0.0)
  a.timeout_ms |> should.equal(30_000)
  a.max_tokens |> should.equal(384)
}

pub fn non_allowlisted_model_is_refused_test() {
  w.admit(w.default_policy(), prices(), req("openai/gpt-5"))
  |> should.equal(Error(w.NotAllowlisted("openai/gpt-5")))
}

pub fn paid_model_refused_when_free_only_test() {
  w.admit(w.default_policy(), prices(), req("openai/gpt-4.1-nano"))
  |> should.equal(Error(w.FreeOnly("openai/gpt-4.1-nano")))
}

pub fn paid_model_admitted_with_opt_in_within_budget_test() {
  let assert Ok(a) =
    w.admit(
      w.allow_paid(w.default_policy()),
      prices(),
      req("openai/gpt-4.1-nano"),
    )
  a.tier |> should.equal(w.Paid)
  { a.estimated_usd <. 0.02 } |> should.be_true
}

pub fn token_ceiling_is_enforced_test() {
  let r = w.Request(..req("google/gemma-4-31b-it:free"), max_tokens: 513)
  w.admit(w.default_policy(), prices(), r)
  |> should.equal(Error(w.TooManyTokens(513, 512)))
}

pub fn policy_cannot_raise_the_ceilings_test() {
  let loose = w.Policy(4096, 5.0, 600_000, False)
  let r = w.Request(..req("google/gemma-4-31b-it:free"), max_tokens: 600)
  w.admit(loose, prices(), r)
  |> should.equal(Error(w.TooManyTokens(600, 512)))
  let assert Ok(a) = w.admit(loose, prices(), req("google/gemma-4-31b-it:free"))
  a.timeout_ms |> should.equal(30_000)
}

pub fn unknown_live_price_is_refused_test() {
  w.admit(w.default_policy(), [], req("google/gemma-4-31b-it:free"))
  |> should.equal(Error(w.PriceUnknown("google/gemma-4-31b-it:free")))
}

pub fn live_price_above_ceiling_is_refused_test() {
  let hiked = [w.Price("google/gemma-4-31b-it:free", 0.000001, 0.0)]
  w.admit(w.default_policy(), hiked, req("google/gemma-4-31b-it:free"))
  |> should.equal(
    Error(w.PriceAboveCeiling("google/gemma-4-31b-it:free", 0.000001, 0.0)),
  )
}

pub fn over_budget_is_refused_test() {
  // haiku 4.5 at 512 completion tokens costs ~0.0026; force a tiny budget.
  let tight = w.Policy(512, 0.001, 30_000, False)
  let assert Error(w.OverBudget(est, budget)) =
    w.admit(tight, prices(), req("anthropic/claude-haiku-4.5"))
  { est >. budget } |> should.be_true
  budget |> should.equal(0.001)
}

pub fn prompt_hygiene_refuses_paths_source_and_secrets_test() {
  w.sanitize_check("please read /home/an/x")
  |> should.equal(Error(w.UnsanitizedPrompt("filesystem path")))
  w.sanitize_check("here: ```gleam let x = 1```")
  |> should.equal(Error(w.UnsanitizedPrompt("code fence")))
  w.sanitize_check("key sk-or-v1-abc")
  |> should.equal(Error(w.UnsanitizedPrompt("credential pattern")))
  w.sanitize_check(string.repeat("a", 2001))
  |> should.equal(Error(w.UnsanitizedPrompt("longer than 2000 characters")))
  w.sanitize_check("abstract design question") |> should.equal(Ok(Nil))
}

pub fn the_lease_review_prompt_is_sanitized_test() {
  let r = req("google/gemma-4-31b-it:free")
  w.sanitize_check(r.system) |> should.equal(Ok(Nil))
  w.sanitize_check(r.user) |> should.equal(Ok(Nil))
  string.contains(r.user, "uxwmloqm") |> should.be_false
  string.contains(r.user, "coord") |> should.be_false
}

pub fn request_json_has_no_tools_and_bounded_tokens_test() {
  let body = w.request_json(req("google/gemma-4-31b-it:free"))
  string.contains(body, "\"tools\"") |> should.be_false
  string.contains(body, "\"max_tokens\":384") |> should.be_true
  string.contains(body, "\"stream\":false") |> should.be_true
  string.contains(body, "\"model\":\"google/gemma-4-31b-it:free\"")
  |> should.be_true
}

pub fn reply_decoding_reads_usage_provider_and_cost_test() {
  let body =
    "{\"id\":\"gen-1\",\"provider\":\"Google\",\"model\":\"google/gemma-4-31b-it:free\",\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\"1. clock skew\"}}],\"usage\":{\"prompt_tokens\":120,\"completion_tokens\":80,\"total_tokens\":200,\"cost\":0}}"
  let assert Ok(r) = w.decode_reply(body)
  r.provider |> should.equal("Google")
  r.content |> should.equal("1. clock skew")
  r.prompt_tokens |> should.equal(120)
  r.completion_tokens |> should.equal(80)
  r.reported_cost_usd |> should.equal(Some(0.0))
  r.finish_reason |> should.equal("stop")
}

pub fn price_list_decoding_handles_string_prices_test() {
  let body =
    "{\"data\":[{\"id\":\"a/b:free\",\"pricing\":{\"prompt\":\"0\",\"completion\":\"0\"}},{\"id\":\"c/d\",\"pricing\":{\"prompt\":\"0.000000075\",\"completion\":\"0.0000002\"}}]}"
  let assert Ok(ps) = w.decode_prices(body)
  list.length(ps) |> should.equal(2)
  let assert Ok(d) = list.find(ps, fn(p) { p.id == "c/d" })
  d.completion |> should.equal(0.0000002)
}

pub fn actual_cost_prefers_provider_figure_test() {
  let price = w.Price("m", 0.000001, 0.000005)
  let r = w.Reply("m", "p", "x", 100, 50, 150, None, "stop")
  w.actual_cost(r, price) |> should.equal(0.00035)
  let r2 = w.Reply(..r, reported_cost_usd: Some(0.0003))
  w.actual_cost(r2, price) |> should.equal(0.0003)
}

fn io_with(credential: option.Option(String), posted: fn() -> Nil) -> w.Io {
  w.Io(
    credential: fn() { credential },
    fetch_prices: fn(_) {
      Ok(#(
        200,
        "{\"data\":[{\"id\":\"google/gemma-4-31b-it:free\",\"pricing\":{\"prompt\":\"0\",\"completion\":\"0\"}}]}",
      ))
    },
    post: fn(_, _, _) {
      posted()
      Ok(#(
        200,
        "{\"provider\":\"Google\",\"model\":\"google/gemma-4-31b-it:free\",\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"content\":\"ok\"}}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}",
      ))
    },
    now_ms: fn() { 1000 },
  )
}

pub fn missing_credential_fails_closed_before_any_request_test() {
  let io = io_with(None, fn() { panic as "post must not be called" })
  w.run(w.default_policy(), io, req("google/gemma-4-31b-it:free"))
  |> should.equal(Error(w.MissingCredential))
}

pub fn run_returns_outcome_with_measured_cost_test() {
  let io = io_with(Some("k"), fn() { Nil })
  let assert Ok(o) =
    w.run(w.default_policy(), io, req("google/gemma-4-31b-it:free"))
  o.reply.content |> should.equal("ok")
  o.cost_usd |> should.equal(0.0)
  o.reply.total_tokens |> should.equal(15)
  let payload = w.report_payload(o, "generated/x.json")
  list.key_find(payload, "tier") |> should.equal(Ok("free"))
  list.key_find(payload, "role")
  |> should.equal(Ok("advisory only; no tools; no side effects"))
}

pub fn non_200_status_is_a_refusal_test() {
  let io =
    w.Io(..io_with(Some("k"), fn() { Nil }), post: fn(_, _, _) {
      Ok(#(402, "{\"error\":\"insufficient credits\"}"))
    })
  let assert Error(w.HttpStatus(402, head)) =
    w.run(w.default_policy(), io, req("google/gemma-4-31b-it:free"))
  string.contains(head, "insufficient") |> should.be_true
}
