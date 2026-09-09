//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Distributed Actor Dead-Man Freshness Switch Verification
//// =============================================================================

import cepaf_gleam/ha/deadman_freshness.{
  ActionInitiateFailover, ActionTripDeadMan, ActionWarnStaleness,
  HeartbeatQuarantined, HeartbeatTripped, active_healthy_actors_count,
  evaluate_freshness_tick, init_deadman_registry, is_l0_constitutional_safe,
  record_heartbeat, register_actor,
}
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn repeated_trip_emits_no_duplicate_actions_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("worker", "L4_SYSTEM", 1000, 2, Some("backup"), 1000)
  let #(tripped, first_actions) = evaluate_freshness_tick(reg, 3000)
  list.length(first_actions) |> should.equal(2)
  let #(again, repeated_actions) = evaluate_freshness_tick(tripped, 4000)
  repeated_actions |> should.equal([])
  again.total_tripped_count |> should.equal(1)
  let assert [actor] = again.actors
  actor.status |> should.equal(HeartbeatTripped(3000))
}

pub fn backward_tick_cannot_clear_a_trip_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("worker", "L4_SYSTEM", 1000, 2, None, 1000)
  let #(tripped, _) = evaluate_freshness_tick(reg, 3000)
  evaluate_freshness_tick(tripped, 1500) |> should.equal(#(tripped, []))
}

pub fn stale_heartbeat_cannot_recover_a_trip_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("worker", "L4_SYSTEM", 1000, 2, None, 1000)
  let #(tripped, _) = evaluate_freshness_tick(reg, 3000)
  record_heartbeat(tripped, "worker", 1500) |> should.equal(tripped)
}

pub fn fresh_recovery_rearms_one_new_trip_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("worker", "L4_SYSTEM", 1000, 2, None, 1000)
  let #(tripped, _) = evaluate_freshness_tick(reg, 3000)
  let recovered = record_heartbeat(tripped, "worker", 3500)
  active_healthy_actors_count(recovered) |> should.equal(1)
  let #(retripped, actions) = evaluate_freshness_tick(recovered, 5500)
  list.length(actions) |> should.equal(1)
  retripped.total_tripped_count |> should.equal(2)
}

pub fn exact_single_interval_trips_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("worker", "L4_SYSTEM", 1000, 1, None, 1000)
  let #(tripped, actions) = evaluate_freshness_tick(reg, 2000)
  list.length(actions) |> should.equal(1)
  tripped.total_tripped_count |> should.equal(1)
}

pub fn repeated_warning_and_duplicate_tick_are_quiet_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("worker", "L4_SYSTEM", 1000, 3, None, 1000)
  let #(warned, actions) = evaluate_freshness_tick(reg, 2100)
  list.length(actions) |> should.equal(1)
  let #(again, repeated) = evaluate_freshness_tick(warned, 2200)
  repeated |> should.equal([])
  evaluate_freshness_tick(again, 2200) |> should.equal(#(again, []))
}

pub fn invalid_intervals_are_quarantined_and_not_heartbeat_recovered_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("worker", "L0_CONSTITUTIONAL", 0, 1, None, 1000)
  let assert [actor] = reg.actors
  actor.status |> should.equal(HeartbeatQuarantined)
  let #(evaluated, actions) = evaluate_freshness_tick(reg, 3000)
  actions |> should.equal([])
  record_heartbeat(evaluated, "worker", 4000) |> should.equal(evaluated)
  is_l0_constitutional_safe(evaluated) |> should.be_false()
}

pub fn stale_reregistration_cannot_clear_a_trip_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("worker", "L4_SYSTEM", 1000, 2, None, 1000)
  let #(tripped, _) = evaluate_freshness_tick(reg, 3000)
  register_actor(tripped, "worker", "L4_SYSTEM", 1000, 2, None, 3000)
  |> should.equal(tripped)
}

pub fn actor_order_is_stable_across_ticks_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("first", "L4_SYSTEM", 1000, 3, None, 1000)
    |> register_actor("second", "L4_SYSTEM", 1000, 3, None, 1000)
  let #(evaluated, _) = evaluate_freshness_tick(reg, 1200)
  list.map(evaluated.actors, fn(actor) { actor.actor_id })
  |> should.equal(list.map(reg.actors, fn(actor) { actor.actor_id }))
}

pub fn explicit_valid_configuration_can_recover_quarantine_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("worker", "L0_CONSTITUTIONAL", 0, 0, None, 1000)
  let repaired =
    register_actor(reg, "worker", "L0_CONSTITUTIONAL", 1000, 2, None, 2000)
  active_healthy_actors_count(repaired) |> should.equal(1)
}

pub fn heartbeat_at_trip_observation_time_does_not_rearm_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("worker", "L4_SYSTEM", 1000, 2, None, 1000)
  let #(tripped, _) = evaluate_freshness_tick(reg, 3000)
  record_heartbeat(tripped, "worker", 3000) |> should.equal(tripped)
}

pub fn main() {
  gleeunit.main()
}

pub fn deadman_init_test() {
  let reg = init_deadman_registry()
  active_healthy_actors_count(reg) |> should.equal(0)
  is_l0_constitutional_safe(reg) |> should.be_true()
}

pub fn deadman_registration_nominal_test() {
  let reg =
    init_deadman_registry()
    |> register_actor(
      "l0_guardian",
      "L0_CONSTITUTIONAL",
      1000,
      3,
      Some("l0_standby"),
      1000,
    )
    |> register_actor("l4_worker_pool", "L4_SYSTEM", 500, 4, None, 1000)

  active_healthy_actors_count(reg) |> should.equal(2)
  is_l0_constitutional_safe(reg) |> should.be_true()

  let #(updated, actions) = evaluate_freshness_tick(reg, 1200)
  actions |> should.equal([])
  active_healthy_actors_count(updated) |> should.equal(2)
}

pub fn deadman_warning_escalation_test() {
  let reg =
    init_deadman_registry()
    |> register_actor("l4_worker", "L4_SYSTEM", 1000, 3, None, 1000)

  // 1500 ms elapsed -> 1 missed heartbeat (interval 1000, max 3) -> Warning
  let #(updated, actions) = evaluate_freshness_tick(reg, 2500)
  active_healthy_actors_count(updated) |> should.equal(0)

  case actions {
    [ActionWarnStaleness(actor, layer, missed)] -> {
      actor |> should.equal("l4_worker")
      layer |> should.equal("L4_SYSTEM")
      missed |> should.equal(1)
    }
    _ -> should.fail()
  }

  // Heartbeat received -> recovers to nominal
  let recovered = record_heartbeat(updated, "l4_worker", 2600)
  active_healthy_actors_count(recovered) |> should.equal(1)
}

pub fn deadman_trip_and_failover_test() {
  let reg =
    init_deadman_registry()
    |> register_actor(
      "l0_consensus",
      "L0_CONSTITUTIONAL",
      1000,
      3,
      Some("l0_consensus_backup"),
      1000,
    )

  // 4500 ms elapsed -> 3+ missed heartbeats -> Trip Dead-Man Switch & Failover
  let #(updated, actions) = evaluate_freshness_tick(reg, 5500)
  active_healthy_actors_count(updated) |> should.equal(0)
  is_l0_constitutional_safe(updated) |> should.be_false()

  // Actions should contain both Failover and Trip
  let has_failover = case actions {
    [ActionInitiateFailover(from, to, _), ActionTripDeadMan(actor, _, _)] -> {
      from == "l0_consensus"
      && to == "l0_consensus_backup"
      && actor == "l0_consensus"
    }
    _ -> False
  }
  has_failover |> should.be_true()
}
