import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import uos_swarm/route

fn always(v: Float) -> fn(route.OperationClass) -> Float {
  fn(_) { v }
}

fn loose_policy() -> route.Policy {
  route.Policy(
    theta: always(0.8),
    min_trials: 1,
    paid_enabled: False,
    free_only_remote: True,
  )
}

fn proven(tier: String, class: route.OperationClass) -> route.Posterior {
  route.Posterior(tier, class, 9.0, 1.0, 3)
}

pub fn deterministic_always_wins_r0_test() {
  let tiers = route.default_tiers([])
  let d =
    route.route(
      route.default_policy(),
      route.R0Runtime,
      tiers,
      [],
      None,
      100,
      100,
    )
  case d {
    route.Route(tier, cost, _) -> {
      tier.provider |> should.equal(route.Deterministic)
      cost |> should.equal(0.0)
    }
    route.Refuse(reason) ->
      panic as { "expected deterministic route, got refuse: " <> reason }
  }
}

pub fn unknown_price_is_ineligible_test() {
  let tier =
    route.Tier("claude/sonnet", route.Claude, "sonnet", None, None, True, True)
  let d =
    route.route(
      loose_policy(),
      route.R4Implementation,
      [tier],
      [],
      None,
      100,
      100,
    )
  case d {
    route.Refuse(_) -> Nil
    route.Route(_, _, _) ->
      panic as "an unknown-price tier must never be auto-dispatched"
  }
}

pub fn unproven_tier_is_not_adequate_test() {
  let tier =
    route.Tier(
      "openrouter/mystery",
      route.OpenRouter,
      "mystery",
      Some(0.0),
      Some(0.0),
      True,
      False,
    )
  // known price, zero cost, but no posterior at all: unknown quality is not a pass.
  let d =
    route.route(loose_policy(), route.R3Advisory, [tier], [], None, 100, 100)
  case d {
    route.Refuse(reason) ->
      string.contains(reason, "no proven tier") |> should.be_true
    route.Route(_, _, _) -> panic as "an unproven tier must never be adequate"
  }
}

pub fn free_remote_chosen_before_paid_test() {
  let free =
    route.Tier(
      "openrouter/free/x",
      route.OpenRouter,
      "free/x",
      Some(0.0),
      Some(0.0),
      True,
      False,
    )
  let paid =
    route.Tier(
      "openrouter/paid/x",
      route.OpenRouter,
      "paid/x",
      Some(0.000001),
      Some(0.000005),
      True,
      True,
    )
  let posteriors = [
    proven("openrouter/free/x", route.R3Advisory),
    proven("openrouter/paid/x", route.R3Advisory),
  ]
  let policy =
    route.Policy(..loose_policy(), paid_enabled: True, free_only_remote: False)
  let budget = Some(route.Budget(10.0, 0.0, 0, "test"))
  let d =
    route.route(
      policy,
      route.R3Advisory,
      [paid, free],
      posteriors,
      budget,
      100,
      100,
    )
  case d {
    route.Route(tier, cost, _) -> {
      tier.id |> should.equal("openrouter/free/x")
      cost |> should.equal(0.0)
    }
    route.Refuse(reason) -> panic as { "expected free tier to win: " <> reason }
  }
}

pub fn paid_refused_when_paid_enabled_false_test() {
  let paid =
    route.Tier(
      "openrouter/paid/x",
      route.OpenRouter,
      "paid/x",
      Some(0.000001),
      Some(0.000005),
      True,
      True,
    )
  let posteriors = [proven("openrouter/paid/x", route.R3Advisory)]
  let policy =
    route.Policy(..loose_policy(), paid_enabled: False, free_only_remote: False)
  let budget = Some(route.Budget(10.0, 0.0, 0, "test"))
  case
    route.route(policy, route.R3Advisory, [paid], posteriors, budget, 100, 100)
  {
    route.Refuse(_) -> Nil
    route.Route(_, _, _) ->
      panic as "paid must never dispatch when paid_enabled is False"
  }
}

pub fn paid_refused_without_budget_even_when_enabled_test() {
  let paid =
    route.Tier(
      "openrouter/paid/x",
      route.OpenRouter,
      "paid/x",
      Some(0.000001),
      Some(0.000005),
      True,
      True,
    )
  let posteriors = [proven("openrouter/paid/x", route.R3Advisory)]
  let policy =
    route.Policy(..loose_policy(), paid_enabled: True, free_only_remote: False)
  let d =
    route.route(policy, route.R3Advisory, [paid], posteriors, None, 100, 100)
  case d {
    route.Refuse(_) -> Nil
    route.Route(_, _, _) -> panic as "paid must never dispatch without a Budget"
  }
}

pub fn paid_allowed_within_cap_and_refused_over_cap_test() {
  let paid =
    route.Tier(
      "openrouter/paid/x",
      route.OpenRouter,
      "paid/x",
      Some(0.001),
      Some(0.001),
      True,
      True,
    )
  let posteriors = [proven("openrouter/paid/x", route.R3Advisory)]
  let policy =
    route.Policy(..loose_policy(), paid_enabled: True, free_only_remote: False)
  // est cost ~= 100*0.001 + 100*0.001 = 0.2
  let within_cap = Some(route.Budget(1.0, 0.0, 0, "test"))
  case
    route.route(
      policy,
      route.R3Advisory,
      [paid],
      posteriors,
      within_cap,
      100,
      100,
    )
  {
    route.Route(tier, cost, _) -> {
      tier.id |> should.equal("openrouter/paid/x")
      { cost >. 0.19 && cost <. 0.21 } |> should.be_true
    }
    route.Refuse(reason) ->
      panic as { "expected paid route within cap: " <> reason }
  }
  let over_cap = Some(route.Budget(0.1, 0.0, 0, "test"))
  case
    route.route(
      policy,
      route.R3Advisory,
      [paid],
      posteriors,
      over_cap,
      100,
      100,
    )
  {
    route.Refuse(_) -> Nil
    route.Route(_, _, _) -> panic as "paid must be refused over the cap"
  }
}

pub fn free_only_remote_refuses_paid_even_with_enabled_flag_and_budget_test() {
  let paid =
    route.Tier(
      "openrouter/paid/x",
      route.OpenRouter,
      "paid/x",
      Some(0.000001),
      Some(0.000005),
      True,
      True,
    )
  let contradictory =
    route.Policy(..loose_policy(), paid_enabled: True, free_only_remote: True)
  let posteriors = [proven(paid.id, route.R3Advisory)]
  let budget = Some(route.Budget(10.0, 0.0, 1, "test"))
  case
    route.route(
      contradictory,
      route.R3Advisory,
      [paid],
      posteriors,
      budget,
      100,
      100,
    )
  {
    route.Refuse(_) -> Nil
    route.Route(_, _, _) ->
      panic as "explicit free-only remote policy must veto paid OpenRouter"
  }
}

pub fn escalation_once_then_jidoka_test() {
  let a =
    route.Tier("a", route.OpenRouter, "a", Some(0.0), Some(0.0), True, False)
  let b =
    route.Tier("b", route.OpenRouter, "b", Some(0.0), Some(0.0), True, False)
  let posteriors = [
    proven("a", route.R3Advisory),
    proven("b", route.R3Advisory),
  ]
  let policy = loose_policy()
  case route.escalate(policy, route.R3Advisory, [a, b], posteriors, None, "a") {
    route.Route(tier, _, _) -> tier.id |> should.equal("b")
    route.Refuse(reason) -> panic as { "expected escalation to b: " <> reason }
  }
  // second failure: the caller narrows `tiers` to what is left before escalating again.
  case route.escalate(policy, route.R3Advisory, [b], posteriors, None, "b") {
    route.Refuse(reason) -> string.contains(reason, "jidoka") |> should.be_true
    route.Route(_, _, _) ->
      panic as "a second escalation failure must be a jidoka stop"
  }
}

pub fn update_ignores_empty_evidence_test() {
  let posteriors = [route.Posterior("a", route.R3Advisory, 1.0, 1.0, 0)]
  route.update(posteriors, "a", route.R3Advisory, True, "")
  |> should.equal(posteriors)
  route.update(posteriors, "a", route.R3Advisory, True, "   ")
  |> should.equal(posteriors)
}

pub fn update_records_verified_pass_and_fail_test() {
  let posteriors = [route.Posterior("a", route.R3Advisory, 1.0, 1.0, 0)]
  let assert Ok(after_pass) =
    route.update(posteriors, "a", route.R3Advisory, True, "ev-pass")
    |> list.find(fn(p) { p.tier == "a" })
  after_pass.alpha |> should.equal(2.0)
  after_pass.beta |> should.equal(1.0)
  after_pass.trials |> should.equal(1)
  let assert Ok(after_fail) =
    route.update(posteriors, "a", route.R3Advisory, False, "ev-fail")
    |> list.find(fn(p) { p.tier == "a" })
  after_fail.alpha |> should.equal(1.0)
  after_fail.beta |> should.equal(2.0)
  after_fail.trials |> should.equal(1)
}

pub fn update_creates_new_posterior_when_absent_test() {
  let assert Ok(p) =
    route.update([], "b", route.R4Implementation, True, "ev-new")
    |> list.find(fn(p) { p.tier == "b" })
  p.class |> should.equal(route.R4Implementation)
  p.trials |> should.equal(1)
  p.alpha |> should.equal(2.0)
  p.beta |> should.equal(1.0)
}

pub fn r6_only_fable_test() {
  let fable =
    route.Tier("claude/fable", route.Claude, "fable", None, None, True, True)
  let sonnet =
    route.Tier("claude/sonnet", route.Claude, "sonnet", None, None, True, True)
  let deterministic =
    route.Tier(
      "deterministic",
      route.Deterministic,
      "deterministic",
      Some(0.0),
      Some(0.0),
      True,
      False,
    )
  let codex =
    route.Tier(
      "codex/gpt-6-astra",
      route.Codex,
      "gpt-6-astra",
      None,
      None,
      False,
      False,
    )
  route.authorized(route.R6DesignAuthority, fable) |> should.be_true
  route.authorized(route.R6DesignAuthority, sonnet) |> should.be_false
  route.authorized(route.R6DesignAuthority, deterministic) |> should.be_false
  route.authorized(route.R6DesignAuthority, codex) |> should.be_false
}

pub fn r5_only_codex_and_antigravity_flagged_unmetered_test() {
  let tiers = route.default_tiers([])
  // theta(R5) is 0.95 under the default policy: mean 19/20 = 0.95 clears it exactly.
  let posteriors = [
    route.Posterior("codex/gpt-6-astra", route.R5SovereignReview, 19.0, 1.0, 3),
    route.Posterior(
      "antigravity/gemini-3.8-flash",
      route.R5SovereignReview,
      19.0,
      1.0,
      3,
    ),
  ]
  let policy = route.default_policy()
  case
    route.route(
      policy,
      route.R5SovereignReview,
      tiers,
      posteriors,
      None,
      100,
      100,
    )
  {
    route.Route(tier, cost, reason) -> {
      let is_codex_or_agy =
        tier.provider == route.Codex || tier.provider == route.Antigravity
      is_codex_or_agy |> should.be_true
      tier.metered |> should.be_false
      cost |> should.equal(0.0)
      string.contains(reason, "manual") |> should.be_true
    }
    route.Refuse(reason) ->
      panic as { "expected a manual R5 route: " <> reason }
  }
  // no other provider is ever authorized for R5.
  list.each(tiers, fn(t) {
    case t.provider {
      route.Codex | route.Antigravity -> Nil
      _ -> route.authorized(route.R5SovereignReview, t) |> should.be_false
    }
  })
}

pub fn decision_payload_route_fields_test() {
  let tier =
    route.Tier(
      "deterministic",
      route.Deterministic,
      "deterministic",
      Some(0.0),
      Some(0.0),
      True,
      False,
    )
  let d =
    route.route(
      route.default_policy(),
      route.R0Runtime,
      [tier],
      [],
      None,
      10,
      10,
    )
  let payload = route.decision_payload(d, route.R0Runtime)
  list.key_find(payload, "class") |> should.equal(Ok("R0"))
  list.key_find(payload, "tier") |> should.equal(Ok("deterministic"))
  list.key_find(payload, "provider") |> should.equal(Ok("deterministic"))
  list.key_find(payload, "estimated_usd") |> should.equal(Ok("0.0"))
  list.key_find(payload, "metered") |> should.equal(Ok("true"))
  case list.key_find(payload, "alternatives") {
    Ok(_) -> Nil
    Error(_) -> panic as "alternatives key must be present"
  }
}

pub fn decision_payload_refuse_fields_test() {
  let d = route.Refuse("no proven tier for R3: x has 0 of 3 verified trials")
  let payload = route.decision_payload(d, route.R3Advisory)
  list.key_find(payload, "class") |> should.equal(Ok("R3"))
  list.key_find(payload, "tier") |> should.equal(Ok("none"))
  list.key_find(payload, "reason")
  |> should.equal(Ok("no proven tier for R3: x has 0 of 3 verified trials"))
}

pub fn default_tiers_shape_test() {
  let tiers =
    route.default_tiers([
      #("vendor/free-model:free", 0.0, 0.0),
      #("openai/gpt-4.1-nano", 0.0000001, 0.0000004),
    ])
  let assert Ok(det) = list.find(tiers, fn(t) { t.id == "deterministic" })
  det.price_in |> should.equal(Some(0.0))
  det.metered |> should.be_true
  let assert Ok(free) =
    list.find(tiers, fn(t) { t.id == "openrouter/vendor/free-model:free" })
  free.paid |> should.be_false
  let assert Ok(nano) =
    list.find(tiers, fn(t) { t.id == "openrouter/openai/gpt-4.1-nano" })
  nano.price_in |> should.equal(Some(0.0000001))
  nano.paid |> should.be_true
  let assert Ok(mistral) =
    list.find(tiers, fn(t) {
      t.id == "openrouter/mistralai/mistral-small-3.2-24b-instruct"
    })
  mistral.price_in |> should.equal(None)
  let assert Ok(fable) = list.find(tiers, fn(t) { t.id == "claude/fable" })
  fable.price_in |> should.equal(None)
  let assert Ok(codex) = list.find(tiers, fn(t) { t.id == "codex/gpt-6-astra" })
  codex.metered |> should.be_false
  let assert Ok(agy) =
    list.find(tiers, fn(t) { t.id == "antigravity/gemini-3.8-flash" })
  agy.metered |> should.be_false
}

fn budget_scratch_path(suffix: String) -> String {
  "/tmp/claude-1000/-home-an-NAS-setup/656f0d2c-6019-4d9e-b0ce-b9e39b240047/scratchpad/route_budget_"
  <> suffix
  <> ".jsonl"
}

pub fn budget_ledger_append_read_round_trip_test() {
  let path = budget_scratch_path("roundtrip")
  let assert Ok(b0) = route.init_budget(path, 10.0, "opA")
  b0.epoch |> should.equal(0)
  b0.spent_usd |> should.equal(0.0)
  let assert Ok(b1) = route.charge(path, b0, 2.5, "opB", "ev-1")
  b1.epoch |> should.equal(1)
  b1.spent_usd |> should.equal(2.5)
  b1.cap_usd |> should.equal(10.0)
  let assert Ok(read_back) = route.read_budget(path)
  read_back |> should.equal(b1)
}

pub fn budget_ledger_epoch_conflict_refusal_test() {
  let path = budget_scratch_path("epoch-conflict")
  let assert Ok(b0) = route.init_budget(path, 10.0, "opA")
  let assert Ok(_b1) = route.charge(path, b0, 1.0, "opB", "ev-2")
  // b0 is now stale: the ledger has moved on to epoch 1.
  case route.charge(path, b0, 1.0, "opC", "ev-3") {
    Error(reason) -> string.contains(reason, "epoch conflict") |> should.be_true
    Ok(_) -> panic as "a stale epoch must be refused"
  }
}

pub fn budget_ledger_over_cap_refusal_test() {
  let path = budget_scratch_path("over-cap")
  let assert Ok(b0) = route.init_budget(path, 1.0, "opA")
  case route.charge(path, b0, 5.0, "opB", "ev-4") {
    Error(reason) -> string.contains(reason, "exceeds cap") |> should.be_true
    Ok(_) -> panic as "an over-cap charge must be refused"
  }
}
