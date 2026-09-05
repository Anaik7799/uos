//// vault_sync_logic_test — Pass-16 exhaustive coverage of pure sync-actor logic.
////
//// Slice D partial: conflict resolution + circuit breaker + state transitions.
//// All these functions are pure (no GCP, no NIF), so the entire SC-VAULT-010
//// + SC-VAULT-011 contract is testable in-process.

import cepaf_gleam/vault.{type VaultHandle}
import cepaf_gleam/vault_sync_actor.{
  CircuitOpen, Degraded, Divergence, NoOp, Nominal, Pull, Push,
  circuit_cooldown_seconds, circuit_open_for, circuit_should_open,
  decide_direction, handle_network_probe, handle_tick, init, record_failure,
  record_success,
}
import gleeunit/should

// VaultHandle is opaque; placeholder via Erlang ref for state-only tests.
@external(erlang, "erlang", "make_ref")
fn fake_handle() -> VaultHandle

// =====================================================================
// decide_direction — full 8-cell truth table (SC-VAULT-011)
// =====================================================================

pub fn equal_versions_yields_noop_test() {
  decide_direction(5, 5, False) |> should.equal(NoOp)
  decide_direction(5, 5, True) |> should.equal(NoOp)
}

pub fn remote_ahead_yields_pull_regardless_of_flag_test() {
  decide_direction(1, 2, False) |> should.equal(Pull(remote_version: 2))
  decide_direction(1, 2, True) |> should.equal(Pull(remote_version: 2))
}

pub fn remote_far_ahead_yields_pull_with_remote_version_test() {
  decide_direction(0, 100, False) |> should.equal(Pull(remote_version: 100))
}

pub fn local_ahead_with_unsynced_flag_yields_push_test() {
  decide_direction(3, 2, True) |> should.equal(Push(local_version: 3))
}

pub fn local_ahead_no_flag_yields_divergence_test() {
  case decide_direction(3, 2, False) {
    Divergence(_) -> Nil
    other -> {
      let _ = other
      panic as "expected Divergence for local-ahead-no-flag"
    }
  }
}

pub fn divergence_carries_explanation_test() {
  case decide_direction(7, 2, False) {
    Divergence(reason) -> {
      // Reason must be a non-empty stable token so dashboards can route it
      should.equal(reason, "local advanced without sync flag")
    }
    _ -> panic as "expected Divergence variant"
  }
}

pub fn zero_versions_both_sides_yields_noop_test() {
  decide_direction(0, 0, False) |> should.equal(NoOp)
  decide_direction(0, 0, True) |> should.equal(NoOp)
}

pub fn pull_dominates_when_both_local_and_remote_grew_test() {
  // SC-VAULT-011: when remote > local, ALWAYS pull. The has_unsynced_flag
  // doesn't override this — Pull wins because last-write-wins on remote.
  decide_direction(3, 5, True) |> should.equal(Pull(remote_version: 5))
}

// =====================================================================
// Circuit breaker dynamics — SC-VAULT-010 (3 fail / 60s cooldown)
// =====================================================================

pub fn circuit_stays_closed_below_threshold_test() {
  circuit_should_open(0) |> should.equal(False)
  circuit_should_open(1) |> should.equal(False)
  circuit_should_open(2) |> should.equal(False)
}

pub fn circuit_opens_at_exactly_three_failures_test() {
  circuit_should_open(3) |> should.equal(True)
}

pub fn circuit_opens_for_high_failure_counts_test() {
  circuit_should_open(10) |> should.equal(True)
  circuit_should_open(1000) |> should.equal(True)
}

pub fn circuit_cooldown_is_60_seconds_test() {
  circuit_cooldown_seconds() |> should.equal(60)
}

pub fn circuit_open_for_adds_60_to_now_test() {
  circuit_open_for(0) |> should.equal(60)
  circuit_open_for(1000) |> should.equal(1060)
  circuit_open_for(1_700_000_000) |> should.equal(1_700_000_060)
}

// =====================================================================
// State machine — record_failure + record_success + handle_tick + probe
// =====================================================================

pub fn record_failure_increments_consecutive_failures_test() {
  let s0 = init(fake_handle())
  let s1 = record_failure(s0, 100)
  s1.consecutive_failures |> should.equal(1)
  let s2 = record_failure(s1, 101)
  s2.consecutive_failures |> should.equal(2)
}

pub fn third_failure_opens_the_circuit_test() {
  let s0 = init(fake_handle())
  let s1 = record_failure(s0, 100)
  let s2 = record_failure(s1, 101)
  let s3 = record_failure(s2, 102)
  // After 3 failures, circuit_open_until is now+60
  s3.consecutive_failures |> should.equal(3)
  s3.circuit_open_until |> should.equal(162)
}

pub fn record_success_resets_failures_and_clears_circuit_test() {
  let s0 = init(fake_handle())
  let s1 = record_failure(s0, 100)
  let s2 = record_failure(s1, 101)
  let s3 = record_failure(s2, 102)
  // Now record success
  let s4 = record_success(s3, 200)
  s4.consecutive_failures |> should.equal(0)
  s4.circuit_open_until |> should.equal(0)
  s4.last_sync_at |> should.equal(200)
}

pub fn handle_tick_returns_circuit_open_when_breaker_tripped_test() {
  let s0 = init(fake_handle())
  let s1 = record_failure(s0, 100)
  let s2 = record_failure(s1, 101)
  let s3 = record_failure(s2, 102)
  // s3.circuit_open_until = 162; tick at now=120 should report CircuitOpen
  let #(_, outcome) = handle_tick(s3, 120)
  case outcome {
    CircuitOpen(reset_in_seconds: r) -> {
      // 162 - 120 = 42 seconds remaining
      should.equal(r, 42)
    }
    _ -> panic as "expected CircuitOpen outcome"
  }
}

pub fn handle_tick_returns_degraded_when_offline_test() {
  let s0 = init(fake_handle())
  let s_offline = handle_network_probe(s0, False)
  let #(_, outcome) = handle_tick(s_offline, 100)
  case outcome {
    Degraded(reason: r) -> should.equal(r, "offline")
    _ -> panic as "expected Degraded(offline)"
  }
}

pub fn handle_tick_returns_nominal_when_online_and_circuit_closed_test() {
  let s0 = init(fake_handle())
  let #(s1, outcome) = handle_tick(s0, 500)
  case outcome {
    Nominal(_, _, _) -> Nil
    _ -> panic as "expected Nominal outcome"
  }
  s1.last_sync_at |> should.equal(500)
}

pub fn network_probe_toggles_online_flag_test() {
  let s0 = init(fake_handle())
  s0.online |> should.equal(True)
  let s_off = handle_network_probe(s0, False)
  s_off.online |> should.equal(False)
  let s_on = handle_network_probe(s_off, True)
  s_on.online |> should.equal(True)
}

pub fn init_starts_with_clean_state_test() {
  let s = init(fake_handle())
  s.consecutive_failures |> should.equal(0)
  s.circuit_open_until |> should.equal(0)
  s.last_sync_at |> should.equal(0)
  s.online |> should.equal(True)
}
