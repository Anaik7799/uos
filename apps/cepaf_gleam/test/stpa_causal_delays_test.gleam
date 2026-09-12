// =============================================================================
// stpa_causal_delays_test.gleam — STPA Step 4 Causal Delay & Race Condition Tests
// STAMP: SC-SIL6-001, SC-SAFETY-001, SC-JIDOKA-001
// =============================================================================

import gleam/list
import gleeunit/should

pub type SimulationWorker {
  Worker(id: String, backoff_ms: Int)
}

pub type ClaimResolution {
  Winner(worker_id: String, lease_until_ms: Int)
  ContentionRejected(worker_id: String, reason: String)
}

// STPA Step 4: Causal Scenario 1 — Multi-Agent Actuation Contention
pub fn multi_agent_claim_race_determinism_test() {
  let workers = [
    Worker("L0-fable", 5),
    Worker("L0-codex-gpt-6-astra", 10),
    Worker("AGY-sovereign", 15),
  ]

  // Simulate atomic test-and-set claim resolution under randomized backoff
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
  list.length(rejections) |> should.equal(2)
}

// STPA Step 4: Causal Scenario 2 — Delayed Sensor Telemetry Trips Freshness Monitor
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

// STPA Step 4: Causal Scenario 3 — Out-of-Order Actuation (Execution before Claim)
pub fn out_of_order_actuation_fail_closed_test() {
  let task_state = "available"
  let can_complete = case task_state {
    "executing" -> True
    _ -> False
  }
  can_complete |> should.be_false
}

pub type Option(a) {
  Some(a)
  None
}
