//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Distributed Actor Dead-Man Freshness Switch Verification
//// =============================================================================

import cepaf_gleam/ha/deadman_freshness.{
  ActionInitiateFailover, ActionTripDeadMan, ActionWarnStaleness,
  HeartbeatNominal, HeartbeatTripped, HeartbeatWarning,
  active_healthy_actors_count, evaluate_freshness_tick,
  init_deadman_registry, is_l0_constitutional_safe, record_heartbeat,
  register_actor,
}
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

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
    |> register_actor("l0_guardian", "L0_CONSTITUTIONAL", 1000, 3, Some("l0_standby"), 1000)
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
    |> register_actor("l0_consensus", "L0_CONSTITUTIONAL", 1000, 3, Some("l0_consensus_backup"), 1000)

  // 4500 ms elapsed -> 3+ missed heartbeats -> Trip Dead-Man Switch & Failover
  let #(updated, actions) = evaluate_freshness_tick(reg, 5500)
  active_healthy_actors_count(updated) |> should.equal(0)
  is_l0_constitutional_safe(updated) |> should.be_false()

  // Actions should contain both Failover and Trip
  let has_failover =
    case actions {
      [ActionInitiateFailover(from, to, _), ActionTripDeadMan(actor, _, _)] -> {
        from == "l0_consensus" && to == "l0_consensus_backup" && actor == "l0_consensus"
      }
      _ -> False
    }
  has_failover |> should.be_true()
}
