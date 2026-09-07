//// Bounded evolution of the hive from verified outcomes. A dream's hypotheses
//// (`dream.Hypothesis`) become `Proposal`s here; each carries a Beta-Binomial
//// posterior over its own fitness (`alpha`/`beta`, prior 1.0/1.0 — the same
//// uniform prior `agent_runtime.prior` uses for model beliefs).
////
//// Rule (enforced by `record`, not merely declared): a proposal never becomes
//// Adopted without verified evidence. `record` takes an `evidence_ref` and
//// updates `alpha`/`beta` ONLY when that reference is non-empty; a call with
//// an empty (or all-whitespace) `evidence_ref` — a bare self-report of success
//// with nothing backing it — is a no-op: the proposal, its posterior, its
//// evidence list and its status are all returned unchanged. There is no path
//// from `Proposed`/`Trialled` to `Adopted` that does not pass through at
//// least three such recorded, evidenced outcomes.
////
//// Selection (`select`) reuses `agent_runtime`'s public Marsaglia-Tsang gamma
//// sampler (`agent_runtime.sample`, over a throwaway `agent_runtime.Belief`)
//// for genuine Beta-posterior Thompson sampling, rather than re-implementing
//// it here.
//// Sanskrit mirror: vikalpa (विकल्प, hypothesis) -> prayoga (प्रयोग,
//// trial/application) -> siddhi (सिद्धि, accomplishment) or bādha (बाध,
//// refutation) — the Nyāya arc a `Proposal` walks from `Proposed` to
//// `Adopted`/`Rejected`.
//// STAMP: SC-TUI-EVOLVE-001.

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import uos_swarm/agent_runtime
import uos_swarm/dream

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub type Status {
  Proposed
  Trialled
  Adopted
  Rejected
}

pub fn status_label(s: Status) -> String {
  case s {
    Proposed -> "Proposed"
    Trialled -> "Trialled"
    Adopted -> "Adopted"
    Rejected -> "Rejected"
  }
}

fn status_from_label(s: String) -> Status {
  case s {
    "Trialled" -> Trialled
    "Adopted" -> Adopted
    "Rejected" -> Rejected
    _ -> Proposed
  }
}

pub type Proposal {
  Proposal(
    id: String,
    hypothesis: String,
    action: String,
    alpha: Float,
    beta: Float,
    status: Status,
    tier: String,
    cost_usd: Float,
    evidence: List(String),
  )
}

/// A trial is adopted at mean >= 0.8, rejected at mean <= 0.2, and only once
/// at least this many verified outcomes have been recorded.
const min_trials = 3

const adopt_at = 0.8

const reject_at = 0.2

/// Illustrative default per-tier relative cost, mirroring
/// `agent_runtime.default_tiers`; used only when `from_dream` is given a
/// tier name outside that table (falls back to sonnet's relative cost 1.0).
fn default_tier_cost(tier: String) -> Float {
  case tier {
    "haiku" -> 0.27
    "sonnet" -> 1.0
    "opus" -> 5.0
    "fable" -> 5.0
    _ -> 1.0
  }
}

/// The mean of the Beta(alpha, beta) posterior — the proposal's current
/// estimated fitness.
pub fn posterior_mean(p: Proposal) -> Float {
  p.alpha /. { p.alpha +. p.beta }
}

/// Verified outcomes recorded so far (alpha + beta both start at 1.0, so
/// each recorded outcome adds exactly 1.0 to their sum).
pub fn trials(p: Proposal) -> Int {
  float.round(p.alpha +. p.beta -. 2.0)
}

/// One `Proposed` proposal per hypothesis in a dream, each starting from the
/// uniform Beta(1, 1) prior and the given `tier`. Never itself evidence of
/// anything: nothing here is Trialled, let alone Adopted.
pub fn from_dream(d: dream.Dream, tier: String) -> List(Proposal) {
  list.map(d.hypotheses, fn(h) {
    Proposal(
      id: "prop-" <> h.id,
      hypothesis: h.text,
      action: h.proposed_action,
      alpha: 1.0,
      beta: 1.0,
      status: Proposed,
      tier: tier,
      cost_usd: default_tier_cost(tier),
      evidence: [],
    )
  })
}

/// Record one verified outcome. A bare self-report — `evidence_ref` empty or
/// all-whitespace — is ignored outright: the proposal comes back byte-for-byte
/// unchanged (posterior, evidence list and status all untouched), so no
/// proposal can ever be talked into Adopted without a real evidence
/// reference. Otherwise: pass -> alpha += 1, fail -> beta += 1, the reference
/// is appended to `evidence`, and status is recomputed from the new
/// posterior — Proposed/Trialled -> Trialled on the first evidenced record,
/// -> Adopted once the mean is >= 0.8 with >= `min_trials` recorded outcomes,
/// -> Rejected once the mean is <= 0.2 with >= `min_trials` recorded
/// outcomes, otherwise it stays Trialled.
pub fn record(
  p: Proposal,
  verified_pass: Bool,
  evidence_ref: String,
) -> Proposal {
  case string.trim(evidence_ref) {
    "" -> p
    ref -> {
      let alpha = case verified_pass {
        True -> p.alpha +. 1.0
        False -> p.alpha
      }
      let beta = case verified_pass {
        True -> p.beta
        False -> p.beta +. 1.0
      }
      let mean = alpha /. { alpha +. beta }
      let t = float.round(alpha +. beta -. 2.0)
      let status = case mean >=. adopt_at && t >= min_trials {
        True -> Adopted
        False ->
          case mean <=. reject_at && t >= min_trials {
            True -> Rejected
            False -> Trialled
          }
      }
      Proposal(
        ..p,
        alpha: alpha,
        beta: beta,
        status: status,
        evidence: list.append(p.evidence, [ref]),
      )
    }
  }
}

/// Thompson sampling: draw one Beta(alpha, beta) sample per proposal (via
/// `agent_runtime.sample` over a throwaway `Belief` carrying this proposal's
/// own posterior), rank descending, and return up to `k` distinct proposals
/// (deterministic for a given `seed`, never sampling the same proposal
/// twice).
pub fn select(ps: List(Proposal), seed: Int, k: Int) -> List(Proposal) {
  let bound = int.max(k, 0)
  ps
  |> list.index_map(fn(p, i) {
    let belief = agent_runtime.Belief("evolve", p.id, p.alpha, p.beta)
    let s = agent_runtime.sample(belief, seed + i * 97 + string.length(p.id))
    #(p, s)
  })
  |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
  |> list.map(fn(pair) { pair.0 })
  |> unique_by_id
  |> list.take(bound)
}

fn unique_by_id(ps: List(Proposal)) -> List(Proposal) {
  ps
  |> list.fold(#([], []), fn(acc, p) {
    let #(seen, out) = acc
    case list.contains(seen, p.id) {
      True -> acc
      False -> #([p.id, ..seen], [p, ..out])
    }
  })
  |> fn(acc) { list.reverse(acc.1) }
}

fn cheapest(tiers: List(#(String, Float))) -> Option(#(String, Float)) {
  tiers
  |> list.sort(fn(a, b) { float.compare(a.1, b.1) })
  |> list.first
  |> option.from_result
}

fn priciest(tiers: List(#(String, Float))) -> Option(#(String, Float)) {
  tiers
  |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
  |> list.first
  |> option.from_result
}

/// For each proposal, choose the lowest-cost tier when its posterior mean is
/// adequate (>= `theta`); otherwise fall back to the highest-cost tier in
/// `tiers` (the most capable one available). `theta` gates the whole
/// proposal, not a per-tier adequacy curve — there is no per-tier belief
/// here, only the proposal's own Beta posterior.
pub fn cheapest_adequate(
  ps: List(Proposal),
  tiers: List(#(String, Float)),
  theta: Float,
) -> List(#(Proposal, String)) {
  let lo = cheapest(tiers)
  let hi = priciest(tiers)
  list.map(ps, fn(p) {
    let adequate = posterior_mean(p) >=. theta
    case adequate, lo, hi {
      True, option.Some(#(name, _)), _ -> #(p, name)
      False, _, option.Some(#(name, _)) -> #(p, name)
      _, _, _ -> #(p, p.tier)
    }
  })
}

fn round2_text(f: Float) -> String {
  float.to_string(int.to_float(float.round(f *. 100.0)) /. 100.0)
}

pub fn to_markdown(ps: List(Proposal)) -> String {
  let header =
    "| id | action | mean | trials | status | tier | cost_usd | evidence |\n|---|---|---|---|---|---|---|---|"
  let rows =
    list.map(ps, fn(p) {
      "| "
      <> p.id
      <> " | "
      <> p.action
      <> " | "
      <> round2_text(posterior_mean(p))
      <> " | "
      <> int.to_string(trials(p))
      <> " | "
      <> status_label(p.status)
      <> " | "
      <> p.tier
      <> " | "
      <> round2_text(p.cost_usd)
      <> " | "
      <> int.to_string(list.length(p.evidence))
      <> " |"
    })
  string.join([header, ..rows], "\n")
}

fn proposal_json(p: Proposal) -> Json {
  json.object([
    #("id", json.string(p.id)),
    #("hypothesis", json.string(p.hypothesis)),
    #("action", json.string(p.action)),
    #("alpha", json.float(p.alpha)),
    #("beta", json.float(p.beta)),
    #("status", json.string(status_label(p.status))),
    #("tier", json.string(p.tier)),
    #("cost_usd", json.float(p.cost_usd)),
    #("evidence", json.array(p.evidence, json.string)),
  ])
}

pub fn to_json(ps: List(Proposal)) -> Json {
  json.array(ps, proposal_json)
}

fn proposal_decoder() -> decode.Decoder(Proposal) {
  use id <- decode.field("id", decode.string)
  use hypothesis <- decode.field("hypothesis", decode.string)
  use action <- decode.field("action", decode.string)
  use alpha <- decode.field("alpha", decode.float)
  use beta <- decode.field("beta", decode.float)
  use status_s <- decode.field("status", decode.string)
  use tier <- decode.field("tier", decode.string)
  use cost_usd <- decode.field("cost_usd", decode.float)
  use evidence <- decode.field("evidence", decode.list(decode.string))
  decode.success(Proposal(
    id,
    hypothesis,
    action,
    alpha,
    beta,
    status_from_label(status_s),
    tier,
    cost_usd,
    evidence,
  ))
}

/// One JSON object per line — the persisted `<proposals.jsonl>` format
/// `uos_hive_cli` reads and writes.
pub fn to_jsonl(ps: List(Proposal)) -> String {
  ps
  |> list.map(fn(p) { json.to_string(proposal_json(p)) })
  |> string.join("\n")
}

/// Malformed lines are silently skipped (mirrors `board.from_jsonl`'s
/// tolerance, but proposals are not chain-linked so there is nothing to
/// quarantine against).
pub fn from_jsonl(text: String) -> List(Proposal) {
  text
  |> string.split("\n")
  |> list.filter(fn(l) { string.trim(l) != "" })
  |> list.filter_map(fn(l) {
    json.parse(from: l, using: proposal_decoder()) |> result.replace_error(Nil)
  })
}
