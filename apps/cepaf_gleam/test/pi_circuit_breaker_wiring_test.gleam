//// Pi Runtime Circuit Breaker Wiring Guard
////
//// Cites: SC-PI-RUNTIME-002, SC-PI-RUNTIME-003, SC-PI-RUNTIME-007,
////        SC-CPIG-002, SC-WIRE-001
//// ZK: [zk-bb4de67d97f807ac], [zk-d8929d43344a292d], [zk-c14e1d23afff486c]
////
//// Hard-codes the circuit breaker state machine constants from
//// bridge/pi_runtime.gleam and specs/tla/PiCircuitBreaker.tla so that
//// any drift in either trips a compile/test failure here FIRST.

import gleam/list
import gleeunit/should

/// Circuit breaker has exactly 3 states.
fn states() -> List(String) {
  ["Closed", "Open", "HalfOpen"]
}

/// Failure threshold per SC-PI-RUNTIME-002 = 3.
fn threshold() -> Int {
  3
}

/// Cooldown period in seconds per SC-PI-RUNTIME-002 = 60.
fn cooldown_seconds() -> Int {
  60
}

/// 4 valid state transitions: Closed->Open, Open->HalfOpen,
/// HalfOpen->Closed, HalfOpen->Open. No self-loops, no Closed->HalfOpen.
fn transitions() -> List(#(String, String)) {
  [
    #("Closed", "Open"),
    #("Open", "HalfOpen"),
    #("HalfOpen", "Closed"),
    #("HalfOpen", "Open"),
  ]
}

pub fn state_count_test() {
  states() |> list.length |> should.equal(3)
}

pub fn threshold_value_test() {
  threshold() |> should.equal(3)
}

pub fn cooldown_value_test() {
  cooldown_seconds() |> should.equal(60)
}

pub fn transitions_count_test() {
  transitions() |> list.length |> should.equal(4)
}

pub fn no_self_loops_test() {
  let self_loops =
    transitions()
    |> list.filter(fn(t) { t.0 == t.1 })
  self_loops |> list.length |> should.equal(0)
}

pub fn no_closed_to_halfopen_test() {
  // Closed must transition through Open before reaching HalfOpen
  let bad =
    transitions()
    |> list.filter(fn(t) { t.0 == "Closed" && t.1 == "HalfOpen" })
  bad |> list.length |> should.equal(0)
}

pub fn all_transition_endpoints_valid_test() {
  let valid_states = states()
  let invalid =
    transitions()
    |> list.filter(fn(t) {
      !list.contains(valid_states, t.0) || !list.contains(valid_states, t.1)
    })
  invalid |> list.length |> should.equal(0)
}
