/// Sentinel Tests — round-robin patrol agent, truth verification, alarm logic
///
/// 21 tests covering: init, all_pages, patrol_next, check_page,
/// alarm_pages, patrol_health, summary, circuit completion.
///
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-SATYA-002, SC-TRUTH-001, SC-SIL4-001
/// अभयं सत्त्वसंशुद्धिर् — Fearlessness and purity of truth (Gita 16.1)
import cepaf_gleam/ha/sentinel.{
  CircuitComplete, PageInfo, SentinelOk, alarm_pages, all_pages, check_page,
  init, patrol_health, patrol_next, summary,
}
import gleam/list
import gleam/string
import gleeunit/should

// ===========================================================================
// 1. init/0
// ===========================================================================

pub fn init_returns_zero_checks_test() {
  init().total_checks |> should.equal(0)
}

pub fn init_alarm_inactive_test() {
  init().alarm_active |> should.be_false()
}

pub fn init_alarm_page_empty_test() {
  init().alarm_page |> should.equal("")
}

pub fn init_patrol_count_zero_test() {
  init().patrol_count |> should.equal(0)
}

pub fn init_current_index_zero_test() {
  init().current_index |> should.equal(0)
}

// ===========================================================================
// 2. all_pages/0
// ===========================================================================

pub fn all_pages_returns_35_test() {
  all_pages() |> list.length() |> should.equal(35)
}

pub fn all_pages_first_is_dashboard_test() {
  let pages = all_pages()
  let first = list.first(pages)
  case first {
    Ok(p) -> p.name |> should.equal("dashboard")
    Error(_) -> should.fail()
  }
}

pub fn all_pages_last_is_sentinel_test() {
  let pages = all_pages()
  let last = list.last(pages)
  case last {
    Ok(p) -> p.name |> should.equal("sentinel")
    Error(_) -> should.fail()
  }
}

pub fn all_pages_routes_start_with_slash_test() {
  let all_valid =
    all_pages()
    |> list.all(fn(p) { string.starts_with(p.route, "/") })
  all_valid |> should.be_true()
}

pub fn all_pages_invariant_counts_positive_test() {
  let all_positive =
    all_pages()
    |> list.all(fn(p) { p.invariant_count > 0 })
  all_positive |> should.be_true()
}

// ===========================================================================
// 3. check_page/1
// ===========================================================================

pub fn check_page_stub_returns_truthful_test() {
  let page = PageInfo("dashboard", "/dashboard", 12)
  let result = check_page(page)
  result.truthful |> should.be_true()
}

pub fn check_page_stores_page_name_test() {
  let page = PageInfo("immune", "/immune", 10)
  let result = check_page(page)
  result.page |> should.equal("immune")
}

pub fn check_page_check_time_non_negative_test() {
  let page = PageInfo("zenoh", "/zenoh", 9)
  let result = check_page(page)
  { result.check_time_ms >= 0 } |> should.be_true()
}

// ===========================================================================
// 4. patrol_next/1 — basic advance
// ===========================================================================

pub fn patrol_next_increments_total_checks_test() {
  let state = init()
  let #(new_state, _action) = patrol_next(state)
  new_state.total_checks |> should.equal(1)
}

pub fn patrol_next_advances_index_test() {
  let state = init()
  let #(new_state, _action) = patrol_next(state)
  new_state.current_index |> should.equal(1)
}

pub fn patrol_next_ok_action_test() {
  let state = init()
  let #(_new_state, action) = patrol_next(state)
  action |> should.equal(SentinelOk)
}

pub fn patrol_next_accumulates_results_test() {
  let state = init()
  let #(s1, _) = patrol_next(state)
  let #(s2, _) = patrol_next(s1)
  s2.results |> list.length() |> should.equal(2)
}

// ===========================================================================
// 5. Circuit completion
// ===========================================================================

pub fn patrol_wraps_after_35_pages_test() {
  let state = init()
  let final_state =
    list.fold(list.repeat(0, 35), state, fn(s, _) {
      let #(next, _) = patrol_next(s)
      next
    })
  final_state.current_index |> should.equal(0)
}

pub fn patrol_circuit_complete_action_test() {
  let state = init()
  let #(_, last_action) =
    list.fold(list.repeat(0, 35), #(state, SentinelOk), fn(acc, _) {
      let #(s, _prev_action) = acc
      patrol_next(s)
    })
  last_action |> should.equal(CircuitComplete(1))
}

// ===========================================================================
// 6. patrol_health/1
// ===========================================================================

pub fn patrol_health_full_on_init_test() {
  patrol_health(init()) |> should.equal(1.0)
}

pub fn patrol_health_after_one_pass_is_one_test() {
  let state = init()
  let #(new_state, _) = patrol_next(state)
  let h = patrol_health(new_state)
  { h >=. 0.99 } |> should.be_true()
}

// ===========================================================================
// 7. alarm_pages/1
// ===========================================================================

pub fn alarm_pages_empty_on_init_test() {
  alarm_pages(init()) |> should.equal([])
}

// ===========================================================================
// 8. summary/1
// ===========================================================================

pub fn summary_contains_sentinel_test() {
  let s = summary(init())
  string.contains(s, "Sentinel") |> should.be_true()
}

pub fn summary_contains_health_test() {
  let s = summary(init())
  string.contains(s, "health=") |> should.be_true()
}
