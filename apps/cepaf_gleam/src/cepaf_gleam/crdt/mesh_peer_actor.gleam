//// Supervised local control actor; transport is a separate worker. Clock reads
//// call standard ERTS directly. Actor lifetime IDs fence delayed delivery reports.

import cepaf_gleam/crdt/mesh_peer as peer
import cepaf_gleam/crdt/mesh_wire as wire
import cepaf_gleam/ha/deadman_freshness
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/string

type TimeUnit {
  Millisecond
  Microsecond
}

type UniqueOption {
  Positive
  Monotonic
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: TimeUnit) -> Int

@external(erlang, "erlang", "system_time")
fn system_time(unit: TimeUnit) -> Int

@external(erlang, "erlang", "unique_integer")
fn unique_integer(options: List(UniqueOption)) -> Int

pub opaque type Handle {
  Handle(subject: Subject(Message))
}

pub type View {
  View(peer: peer.State, last_tick_gossip: Result(Nil, peer.PeerError))
}

type Message {
  TimerTick
  Gossip(Subject(Result(Nil, peer.PeerError)))
  Inbound(String, String, Subject(Result(Nil, peer.PeerError)))
  Worker(String, Subject(Result(Nil, peer.PeerError)))
  Health(Float, Float, Bool, String, Subject(Result(Nil, peer.PeerError)))
  Pull(Int, Subject(Result(List(peer.Frame), peer.PeerError)))
  Report(
    peer.FrameId,
    String,
    peer.Delivery,
    Subject(Result(Nil, peer.PeerError)),
  )
  Snapshot(Subject(Result(View, peer.PeerError)))
  Advisories(
    Subject(
      Result(#(List(deadman_freshness.DeadManAction), Int), peer.PeerError),
    ),
  )
  Shutdown(Subject(Result(View, peer.PeerError)))
}

type State {
  State(
    peer: peer.State,
    config: peer.Config,
    origin_mono: Int,
    subject: Subject(Message),
    timer: process.Timer,
    last_tick_gossip: Result(Nil, peer.PeerError),
  )
}

fn mono(state: State) {
  int.max(0, monotonic_time(Millisecond) - state.origin_mono)
}

fn view(state: State) {
  View(state.peer, state.last_tick_gossip)
}

fn update(
  state: State,
  operation: Result(peer.State, peer.PeerError),
  reply: Subject(Result(Nil, peer.PeerError)),
) {
  case operation {
    Ok(next) -> {
      process.send(reply, Ok(Nil))
      actor.continue(State(..state, peer: next))
    }
    Error(error) -> {
      process.send(reply, Error(error))
      actor.continue(state)
    }
  }
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    TimerTick -> {
      let timer =
        process.send_after(
          state.subject,
          peer.tick_interval(state.config),
          TimerTick,
        )
      case peer.tick(state.peer, mono(state), system_time(Microsecond)) {
        Ok(peer.Tick(next, outcome)) ->
          actor.continue(
            State(..state, peer: next, timer: timer, last_tick_gossip: outcome),
          )
        Error(error) ->
          actor.continue(
            State(..state, timer: timer, last_tick_gossip: Error(error)),
          )
      }
    }
    Gossip(reply) ->
      update(state, peer.gossip(state.peer, system_time(Microsecond)), reply)
    Inbound(sender, bytes, reply) ->
      update(
        state,
        peer.receive_wire(
          state.peer,
          sender,
          bytes,
          mono(state),
          system_time(Microsecond),
        ),
        reply,
      )
    Worker(worker, reply) ->
      update(
        state,
        peer.record_worker(state.peer, worker, system_time(Microsecond)),
        reply,
      )
    Health(score, exponent, stable, breaker, reply) ->
      update(
        state,
        peer.record_health(
          state.peer,
          score,
          exponent,
          stable,
          breaker,
          system_time(Microsecond),
        ),
        reply,
      )
    Pull(maximum, reply) -> {
      process.send(reply, Ok(list.take(peer.outbound(state.peer), maximum)))
      actor.continue(state)
    }
    Report(id, destination, outcome, reply) ->
      update(
        state,
        peer.report_delivery(state.peer, id, destination, outcome),
        reply,
      )
    Snapshot(reply) -> {
      process.send(reply, Ok(view(state)))
      actor.continue(state)
    }
    Advisories(reply) -> {
      let #(next, actions, overflow) = peer.take_advisories(state.peer)
      process.send(reply, Ok(#(actions, overflow)))
      actor.continue(State(..state, peer: next))
    }
    Shutdown(reply) -> {
      let _ = process.cancel_timer(state.timer)
      process.send(reply, Ok(view(state)))
      actor.stop()
    }
  }
}

pub fn start(config: peer.Config) -> actor.StartResult(Handle) {
  actor.new_with_initialiser(1000, fn(subject) {
    let origin = monotonic_time(Millisecond)
    use initial <- result.try(
      peer.init(
        config,
        0,
        system_time(Microsecond),
        unique_integer([Positive, Monotonic]),
      )
      |> result.map_error(fn(_) { "invalid initial peer clocks" }),
    )
    let timer =
      process.send_after(subject, peer.tick_interval(config), TimerTick)
    Ok(
      actor.initialised(State(initial, config, origin, subject, timer, Ok(Nil)))
      |> actor.returning(Handle(subject)),
    )
  })
  |> actor.on_message(handle)
  |> actor.start
}

/// Normal controlled shutdown is transient; abnormal crashes are supervised.
/// In-memory outbox durability across a VM/process crash is not claimed.
pub fn supervised(
  config: peer.Config,
) -> supervision.ChildSpecification(Handle) {
  supervision.worker(fn() { start(config) })
  |> supervision.restart(supervision.Transient)
  |> supervision.timeout(1000)
}

fn call(
  handle: Handle,
  request: fn(Subject(Result(a, peer.PeerError))) -> Message,
) -> Result(a, peer.PeerError) {
  use owner <- result.try(
    process.subject_owner(handle.subject)
    |> result.map_error(fn(_) { peer.ActorUnavailable }),
  )
  let reply = process.new_subject()
  let monitor = process.monitor(owner)
  let selector =
    process.new_selector()
    |> process.select(reply)
    |> process.select_specific_monitor(monitor, fn(_) {
      Error(peer.ActorUnavailable)
    })
  process.send(handle.subject, request(reply))
  let response = process.selector_receive(selector, 1000)
  process.demonitor_process(monitor)
  response
  |> result.map_error(fn(_) { peer.ActorUnavailable })
  |> result.flatten
}

pub fn gossip(handle: Handle) -> Result(Nil, peer.PeerError) {
  call(handle, Gossip)
}

pub fn receive_wire(
  handle: Handle,
  routing_id: String,
  bytes: String,
) -> Result(Nil, peer.PeerError) {
  case
    string.byte_size(bytes) <= wire.max_bytes
    && string.byte_size(routing_id) <= wire.max_string_bytes
  {
    True -> call(handle, Inbound(routing_id, bytes, _))
    False -> Error(peer.WireFailure(wire.ByteLimit))
  }
}

pub fn record_worker(
  handle: Handle,
  worker: String,
) -> Result(Nil, peer.PeerError) {
  case string.byte_size(worker) <= wire.max_string_bytes {
    True -> call(handle, Worker(worker, _))
    False -> Error(peer.WireFailure(wire.StringLimit))
  }
}

pub fn record_health(
  handle: Handle,
  score: Float,
  exponent: Float,
  stable: Bool,
  breaker: String,
) -> Result(Nil, peer.PeerError) {
  use _ <- result.try(
    wire.validate(
      wire.Array([wire.Real(score), wire.Real(exponent), wire.Text(breaker)]),
    )
    |> result.map_error(peer.WireFailure),
  )
  call(handle, Health(score, exponent, stable, breaker, _))
}

/// Pulling transfers no custody: frames remain until their exact report arrives.
pub fn pull(
  handle: Handle,
  maximum: Int,
) -> Result(List(peer.Frame), peer.PeerError) {
  case maximum >= 1 && maximum <= peer.max_frames {
    True -> call(handle, Pull(maximum, _))
    False -> Error(peer.InvalidConfig)
  }
}

pub fn report_delivery(
  handle: Handle,
  id: peer.FrameId,
  destination: String,
  outcome: peer.Delivery,
) -> Result(Nil, peer.PeerError) {
  case
    string.byte_size(destination) <= wire.max_string_bytes
    && id.instance >= 0
    && id.instance <= wire.max_integer
    && id.sequence >= 0
    && id.sequence <= wire.max_integer
  {
    True -> call(handle, Report(id, destination, outcome, _))
    False -> Error(peer.NotOutstanding)
  }
}

pub fn snapshot(handle: Handle) -> Result(View, peer.PeerError) {
  call(handle, Snapshot)
}

pub fn take_advisories(
  handle: Handle,
) -> Result(#(List(deadman_freshness.DeadManAction), Int), peer.PeerError) {
  call(handle, Advisories)
}

/// Caller receives the complete retained state for explicit shutdown handoff.
/// A failed/timed-out call does not establish that the handoff was received.
pub fn shutdown(handle: Handle) -> Result(View, peer.PeerError) {
  call(handle, Shutdown)
}
