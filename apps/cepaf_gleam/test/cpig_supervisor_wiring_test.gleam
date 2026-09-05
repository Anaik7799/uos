//// Pass-21 wiring guard for cpig_supervisor.
////
//// Cites: SC-CPIG-002 (subscriber must be available even when Zenoh router
//// is offline), SC-WIRE-001 (compile-time wiring guard), SC-CPIG-013 (real
//// subscription opt-in via env var), SC-PI-RUNTIME-001 (subprocess parity:
//// safe-by-default).

import cepaf_gleam/actors/cpig_subscriber
import cepaf_gleam/actors/cpig_supervisor
import gleeunit/should

pub fn supervisor_init_state_is_constructable_test() {
  // SC-WIRE-001: init_state must construct without panicking, regardless of
  // env or runtime state.
  let s = cpig_supervisor.init_state()
  s.live_subscription |> should.equal(False)
  s.raw_deliveries |> should.equal(0)
  s.inner.messages_processed |> should.equal(0)
}

pub fn supervisor_start_is_safe_default_off_test() {
  // SC-CPIG-002 + SC-PI-RUNTIME-001: default `start()` must succeed without
  // requiring a Zenoh router. We accept either Ok(_) (router up) or
  // Error(_) (router down), but the call MUST return — never panic.
  let result = cpig_supervisor.start()
  case result {
    Ok(_) -> True
    Error(_) -> True
  }
  |> should.equal(True)
}

pub fn supervisor_apply_event_advances_inner_state_test() {
  // The supervisor delegates message handling to cpig_subscriber. Apply a
  // well-formed event and verify the inner state advances.
  let s0 = cpig_supervisor.init_state()
  let payload =
    "{\"score\":54,\"pct\":90,\"drift\":[\"foo\"],\"as_of\":\"2026-04-28T00:00:00Z\"}"
  let s1 = cpig_supervisor.apply_event(s0, "indrajaal/l4/cpig/score", payload)
  s1.raw_deliveries |> should.equal(1)
  s1.inner.messages_processed |> should.equal(1)
  s1.inner.last_score |> should.equal(54)
}

pub fn supervisor_loop_is_exposed_for_testing_test() {
  // SC-WIRE-001: loop/2 must be a public symbol so the wiring guard can
  // verify the OTP message contract at compile time.
  let s = cpig_supervisor.init_state()
  let msg = cpig_subscriber.tick_msg()
  // We don't need to consume the actor.Next here — just prove `loop` is
  // callable with a valid (state, msg) pair. If the symbol disappears,
  // this test fails to compile (the wiring guard).
  let _ = cpig_supervisor.loop(s, msg)
  True |> should.equal(True)
}

pub fn supervisor_summary_renders_human_readable_test() {
  let s = cpig_supervisor.init_state()
  let line = cpig_supervisor.summary(s)
  // Must contain the canonical prefix.
  case line {
    "CpigSupervisor:" <> _ -> True
    _ -> False
  }
  |> should.equal(True)
}
