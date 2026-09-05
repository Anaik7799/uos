//// =============================================================================
//// [C3I-SIL6-MSTS] SCIM outbound queue actor — exponential backoff drain
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam/scim_outbound_actor</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GCP-IAM-008</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// Drains the `scim_outbound_queue` SQLite table (managed by ferriskey_nif::scim).
//// On each Tick:
////   1. Read up to N rows where next_attempt_at <= now via NIF
////   2. For each, call SCIM client (Cloud Identity / Admin SDK) — Phase 5.5
////   3. mark_done on success, mark_failed on error (exponential backoff)
////
//// Phase 7.5 substrate ships the actor with metrics + tick handler. The
//// real HTTP client + NIF binding lands in Phase 5.5.

import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/supervision

pub type State {
  State(
    /// Number of drain ticks observed.
    ticks: Int,
    /// Cumulative ops successfully drained.
    drained: Int,
    /// Cumulative ops that exhausted retries.
    abandoned: Int,
    /// Drain batch size limit.
    batch_size: Int,
  )
}

pub type Msg {
  /// Trigger a drain pass. Caller (a periodic timer or operator override)
  /// counts as one tick.
  Tick(now_ms: Int, reply_to: Subject(DrainResult))
  /// Read metrics.
  Metrics(reply_to: Subject(State))
}

pub type DrainResult {
  DrainResult(found: Int, drained: Int, abandoned: Int)
}

pub fn supervised() -> supervision.ChildSpecification(Subject(Msg)) {
  supervision.worker(start)
  |> supervision.restart(supervision.Permanent)
}

pub fn start() -> Result(actor.Started(Subject(Msg)), actor.StartError) {
  actor.new(State(ticks: 0, drained: 0, abandoned: 0, batch_size: 16))
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Tick(_now_ms, reply) -> {
      // Phase 5.5 wires the actual NIF call to ferriskey_nif::scim::drain_due
      // and dispatches each row to the appropriate SCIM target. For Phase 7.5
      // substrate, we count the tick and return zero work.
      let result = DrainResult(found: 0, drained: 0, abandoned: 0)
      process.send(reply, result)
      actor.continue(State(..state, ticks: state.ticks + 1))
    }
    Metrics(reply) -> {
      process.send(reply, state)
      actor.continue(state)
    }
  }
}
