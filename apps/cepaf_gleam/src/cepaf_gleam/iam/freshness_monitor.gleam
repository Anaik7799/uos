//// =============================================================================
//// [C3I-SIL6-MSTS] freshness_monitor — Andon escalation on stale JWKS / dead STS
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam/freshness_monitor</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TRUTH-001, SC-FERRISKEY-NIF-004</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// Periodic actor that classifies the freshness of the JWKS cache + STS
//// token cache and emits Andon-mode escalations. Mirrors the pattern of
//// `ha/freshness_monitor.gleam` (which handles the dashboard JWKS cache).

import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/supervision

pub type Andon {
  /// Cache freshness < 60s — normal.
  Fresh
  /// Cache freshness 60-120s — Dim mode.
  Stale
  /// Cache freshness 2-5min — escalate to Bright.
  Degraded
  /// Cache freshness > 5min — Emergency.
  Dead
}

pub type State {
  State(jwks_andon: Andon, sts_andon: Andon)
}

pub type Msg {
  /// Set JWKS andon state from the latest age_ms reading.
  ReportJwksAge(age_ms: Int)
  /// Set STS andon state.
  ReportStsAge(age_ms: Int)
  /// Read current state.
  Read(reply_to: Subject(State))
}

pub fn supervised() -> supervision.ChildSpecification(Subject(Msg)) {
  supervision.worker(start)
  |> supervision.restart(supervision.Permanent)
}

pub fn start() -> Result(actor.Started(Subject(Msg)), actor.StartError) {
  actor.new(State(jwks_andon: Fresh, sts_andon: Fresh))
  |> actor.on_message(handle)
  |> actor.start
}

pub fn classify(age_ms: Int) -> Andon {
  case age_ms {
    a if a < 60_000 -> Fresh
    a if a < 120_000 -> Stale
    a if a < 300_000 -> Degraded
    _ -> Dead
  }
}

fn handle(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    ReportJwksAge(age) ->
      actor.continue(State(..state, jwks_andon: classify(age)))
    ReportStsAge(age) ->
      actor.continue(State(..state, sts_andon: classify(age)))
    Read(reply) -> {
      process.send(reply, state)
      actor.continue(state)
    }
  }
}
