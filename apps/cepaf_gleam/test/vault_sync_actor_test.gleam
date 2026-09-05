//// vault_sync_actor_test — Wave-14 paired schedule + sync actor coverage.
////
//// Tests the pure-functional state machine of `vault_sync_actor.gleam`.
//// Per [zk-3346fc607a1ef9e6] Stub-That-Lies guard, we test ONLY the
//// dependency-free pure functions; IO (Zenoh emit, ADC probe, GCP HTTP
//// roundtrip) is honestly deferred to W2/Wave-14 worker bridge in
//// `planning_daemon/src/vault_workers.rs`.

import cepaf_gleam/vault_sync_actor.{
  CircuitOpen, Degraded, Divergence, NoOp, Nominal, Pull, Push,
  circuit_cooldown_seconds, circuit_open_for, circuit_should_open,
  decide_direction, handle_network_probe, handle_tick, record_failure,
  record_success,
}
import gleeunit/should

// We need a VaultHandle for State construction; vault.gleam's init()
// returns Err in the current Slice-B skeleton, so tests below construct
// State indirectly via the public init() function which takes a handle.
//
// We can't construct VaultHandle (it's opaque), but we CAN test pure
// transitions on the breaker / direction helpers without a State value.

// =====================================================================
// Circuit breaker — SC-VAULT-010
// =====================================================================

pub fn circuit_does_not_open_at_zero_failures_test() {
  circuit_should_open(0) |> should.equal(False)
}

pub fn circuit_does_not_open_at_two_failures_test() {
  circuit_should_open(2) |> should.equal(False)
}

pub fn circuit_opens_at_three_failures_test() {
  circuit_should_open(3) |> should.equal(True)
}

pub fn circuit_opens_above_three_failures_test() {
  circuit_should_open(7) |> should.equal(True)
}

pub fn circuit_cooldown_is_60_seconds_test() {
  circuit_cooldown_seconds() |> should.equal(60)
}

pub fn circuit_open_for_adds_cooldown_test() {
  circuit_open_for(1000) |> should.equal(1060)
}

// =====================================================================
// Direction decision — SC-VAULT-011 (monotonic version vector + LWW)
// =====================================================================

pub fn equal_versions_no_op_test() {
  decide_direction(5, 5, False) |> should.equal(NoOp)
}

pub fn remote_newer_pulls_test() {
  decide_direction(3, 7, False) |> should.equal(Pull(remote_version: 7))
}

pub fn local_newer_with_unsynced_flag_pushes_test() {
  decide_direction(7, 3, True) |> should.equal(Push(local_version: 7))
}

pub fn local_newer_without_unsynced_flag_is_divergence_test() {
  case decide_direction(7, 3, False) {
    Divergence(_) -> Nil
    _ -> panic as "expected Divergence for local-ahead-without-flag"
  }
}

pub fn divergence_includes_reason_test() {
  case decide_direction(9, 4, False) {
    Divergence(reason: r) ->
      case r {
        "local advanced without sync flag" -> Nil
        _ -> panic as "unexpected divergence reason"
      }
    _ -> panic as "expected Divergence variant"
  }
}

// =====================================================================
// Outcome shape — make sure constructors exist and round-trip
// =====================================================================

pub fn nominal_outcome_carries_counts_test() {
  let outcome = Nominal(pulled: 3, pushed: 1, duration_ms: 42)
  case outcome {
    Nominal(pulled: 3, pushed: 1, duration_ms: 42) -> Nil
    _ -> panic as "Nominal field decomposition failed"
  }
}

pub fn degraded_outcome_carries_reason_test() {
  let outcome = Degraded(reason: "no_adc")
  case outcome {
    Degraded(reason: "no_adc") -> Nil
    _ -> panic as "Degraded reason decomposition failed"
  }
}

pub fn circuit_open_outcome_reports_seconds_test() {
  let outcome = CircuitOpen(reset_in_seconds: 45)
  case outcome {
    CircuitOpen(reset_in_seconds: 45) -> Nil
    _ -> panic as "CircuitOpen reset_in_seconds decomposition failed"
  }
}

// =====================================================================
// State transitions — exercised at the type level. Real State requires
// a VaultHandle which is opaque; the pure helpers above cover the
// failure-counter and breaker-cooldown invariants we care about.
// =====================================================================

pub fn module_exports_compile_test() {
  // If this file compiles, all the following symbols exist and have
  // the expected types — a wiring-guard for vault_sync_actor public API.
  let _f1 = circuit_should_open
  let _f2 = circuit_open_for
  let _f3 = circuit_cooldown_seconds
  let _f4 = decide_direction
  let _f5 = handle_tick
  let _f6 = handle_network_probe
  let _f7 = record_failure
  let _f8 = record_success
  Nil
}
