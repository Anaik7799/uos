//// Bounded local Mini backend telemetry. No request identities or payloads retained.
//// State is process-local and reset on collector restart; epoch identifies each reset.

import cepaf_gleam/telegram/types
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const active_limit = 128

pub const recent_limit = 20

pub const lifetime_us = 30_000_000

pub const counter_limit = 9_007_199_254_740_991

pub type Outcome {
  Observed
  Unavailable
  Forbidden
}

pub opaque type Ticket {
  Ticket(epoch: String, trace: String)
}

pub type Span {
  Span(
    trace_id: String,
    span_id: String,
    page: types.MiniAppPage,
    started_at: Int,
    duration_us: Int,
    outcome: Outcome,
  )
}

type Pending {
  Pending(
    span_id: String,
    page: types.MiniAppPage,
    started_at: Int,
    mono_us: Int,
  )
}

pub type Snapshot {
  Snapshot(
    epoch: String,
    started_at: Int,
    active: Int,
    recent: List(Span),
    accepted: Int,
    completed: Int,
    dropped: Int,
    expired: Int,
    saturated: Bool,
  )
}

pub opaque type State {
  State(
    epoch: String,
    started_at: Int,
    last_us: Int,
    active: Dict(String, Pending),
    recent: List(Span),
    accepted: Int,
    completed: Int,
    dropped: Int,
    expired: Int,
    saturated: Bool,
  )
}

fn valid_hex(value: String, size: Int) -> Bool {
  string.byte_size(value) == size
  && value != string.repeat("0", size)
  && list.all(string.to_graphemes(value), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}

pub fn new(
  epoch: String,
  now_us: Int,
  wall_seconds: Int,
) -> Result(State, String) {
  case valid_hex(epoch, 32) && wall_seconds > 0 {
    True ->
      Ok(State(epoch, wall_seconds, now_us, dict.new(), [], 0, 0, 0, 0, False))
    False -> Error("invalid_epoch_or_clock")
  }
}

pub fn increment(value: Int, count: Int) -> #(Int, Bool) {
  case count >= counter_limit - value {
    True -> #(counter_limit, True)
    False -> #(value + count, False)
  }
}

pub fn prune(state: State, now_us: Int) -> Result(State, String) {
  use _ <- result.try(case now_us >= state.last_us {
    True -> Ok(Nil)
    False -> Error("monotonic_clock_regressed")
  })
  let active =
    dict.filter(state.active, fn(_, p) { now_us - p.mono_us < lifetime_us })
  let lost = dict.size(state.active) - dict.size(active)
  let #(expired, saturated) = increment(state.expired, lost)
  Ok(
    State(
      ..state,
      active: active,
      expired: expired,
      saturated: state.saturated || saturated,
      last_us: now_us,
    ),
  )
}

pub fn begin(
  state: State,
  page: types.MiniAppPage,
  trace: String,
  span: String,
  now_us: Int,
  wall_seconds: Int,
) -> Result(#(State, Option(Ticket)), String) {
  use state <- result.try(prune(state, now_us))
  use _ <- result.try(
    case
      valid_hex(trace, 32)
      && valid_hex(span, 16)
      && wall_seconds > 0
      && !dict.has_key(state.active, trace)
      && !list.any(state.recent, fn(s) { s.trace_id == trace })
    {
      True -> Ok(Nil)
      False -> Error("invalid_or_duplicate_span")
    },
  )
  case dict.size(state.active) >= active_limit {
    True -> {
      let #(dropped, saturated) = increment(state.dropped, 1)
      Ok(#(
        State(
          ..state,
          dropped: dropped,
          saturated: state.saturated || saturated,
        ),
        None,
      ))
    }
    False -> {
      let #(accepted, saturated) = increment(state.accepted, 1)
      Ok(#(
        State(
          ..state,
          active: dict.insert(
            state.active,
            trace,
            Pending(span, page, wall_seconds, now_us),
          ),
          accepted: accepted,
          saturated: state.saturated || saturated,
        ),
        Some(Ticket(state.epoch, trace)),
      ))
    }
  }
}

pub fn finish(
  state: State,
  ticket: Ticket,
  outcome: Outcome,
  now_us: Int,
) -> Result(State, String) {
  use state <- result.try(prune(state, now_us))
  use _ <- result.try(case ticket.epoch == state.epoch {
    True -> Ok(Nil)
    False -> Error("collector_epoch_changed")
  })
  use p <- result.try(
    dict.get(state.active, ticket.trace)
    |> result.replace_error("span_missing_or_expired"),
  )
  let span =
    Span(
      ticket.trace,
      p.span_id,
      p.page,
      p.started_at,
      now_us - p.mono_us,
      outcome,
    )
  let #(completed, saturated) = increment(state.completed, 1)
  Ok(
    State(
      ..state,
      active: dict.delete(state.active, ticket.trace),
      recent: list.take([span, ..state.recent], recent_limit),
      completed: completed,
      saturated: state.saturated || saturated,
    ),
  )
}

pub fn snapshot(state: State) -> Snapshot {
  Snapshot(
    state.epoch,
    state.started_at,
    dict.size(state.active),
    state.recent,
    state.accepted,
    state.completed,
    state.dropped,
    state.expired,
    state.saturated,
  )
}

pub fn outcome_name(value: Outcome) -> String {
  case value {
    Observed -> "observed"
    Unavailable -> "unavailable"
    Forbidden -> "forbidden"
  }
}
