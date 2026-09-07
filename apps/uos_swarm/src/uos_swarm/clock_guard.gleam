//// Bounded, observation-only clock guard. Physical/monotonic readings and
//// Lamport counters remain distinct; findings never grant action authority.

import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import gleam/string
import uos_swarm/board
import uos_swarm/board_reader
import uos_swarm/clock_contract as clock

@external(erlang, "clock_guard_ffi", "sample")
pub fn live_sample() -> Result(Sample, String)

@external(erlang, "clock_guard_ffi", "parse")
pub fn parse_tracking(value: String) -> Result(#(Int, Int, Int, String), String)

@external(erlang, "clock_guard_ffi", "load_floor")
pub fn load_floor(path: String) -> Result(Int, String)

@external(erlang, "clock_guard_ffi", "store_floor")
pub fn store_floor(path: String, floor: Int) -> Result(Nil, String)

pub const state_version = 1

pub type Sample {
  Sample(evidence: clock.Evidence, observed: clock.Reading)
}

pub type CausalEvent {
  CausalEvent(
    id: String,
    actor: String,
    domain: clock.Domain,
    utc_us: Int,
    lamport: Int,
    parent_lamport: Option(Int),
    observed_boot_us: Int,
  )
}

pub type BoardSnapshot {
  BoardSnapshot(
    events: List(CausalEvent),
    actor_last_seen: List(#(String, Int)),
  )
}

pub type Fault {
  ClockFault(clock.Failure)
  SampleUnavailable(String)
  BoardUnavailable(String)
  BootChanged
  StaleActor(String)
  EventDomainMismatch(String)
  EventObservedInFuture(String)
  EventClockDomainUnknown(String)
}

pub type Config {
  Config(
    version: Int,
    interval_ms: Int,
    actor_ttl_us: Int,
    retention: Int,
    policy: clock.Policy,
  )
}

pub fn strict_config() -> Config {
  // Chrony polling may legitimately exceed two minutes; source age remains
  // independently bounded to one hour and is never refreshed by this query.
  let clock.Policy(offset, uncertainty, _, step, future) = clock.strict_policy
  Config(
    1,
    30_000,
    120_000_000,
    64,
    clock.Policy(offset, uncertainty, 3_600_000_000, step, future),
  )
}

pub type Report {
  Report(
    sequence: Int,
    observed: Option(clock.Reading),
    source_ref: String,
    offset_us: Option(Int),
    uncertainty_us: Option(Int),
    evidence_age_us: Option(Int),
    lamport_floor: Int,
    faults: List(Fault),
  )
}

pub type State {
  State(
    version: Int,
    config: Config,
    previous: Option(clock.Reading),
    lamport_floor: Int,
    sequence: Int,
    reports: List(Report),
    last_faults: List(Fault),
  )
}

pub fn new(config: Config, durable_lamport_floor: Int) -> State {
  State(state_version, config, None, durable_lamport_floor, 0, [], [])
}

fn cap(items: List(a), maximum: Int) -> List(a) {
  items |> list.take(int.max(1, int.min(maximum, 256)))
}

fn clock_faults(state: State, sample: Sample) -> List(Fault) {
  let validation = case
    clock.validate(sample.evidence, sample.observed, state.config.policy)
  {
    Ok(_) -> []
    Error(failure) -> [ClockFault(failure)]
  }
  case state.previous {
    None -> validation
    Some(previous) ->
      case clock.continuity(previous, sample.observed, state.config.policy) {
        Ok(_) -> validation
        Error(clock.ClockDomainChanged) -> [BootChanged, ..validation]
        Error(failure) -> [ClockFault(failure), ..validation]
      }
  }
}

fn event_faults(
  event: CausalEvent,
  sample: Sample,
  config: Config,
) -> List(Fault) {
  let domain = case event.domain == sample.observed.domain {
    True -> []
    False -> [EventDomainMismatch(event.id)]
  }
  let observed = case event.observed_boot_us {
    value if value < 0 -> [EventClockDomainUnknown(event.id), ..domain]
    value if value > sample.observed.boot_us -> [
      EventObservedInFuture(event.id),
      ..domain
    ]
    _ -> domain
  }
  let physical = case
    clock.event_time(
      event.utc_us,
      sample.observed,
      sample.evidence,
      config.policy,
    )
  {
    Ok(_) -> observed
    Error(failure) -> [ClockFault(failure), ..observed]
  }
  case event.parent_lamport {
    None -> physical
    Some(parent) ->
      case clock.causal_edge(parent, event.lamport) {
        Ok(_) -> physical
        Error(failure) -> [ClockFault(failure), ..physical]
      }
  }
}

pub fn from_board_input(
  input: board_reader.Input(board.Message),
  expected_active_actors: List(String),
) -> BoardSnapshot {
  let events = input.events
  let causal =
    list.map(events, fn(message) {
      let parent_id = case message.causality.in_reply_to {
        Some(id) -> Some(id)
        None -> list.first(message.causality.caused_by) |> option.from_result
      }
      let parent_lamport =
        parent_id
        |> option.then(fn(id) {
          events
          |> list.find(fn(candidate) { candidate.id == id })
          |> result.map(fn(parent) { parent.lamport })
          |> option.from_result
        })
      CausalEvent(
        message.id,
        message.from.id,
        clock.Domain("unknown", "unknown"),
        message.ts_us,
        message.lamport,
        parent_lamport,
        -1,
      )
    })
  let actors =
    expected_active_actors
    |> list.map(fn(id) {
      let latest =
        events
        |> list.filter(fn(message) { message.from.id == id })
        |> list.fold(0, fn(n, message) { int.max(n, message.ts_us) })
      #(id, latest)
    })
  BoardSnapshot(causal, actors)
}

pub fn audit(
  state: State,
  sample_result: Result(Sample, String),
  board_result: Result(BoardSnapshot, String),
) -> State {
  case sample_result {
    Error(reason) ->
      add_report(state, None, "unknown", None, None, None, [
        SampleUnavailable(reason),
      ])
    Ok(sample) -> {
      let Sample(evidence, observed) = sample
      let base = clock_faults(state, sample)
      let #(board_faults, floor) = case board_result {
        Error(reason) -> #([BoardUnavailable(reason)], state.lamport_floor)
        Ok(BoardSnapshot(events, actors)) -> {
          let event_findings =
            events
            |> list.flat_map(fn(e) { event_faults(e, sample, state.config) })
          let stale =
            actors
            |> list.filter_map(fn(pair) {
              case
                observed.utc_us - pair.1 > state.config.actor_ttl_us
                || pair.1 > observed.utc_us
              {
                True -> Ok(StaleActor(pair.0))
                False -> Error(Nil)
              }
            })
          let max_seen =
            events
            |> list.fold(state.lamport_floor, fn(n, e) { int.max(n, e.lamport) })
          #(list.append(event_findings, stale), max_seen)
        }
      }
      add_report(
        State(..state, previous: Some(observed), lamport_floor: floor),
        Some(observed),
        evidence.source_ref,
        Some(evidence.offset_us),
        Some(evidence.uncertainty_us),
        Some(observed.boot_us - evidence.reading.boot_us),
        list.append(base, board_faults),
      )
    }
  }
}

fn add_report(
  state: State,
  reading,
  source,
  offset,
  uncertainty,
  age,
  faults,
) -> State {
  let faults = cap(faults, 64)
  let report =
    Report(
      state.sequence + 1,
      reading,
      source,
      offset,
      uncertainty,
      age,
      state.lamport_floor,
      faults,
    )
  let reports = case faults == state.last_faults {
    True -> state.reports
    False -> cap([report, ..state.reports], state.config.retention)
  }
  State(
    ..state,
    sequence: state.sequence + 1,
    reports: reports,
    last_faults: faults,
  )
}

pub fn reload(state: State, config: Config) -> Result(State, String) {
  case
    config.version == 1
    && config.interval_ms >= 50
    && config.actor_ttl_us > 0
    && config.retention > 0
    && config.retention <= 256
  {
    True ->
      Ok(
        State(
          ..state,
          version: state_version,
          config: config,
          reports: cap(state.reports, config.retention),
        ),
      )
    False -> Error("invalid clock guard configuration")
  }
}

pub type Message {
  Tick
  Snapshot(Subject(State))
  Reload(Config, Subject(Result(Nil, String)))
  Stop
}

type Runtime {
  Runtime(
    state: State,
    sample: fn() -> Result(Sample, String),
    board: fn() -> Result(BoardSnapshot, String),
    persist_floor: fn(Int) -> Result(Nil, String),
    self: Subject(Message),
  )
}

pub fn start_actor(
  config: Config,
  floor: Int,
  sample,
  board,
  persist_floor,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    process.send_after(self, int.max(config.interval_ms, 50), Tick)
    Ok(
      actor.initialised(Runtime(
        new(config, floor),
        sample,
        board,
        persist_floor,
        self,
      ))
      |> actor.returning(self),
    )
  })
  |> actor.on_message(handle)
  |> actor.start
}

pub fn child_spec(
  config: Config,
  floor: Int,
  sample,
  board,
  persist_floor,
) -> ChildSpecification(Subject(Message)) {
  supervision.worker(fn() {
    start_actor(config, floor, sample, board, persist_floor)
  })
}

fn handle(runtime: Runtime, message: Message) -> actor.Next(Runtime, Message) {
  case message {
    Tick -> {
      let next = audit(runtime.state, runtime.sample(), runtime.board())
      let next = case runtime.persist_floor(next.lamport_floor) {
        Ok(_) -> next
        Error(reason) ->
          add_report(next, next.previous, "durable-floor", None, None, None, [
            BoardUnavailable(reason),
          ])
      }
      process.send_after(
        runtime.self,
        int.max(next.config.interval_ms, 50),
        Tick,
      )
      actor.continue(Runtime(..runtime, state: next))
    }
    Snapshot(reply) -> {
      process.send(reply, runtime.state)
      actor.continue(runtime)
    }
    Reload(config, reply) ->
      case reload(runtime.state, config) {
        Ok(next) -> {
          process.send(reply, Ok(Nil))
          actor.continue(Runtime(..runtime, state: next))
        }
        Error(reason) -> {
          process.send(reply, Error(reason))
          actor.continue(runtime)
        }
      }
    Stop -> actor.stop()
  }
}

pub fn report_json(report: Report) -> Json {
  let #(host_id, boot_id, utc_us, boot_us) = case report.observed {
    Some(reading) -> #(
      json.string(reading.domain.host_id),
      json.string(reading.domain.boot_id),
      json.int(reading.utc_us),
      json.int(reading.boot_us),
    )
    None -> #(json.null(), json.null(), json.null(), json.null())
  }
  let optional_int = fn(value) {
    case value {
      Some(n) -> json.int(n)
      None -> json.null()
    }
  }
  json.object([
    #("schema", json.string("uos-clock-guard/v1")),
    #("sequence", json.int(report.sequence)),
    #("healthy", json.bool(list.is_empty(report.faults))),
    #("source", json.string(report.source_ref)),
    #("host_id", host_id),
    #("boot_id", boot_id),
    #("observed_utc_us", utc_us),
    #("observed_boot_us", boot_us),
    #("offset_us", optional_int(report.offset_us)),
    #("uncertainty_us", optional_int(report.uncertainty_us)),
    #("reference_age_us", optional_int(report.evidence_age_us)),
    #("lamport_floor", json.int(report.lamport_floor)),
    #(
      "faults",
      json.array(report.faults, fn(f) {
        json.object([
          #("code", json.string(fault_label(f))),
          #("detail", json.string(string.slice(fault_detail(f), 0, 512))),
        ])
      }),
    ),
  ])
}

fn fault_detail(fault: Fault) -> String {
  case fault {
    ClockFault(f) -> clock.failure_label(f)
    SampleUnavailable(reason) | BoardUnavailable(reason) -> reason
    BootChanged -> "host or boot domain changed"
    StaleActor(id) -> id
    EventDomainMismatch(id)
    | EventObservedInFuture(id)
    | EventClockDomainUnknown(id) -> id
  }
}

pub fn fault_label(fault: Fault) -> String {
  case fault {
    ClockFault(f) -> clock.failure_label(f)
    SampleUnavailable(_) -> "sample_unavailable"
    BoardUnavailable(_) -> "board_unavailable"
    BootChanged -> "boot_changed"
    StaleActor(_) -> "stale_actor"
    EventDomainMismatch(_) -> "event_domain_mismatch"
    EventObservedInFuture(_) -> "event_observed_in_future"
    EventClockDomainUnknown(_) -> "event_clock_domain_unknown"
  }
}
