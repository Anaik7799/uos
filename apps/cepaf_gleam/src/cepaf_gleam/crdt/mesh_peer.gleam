//// Opaque cooperative peer state. Routing checks are not authentication.
//// Outbound acceptance means transport custody, not remote application.

import cepaf_gleam/crdt/delta_mesh_engine as engine
import cepaf_gleam/crdt/mesh_sync as sync
import cepaf_gleam/crdt/mesh_wire as wire
import cepaf_gleam/ha/deadman_freshness as deadman
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string

pub const max_peers = 16

pub const max_frames = 256

pub const max_outbound_bytes = 1_048_576

pub const max_advisories = 64

pub type Peer {
  Peer(node: String, fqdn: String)
}

pub opaque type Config {
  Config(
    node: String,
    fqdn: String,
    peers: List(Peer),
    tick_ms: Int,
    heartbeat_ms: Int,
    max_missed: Int,
  )
}

pub type PeerError {
  InvalidConfig
  InvalidClock
  UnknownPeer
  SenderMismatch
  WireFailure(wire.WireError)
  EngineQueueFull
  FrameQuota
  ByteQuota
  SequenceLimit
  NotOutstanding
  ActorUnavailable
}

pub type FrameId {
  FrameId(instance: Int, sequence: Int)
}

pub type Frame {
  Frame(id: FrameId, destination: String, wire: String)
}

pub type Delivery {
  TransportAccepted
  TransportFailed
}

pub opaque type State {
  State(
    config: Config,
    engine: engine.DeltaMeshEngine,
    freshness: deadman.DeadManRegistry,
    activity: List(#(String, Int)),
    outbox: List(Frame),
    bytes: Int,
    next_id: Int,
    instance: Int,
    last_mono: Int,
    actions: List(deadman.DeadManAction),
    action_overflow: Int,
  )
}

pub type Tick {
  Tick(state: State, gossip: Result(Nil, PeerError))
}

fn bounded(items: List(a), count: Int) -> Bool {
  case items {
    [] -> True
    [_, ..rest] -> count > 0 && bounded(rest, count - 1)
  }
}

fn identity(value: String) -> Bool {
  string.byte_size(value) <= wire.max_string_bytes && string.trim(value) != ""
}

pub fn config(
  node: String,
  fqdn: String,
  peers: List(Peer),
  tick_ms: Int,
  heartbeat_ms: Int,
  max_missed: Int,
) -> Result(Config, PeerError) {
  case
    identity(node)
    && identity(fqdn)
    && bounded(peers, max_peers)
    && list.all(peers, fn(p) {
      identity(p.node) && identity(p.fqdn) && p.node != node
    })
    && list.length(list.unique(list.map(peers, fn(p) { p.node })))
    == list.length(peers)
    && tick_ms >= 1
    && tick_ms <= 60_000
    && heartbeat_ms >= tick_ms
    && heartbeat_ms <= 60_000
    && max_missed >= 1
    && max_missed <= 100
  {
    True -> Ok(Config(node, fqdn, peers, tick_ms, heartbeat_ms, max_missed))
    False -> Error(InvalidConfig)
  }
}

pub fn tick_interval(config: Config) -> Int {
  config.tick_ms
}

pub fn local_node(config: Config) -> String {
  config.node
}

pub fn configured_peers(config: Config) -> List(Peer) {
  config.peers
}

fn valid_clock(value: Int) -> Bool {
  value >= 0 && value <= wire.max_integer
}

pub fn init(
  config: Config,
  mono_ms: Int,
  utc_us: Int,
  instance: Int,
) -> Result(State, PeerError) {
  case valid_clock(mono_ms) && valid_clock(utc_us) && valid_clock(instance) {
    False -> Error(InvalidClock)
    True -> {
      let initial = engine.init_engine(config.node, config.fqdn, utc_us)
      let registered =
        list.fold(config.peers, initial, fn(e, p) {
          engine.register_peer(e, p.node, p.fqdn)
        })
      let freshness =
        list.fold(config.peers, deadman.init_deadman_registry(), fn(r, p) {
          deadman.register_actor(
            r,
            p.node,
            "L6",
            config.heartbeat_ms,
            config.max_missed,
            None,
            mono_ms,
          )
        })
      Ok(State(
        config,
        registered,
        freshness,
        [],
        [],
        0,
        1,
        instance,
        mono_ms,
        [],
        0,
      ))
    }
  }
}

pub fn outbound(state: State) -> List(Frame) {
  state.outbox
}

pub fn outbound_bytes(state: State) -> Int {
  state.bytes
}

pub fn engine_snapshot(state: State) -> engine.DeltaMeshEngine {
  state.engine
}

pub fn freshness(state: State) -> deadman.DeadManRegistry {
  state.freshness
}

pub fn advisory_overflow(state: State) -> Int {
  state.action_overflow
}

pub fn take_advisories(
  state: State,
) -> #(State, List(deadman.DeadManAction), Int) {
  #(
    State(..state, actions: [], action_overflow: 0),
    state.actions,
    state.action_overflow,
  )
}

fn check_engine(candidate: engine.DeltaMeshEngine) -> Result(Nil, PeerError) {
  sync.encode_sync_message(sync.SyncDelta(
    candidate.local_node_id,
    candidate.local_mesh_state,
    candidate.local_health_map,
    candidate.local_mesh_state.epoch_us,
  ))
  |> result.map(fn(_) { Nil })
  |> result.map_error(WireFailure)
}

fn add_frame(
  state: State,
  destination: String,
  bytes: String,
) -> Result(State, PeerError) {
  case
    list.length(state.outbox) >= max_frames,
    state.bytes + string.byte_size(bytes) > max_outbound_bytes,
    state.next_id >= wire.max_integer
  {
    True, _, _ -> Error(FrameQuota)
    _, True, _ -> Error(ByteQuota)
    _, _, True -> Error(SequenceLimit)
    False, False, False ->
      Ok(
        State(
          ..state,
          outbox: list.append(state.outbox, [
            Frame(FrameId(state.instance, state.next_id), destination, bytes),
          ]),
          bytes: state.bytes + string.byte_size(bytes),
          next_id: state.next_id + 1,
        ),
      )
  }
}

fn route_messages(
  state: State,
  messages: List(sync.MeshSyncMessage),
  destinations: List(String),
) -> Result(State, PeerError) {
  list.try_fold(messages, state, fn(s, message) {
    use bytes <- result.try(
      sync.encode_sync_message(message) |> result.map_error(WireFailure),
    )
    list.try_fold(destinations, s, fn(s, destination) {
      add_frame(s, destination, bytes)
    })
  })
}

fn commit_engine(
  state: State,
  candidate: engine.DeltaMeshEngine,
  destinations: List(String),
) -> Result(State, PeerError) {
  use _ <- result.try(check_engine(candidate))
  let #(drained, messages) = engine.drain_pending_outbound(candidate)
  use staged <- result.try(route_messages(state, messages, destinations))
  Ok(State(..staged, engine: drained))
}

pub fn gossip(state: State, utc_us: Int) -> Result(State, PeerError) {
  use _ <- result.try(case state.engine.gossip_round < wire.max_integer {
    True -> Ok(Nil)
    False -> Error(SequenceLimit)
  })
  use _ <- result.try(case valid_clock(utc_us) {
    True -> Ok(Nil)
    False -> Error(InvalidClock)
  })
  use #(candidate, _) <- result.try(
    engine.generate_gossip_digest(state.engine, utc_us)
    |> result.map_error(fn(_) { EngineQueueFull }),
  )
  commit_engine(
    state,
    candidate,
    list.map(state.config.peers, fn(p) { p.node }),
  )
}

pub fn record_worker(
  state: State,
  worker: String,
  utc_us: Int,
) -> Result(State, PeerError) {
  use _ <- result.try(case valid_clock(utc_us) {
    True -> Ok(Nil)
    False -> Error(InvalidClock)
  })
  commit_engine(
    state,
    engine.record_worker_active(state.engine, worker, utc_us),
    [],
  )
}

pub fn record_health(
  state: State,
  score: Float,
  exponent: Float,
  stable: Bool,
  breaker: String,
  utc_us: Int,
) -> Result(State, PeerError) {
  use _ <- result.try(case valid_clock(utc_us) {
    True -> Ok(Nil)
    False -> Error(InvalidClock)
  })
  commit_engine(
    state,
    engine.record_local_health(
      state.engine,
      state.config.node,
      score,
      exponent,
      stable,
      breaker,
      utc_us,
    ),
    [],
  )
}

pub fn receive_wire(
  state: State,
  routing_id: String,
  bytes: String,
  mono_ms: Int,
  utc_us: Int,
) -> Result(State, PeerError) {
  use _ <- result.try(
    case
      valid_clock(mono_ms) && mono_ms >= state.last_mono && valid_clock(utc_us)
    {
      True -> Ok(Nil)
      False -> Error(InvalidClock)
    },
  )
  use _ <- result.try(
    case list.any(state.config.peers, fn(p) { p.node == routing_id }) {
      True -> Ok(Nil)
      False -> Error(UnknownPeer)
    },
  )
  use message <- result.try(
    sync.decode_sync_message(bytes) |> result.map_error(WireFailure),
  )
  let #(sender, remote_epoch) = case message {
    sync.SyncDigest(node, _, _, epoch)
    | sync.SyncDelta(node, _, _, epoch)
    | sync.SyncAck(node, _, _, epoch) -> #(node, epoch)
  }
  use _ <- result.try(case sender == routing_id {
    True -> Ok(Nil)
    False -> Error(SenderMismatch)
  })
  use #(candidate, _) <- result.try(
    engine.handle_incoming_message(state.engine, message, utc_us)
    |> result.map_error(fn(_) { EngineQueueFull }),
  )
  use accepted <- result.try(commit_engine(state, candidate, [sender]))
  let previous = list.key_find(state.activity, sender) |> result.unwrap(-1)
  case remote_epoch > previous {
    True ->
      Ok(
        State(
          ..accepted,
          activity: list.key_set(state.activity, sender, remote_epoch),
          freshness: deadman.record_heartbeat(state.freshness, sender, mono_ms),
          last_mono: mono_ms,
        ),
      )
    False -> Ok(State(..accepted, last_mono: mono_ms))
  }
}

/// Only the exact retained frame/address pair can retire. Failed transport
/// preserves all bytes and IDs, permitting a later retry of that same frame.
pub fn report_delivery(
  state: State,
  id: FrameId,
  destination: String,
  outcome: Delivery,
) -> Result(State, PeerError) {
  use frame <- result.try(
    list.find(state.outbox, fn(f) { f.id == id && f.destination == destination })
    |> result.map_error(fn(_) { NotOutstanding }),
  )
  case outcome {
    TransportFailed -> Ok(state)
    TransportAccepted ->
      Ok(
        State(
          ..state,
          outbox: list.filter(state.outbox, fn(f) { f.id != id }),
          bytes: state.bytes - string.byte_size(frame.wire),
        ),
      )
  }
}

/// Freshness commits independently of gossip quota. Advisory overflow is counted
/// explicitly; authoritative current statuses remain in the bounded registry.
pub fn tick(
  state: State,
  mono_ms: Int,
  utc_us: Int,
) -> Result(Tick, PeerError) {
  use _ <- result.try(case valid_clock(mono_ms) && mono_ms >= state.last_mono {
    True -> Ok(Nil)
    False -> Error(InvalidClock)
  })
  let #(registry, actions) =
    deadman.evaluate_freshness_tick(state.freshness, mono_ms)
  let all = list.append(state.actions, actions)
  let fresh =
    State(
      ..state,
      freshness: registry,
      last_mono: mono_ms,
      actions: list.take(all, max_advisories),
      action_overflow: int.min(
        wire.max_integer,
        state.action_overflow + int.max(0, list.length(all) - max_advisories),
      ),
    )
  case gossip(fresh, utc_us) {
    Ok(sent) -> Ok(Tick(sent, Ok(Nil)))
    Error(error) -> Ok(Tick(fresh, Error(error)))
  }
}
