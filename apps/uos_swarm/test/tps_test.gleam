//// Tests for uos_tui/tps: Toyota Production System flow control.
//// Reference: Toyota Production System / Lean Kanban board concepts.
//// STAMP id: SC-TUI-W09-001

import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import prng
import uos_swarm/tps.{
  type Board, type Card, Card, Defects, Done, Failed, Green, Motion,
  Overprocessing, Overproduction, Planned, Red, Running, Verifying, Waiting,
  Yellow,
}

fn card(id: String, column: tps.Column) -> Card {
  Card(
    id: id,
    slice: "slice-" <> id,
    owner: "w09",
    column: column,
    muda: [],
    cycle_minutes: option.None,
  )
}

fn board_with(n: Int, wip_limit: Int) -> Board {
  let base = tps.new(wip_limit, 30)
  list.fold(prng.range(1, n), base, fn(b, i) {
    tps.add(b, card("c" <> string.inspect(i), Planned))
  })
}

pub fn new_board_wip_zero_test() {
  let b = tps.new(2, 30)
  tps.wip(b) |> should.equal(0)
}

pub fn add_ignores_duplicate_test() {
  let b = tps.new(5, 30)
  let b = tps.add(b, card("dup", Planned))
  let b = tps.add(b, card("dup", Running))
  list.length(b.cards) |> should.equal(1)
}

pub fn pull_respects_wip_limit_unit_test() {
  let b = board_with(3, 1)
  let assert_ok = tps.pull(b, "c1")
  case assert_ok {
    Ok(b2) -> {
      tps.wip(b2) |> should.equal(1)
      case tps.pull(b2, "c2") {
        Error(_) -> should.be_true(True)
        Ok(_) -> should.be_true(False)
      }
    }
    Error(_) -> should.be_true(False)
  }
}

pub fn pull_blocked_when_line_stopped_test() {
  let b = board_with(2, 5)
  let b = tps.jidoka(b, "c1")
  case tps.pull(b, "c2") {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.be_true(False)
  }
}

pub fn illegal_transition_errors_test() {
  let b = board_with(1, 5)
  case tps.move(b, "c1", Done) {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.be_true(False)
  }
}

pub fn legal_transition_chain_test() {
  let b = board_with(1, 5)
  let result = {
    use b <- try_result(tps.pull(b, "c1"))
    use b <- try_result(tps.move(b, "c1", Verifying))
    use b <- try_result(tps.move(b, "c1", Done))
    Ok(b)
  }
  case result {
    Ok(b) -> {
      case list.find(b.cards, fn(c) { c.id == "c1" }) {
        Ok(c) -> c.column |> should.equal(Done)
        Error(_) -> should.be_true(False)
      }
    }
    Error(_) -> should.be_true(False)
  }
}

fn try_result(r: Result(a, e), f: fn(a) -> Result(b, e)) -> Result(b, e) {
  case r {
    Ok(v) -> f(v)
    Error(e) -> Error(e)
  }
}

pub fn jidoka_stops_line_and_records_test() {
  let b = board_with(1, 5)
  let b = tps.jidoka(b, "c1")
  b.line_stopped |> should.equal(True)
  b.jidoka_stops |> should.equal(1)
}

pub fn resume_clears_line_stopped_test() {
  let b = board_with(1, 5)
  let b = tps.jidoka(b, "c1")
  let b = tps.resume(b)
  b.line_stopped |> should.equal(False)
}

pub fn andon_green_test() {
  let b = board_with(3, 5)
  tps.andon(b) |> should.equal(Green)
}

pub fn andon_red_when_line_stopped_test() {
  let b = board_with(1, 5)
  let b = tps.jidoka(b, "c1")
  tps.andon(b) |> should.equal(Red)
}

pub fn andon_yellow_when_wip_at_limit_test() {
  let b = board_with(2, 1)
  case tps.pull(b, "c1") {
    Ok(b2) -> tps.andon(b2) |> should.equal(Yellow)
    Error(_) -> should.be_true(False)
  }
}

pub fn takt_arithmetic_test() {
  tps.takt(480, 8) |> should.equal(60.0)
  tps.takt(480, 0) |> should.equal(0.0)
  tps.takt(480, -3) |> should.equal(0.0)
}

pub fn first_pass_yield_no_finished_is_100_test() {
  let b = board_with(1, 5)
  tps.first_pass_yield(b) |> should.equal(100)
}

pub fn first_pass_yield_with_done_and_failed_test() {
  let b = tps.new(5, 30)
  let b = tps.add(b, card("d1", Done))
  let b = tps.add(b, card("d2", Done))
  let b = tps.add(b, card("f1", Failed))
  tps.first_pass_yield(b) |> should.equal(66)
}

pub fn throughput_test() {
  let b = tps.new(5, 30)
  let b = tps.add(b, card("d1", Done))
  let b = tps.add(b, card("d2", Done))
  tps.throughput(b, 60) |> should.equal(2.0)
  tps.throughput(b, 0) |> should.equal(0.0)
}

pub fn muda_report_counts_test() {
  let b = tps.new(5, 30)
  let c1 = Card(..card("m1", Planned), muda: [Waiting, Waiting, Defects])
  let c2 = Card(..card("m2", Planned), muda: [Motion])
  let b = tps.add(b, c1)
  let b = tps.add(b, c2)
  let report = tps.muda_report(b)
  case list.find(report, fn(p) { p.0 == Waiting }) {
    Ok(#(_, n)) -> n |> should.equal(2)
    Error(_) -> should.be_true(False)
  }
  case list.find(report, fn(p) { p.0 == Overproduction }) {
    Ok(#(_, n)) -> n |> should.equal(0)
    Error(_) -> should.be_true(False)
  }
  case list.find(report, fn(p) { p.0 == Overprocessing }) {
    Ok(#(_, n)) -> n |> should.equal(0)
    Error(_) -> should.be_true(False)
  }
}

pub fn markdown_contains_every_card_id_test() {
  let b = board_with(5, 5)
  let md = tps.to_markdown(b)
  list.each(prng.range(1, 5), fn(i) {
    let id = "c" <> string.inspect(i)
    should.be_true(string.contains(md, id))
  })
}

pub fn labels_are_nonempty_test() {
  should.be_true(string.length(tps.muda_label(Overproduction)) > 0)
  should.be_true(string.length(tps.column_label(Planned)) > 0)
}

// Property test: after any random sequence of pull/move operations, wip
// never exceeds the board's wip_limit. 300 seeds.
pub fn property_wip_never_exceeds_limit_test() {
  let wip_limit = 3
  let seeds = prng.seeds(300)
  list.each(seeds, fn(seed) {
    let b = board_with(8, wip_limit)
    let #(ops, _seed) = prng.ints(seed, 20, 0, 3)
    let final =
      list.fold(ops, b, fn(acc, n) {
        let idx = n % 8 + 1
        let id = "c" <> string.inspect(idx)
        case n % 3 {
          0 ->
            case tps.pull(acc, id) {
              Ok(nb) -> nb
              Error(_) -> acc
            }
          1 ->
            case tps.move(acc, id, Verifying) {
              Ok(nb) -> nb
              Error(_) -> acc
            }
          _ ->
            case tps.move(acc, id, Done) {
              Ok(nb) -> nb
              Error(_) -> acc
            }
        }
      })
    should.be_true(tps.wip(final) <= wip_limit)
  })
}

// Fuzz/chaos test: operations against random (mostly nonexistent) ids
// never crash, regardless of grapheme-heavy or garbage input.
pub fn fuzz_random_ids_never_crash_test() {
  let seeds = prng.seeds(50)
  list.each(seeds, fn(seed) {
    let b = board_with(4, 2)
    let #(id, seed2) = prng.text(seed, 6)
    let _ = tps.pull(b, id)
    let _ = tps.move(b, id, Running)
    let _ = tps.jidoka(b, id)
    let b2 = tps.jidoka(b, id)
    let _ = tps.resume(b2)
    let #(_junk, _seed3) = prng.int_between(seed2, 0, 10)
    should.be_true(True)
  })
}
