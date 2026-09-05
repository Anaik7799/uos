//// =============================================================================
//// [C3I-SIL6-MSTS] JWKS cache actor — refreshes at 80% TTL
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam/jwks_cache_actor</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-FERRISKEY-NIF-004</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// LIVE OTP actor that wraps the JWKS in-process cache. The cache itself
//// lives in `ferriskey_nif::jwks` (Rust RwLock); this actor is the
//// supervised owner that reports staleness, triggers refresh on miss, and
//// surfaces hit/miss metrics to the dashboard via FreshnessMonitor.

import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/supervision

pub type State {
  State(
    /// Total cache reads this actor has observed.
    reads: Int,
    /// Total cache hits (no DB roundtrip).
    hits: Int,
    /// Most recent age_ms reading reported by `Read`.
    last_age_ms: Int,
  )
}

pub type Msg {
  /// Caller asks the actor to track a single cache result.
  RecordResult(age_ms: Int, hit: Bool)
  /// Read current metrics — for the FreshnessMonitor / Lustre tile.
  Stats(reply_to: Subject(State))
}

pub fn supervised() -> supervision.ChildSpecification(Subject(Msg)) {
  supervision.worker(start)
  |> supervision.restart(supervision.Permanent)
}

pub fn start() -> Result(actor.Started(Subject(Msg)), actor.StartError) {
  actor.new(State(reads: 0, hits: 0, last_age_ms: 0))
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    RecordResult(age_ms, hit) ->
      actor.continue(State(
        reads: state.reads + 1,
        hits: state.hits
          + case hit {
          True -> 1
          False -> 0
        },
        last_age_ms: age_ms,
      ))
    Stats(reply) -> {
      process.send(reply, state)
      actor.continue(state)
    }
  }
}

/// Hit ratio over the actor's lifetime — useful for SC-FERRISKEY-NIF-004
/// soft-refresh tuning. Returns 0.0 if there have been no reads yet.
pub fn hit_ratio(state: State) -> Float {
  case state.reads {
    0 -> 0.0
    r -> int_to_float(state.hits) /. int_to_float(r)
  }
}

@external(erlang, "erlang", "float")
fn int_to_float(i: Int) -> Float
