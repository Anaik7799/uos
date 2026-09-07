import gleam/list
import gleam/string
import gleeunit/should
import uos_swarm/dream
import uos_swarm/evolve
import uos_swarm/sangita

fn p(id: String, alpha: Float, beta: Float) -> evolve.Proposal {
  evolve.Proposal(
    id: id,
    hypothesis: "test hypothesis " <> id,
    action: "audit",
    alpha: alpha,
    beta: beta,
    status: evolve.Proposed,
    tier: "sonnet",
    cost_usd: 1.0,
    evidence: [],
  )
}

pub fn from_dream_seeds_proposed_uniform_prior_test() {
  let d =
    dream.Dream(
      seed: 1,
      consolidated: 2,
      hypotheses: [
        dream.Hypothesis("dream-1-0", "aspect 15 failed", ["m1"], 0.5, "audit", [
          15,
        ]),
      ],
      citation: dream.citation,
    )
  let ps = evolve.from_dream(d, "haiku")
  list.length(ps) |> should.equal(1)
  case ps {
    [only] -> {
      only.id |> should.equal("prop-dream-1-0")
      only.hypothesis |> should.equal("aspect 15 failed")
      only.action |> should.equal("audit")
      only.alpha |> should.equal(1.0)
      only.beta |> should.equal(1.0)
      only.status |> should.equal(evolve.Proposed)
      only.tier |> should.equal("haiku")
      only.cost_usd |> should.equal(0.27)
      only.evidence |> should.equal([])
    }
    _ -> should.fail()
  }
}

pub fn record_ignores_self_report_without_evidence_test() {
  let p0 = p("x", 1.0, 1.0)
  evolve.record(p0, True, "") |> should.equal(p0)
  evolve.record(p0, True, "   ") |> should.equal(p0)
  evolve.record(p0, False, "") |> should.equal(p0)
}

pub fn record_moves_proposed_to_trialled_on_first_evidenced_record_test() {
  let p0 = p("x", 1.0, 1.0)
  let p1 = evolve.record(p0, True, "ev-1")
  p1.status |> should.equal(evolve.Trialled)
  p1.alpha |> should.equal(2.0)
  p1.beta |> should.equal(1.0)
  p1.evidence |> should.equal(["ev-1"])
}

pub fn record_adopts_at_mean_0_8_with_3_trials_test() {
  let p0 = p("x", 1.0, 1.0)
  let p1 = evolve.record(p0, True, "ev-1")
  let p2 = evolve.record(p1, True, "ev-2")
  p2.status |> should.equal(evolve.Trialled)
  let p3 = evolve.record(p2, True, "ev-3")
  // alpha=4, beta=1, mean=0.8, trials=3 -> Adopted
  p3.alpha |> should.equal(4.0)
  p3.beta |> should.equal(1.0)
  evolve.trials(p3) |> should.equal(3)
  p3.status |> should.equal(evolve.Adopted)
}

pub fn record_never_adopts_before_3_trials_even_at_100_percent_test() {
  let p0 = p("x", 1.0, 1.0)
  let p1 = evolve.record(p0, True, "ev-1")
  let p2 = evolve.record(p1, True, "ev-2")
  // alpha=3, beta=1, mean=0.75 < 0.8 anyway, and only 2 trials.
  p2.status |> should.equal(evolve.Trialled)
}

pub fn record_rejects_at_mean_0_2_with_3_trials_test() {
  let p0 = p("y", 1.0, 1.0)
  let p1 = evolve.record(p0, False, "ev-1")
  let p2 = evolve.record(p1, False, "ev-2")
  p2.status |> should.equal(evolve.Trialled)
  let p3 = evolve.record(p2, False, "ev-3")
  // alpha=1, beta=4, mean=0.2, trials=3 -> Rejected
  p3.beta |> should.equal(4.0)
  evolve.trials(p3) |> should.equal(3)
  p3.status |> should.equal(evolve.Rejected)
}

pub fn select_returns_k_distinct_proposals_test() {
  let ps = [
    p("a", 5.0, 1.0),
    p("b", 1.0, 5.0),
    p("c", 3.0, 3.0),
    p("d", 8.0, 1.0),
    p("e", 1.0, 8.0),
  ]
  let chosen = evolve.select(ps, 17, 3)
  list.length(chosen) |> should.equal(3)
  let ids = list.map(chosen, fn(x) { x.id })
  list.unique(ids) |> list.length |> should.equal(3)
  // every chosen proposal really came from the input set
  list.each(chosen, fn(c) {
    list.any(ps, fn(orig) { orig.id == c.id }) |> should.be_true
  })
}

pub fn select_is_deterministic_for_a_seed_test() {
  let ps = [p("a", 5.0, 1.0), p("b", 1.0, 5.0), p("c", 3.0, 3.0)]
  let s1 = evolve.select(ps, 9, 2) |> list.map(fn(x) { x.id })
  let s2 = evolve.select(ps, 9, 2) |> list.map(fn(x) { x.id })
  s1 |> should.equal(s2)
}

pub fn select_bounds_k_to_available_proposals_test() {
  let ps = [p("a", 5.0, 1.0), p("b", 1.0, 5.0)]
  evolve.select(ps, 3, 10) |> list.length |> should.equal(2)
  evolve.select(ps, 3, 0) |> list.length |> should.equal(0)
}

pub fn cheapest_adequate_picks_cheap_tier_when_adequate_test() {
  let tiers = [#("haiku", 0.27), #("sonnet", 1.0), #("opus", 5.0)]
  // mean = 9 / (9 + 1) = 0.9 >= theta 0.5 -> adequate -> cheapest tier.
  let adequate_p = p("good", 9.0, 1.0)
  case evolve.cheapest_adequate([adequate_p], tiers, 0.5) {
    [#(proposal, tier)] -> {
      proposal.id |> should.equal("good")
      tier |> should.equal("haiku")
    }
    _ -> should.fail()
  }
}

pub fn cheapest_adequate_falls_back_to_highest_tier_when_inadequate_test() {
  let tiers = [#("haiku", 0.27), #("sonnet", 1.0), #("opus", 5.0)]
  // mean = 1 / (1 + 9) = 0.1 < theta 0.5 -> inadequate -> highest-cost tier.
  let weak_p = p("weak", 1.0, 9.0)
  case evolve.cheapest_adequate([weak_p], tiers, 0.5) {
    [#(proposal, tier)] -> {
      proposal.id |> should.equal("weak")
      tier |> should.equal("opus")
    }
    _ -> should.fail()
  }
}

pub fn to_markdown_lists_every_proposal_test() {
  let ps = [p("a", 5.0, 1.0), p("b", 1.0, 5.0)]
  let md = evolve.to_markdown(ps)
  ["a", "b", "Proposed"]
  |> list.all(fn(n) { string.contains(md, n) })
  |> should.be_true
}

pub fn to_jsonl_from_jsonl_round_trip_test() {
  let ps = [
    p("a", 5.0, 1.0),
    evolve.Proposal(
      "b",
      "hyp b",
      "verify",
      3.0,
      3.0,
      evolve.Trialled,
      "opus",
      5.0,
      ["ev-1", "ev-2"],
    ),
    evolve.Proposal(
      "c",
      "hyp c",
      "retire",
      9.0,
      1.0,
      evolve.Adopted,
      "haiku",
      0.27,
      ["ev-1", "ev-2", "ev-3"],
    ),
  ]
  let round = evolve.from_jsonl(evolve.to_jsonl(ps))
  round |> should.equal(ps)
}

pub fn from_jsonl_skips_malformed_lines_test() {
  let text = "not json\n" <> evolve.to_jsonl([p("a", 5.0, 1.0)])
  let round = evolve.from_jsonl(text)
  list.length(round) |> should.equal(1)
}

pub fn record_in_harmony_refuses_a_drop_test() {
  let p =
    evolve.Proposal(
      "p-harmony",
      "verify the quiet senders",
      "verify",
      1.0,
      1.0,
      evolve.Proposed,
      "deterministic",
      0.0,
      [],
    )
  let hi = sangita.Harmony(0.9, [], [], 1, "Yaman")
  let lo = sangita.Harmony(0.6, [], [], 1, "Malkauns")
  let assert Error(why) = evolve.record_in_harmony(p, True, "ev-1", hi, lo)
  string.contains(why, "harmony gate refused") |> should.be_true
  let assert Ok(q) = evolve.record_in_harmony(p, True, "ev-1", hi, hi)
  q.alpha |> should.equal(2.0)
}
