import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import uos_swarm/openrouter_worker as w
import uos_swarm/route

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
  w.sanitize_check(string.repeat("a", w.prompt_field_chars_ceiling + 1))
  |> should.equal(
    Error(
      w.UnsanitizedPrompt(
        "longer than "
        <> int.to_string(w.prompt_field_chars_ceiling)
        <> " characters",
      ),
    ),
  )
  w.sanitize_check("abstract design question") |> should.equal(Ok(Nil))
}

/// The host OS NVMe serial is the one identifier canonical policy names as
/// hard-denied (ops/kubernetes/nas-k8s-lab/src/spec.rs), yet this checker
/// refused paths and credentials and let it through. Falsifier: drop the
/// fragment from `forbidden_fragments`.
pub fn prompt_hygiene_refuses_the_denied_os_nvme_serial_test() {
  w.sanitize_check("which bay holds 25503L801736?")
  |> should.equal(Error(w.UnsanitizedPrompt("host OS NVMe serial")))
}

pub fn the_lease_review_prompt_is_sanitized_test() {
  let r = req("google/gemma-4-31b-it:free")
  w.sanitize_check(r.system) |> should.equal(Ok(Nil))
  w.sanitize_check(r.user) |> should.equal(Ok(Nil))
  string.contains(r.user, "uxwmloqm") |> should.be_false
  string.contains(r.user, "coord") |> should.be_false
}

pub fn gemma_4_26b_is_in_allowlist_test() {
  let list = w.allowlist()
  let assert Ok(free) = list.find(list, fn(a) { a.id == "google/gemma-4-26b-a4b-it:free" })
  free.tier |> should.equal(w.Free)
  let assert Ok(paid) = list.find(list, fn(a) { a.id == "google/gemma-4-26b-a4b-it" })
  paid.tier |> should.equal(w.Paid)
}

pub fn combining_marks_cannot_bypass_actual_utf8_request_bound_test() {
  // One user-perceived character can hold thousands of combining code points.
  let oversized = "a" <> string.repeat("\u{0301}", 524_288)
  string.length(oversized) |> should.equal(1)
  w.sanitize_check(oversized)
  |> should.equal(
    Error(
      w.UnsanitizedPrompt(
        "longer than "
        <> int.to_string(w.prompt_field_bytes_ceiling)
        <> " UTF-8 bytes",
      ),
    ),
  )
  let io =
    w.Io(..routing_io("moonshotai/kimi-k3"), post: fn(_, _, _) {
      panic as "oversized UTF-8 input must not POST"
    })
  let request =
    w.Request("moonshotai/kimi-k3", "bounded advice", oversized, 4096)
  w.run(w.profile_policy(w.CodingKimi), io, request)
  |> should.equal(
    Error(
      w.UnsanitizedPrompt(
        "longer than "
        <> int.to_string(w.prompt_field_bytes_ceiling)
        <> " UTF-8 bytes",
      ),
    ),
  )
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

pub fn run_routed_refuses_when_route_refuses_test() {
  // No proven tiers and no live free/paid prices: the router has nothing eligible for
  // R3Advisory, so `run_routed` must refuse before ever reaching `run`'s own `post`.
  let io = io_with(Some("k"), fn() { panic as "post must not be called" })
  let result =
    w.run_routed(
      w.default_policy(),
      route.default_policy(),
      io,
      req("google/gemma-4-31b-it:free"),
      [],
      None,
    )
  case result {
    Error(w.RouteRefused(reason)) ->
      string.contains(reason, "no proven tier") |> should.be_true
    other ->
      panic as { "expected RouteRefused, got: " <> string.inspect(other) }
  }
}

fn profile_prices() -> List(w.Price) {
  // Independent public-catalog observations, 2026-09-09. The accepted ZDR
  // provider ceiling for DeepSeek Pro is intentionally above this minimum.
  [
    w.Price("inclusionai/ling-3.0-flash-fin:free", 0.0, 0.0),
    w.Price("z-ai/glm-5.3", 0.0000014, 0.0000044),
    w.Price("moonshotai/kimi-k3", 0.000003, 0.000015),
    w.Price("deepseek/deepseek-v4-pro-0813", 0.00000057948, 0.00000173844),
    w.Price("deepseek/deepseek-v4-flash-0731", 0.000000065, 0.00000018),
    w.Price("google/gemma-4-31b-it", 0.00000009, 0.00000034),
  ]
}

pub fn explicit_profiles_preserve_free_default_and_exact_model_names_test() {
  list.length(w.profiles()) |> should.equal(6)
  list.each(w.profiles(), fn(profile) {
    w.profile_from_name(w.profile_name(profile)) |> should.equal(Ok(profile))
    { string.trim(w.profile_label(profile)) != "" } |> should.be_true
  })
  w.profile_from_name("automatic_paid_fallback") |> should.equal(Error(Nil))
  w.profile_model(w.FreeAdvisory)
  |> should.equal("inclusionai/ling-3.0-flash-fin:free")
  w.profile_model(w.CodingGlm) |> should.equal("z-ai/glm-5.3")
  w.profile_model(w.CodingKimi) |> should.equal("moonshotai/kimi-k3")
  w.profile_model(w.CodingDeepSeek)
  |> should.equal("deepseek/deepseek-v4-pro-0813")
  w.profile_model(w.CodingEfficient)
  |> should.equal("deepseek/deepseek-v4-flash-0731")
  w.profile_model(w.DecisionGemma) |> should.equal("google/gemma-4-31b-it")
  w.profile_policy(w.FreeAdvisory)
  |> should.equal(w.Policy(512, 0.02, 30_000, True))
}

pub fn paid_profiles_require_opt_in_and_support_4096_tokens_test() {
  list.each(
    [
      w.CodingGlm,
      w.CodingKimi,
      w.CodingDeepSeek,
      w.CodingEfficient,
      w.DecisionGemma,
    ],
    fn(profile) {
      let model = w.profile_model(profile)
      let request = w.Request(..req(model), max_tokens: 4096)
      w.admit(w.default_policy(), profile_prices(), request)
      |> should.equal(Error(w.FreeOnly(model)))
      let policy = w.profile_policy(profile)
      policy |> should.equal(w.Policy(4096, 0.25, 30_000, False))
      let assert Ok(admitted) = w.admit(policy, profile_prices(), request)
      admitted.model |> should.equal(model)
      admitted.max_tokens |> should.equal(4096)
      admitted.tier |> should.equal(w.Paid)
      { admitted.estimated_usd >. 0.0 && admitted.estimated_usd <. 0.25 }
      |> should.be_true
    },
  )
}

pub fn paid_hard_token_timeout_and_lower_budget_limits_cannot_be_bypassed_test() {
  let model = "moonshotai/kimi-k3"
  let loose = w.Policy(9999, 5.0, 600_000, False)
  w.admit(loose, profile_prices(), w.Request(..req(model), max_tokens: 4097))
  |> should.equal(Error(w.TooManyTokens(4097, 4096)))
  let request = w.Request(..req(model), max_tokens: 4096)
  let assert Ok(admitted) = w.admit(loose, profile_prices(), request)
  admitted.timeout_ms |> should.equal(30_000)
  let tight = w.Policy(4096, 0.01, 30_000, False)
  let assert Error(w.OverBudget(estimated, budget)) =
    w.admit(tight, profile_prices(), request)
  { estimated >. budget } |> should.be_true
  budget |> should.equal(0.01)
}

pub fn deepseek_pro_admits_eligible_zdr_price_but_refuses_above_cap_test() {
  let model = "deepseek/deepseek-v4-pro-0813"
  let policy = w.profile_policy(w.CodingDeepSeek)
  let request = w.Request(..req(model), max_tokens: 4096)
  let eligible = [w.Price(model, 0.00000132, 0.00000396)]
  w.admit(policy, eligible, request) |> should.be_ok
  let hiked = [w.Price(model, 0.00000132, 0.00000397)]
  w.admit(policy, hiked, request)
  |> should.equal(Error(w.PriceAboveCeiling(model, 0.00000132, 0.00000397)))
}

fn number() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

pub fn gemma_provider_price_at_the_authorized_boundary_remains_eligible_test() {
  let decoder =
    decode.subfield(
      ["provider", "max_price", "completion"],
      number(),
      decode.success,
    )
  let assert Ok(cap) =
    json.parse(w.request_json(req(w.profile_model(w.DecisionGemma))), decoder)
  // Provider filters compare prices, not approximate equality. A tiny downward
  // rounding error can exclude the only eligible USD0.34/M endpoint.
  { cap >=. 0.34 } |> should.be_true
  { cap <=. 0.34 } |> should.be_true
}

pub fn request_provider_caps_use_million_token_units_and_zero_request_fees_test() {
  list.each(
    [
      #(w.FreeAdvisory, 0.0, 0.0),
      #(w.CodingGlm, 1.4, 4.4),
      #(w.CodingKimi, 3.0, 15.0),
      #(w.CodingDeepSeek, 1.32, 3.96),
      #(w.CodingEfficient, 0.065, 0.18),
      #(w.DecisionGemma, 0.09, 0.34),
    ],
    fn(entry) {
      let #(profile, prompt_cap, completion_cap) = entry
      let decoder = {
        use zdr <- decode.subfield(["provider", "zdr"], decode.bool)
        use prompt <- decode.subfield(
          ["provider", "max_price", "prompt"],
          number(),
        )
        use completion <- decode.subfield(
          ["provider", "max_price", "completion"],
          number(),
        )
        use request_fee <- decode.subfield(
          ["provider", "max_price", "request"],
          number(),
        )
        decode.success(#(zdr, prompt, completion, request_fee))
      }
      let assert Ok(#(zdr, prompt, completion, request_fee)) =
        json.parse(w.request_json(req(w.profile_model(profile))), decoder)
      zdr |> should.be_true
      { float.absolute_value(prompt -. prompt_cap) <. 0.000000001 }
      |> should.be_true
      { float.absolute_value(completion -. completion_cap) <. 0.000000001 }
      |> should.be_true
      request_fee |> should.equal(0.0)
    },
  )
}

pub fn mandatory_glm_reasoning_is_bounded_without_invalid_disable_flag_test() {
  let body = w.request_json(req(w.profile_model(w.CodingGlm)))
  let decoder = {
    use effort <- decode.subfield(["reasoning", "effort"], decode.string)
    use excluded <- decode.subfield(["reasoning", "exclude"], decode.bool)
    decode.success(#(effort, excluded))
  }
  json.parse(body, decoder) |> should.equal(Ok(#("low", True)))
  json.parse(
    body,
    decode.subfield(["reasoning", "enabled"], decode.bool, decode.success),
  )
  |> should.be_error
}

pub fn optional_reasoning_is_disabled_and_excluded_for_bounded_profiles_test() {
  list.each(
    [
      w.FreeAdvisory, w.CodingKimi, w.CodingDeepSeek, w.CodingEfficient,
      w.DecisionGemma,
    ],
    fn(profile) {
      let decoder = {
        use enabled <- decode.subfield(["reasoning", "enabled"], decode.bool)
        use excluded <- decode.subfield(["reasoning", "exclude"], decode.bool)
        decode.success(#(enabled, excluded))
      }
      json.parse(w.request_json(req(w.profile_model(profile))), decoder)
      |> should.equal(Ok(#(False, True)))
    },
  )
}

pub fn routed_candidates_share_allowlist_and_reject_unknown_or_hiked_prices_test() {
  let tiers =
    w.route_tiers(
      list.append(profile_prices(), [
        w.Price("unknown/model:free", 0.0, 0.0),
        w.Price("google/gemma-4-31b-it:free", 0.000001, 0.0),
        w.Price("openai/gpt-4.1-nano", -1.0, 0.0),
      ]),
    )
  let remotes = list.filter(tiers, fn(t) { t.provider == route.OpenRouter })
  list.length(remotes) |> should.equal(6)
  list.each(profile_prices(), fn(price) {
    let assert Ok(tier) = list.find(remotes, fn(t) { t.model == price.id })
    tier.id |> should.equal("openrouter/" <> price.id)
    tier.price_in |> should.equal(Some(price.prompt))
    tier.price_out |> should.equal(Some(price.completion))
  })
}

fn routing_io(selected_model: String) -> w.Io {
  w.Io(
    credential: fn() { Some("test-credential") },
    fetch_prices: fn(_) {
      let body =
        json.object([
          #(
            "data",
            json.array(list.append(prices(), profile_prices()), fn(price) {
              json.object([
                #("id", json.string(price.id)),
                #(
                  "pricing",
                  json.object([
                    #("prompt", json.float(price.prompt)),
                    #("completion", json.float(price.completion)),
                  ]),
                ),
              ])
            }),
          ),
        ])
        |> json.to_string
      Ok(#(200, body))
    },
    post: fn(_, body, timeout) {
      json.parse(body, decode.field("model", decode.string, decode.success))
      |> should.equal(Ok(selected_model))
      timeout |> should.equal(30_000)
      let reply =
        json.object([
          #("model", json.string(selected_model)),
          #(
            "choices",
            json.array([Nil], fn(_) {
              json.object([
                #("finish_reason", json.string("stop")),
                #(
                  "message",
                  json.object([#("content", json.string("bounded advice"))]),
                ),
              ])
            }),
          ),
          #(
            "usage",
            json.object([
              #("prompt_tokens", json.int(10)),
              #("completion_tokens", json.int(5)),
              #("total_tokens", json.int(15)),
              #(
                "cost",
                json.float(case string.ends_with(selected_model, ":free") {
                  True -> 0.0
                  False -> 0.0001
                }),
              ),
            ]),
          ),
        ])
        |> json.to_string
      Ok(#(200, reply))
    },
    now_ms: fn() { 1000 },
  )
}

pub fn routed_dispatch_posts_selected_model_instead_of_original_request_model_test() {
  let chosen = "inclusionai/ling-3.0-flash-fin:free"
  let posteriors = [
    route.Posterior("openrouter/" <> chosen, route.R3Advisory, 9.0, 1.0, 8),
  ]
  let assert Ok(outcome) =
    w.run_routed(
      w.default_policy(),
      route.default_policy(),
      routing_io(chosen),
      req("google/gemma-4-31b-it:free"),
      posteriors,
      None,
    )
  outcome.admitted.model |> should.equal(chosen)
  outcome.reply.model |> should.equal(chosen)
}

pub fn selected_non_openrouter_tier_never_posts_to_openrouter_test() {
  let io = io_with(Some("k"), fn() { panic as "local selection must not POST" })
  let posteriors = [
    route.Posterior("deterministic", route.R3Advisory, 9.0, 1.0, 8),
  ]
  w.run_routed(
    w.default_policy(),
    route.default_policy(),
    io,
    req("google/gemma-4-31b-it:free"),
    posteriors,
    None,
  )
  |> should.equal(
    Error(w.RouteRefused("selected tier is not OpenRouter: deterministic")),
  )
}

pub fn paid_route_selection_still_requires_worker_paid_opt_in_test() {
  let chosen = "moonshotai/kimi-k3"
  let io =
    w.Io(..routing_io(chosen), post: fn(_, _, _) {
      panic as "free worker policy must not POST selected paid model"
    })
  let route_policy =
    route.Policy(
      ..route.default_policy(),
      paid_enabled: True,
      free_only_remote: False,
    )
  let posteriors = [
    route.Posterior("openrouter/" <> chosen, route.R3Advisory, 9.0, 1.0, 8),
  ]
  // A caller-supplied Budget exercises pure eligibility; it is not a reservation.
  let budget = Some(route.Budget(10.0, 0.0, 1, "test-only"))
  w.run_routed(
    w.default_policy(),
    route_policy,
    io,
    req("google/gemma-4-31b-it:free"),
    posteriors,
    budget,
  )
  |> should.equal(Error(w.FreeOnly(chosen)))
}

pub fn selected_paid_profile_posts_exact_model_under_explicit_policy_test() {
  let chosen = "moonshotai/kimi-k3"
  let route_policy =
    route.Policy(
      ..route.default_policy(),
      paid_enabled: True,
      free_only_remote: False,
    )
  let posteriors = [
    route.Posterior("openrouter/" <> chosen, route.R3Advisory, 9.0, 1.0, 8),
  ]
  let budget = Some(route.Budget(10.0, 0.0, 1, "test-only"))
  let request = w.Request(..req("google/gemma-4-31b-it:free"), max_tokens: 4096)
  let assert Ok(outcome) =
    w.run_routed(
      w.profile_policy(w.CodingKimi),
      route_policy,
      routing_io(chosen),
      request,
      posteriors,
      budget,
    )
  outcome.admitted.model |> should.equal(chosen)
  outcome.admitted.max_tokens |> should.equal(4096)
}

fn paid_receipt_io(
  actual_model: String,
  completion_tokens: Int,
  cost: option.Option(Float),
) -> w.Io {
  let usage = [
    #("prompt_tokens", json.int(10)),
    #("completion_tokens", json.int(completion_tokens)),
    #("total_tokens", json.int(10 + completion_tokens)),
  ]
  let cost_field = case cost {
    Some(value) -> [#("cost", json.float(value))]
    None -> []
  }
  let body =
    json.object([
      #("model", json.string(actual_model)),
      #(
        "choices",
        json.array([Nil], fn(_) {
          json.object([
            #("finish_reason", json.string("stop")),
            #(
              "message",
              json.object([#("content", json.string("bounded advice"))]),
            ),
          ])
        }),
      ),
      #("usage", json.object(list.append(usage, cost_field))),
    ])
    |> json.to_string
  w.Io(..routing_io("moonshotai/kimi-k3"), post: fn(_, _, _) {
    Ok(#(200, body))
  })
}

pub fn paid_completion_requires_actual_reported_cost_not_catalog_estimate_test() {
  let model = "moonshotai/kimi-k3"
  w.run(
    w.profile_policy(w.CodingKimi),
    paid_receipt_io(model, 5, None),
    req(model),
  )
  |> should.equal(
    Error(w.BadResponse("paid completion is missing reported usage cost")),
  )
  let assert Ok(outcome) =
    w.run(
      w.profile_policy(w.CodingKimi),
      paid_receipt_io(model, 5, Some(0.000123)),
      req(model),
    )
  outcome.cost_usd |> should.equal(0.000123)
  outcome.reply.reported_cost_usd |> should.equal(Some(0.000123))
}

pub fn paid_receipt_must_match_admitted_model_and_completion_limit_test() {
  let request = req("moonshotai/kimi-k3")
  w.run(
    w.profile_policy(w.CodingKimi),
    paid_receipt_io("z-ai/glm-5.3", 5, Some(0.0001)),
    request,
  )
  |> should.equal(
    Error(w.BadResponse("paid completion model differs from admitted model")),
  )
  w.run(
    w.profile_policy(w.CodingKimi),
    paid_receipt_io(request.model, request.max_tokens + 1, Some(0.0001)),
    request,
  )
  |> should.equal(
    Error(w.BadResponse("paid completion exceeds admitted max_tokens")),
  )
}

pub fn paid_receipt_cannot_exceed_hard_or_requested_cost_budget_test() {
  let request = req("moonshotai/kimi-k3")
  let loose = w.Policy(9999, 5.0, 600_000, False)
  w.run(loose, paid_receipt_io(request.model, 5, Some(0.251)), request)
  |> should.equal(
    Error(w.BadResponse("paid reported cost exceeds request budget")),
  )
  let tight = w.Policy(4096, 0.01, 30_000, False)
  w.run(tight, paid_receipt_io(request.model, 5, Some(0.011)), request)
  |> should.equal(
    Error(w.BadResponse("paid reported cost exceeds request budget")),
  )
}
