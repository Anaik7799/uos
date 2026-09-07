import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import prng
import uos_tui/frame
import uos_tui/geometry.{Size}
import uos_tui/palette.{type Command, Command}
import uos_tui/render

fn sample_registry() -> List(Command(Nil)) {
  [
    Command(
      id: "doctor",
      title: "doctor",
      keywords: ["health", "check"],
      action: Nil,
    ),
    Command(
      id: "undo",
      title: "undo command",
      keywords: ["revert"],
      action: Nil,
    ),
    Command(id: "docs", title: "open docs", keywords: ["doc"], action: Nil),
  ]
}

pub fn score_exact_subsequence_test() {
  palette.score("doc", "doctor")
  |> should.equal(Some(340))
}

pub fn score_case_insensitive_test() {
  palette.score("DOC", "Doctor")
  |> should.equal(palette.score("doc", "doctor"))
}

pub fn score_prefix_bonus_orders_correctly_test() {
  let doctor = palette.score("doc", "doctor")
  let undo = palette.score("doc", "undo command")
  case doctor, undo {
    Some(d), Some(u) -> should.be_true(d > u)
    _, _ -> should.fail()
  }
}

pub fn score_non_match_is_none_test() {
  palette.score("xyz", "doctor")
  |> should.equal(None)
}

pub fn score_empty_query_always_matches_test() {
  palette.score("", "anything")
  |> should.equal(Some(0))
  palette.score("", "")
  |> should.equal(Some(0))
}

pub fn score_out_of_order_is_none_test() {
  palette.score("tod", "doctor")
  |> should.equal(None)
}

pub fn rank_stability_for_ties_test() {
  let candidates = ["alpha", "beta", "gamma"]
  let ranked = palette.rank("", candidates)
  ranked
  |> list.map(fn(pair) {
    let #(name, _) = pair
    name
  })
  |> should.equal(candidates)
}

pub fn rank_orders_by_descending_score_test() {
  let candidates = ["doctor", "undo command", "unrelated"]
  let ranked = palette.rank("doc", candidates)
  ranked
  |> list.map(fn(pair) {
    let #(name, _) = pair
    name
  })
  |> should.equal(["doctor", "undo command"])
}

pub fn search_matches_keywords_test() {
  let results = palette.search(sample_registry(), "health", 10)
  results
  |> list.map(fn(c) { c.id })
  |> should.equal(["doctor"])
}

pub fn search_respects_limit_test() {
  let results = palette.search(sample_registry(), "", 1)
  list.length(results)
  |> should.equal(1)
}

pub fn search_limit_zero_returns_empty_test() {
  palette.search(sample_registry(), "doc", 0)
  |> should.equal([])
}

pub fn view_renders_well_formed_test() {
  let widget =
    palette.view("doc", [], 0, fn(_) { Nil }, fn(_) { Nil }, fn(_) { Nil })
  let frame_out =
    render.compose(widget, Size(60, 12), Some("palette-input"), render.dark)
  frame.is_well_formed(frame_out)
  |> should.be_true()
}

pub fn property_ranked_subset_and_scores_non_increasing_test() {
  let seeds = prng.seeds(6)
  list.each(seeds, fn(seed) {
    let #(candidates, seed2) = random_candidates(seed, 8)
    let #(query, _) = prng.text(seed2, 3)
    let ranked = palette.rank(query, candidates)
    let names =
      list.map(ranked, fn(pair) {
        let #(name, _) = pair
        name
      })
    should.be_true(list.all(names, fn(n) { list.contains(candidates, n) }))
    let scores =
      list.map(ranked, fn(pair) {
        let #(_, s) = pair
        s
      })
    should.be_true(non_increasing(scores))
  })
}

fn random_candidates(
  seed: prng.Seed,
  count: Int,
) -> #(List(String), prng.Seed) {
  list.fold(prng.range(1, count), #([], seed), fn(acc, _) {
    let #(xs, s) = acc
    let #(text, s2) = prng.text(s, 5)
    #([text, ..xs], s2)
  })
}

fn non_increasing(xs: List(Int)) -> Bool {
  case xs {
    [] -> True
    [_] -> True
    [a, b, ..rest] ->
      case a >= b {
        True -> non_increasing([b, ..rest])
        False -> False
      }
  }
}

pub fn fuzz_score_never_crashes_test() {
  let seeds = prng.seeds(500)
  list.each(seeds, fn(seed) {
    let #(query, seed2) = prng.text(seed, 4)
    let #(candidate, _) = prng.text(seed2, 6)
    let _ = palette.score(query, candidate)
    Nil
  })
}
