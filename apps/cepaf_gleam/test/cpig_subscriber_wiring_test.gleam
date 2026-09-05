//// Wiring guard test for cepaf_gleam/actors/cpig_subscriber.
////
//// STAMP: SC-CPIG-002 (drift validator subscriber wiring), SC-WIRE-001
//// (wiring guard MUST compile before any test).
////
//// Asserts:
////   1. Initial CpigState constructs cleanly with default values.
////   2. Topic-family prefix `indrajaal/l4/cpig/` is preserved.
////   3. Message constructors are usable (round-trip + shutdown classify).

import cepaf_gleam/actors/cpig_subscriber
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// SC-CPIG-002 — initial state defaults
// ---------------------------------------------------------------------------

pub fn initial_state_defaults_test() {
  let s = cpig_subscriber.init_state()
  s.last_score |> should.equal(0)
  s.last_pct |> should.equal(0)
  s.last_drift |> should.equal([])
  s.last_seen |> should.equal("")
  s.messages_processed |> should.equal(0)
  s.bridge_healthy |> should.be_false
}

pub fn current_state_matches_init_test() {
  cpig_subscriber.current_state()
  |> should.equal(cpig_subscriber.init_state())
}

pub fn drift_rule_count_zero_test() {
  cpig_subscriber.init_state()
  |> cpig_subscriber.drift_rule_count
  |> should.equal(0)
}

// ---------------------------------------------------------------------------
// SC-CPIG-002 / SC-ZMOF-001 — topic-family prefix is canonical
// ---------------------------------------------------------------------------

pub fn topic_family_prefix_test() {
  cpig_subscriber.subscription_prefix()
  |> should.equal("indrajaal/l4/cpig/")
}

pub fn topic_family_starts_with_indrajaal_test() {
  cpig_subscriber.subscription_prefix()
  |> string.starts_with("indrajaal/l4/cpig/")
  |> should.be_true
}

pub fn score_topic_under_family_test() {
  cpig_subscriber.score_topic
  |> string.starts_with(cpig_subscriber.subscription_prefix())
  |> should.be_true
}

// ---------------------------------------------------------------------------
// SC-WIRE-001 — message constructors and shutdown classification
// ---------------------------------------------------------------------------

pub fn event_msg_constructor_test() {
  let msg =
    cpig_subscriber.event_msg(
      "indrajaal/l4/cpig/score",
      "{\"score\":60,\"pct\":100,\"drift\":[],\"as_of\":\"2026-04-28T00:00:00Z\"}",
    )
  cpig_subscriber.is_shutdown(msg) |> should.be_false
}

pub fn tick_msg_not_shutdown_test() {
  cpig_subscriber.is_shutdown(cpig_subscriber.tick_msg()) |> should.be_false
}

pub fn shutdown_classification_test() {
  cpig_subscriber.is_shutdown(cpig_subscriber.CpigShutdown) |> should.be_true
}

// ---------------------------------------------------------------------------
// SC-CPIG-013 — handle_message preserves invariant on bad payload
// ---------------------------------------------------------------------------

pub fn handle_message_bad_payload_keeps_state_shape_test() {
  let s0 = cpig_subscriber.init_state()
  let s1 =
    cpig_subscriber.handle_message(
      s0,
      cpig_subscriber.event_msg("indrajaal/l4/cpig/score", "not-json"),
    )
  // Counter advances even on decode error; bridge_healthy reflects last decode.
  s1.messages_processed |> should.equal(1)
  s1.bridge_healthy |> should.be_false
  s1.last_score |> should.equal(0)
}
