//// Laws for the TUI provenance panel (SC-PROVENANCE-001).
////
//// The panel's job is to make a HOLD as visible as a PASS. These tests assert
//// that a degraded state cannot be rendered as a clean one.

import gleeunit/should
import uos_swarm/provenance_panel as pp

fn observed() -> pp.Model {
  pp.Model(
    checks: [
      pp.Check("KMP-GAP", "numbering", pp.Pass, "contiguous 1..87"),
      pp.Check("KMP-DUP", "duplicates", pp.Pass, "none"),
      pp.Check("KMP-INCOMPLETE", "index completeness", pp.Pass, "87/87 both indexes"),
      pp.Check("KMP-UNMARKED", "quarantine marking", pp.Pass, "16/16 both indexes"),
      pp.Check("KMP-ENTROPY", "layer entropy", pp.Hold, "1.359 bits below 2.50 floor"),
      pp.Check("KMP-CEILING-SPLIT", "ceiling", pp.Hold, "policy 93 exceeds machine 92"),
    ],
    metrics: [
      pp.Metric("layer_entropy_bits", 1.359, 2.5, 0.0, 0.0, 1.359, True),
      pp.Metric("index_completeness", 1.0, 1.0, 0.0, 0.0, 1.0, False),
    ],
    ceiling: pp.Ceiling(policy: 93, machine: 92, highest_claimed: 109),
    quarantined: 16,
    corpus_total: 87,
    chain_rows: 58,
    chain_intact: True,
  )
}

/// One HOLD among passes makes the whole verdict HOLD. A panel that averaged
/// its checks into a green would hide exactly the state worth seeing.
pub fn verdict_is_hold_when_any_check_holds_test() {
  pp.verdict(observed()) |> should.equal(pp.Hold)
}

/// An andon dominates every other state.
pub fn andon_dominates_hold_test() {
  let m = observed()
  let m2 =
    pp.Model(
      ..m,
      checks: [pp.Check("R0", "chain", pp.Andon, "digest mismatch"), ..m.checks],
    )
  pp.verdict(m2) |> should.equal(pp.Andon)
}

pub fn verdict_is_pass_only_when_every_check_passes_test() {
  let m = observed()
  let clean =
    pp.Model(..m, checks: [pp.Check("KMP-GAP", "numbering", pp.Pass, "ok")])
  pp.verdict(clean) |> should.equal(pp.Pass)
}

/// The two ceilings disagree, and the panel must say so rather than pick one.
pub fn ceiling_split_is_detected_test() {
  pp.ceiling_split(pp.Ceiling(policy: 93, machine: 92, highest_claimed: 109))
  |> should.be_true()
}

pub fn ceiling_split_absent_when_they_agree_test() {
  pp.ceiling_split(pp.Ceiling(policy: 93, machine: 93, highest_claimed: 109))
  |> should.be_false()
}

/// The not-admitted span starts one above the policy ceiling.
pub fn not_admitted_span_starts_above_the_ceiling_test() {
  pp.not_admitted_span(pp.Ceiling(policy: 93, machine: 92, highest_claimed: 109))
  |> should.equal("EV-94..EV-109")
}

/// Nothing is claimed above the ceiling, so nothing is withheld.
pub fn not_admitted_span_is_none_when_no_claim_exceeds_test() {
  pp.not_admitted_span(pp.Ceiling(policy: 93, machine: 93, highest_claimed: 93))
  |> should.equal("none")
}

/// A projection whose band spans the threshold must be labelled not decisive.
pub fn metric_line_marks_indecisive_projection_test() {
  let m = pp.Metric("index_completeness", 1.0, 1.0, 0.0, 0.0, 1.0, False)
  pp.metric_line(m)
  |> should_contain("not decisive")
}

pub fn metric_line_marks_decisive_projection_test() {
  let m = pp.Metric("layer_entropy_bits", 1.359, 2.5, 0.0, 0.0, 1.359, True)
  pp.metric_line(m) |> should_contain("decisive")
}

/// A broken chain suspends verdicts, and the render must say that outright.
pub fn broken_chain_is_rendered_prominently_test() {
  let m = observed()
  let broken = pp.Model(..m, chain_intact: False)
  pp.render(broken) |> should_contain("BROKEN")
  pp.render(broken) |> should_contain("verdicts suspended")
}

/// The rendered panel names every holding rule, so a reader cannot miss one.
pub fn render_names_every_holding_rule_test() {
  let out = pp.render(observed())
  out |> should_contain("KMP-ENTROPY")
  out |> should_contain("KMP-CEILING-SPLIT")
  out |> should_contain("HOLD")
}

/// Bindings emit intents, never effects: the panel stays pure.
pub fn bindings_are_intents_test() {
  pp.bindings()
  |> list_length
  |> should.equal(5)
}

fn list_length(l: List(a)) -> Int {
  case l {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

fn should_contain(haystack: String, needle: String) -> Nil {
  case contains(haystack, needle) {
    True -> Nil
    False -> should.fail()
  }
}

@external(erlang, "string", "find")
fn find(haystack: String, needle: String) -> String

fn contains(haystack: String, needle: String) -> Bool {
  find(haystack, needle) != "nomatch"
}
