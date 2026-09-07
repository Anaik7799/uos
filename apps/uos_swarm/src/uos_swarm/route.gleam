//// Global intelligence routing: deterministic-first, cheapest-eligible tier across Claude,
//// Codex, Antigravity and OpenRouter, per
//// docs/design/20260907-0925-uos-global-intelligence-routing-design.md and
//// contracts/rules/20260907-0930-intelligence-routing-rule.md.
////
//// route(o) = argmin cost over tiers with P(adequate) >= theta(class), cost <= budget,
//// authorized. Default remote free-only; no automatic paid fallback: a refused free route
//// stays `Refuse`, it is never silently retried on a paid tier. Paid dispatch stays disabled
//// unless a shared atomic aggregate `Budget` (the enforceable upper bound) is supplied and
//// `paid_enabled` is set. Unknown prices and unknown quality are never treated as zero cost or
//// as a pass: a tier with `price_in`/`price_out` of `None` cannot be auto-dispatched, and a
//// tier with no verified trials is "unproven", not adequate. Posteriors are per (tier, class)
//// and are updated only from verified outcomes carrying a non-empty evidence reference.
////
//// Eligibility rules (implemented and tested):
//// (a) authorized: R6 (design authority) only `claude/fable`; R5 (sovereign review) only
////     Codex and Antigravity; R0 (runtime control) only `Deterministic`. Every other class
////     admits any provider, subject to (b)-(d).
//// (b) price known unless the tier is `Deterministic` or an OpenRouter `:free` model (price 0
////     by the live list) — an unknown price makes a metered tier ineligible for automatic
////     dispatch. Codex and Antigravity are unmetered (`metered: False`); they are eligible
////     only for R5, surfaced as "manual" decisions (the tier's own `metered` field says so),
////     and are never auto-dispatched by anything other than R5.
//// (c) adequacy: posterior mean >= theta(class) AND trials >= min_trials, otherwise the tier
////     is "unproven" and not adequate. A `Deterministic` tier is adequate by construction only
////     for R0 (runtime control) and R1 (mechanical verification) — the two classes the design
////     doc lists a deterministic/script route for; every other class, including for a
////     `Deterministic` tier, needs ordinary verified-outcome proof.
//// (d) paid tiers are eligible only if `paid_enabled` AND a `Budget` is given AND
////     `spent + estimate <= cap` (the enforceable upper bound).
//// (e) remote free tiers are preferred over paid ones: since a free tier costs 0.0 and the
////     router always picks the cheapest eligible tier, this holds automatically whenever both
////     are eligible.
////
//// Module note: `default_tiers` mirrors `uos_swarm/openrouter_worker.allowlist()`'s paid
//// model ids as a local constant rather than importing that module, because
//// `openrouter_worker.run_routed` depends on this module for `Policy`/`Budget`/`route` and
//// Gleam forbids import cycles. A drift between the two lists only changes which ids
//// `default_tiers` offers as candidates; it never changes what `openrouter_worker.admit`
//// actually allows to be dispatched (that check is authoritative and unaffected by this one).

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

pub type OperationClass {
  R0Runtime
  R1Verification
  R2Docs
  R3Advisory
  R4Implementation
  R5SovereignReview
  R6DesignAuthority
}

pub type Provider {
  Deterministic
  OpenRouter
  Claude
  Codex
  Antigravity
}

/// `price_in`/`price_out` are USD per token. `None` means the price is UNKNOWN and must never
/// be treated as zero. `metered: False` marks a subscription CLI (Codex, Antigravity) whose
/// cost is tracked as calls/wall time, not USD.
pub type Tier {
  Tier(
    id: String,
    provider: Provider,
    model: String,
    price_in: Option(Float),
    price_out: Option(Float),
    metered: Bool,
    paid: Bool,
  )
}

/// Beta(alpha, beta) posterior of P(adequate) for one (tier, class) pair, updated only from
/// verified outcomes on the board.
pub type Posterior {
  Posterior(
    tier: String,
    class: OperationClass,
    alpha: Float,
    beta: Float,
    trials: Int,
  )
}

/// The shared atomic aggregate budget: `cap_usd` is the enforceable upper bound, `spent_usd`
/// the running total, `epoch` the ledger version this value was read at, `holder` the last
/// writer.
pub type Budget {
  Budget(cap_usd: Float, spent_usd: Float, epoch: Int, holder: String)
}

pub type Decision {
  Route(tier: Tier, estimated_usd: Float, reason: String)
  Refuse(reason: String)
}

pub type Policy {
  Policy(
    theta: fn(OperationClass) -> Float,
    min_trials: Int,
    paid_enabled: Bool,
    free_only_remote: Bool,
  )
}

fn default_theta(class: OperationClass) -> Float {
  case class {
    R0Runtime -> 1.0
    R1Verification -> 0.95
    R2Docs -> 0.9
    R3Advisory -> 0.8
    R4Implementation -> 0.9
    R5SovereignReview -> 0.95
    R6DesignAuthority -> 1.0
  }
}

/// Default policy: free-only remote, paid dispatch disabled, 3 verified trials minimum.
pub fn default_policy() -> Policy {
  Policy(
    theta: default_theta,
    min_trials: 3,
    paid_enabled: False,
    free_only_remote: True,
  )
}

/// Rule (a): the coord-policy authorization gate. `R0` admits only `Deterministic`; `R5`
/// admits only `Codex`/`Antigravity`; `R6` admits only `claude/fable`. Every other class
/// admits any provider (subject to the other eligibility rules).
pub fn authorized(class: OperationClass, tier: Tier) -> Bool {
  case class {
    R0Runtime -> tier.provider == Deterministic
    R5SovereignReview -> tier.provider == Codex || tier.provider == Antigravity
    R6DesignAuthority -> tier.provider == Claude && tier.model == "fable"
    R1Verification | R2Docs | R3Advisory | R4Implementation -> True
  }
}

fn is_free_openrouter(t: Tier) -> Bool {
  case t.provider {
    OpenRouter -> string.ends_with(t.id, ":free")
    _ -> False
  }
}

/// Rule (b), price half: known unless `Deterministic` or an OpenRouter `:free` model.
fn price_known(t: Tier) -> Bool {
  case t.provider {
    Deterministic -> True
    _ ->
      case is_free_openrouter(t) {
        True -> True
        False -> option.is_some(t.price_in) && option.is_some(t.price_out)
      }
  }
}

fn tier_cost(t: Tier, est_in_tokens: Int, est_out_tokens: Int) -> Float {
  case is_free_openrouter(t) {
    True -> 0.0
    False ->
      case t.price_in, t.price_out {
        Some(pin), Some(pout) ->
          int.to_float(est_in_tokens)
          *. pin
          +. int.to_float(est_out_tokens)
          *. pout
        _, _ -> 0.0
      }
  }
}

fn find_posterior(
  tier_id: String,
  class: OperationClass,
  posteriors: List(Posterior),
) -> Result(Posterior, Nil) {
  list.find(posteriors, fn(p) { p.tier == tier_id && p.class == class })
}

fn trials_for(
  t: Tier,
  class: OperationClass,
  posteriors: List(Posterior),
) -> Int {
  case find_posterior(t.id, class, posteriors) {
    Ok(p) -> p.trials
    Error(_) -> 0
  }
}

fn proven(
  policy: Policy,
  class: OperationClass,
  t: Tier,
  posteriors: List(Posterior),
) -> Bool {
  case find_posterior(t.id, class, posteriors) {
    Ok(p) -> {
      let mean = p.alpha /. { p.alpha +. p.beta }
      p.trials >= policy.min_trials && mean >=. policy.theta(class)
    }
    Error(_) -> False
  }
}

/// Rule (c): posterior-proven adequacy. `Deterministic` is adequate by construction only for
/// R0/R1; every other (tier, class) pair needs verified-outcome proof.
fn adequate(
  policy: Policy,
  class: OperationClass,
  t: Tier,
  posteriors: List(Posterior),
) -> Bool {
  case t.provider {
    Deterministic ->
      case class {
        R0Runtime | R1Verification -> True
        _ -> proven(policy, class, t, posteriors)
      }
    _ -> proven(policy, class, t, posteriors)
  }
}

fn paid_allowed(policy: Policy, budget: Option(Budget), cost: Float) -> Bool {
  case policy.paid_enabled, budget {
    True, Some(b) -> b.spent_usd +. cost <=. b.cap_usd
    _, _ -> False
  }
}

fn require(cond: Bool) -> Result(Nil, Nil) {
  case cond {
    True -> Ok(Nil)
    False -> Error(Nil)
  }
}

/// Rule (b), cost half plus (d): the estimated cost of a metered tier, or `Error` when the
/// tier cannot be automatically dispatched (unknown price, unmetered outside R5, paid without
/// an authorized budget).
fn priced_cost(
  policy: Policy,
  class: OperationClass,
  budget: Option(Budget),
  est_in_tokens: Int,
  est_out_tokens: Int,
  t: Tier,
) -> Result(Float, Nil) {
  case t.metered {
    False -> {
      use _ <- result.try(require(class == R5SovereignReview))
      Ok(0.0)
    }
    True -> {
      use _ <- result.try(require(price_known(t)))
      let cost = tier_cost(t, est_in_tokens, est_out_tokens)
      case t.paid {
        True -> {
          use _ <- result.try(require(paid_allowed(policy, budget, cost)))
          Ok(cost)
        }
        False -> Ok(cost)
      }
    }
  }
}

type Candidate {
  Candidate(tier: Tier, cost: Float, trials: Int)
}

fn candidate_for(
  policy: Policy,
  class: OperationClass,
  budget: Option(Budget),
  est_in_tokens: Int,
  est_out_tokens: Int,
  posteriors: List(Posterior),
  t: Tier,
) -> Result(Candidate, Nil) {
  use _ <- result.try(require(authorized(class, t)))
  case t.provider {
    Deterministic ->
      case adequate(policy, class, t, posteriors) {
        True -> Ok(Candidate(t, 0.0, trials_for(t, class, posteriors)))
        False -> Error(Nil)
      }
    _ -> {
      use cost <- result.try(priced_cost(
        policy,
        class,
        budget,
        est_in_tokens,
        est_out_tokens,
        t,
      ))
      use _ <- result.try(require(adequate(policy, class, t, posteriors)))
      Ok(Candidate(t, cost, trials_for(t, class, posteriors)))
    }
  }
}

fn eligible_candidates(
  policy: Policy,
  class: OperationClass,
  tiers: List(Tier),
  posteriors: List(Posterior),
  budget: Option(Budget),
  est_in_tokens: Int,
  est_out_tokens: Int,
) -> List(Candidate) {
  list.filter_map(tiers, fn(t) {
    candidate_for(
      policy,
      class,
      budget,
      est_in_tokens,
      est_out_tokens,
      posteriors,
      t,
    )
  })
}

/// Cheapest first; ties broken by lower `price_out` (unknown treated as 0.0, which only
/// matters among tiers already known-priced or free), then by more verified trials (the
/// tier needing fewer additional trials to stay proven).
fn compare_candidates(a: Candidate, b: Candidate) -> order.Order {
  float.compare(a.cost, b.cost)
  |> order.break_tie(with: float.compare(
    option.unwrap(a.tier.price_out, 0.0),
    option.unwrap(b.tier.price_out, 0.0),
  ))
  |> order.break_tie(with: int.compare(b.trials, a.trials))
}

pub fn class_label(class: OperationClass) -> String {
  case class {
    R0Runtime -> "R0"
    R1Verification -> "R1"
    R2Docs -> "R2"
    R3Advisory -> "R3"
    R4Implementation -> "R4"
    R5SovereignReview -> "R5"
    R6DesignAuthority -> "R6"
  }
}

fn provider_label(p: Provider) -> String {
  case p {
    Deterministic -> "deterministic"
    OpenRouter -> "openrouter"
    Claude -> "claude"
    Codex -> "codex"
    Antigravity -> "antigravity"
  }
}

fn decision_reason(
  class: OperationClass,
  tier: Tier,
  cost: Float,
  alt_ids: List(String),
) -> String {
  let base =
    "cheapest eligible tier for "
    <> class_label(class)
    <> ": "
    <> tier.id
    <> " (est $"
    <> float.to_string(cost)
    <> ")"
  let manual_note = case tier.metered {
    False -> " [manual: unmetered, not auto-dispatched]"
    True -> ""
  }
  let alt_note = case alt_ids {
    [] -> " | alternatives: none"
    _ -> " | alternatives: " <> string.join(alt_ids, ", ")
  }
  base <> manual_note <> alt_note
}

fn priced(class: OperationClass, t: Tier) -> Bool {
  case t.provider {
    Deterministic -> True
    _ ->
      case t.metered {
        False -> class == R5SovereignReview
        True -> price_known(t)
      }
  }
}

fn refusal_reason(
  policy: Policy,
  class: OperationClass,
  tiers: List(Tier),
  posteriors: List(Posterior),
) -> String {
  let authorized_tiers = list.filter(tiers, fn(t) { authorized(class, t) })
  case authorized_tiers {
    [] -> "no authorized tier for " <> class_label(class)
    _ -> {
      let priced_tiers =
        list.filter(authorized_tiers, fn(t) { priced(class, t) })
      case priced_tiers {
        [] -> "no price-known authorized tier for " <> class_label(class)
        _ -> {
          let sorted =
            list.sort(priced_tiers, fn(a, b) {
              int.compare(
                trials_for(b, class, posteriors),
                trials_for(a, class, posteriors),
              )
            })
          case sorted {
            [t, ..] -> {
              let trials = trials_for(t, class, posteriors)
              "no proven tier for "
              <> class_label(class)
              <> ": "
              <> t.id
              <> " has "
              <> int.to_string(trials)
              <> " of "
              <> int.to_string(policy.min_trials)
              <> " verified trials"
            }
            [] -> "no eligible tier for " <> class_label(class)
          }
        }
      }
    }
  }
}

/// `route(o) = argmin cost over T(o)` subject to `P(adequate) >= theta(class)`,
/// `cost <= budget`, `authorized`. Deterministic tiers cost 0.0 and always win when eligible.
/// A refused free route is never silently retried on a paid tier: this always returns
/// `Refuse` unless a paid tier is itself eligible under rule (d).
pub fn route(
  policy: Policy,
  class: OperationClass,
  tiers: List(Tier),
  posteriors: List(Posterior),
  budget: Option(Budget),
  est_in_tokens: Int,
  est_out_tokens: Int,
) -> Decision {
  let candidates =
    eligible_candidates(
      policy,
      class,
      tiers,
      posteriors,
      budget,
      est_in_tokens,
      est_out_tokens,
    )
    |> list.sort(compare_candidates)
  case candidates {
    [] -> Refuse(refusal_reason(policy, class, tiers, posteriors))
    [best, ..rest] -> {
      let alt_ids = list.map(rest, fn(c) { c.tier.id })
      Route(
        best.tier,
        best.cost,
        decision_reason(class, best.tier, best.cost, alt_ids),
      )
    }
  }
}

const escalation_default_tokens = 200

/// Escalate once to the next-cheapest eligible tier in `tiers`, excluding `failed_tier`. The
/// caller is responsible for narrowing `tiers` further on a second call (removing every tier
/// already tried) so that a second failure yields no eligible candidate and this returns
/// `Refuse("jidoka: ...")` — the andon stop for the L0 authority. Posterior updates from the
/// verified outcome belong to `update`, not to this function.
pub fn escalate(
  policy: Policy,
  class: OperationClass,
  tiers: List(Tier),
  posteriors: List(Posterior),
  budget: Option(Budget),
  failed_tier: String,
) -> Decision {
  let remaining = list.filter(tiers, fn(t) { t.id != failed_tier })
  case
    route(
      policy,
      class,
      remaining,
      posteriors,
      budget,
      escalation_default_tokens,
      escalation_default_tokens,
    )
  {
    Route(t, e, r) ->
      Route(t, e, "escalated after " <> failed_tier <> " failed: " <> r)
    Refuse(reason) ->
      Refuse(
        "jidoka: escalation from "
        <> failed_tier
        <> " exhausted eligible tiers for "
        <> class_label(class)
        <> ": "
        <> reason,
      )
  }
}

/// Update the (tier, class) posterior from a verified outcome only. A `record` without an
/// evidence reference is not representable in this API: an empty `evidence_ref` is ignored and
/// the posteriors list is returned unchanged, never from self-report.
pub fn update(
  posteriors: List(Posterior),
  tier: String,
  class: OperationClass,
  verified_pass: Bool,
  evidence_ref: String,
) -> List(Posterior) {
  case string.trim(evidence_ref) {
    "" -> posteriors
    _ ->
      case list.any(posteriors, fn(p) { p.tier == tier && p.class == class }) {
        True ->
          list.map(posteriors, fn(p) {
            case p.tier == tier && p.class == class {
              True ->
                case verified_pass {
                  True ->
                    Posterior(..p, alpha: p.alpha +. 1.0, trials: p.trials + 1)
                  False ->
                    Posterior(..p, beta: p.beta +. 1.0, trials: p.trials + 1)
                }
              False -> p
            }
          })
        False -> {
          let seeded = case verified_pass {
            True -> Posterior(tier, class, 2.0, 1.0, 1)
            False -> Posterior(tier, class, 1.0, 2.0, 1)
          }
          [seeded, ..posteriors]
        }
      }
  }
}

fn split_alternatives(reason: String) -> #(String, String) {
  case string.split_once(reason, " | alternatives: ") {
    Ok(#(summary, alts)) -> #(summary, alts)
    Error(_) -> #(reason, "none")
  }
}

fn bool_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

/// Board payload for a `Dispatch` recording this routing decision: class, tier, estimated
/// cost, reason and alternatives.
pub fn decision_payload(
  d: Decision,
  class: OperationClass,
) -> List(#(String, String)) {
  case d {
    Route(tier, est, reason) -> {
      let #(summary, alts) = split_alternatives(reason)
      [
        #("class", class_label(class)),
        #("tier", tier.id),
        #("provider", provider_label(tier.provider)),
        #("estimated_usd", float.to_string(est)),
        #("reason", summary),
        #("alternatives", alts),
        #("metered", bool_string(tier.metered)),
      ]
    }
    Refuse(reason) -> [
      #("class", class_label(class)),
      #("tier", "none"),
      #("estimated_usd", "0.0"),
      #("reason", reason),
      #("alternatives", "none"),
    ]
  }
}

/// Mirrors `uos_swarm/openrouter_worker.allowlist()`'s paid model ids (see the module note
/// above for why this is a local copy rather than an import).
const openrouter_paid_ids = [
  "google/gemini-2.5-flash-lite", "openai/gpt-4.1-nano",
  "mistralai/mistral-small-3.2-24b-instruct", "anthropic/claude-haiku-4.5",
]

/// The default tier universe: deterministic (0/0); every OpenRouter `:free` id in
/// `live_prices`; the OpenRouter paid allowlist priced from `live_prices` when known (else
/// `None`); Claude haiku/sonnet/opus/fable with `None` prices (relative weights, not USD
/// prices); Codex `gpt-6-astra` and Antigravity `gemini-3.8-flash`, unmetered.
pub fn default_tiers(live_prices: List(#(String, Float, Float))) -> List(Tier) {
  let deterministic =
    Tier(
      "deterministic",
      Deterministic,
      "deterministic",
      Some(0.0),
      Some(0.0),
      True,
      False,
    )
  let free_tiers =
    live_prices
    |> list.filter(fn(p) { string.ends_with(p.0, ":free") })
    |> list.map(fn(p) {
      Tier(
        "openrouter/" <> p.0,
        OpenRouter,
        p.0,
        Some(0.0),
        Some(0.0),
        True,
        False,
      )
    })
  let paid_tiers =
    openrouter_paid_ids
    |> list.map(fn(id) {
      let #(pin, pout) = case list.find(live_prices, fn(p) { p.0 == id }) {
        Ok(#(_, pin, pout)) -> #(Some(pin), Some(pout))
        Error(_) -> #(None, None)
      }
      Tier("openrouter/" <> id, OpenRouter, id, pin, pout, True, True)
    })
  let claude_tiers = [
    Tier("claude/haiku", Claude, "haiku", None, None, True, True),
    Tier("claude/sonnet", Claude, "sonnet", None, None, True, True),
    Tier("claude/opus", Claude, "opus", None, None, True, True),
    Tier("claude/fable", Claude, "fable", None, None, True, True),
  ]
  let codex_tier =
    Tier("codex/gpt-6-astra", Codex, "gpt-6-astra", None, None, False, False)
  let agy_tier =
    Tier(
      "antigravity/gemini-3.8-flash",
      Antigravity,
      "gemini-3.8-flash",
      None,
      None,
      False,
      False,
    )
  [deterministic]
  |> list.append(free_tiers)
  |> list.append(paid_tiers)
  |> list.append(claude_tiers)
  |> list.append([codex_tier, agy_tier])
}

// ---- shared atomic aggregate budget: append-only JSONL ledger ----
// The current state is always the LAST line. `charge` re-reads the file immediately before
// appending and refuses when the epoch it now sees differs from the epoch the caller holds
// (a concurrent writer already advanced it) or when the charge would exceed the cap. This is
// the cooperative atomicity available without a NIF: it detects a lost update after the fact,
// it does not lock the file.

@external(erlang, "uos_swarm_ffi", "file_read")
fn file_read(path: String) -> Result(String, String)

@external(erlang, "uos_swarm_ffi", "file_append")
fn file_append(path: String, line: String) -> Result(Nil, String)

@external(erlang, "uos_swarm_ffi", "file_write")
fn file_write(path: String, content: String) -> Result(Nil, String)

@external(erlang, "uos_swarm_ffi", "system_time_us")
fn system_time_us() -> Int

fn lenient_float() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

fn budget_decoder() -> decode.Decoder(Budget) {
  use cap <- decode.field("cap_usd", lenient_float())
  use spent <- decode.field("spent_usd", lenient_float())
  use epoch <- decode.field("epoch", decode.int)
  use holder <- decode.field("holder", decode.string)
  decode.success(Budget(cap, spent, epoch, holder))
}

fn decode_budget_line(line: String) -> Result(Budget, String) {
  json.parse(line, budget_decoder())
  |> result.map_error(fn(e) { "bad budget ledger line: " <> string.inspect(e) })
}

fn last_budget_line(content: String) -> Result(Budget, String) {
  let lines =
    content
    |> string.split("\n")
    |> list.filter(fn(l) { string.trim(l) != "" })
  case list.last(lines) {
    Ok(line) -> decode_budget_line(line)
    Error(_) -> Error("budget ledger is empty")
  }
}

/// Read the shared budget: the last line of the append-only JSONL ledger at `path`.
pub fn read_budget(path: String) -> Result(Budget, String) {
  use content <- result.try(file_read(path))
  last_budget_line(content)
}

fn ledger_line(
  epoch: Int,
  cap_usd: Float,
  spent_usd: Float,
  holder: String,
  amount: Float,
  evidence_ref: String,
) -> String {
  json.object([
    #("epoch", json.int(epoch)),
    #("cap_usd", json.float(cap_usd)),
    #("spent_usd", json.float(spent_usd)),
    #("holder", json.string(holder)),
    #("amount", json.float(amount)),
    #("evidence_ref", json.string(evidence_ref)),
    #("ts_us", json.int(system_time_us())),
  ])
  |> json.to_string
}

/// Create (or overwrite) a budget ledger at `path` at epoch 0 with `spent_usd = 0.0`.
pub fn init_budget(
  path: String,
  cap_usd: Float,
  holder: String,
) -> Result(Budget, String) {
  let line = ledger_line(0, cap_usd, 0.0, holder, 0.0, "init")
  use _ <- result.try(file_write(path, line <> "\n"))
  Ok(Budget(cap_usd, 0.0, 0, holder))
}

/// Charge `amount` against the shared budget at `path`. Refuses when `spent + amount > cap`
/// (checked against the freshly re-read ledger, not the caller's possibly-stale `budget`) or
/// when the ledger's current epoch no longer matches the epoch `budget` was read at (a
/// concurrent writer already appended).
pub fn charge(
  path: String,
  budget: Budget,
  amount: Float,
  holder: String,
  evidence_ref: String,
) -> Result(Budget, String) {
  use current <- result.try(read_budget(path))
  case current.epoch != budget.epoch {
    True ->
      Error(
        "charge refused: epoch conflict, ledger is at epoch "
        <> int.to_string(current.epoch)
        <> " but caller holds epoch "
        <> int.to_string(budget.epoch),
      )
    False ->
      case current.spent_usd +. amount >. current.cap_usd {
        True ->
          Error(
            "charge refused: spent "
            <> float.to_string(current.spent_usd)
            <> " + amount "
            <> float.to_string(amount)
            <> " exceeds cap "
            <> float.to_string(current.cap_usd),
          )
        False -> {
          let next_epoch = current.epoch + 1
          let new_spent = current.spent_usd +. amount
          let line =
            ledger_line(
              next_epoch,
              current.cap_usd,
              new_spent,
              holder,
              amount,
              evidence_ref,
            )
          use _ <- result.try(file_append(path, line <> "\n"))
          Ok(Budget(current.cap_usd, new_spent, next_epoch, holder))
        }
      }
  }
}
