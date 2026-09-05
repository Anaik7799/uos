//// =============================================================================
//// [C3I-SIL6-MSTS] STS token cache actor — eviction on expires_at
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/iam/sts_token_cache_actor</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GCP-IAM-003, SC-GCP-IAM-009</stamp-controls></compliance>
//// </c3i-module>
//// =============================================================================
////
//// LIVE OTP actor that owns the per-realm rate limiter for STS exchanges.
//// SC-GCP-IAM-009 mandates a token-bucket limit of 60 rpm/realm — this
//// actor is the canonical place that decision is made.

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/supervision

/// Per-realm sliding-window count: list of issued-at unix-ms timestamps
/// within the last 60 seconds.
pub type State {
  State(
    /// Per-realm sliding window of issue timestamps (ms).
    windows: Dict(String, List(Int)),
    rpm_limit: Int,
    window_ms: Int,
  )
}

pub type Decision {
  Allowed(remaining_in_window: Int)
  Throttled(retry_after_ms: Int)
}

pub type Msg {
  /// Ask the actor whether the realm may make another STS exchange `now_ms`.
  CheckAllow(realm: String, now_ms: Int, reply_to: Subject(Decision))
  /// Force-clear a realm's window — used during operator emergency overrides.
  Reset(realm: String)
}

pub fn supervised() -> supervision.ChildSpecification(Subject(Msg)) {
  supervision.worker(start)
  |> supervision.restart(supervision.Permanent)
}

pub fn start() -> Result(actor.Started(Subject(Msg)), actor.StartError) {
  actor.new(State(windows: dict.new(), rpm_limit: 60, window_ms: 60_000))
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    CheckAllow(realm, now_ms, reply) -> {
      let prev = case dict.get(state.windows, realm) {
        Ok(xs) -> xs
        Error(_) -> []
      }
      // Drop entries older than the window.
      let cutoff = now_ms - state.window_ms
      let pruned = list_filter(prev, fn(t) { t > cutoff })
      let count = list_length(pruned)
      case count >= state.rpm_limit {
        True -> {
          // Compute the retry_after as ms until the oldest entry leaves.
          let oldest = list_min(pruned, now_ms)
          let retry = oldest + state.window_ms - now_ms
          process.send(reply, Throttled(retry_after_ms: retry))
          actor.continue(
            State(..state, windows: dict.insert(state.windows, realm, pruned)),
          )
        }
        False -> {
          let new_list = [now_ms, ..pruned]
          process.send(
            reply,
            Allowed(remaining_in_window: state.rpm_limit - count - 1),
          )
          actor.continue(
            State(..state, windows: dict.insert(state.windows, realm, new_list)),
          )
        }
      }
    }
    Reset(realm) ->
      actor.continue(State(..state, windows: dict.delete(state.windows, realm)))
  }
}

fn list_filter(xs: List(a), p: fn(a) -> Bool) -> List(a) {
  case xs {
    [] -> []
    [h, ..t] ->
      case p(h) {
        True -> [h, ..list_filter(t, p)]
        False -> list_filter(t, p)
      }
  }
}

fn list_length(xs: List(a)) -> Int {
  case xs {
    [] -> 0
    [_, ..t] -> 1 + list_length(t)
  }
}

fn list_min(xs: List(Int), default: Int) -> Int {
  case xs {
    [] -> default
    [h, ..t] -> min_step(t, h)
  }
}

fn min_step(xs: List(Int), acc: Int) -> Int {
  case xs {
    [] -> acc
    [h, ..t] -> {
      let next = case h < acc {
        True -> h
        False -> acc
      }
      min_step(t, next)
    }
  }
}
