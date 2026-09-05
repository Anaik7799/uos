/// Chaos apoptosis tests — stochastic lifecycle management
/// SC-ULTRA-001 Focus 8: Continuous Stochastic Apoptosis
import cepaf_gleam/chaos/apoptosis
import gleeunit/should

pub fn init_has_zero_deaths_test() {
  let state = apoptosis.init()
  state.total_deaths |> should.equal(0)
  state.total_resurrections |> should.equal(0)
}

pub fn register_adds_container_test() {
  let state =
    apoptosis.init()
    |> apoptosis.register("app-1", 1000)
  list.length(state.lifespans) |> should.equal(1)
}

pub fn excluded_containers_not_killed_test() {
  let state =
    apoptosis.init()
    |> apoptosis.register("indrajaal-db-prod", 1000)
  // Even at far future, db-prod is excluded
  let due = apoptosis.due_for_death(state, 999_999_999)
  list.length(due) |> should.equal(0)
}

pub fn non_excluded_container_can_die_test() {
  let state =
    apoptosis.init()
    |> apoptosis.register("app-1", 1000)
  let due = apoptosis.due_for_death(state, 999_999_999)
  list.length(due) |> should.equal(1)
}

pub fn record_death_increments_count_test() {
  let state =
    apoptosis.init()
    |> apoptosis.register("app-1", 1000)
    |> apoptosis.record_death("app-1", 50_000)
  state.total_deaths |> should.equal(1)
}

pub fn resurrection_increments_count_test() {
  let state =
    apoptosis.init()
    |> apoptosis.register("app-1", 1000)
    |> apoptosis.record_death("app-1", 50_000)
    |> apoptosis.record_resurrection("app-1", 51_000)
  state.total_resurrections |> should.equal(1)
}

pub fn anti_fragility_score_positive_test() {
  let state = apoptosis.init()
  let score = apoptosis.anti_fragility_score(state)
  { score >=. 0.0 } |> should.be_true()
}

pub fn max_concurrent_deaths_enforced_test() {
  let state =
    apoptosis.init()
    |> apoptosis.register("app-1", 1000)
    |> apoptosis.register("app-2", 1000)
    |> apoptosis.register("app-3", 1000)
  // Config allows max 1 concurrent death
  let due = apoptosis.due_for_death(state, 999_999_999)
  list.length(due) |> should.equal(1)
}

import gleam/list
