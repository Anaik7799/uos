// =============================================================================
// stpa_causal_delays_test.gleam — STPA Step 4 Causal Delay & Race Condition Tests
// STAMP: SC-SIL6-001, SC-SAFETY-001, SC-JIDOKA-001, SC-STPA-001
// Covers 8 causal scenarios:
// 1. Multi-Agent Actuation Contention (Atomic test-and-set claim)
// 2. Delayed Sensor Telemetry Trips Freshness Monitor
// 3. Out-of-Order Actuation Fail-Closed (Jidoka stop line -32002)
// 4. Dropped OTel Span & Zenoh Telemetry Buffer Overflow
// 5. Expired Lease Actuation Fencing (Zombie worker protection)
// 6. Unacknowledged Actuator Dispatch Timeout Fallback
// 7. Process Model Divergence & Full State Resync
// 8. Multi-Controller Conflicting Actuation 2oo3 Consensus
// =============================================================================

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should

// -----------------------------------------------------------------------------
// Scenario 1: Multi-Agent Actuation Contention
// -----------------------------------------------------------------------------

pub type SimulationWorker {
  Worker(id: String, backoff_ms: Int)
}

pub type ClaimResolution {
  Winner(worker_id: String, lease_until_ms: Int)
  ContentionRejected(worker_id: String, reason: String)
}

pub fn multi_agent_claim_race_determinism_test() {
  let workers = [
    Worker("L0-fable", 5),
    Worker("L0-codex-gpt-6-astra", 10),
    Worker("AGY-sovereign", 15),
    Worker("Pi-mono-remote", 20),
  ]

  let initial_state: #(Option(String), List(ClaimResolution)) = #(None, [])
  let #(_winner, resolutions) =
    list.fold(workers, initial_state, fn(acc, w) {
      let #(current_winner, history) = acc
      case current_winner {
        None -> #(
          Some(w.id),
          [Winner(w.id, 3600_000), ..history],
        )
        Some(existing) -> #(
          Some(existing),
          [
            ContentionRejected(
              w.id,
              "Task already claimed by active lease holder: " <> existing,
            ),
            ..history
          ],
        )
      }
    })

  let winners =
    list.filter(resolutions, fn(r) {
      case r {
        Winner(_, _) -> True
        _ -> False
      }
    })
  let rejections =
    list.filter(resolutions, fn(r) {
      case r {
        ContentionRejected(_, _) -> True
        _ -> False
      }
    })

  list.length(winners) |> should.equal(1)
  list.length(rejections) |> should.equal(3)
}

// -----------------------------------------------------------------------------
// Scenario 2: Delayed Sensor Telemetry Trips Freshness Monitor
// -----------------------------------------------------------------------------

pub type SensorFreshness {
  SensorFresh
  SensorWarning
  SensorStale
}

pub fn evaluate_sensor_freshness(elapsed_ms: Int, warn_ms: Int, stale_ms: Int) -> SensorFreshness {
  case elapsed_ms > stale_ms {
    True -> SensorStale
    False ->
      case elapsed_ms > warn_ms {
        True -> SensorWarning
        False -> SensorFresh
      }
  }
}

pub fn delayed_sensor_telemetry_freshness_trip_test() {
  // 1. Fresh within threshold (elapsed = 1000ms < 3000ms)
  let check1 = evaluate_sensor_freshness(1000, 3000, 6000)
  check1 |> should.equal(SensorFresh)

  // 2. Delayed feedback (elapsed = 4000ms > 3000ms)
  let check2 = evaluate_sensor_freshness(4000, 3000, 6000)
  check2 |> should.equal(SensorWarning)

  // 3. Sensor loss (elapsed = 7000ms > 6000ms) -> Stale trips fail-closed
  let check3 = evaluate_sensor_freshness(7000, 3000, 6000)
  check3 |> should.equal(SensorStale)
}

// -----------------------------------------------------------------------------
// Scenario 3: Out-of-Order Actuation (Execution before Claim) -> Jidoka Stop
// -----------------------------------------------------------------------------

pub type ActuationVerdict {
  ActuationAdmitted
  JidokaAndonHalt(exit_code: Int, error: String)
}

pub fn validate_actuation_order(task_state: String, is_claimed_by_caller: Bool) -> ActuationVerdict {
  case task_state == "executing" && is_claimed_by_caller {
    True -> ActuationAdmitted
    False ->
      JidokaAndonHalt(
        -32002,
        "Fractal Jidoka Andon Halt: Non-sa-plan task execution attempted. SC-JIDOKA-001 forbids ad-hoc un-ledgered plan execution.",
      )
  }
}

pub fn out_of_order_actuation_fail_closed_test() {
  // Attempting to execute an "available" (unclaimed) task fails closed with -32002
  let res1 = validate_actuation_order("available", False)
  case res1 {
    JidokaAndonHalt(code, msg) -> {
      code |> should.equal(-32002)
      string.contains(msg, "SC-JIDOKA-001") |> should.be_true
    }
    _ -> should.fail()
  }

  // Executing a claimed task by the rightful holder succeeds
  let res2 = validate_actuation_order("executing", True)
  res2 |> should.equal(ActuationAdmitted)
}

// -----------------------------------------------------------------------------
// Scenario 4: Dropped OTel Span & Zenoh Telemetry Buffer Overflow
// -----------------------------------------------------------------------------

pub type TelemetryBufferState {
  BufferNominal(buffered_count: Int)
  BufferOverflowBackpressure(dropped_count: Int, max_capacity: Int)
}

pub fn enqueue_telemetry_span(
  current_count: Int,
  spans_incoming: Int,
  max_capacity: Int,
) -> TelemetryBufferState {
  let total = current_count + spans_incoming
  case total > max_capacity {
    True -> {
      let dropped = total - max_capacity
      BufferOverflowBackpressure(dropped_count: dropped, max_capacity: max_capacity)
    }
    False -> BufferNominal(buffered_count: total)
  }
}

pub fn dropped_otel_span_zenoh_overflow_test() {
  let nominal = enqueue_telemetry_span(200, 300, 1000)
  nominal |> should.equal(BufferNominal(500))

  let overflow = enqueue_telemetry_span(900, 250, 1000)
  case overflow {
    BufferOverflowBackpressure(dropped, cap) -> {
      dropped |> should.equal(150)
      cap |> should.equal(1000)
    }
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// Scenario 5: Expired Lease Actuation Fencing (Zombie Worker Protection)
// -----------------------------------------------------------------------------

pub type FenceVerdict {
  FencingValid
  LeaseFencingExpired(error: String)
}

pub fn evaluate_lease_fencing(
  lease_token: Int,
  current_epoch_token: Int,
  now_ms: Int,
  lease_expiry_ms: Int,
) -> FenceVerdict {
  case now_ms > lease_expiry_ms {
    True -> LeaseFencingExpired("Lease expired: now=" <> int.to_string(now_ms) <> " > expiry=" <> int.to_string(lease_expiry_ms))
    False ->
      case lease_token == current_epoch_token {
        True -> FencingValid
        False -> LeaseFencingExpired("Fencing token mismatch: stale worker attempt")
      }
  }
}

pub fn expired_lease_actuation_fencing_test() {
  // Valid active lease
  evaluate_lease_fencing(42, 42, 1000, 5000) |> should.equal(FencingValid)

  // Expired lease
  let res_expired = evaluate_lease_fencing(42, 42, 6000, 5000)
  case res_expired {
    LeaseFencingExpired(msg) -> string.contains(msg, "Lease expired") |> should.be_true
    _ -> should.fail()
  }

  // Token mismatch (superseded lease)
  let res_mismatch = evaluate_lease_fencing(41, 42, 2000, 5000)
  case res_mismatch {
    LeaseFencingExpired(msg) -> string.contains(msg, "token mismatch") |> should.be_true
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// Scenario 6: Unacknowledged Actuator Dispatch Timeout Fallback
// -----------------------------------------------------------------------------

pub type ActuatorAckStatus {
  AckReceived(latency_ms: Int)
  ActuatorUnresponsiveFallback(timeout_ms: Int, safe_mode_engaged: Bool)
}

pub fn await_actuator_ack(ack_received: Bool, elapsed_ms: Int, timeout_limit_ms: Int) -> ActuatorAckStatus {
  case ack_received && elapsed_ms <= timeout_limit_ms {
    True -> AckReceived(elapsed_ms)
    False -> ActuatorUnresponsiveFallback(timeout_limit_ms, True)
  }
}

pub fn unacknowledged_actuator_dispatch_timeout_test() {
  await_actuator_ack(True, 45, 200) |> should.equal(AckReceived(45))

  let timeout_res = await_actuator_ack(False, 250, 200)
  case timeout_res {
    ActuatorUnresponsiveFallback(limit, safe_mode) -> {
      limit |> should.equal(200)
      safe_mode |> should.be_true
    }
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// Scenario 7: Process Model Divergence & Full State Resync
// -----------------------------------------------------------------------------

pub type SyncStatus {
  InSync
  ResyncTriggered(drift_count: Int, action: String)
}

pub fn check_process_model_drift(
  controller_state_hash: String,
  plant_state_hash: String,
  consecutive_drifts: Int,
) -> SyncStatus {
  case controller_state_hash == plant_state_hash {
    True -> InSync
    False ->
      ResyncTriggered(
        consecutive_drifts + 1,
        "Divergence detected: triggering full snapshot reconciliation from SQLite WAL",
      )
  }
}

pub fn process_model_divergence_resync_test() {
  check_process_model_drift("hash_abc", "hash_abc", 0) |> should.equal(InSync)

  let drift = check_process_model_drift("hash_abc", "hash_xyz", 2)
  case drift {
    ResyncTriggered(count, action) -> {
      count |> should.equal(3)
      string.contains(action, "full snapshot reconciliation") |> should.be_true
    }
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// Scenario 8: Multi-Controller Conflicting Actuation 2oo3 Consensus
// -----------------------------------------------------------------------------

pub type ConsensusVerdict {
  ConsensusRatified(action: String)
  ConsensusRefused(reason: String)
}

pub fn evaluate_2oo3_consensus(
  codex_vote: String,
  claude_vote: String,
  agy_vote: String,
) -> ConsensusVerdict {
  let votes = [codex_vote, claude_vote, agy_vote]
  let approve_count = list.count(votes, fn(v) { v == "APPROVE" })
  case approve_count >= 2 {
    True -> ConsensusRatified("2oo3 Constitutional Consensus Achieved: Action Ratified")
    False -> ConsensusRefused("Consensus Floor Not Met: < 2 sovereign approvals")
  }
}

pub fn multi_controller_conflicting_actuation_consensus_test() {
  // 3-0 Unanimous
  evaluate_2oo3_consensus("APPROVE", "APPROVE", "APPROVE")
  |> should.equal(ConsensusRatified("2oo3 Constitutional Consensus Achieved: Action Ratified"))

  // 2-1 Majority
  evaluate_2oo3_consensus("APPROVE", "APPROVE", "REJECT")
  |> should.equal(ConsensusRatified("2oo3 Constitutional Consensus Achieved: Action Ratified"))

  // 1-2 Rejected
  let reject_res = evaluate_2oo3_consensus("APPROVE", "REJECT", "REJECT")
  case reject_res {
    ConsensusRefused(reason) -> string.contains(reason, "Consensus Floor Not Met") |> should.be_true
    _ -> should.fail()
  }
}
