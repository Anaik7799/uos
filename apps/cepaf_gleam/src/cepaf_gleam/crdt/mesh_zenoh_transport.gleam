//// Cooperative run-scoped carrier. Broker custody is separate from peer
//// application. No authentication, deletion or crash durability.

import cepaf_gleam/crdt/mesh_peer as peer
import cepaf_gleam/crdt/mesh_peer_actor as peers
import cepaf_gleam/crdt/mesh_wire
import cepaf_gleam/crdt/mesh_zenoh_http as http
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/string

pub const max_publications = 256

pub type Error {
  InvalidConfig
  Http(http.Error)
  InvalidSample
  NamespaceConflict
  Peer(peer.PeerError)
  RunQuota
  Unavailable
}

pub opaque type Config {
  Config(
    endpoint: http.Endpoint,
    run: String,
    local: String,
    peers: List(String),
  )
}

pub opaque type Handle {
  Handle(subject: Subject(Message))
}

pub type Stats {
  Stats(
    published: Int,
    applied: Int,
    failures: Int,
    last_error: Option(Error),
    halted: Bool,
    custody_pending: Bool,
    last_stored_wire: Option(String),
    last_applied_wire: Option(String),
  )
}

type Message {
  Tick
  Snapshot(Subject(Stats))
  Shutdown(Subject(Stats))
}

type Pending {
  Custodied(frame: peer.Frame, route_sequence: Int)
}

type State {
  State(
    config: Config,
    peer: peers.Handle,
    subject: Subject(Message),
    timer: process.Timer,
    send_seq: Dict(String, Int),
    recv_seq: Dict(String, Int),
    next_peer: Int,
    publish_turn: Bool,
    pending: Option(Pending),
    stats: Stats,
  )
}

type Envelope {
  Envelope(
    sender: String,
    destination: String,
    instance: Int,
    sequence: Int,
    wire: String,
  )
}

type Registered {
  Yes
  No
}

@external(erlang, "global", "register_name")
fn register_worker(
  name: #(String, String, String),
  owner: process.Pid,
) -> Registered

pub fn config(
  endpoint: http.Endpoint,
  run: String,
  local: String,
  peers: List(String),
) -> Result(Config, Error) {
  case
    http.segment(run)
    && http.segment(local)
    && bounded_peers(peers, 16)
    && list.all(peers, fn(p) { http.segment(p) && p != local })
    && list.length(list.unique(peers)) == list.length(peers)
  {
    True -> Ok(Config(endpoint, run, local, peers))
    False -> Error(InvalidConfig)
  }
}

fn bounded_peers(xs: List(a), left: Int) -> Bool {
  case xs {
    [] -> True
    [_, ..rest] -> left > 0 && bounded_peers(rest, left - 1)
  }
}

fn key(
  config: Config,
  sender: String,
  destination: String,
  seq: Int,
) -> String {
  "uos/tui/state/ev98-peer/01a08017-fd72-7b20-9d32-4df53154bcc8/"
  <> config.run
  <> "/"
  <> sender
  <> "/"
  <> destination
  <> "/"
  <> int.to_string(seq)
}

fn envelope(frame: peer.Frame, sender: String) -> Envelope {
  Envelope(
    sender,
    frame.destination,
    frame.id.instance,
    frame.id.sequence,
    frame.wire,
  )
}

fn encode(e: Envelope) -> String {
  json.array(
    [
      json.string("uos.ev98.transport.v1"),
      json.string(e.sender),
      json.string(e.destination),
      json.int(e.instance),
      json.int(e.sequence),
      json.string(e.wire),
    ],
    fn(x) { x },
  )
  |> json.to_string
}

fn envelope_decoder() -> decode.Decoder(Envelope) {
  use version <- decode.field(0, decode.string)
  use sender <- decode.field(1, decode.string)
  use destination <- decode.field(2, decode.string)
  use instance <- decode.field(3, decode.int)
  use sequence <- decode.field(4, decode.int)
  use wire <- decode.field(5, decode.string)
  use all <- decode.then(decode.list(decode.dynamic))
  case
    version == "uos.ev98.transport.v1"
    && list.length(all) == 6
    && http.segment(sender)
    && http.segment(destination)
    && instance >= 0
    && instance <= mesh_wire.max_integer
    && sequence >= 0
    && sequence <= mesh_wire.max_integer
    && string.byte_size(wire) <= mesh_wire.max_bytes
  {
    True ->
      decode.success(Envelope(sender, destination, instance, sequence, wire))
    False ->
      decode.failure(Envelope("", "", 0, 0, ""), "bounded transport envelope")
  }
}

fn sample_decoder() -> decode.Decoder(#(String, Envelope)) {
  use key <- decode.field("key", decode.string)
  use encoding <- decode.field("encoding", decode.string)
  use value <- decode.field("value", envelope_decoder())
  case encoding == "application/json" {
    True -> decode.success(#(key, value))
    False -> decode.failure(#(key, value), "application/json")
  }
}

// Before JSON parsing, bound depth and permit only one flat sample object.
// Its keys are decoded before duplicate detection, including escaped names.
fn scan(
  bytes: BitArray,
  depth: Int,
  in_string: Bool,
  escaped: Bool,
  token: BitArray,
  is_key: Bool,
  expecting_key: Bool,
  keys: List(String),
) -> Result(Nil, Error) {
  case bit_array.byte_size(token) > 64 {
    True -> Error(InvalidSample)
    False ->
      scan_inner(
        bytes,
        depth,
        in_string,
        escaped,
        token,
        is_key,
        expecting_key,
        keys,
      )
  }
}

fn scan_inner(
  bytes: BitArray,
  depth: Int,
  in_string: Bool,
  escaped: Bool,
  token: BitArray,
  is_key: Bool,
  expecting_key: Bool,
  keys: List(String),
) -> Result(Nil, Error) {
  case bytes {
    <<>> ->
      case depth == 0 && !in_string {
        True -> Ok(Nil)
        False -> Error(InvalidSample)
      }
    <<c:8, rest:bits>> ->
      case in_string {
        True ->
          case escaped, c {
            True, _ ->
              scan(
                rest,
                depth,
                True,
                False,
                case is_key {
                  True -> <<token:bits, c>>
                  False -> <<>>
                },
                is_key,
                expecting_key,
                keys,
              )
            False, 92 ->
              scan(
                rest,
                depth,
                True,
                True,
                case is_key {
                  True -> <<token:bits, c>>
                  False -> <<>>
                },
                is_key,
                expecting_key,
                keys,
              )
            False, 34 -> {
              case is_key {
                False ->
                  scan(rest, depth, False, False, <<>>, False, False, keys)
                True -> {
                  use text <- result.try(
                    bit_array.to_string(<<token:bits, 34>>)
                    |> result.map_error(fn(_) { InvalidSample }),
                  )
                  use name <- result.try(
                    json.parse(text, decode.string)
                    |> result.map_error(fn(_) { InvalidSample }),
                  )
                  case
                    list.contains(keys, name)
                    || !list.contains(
                      ["key", "value", "encoding", "time", "timestamp"],
                      name,
                    )
                  {
                    True -> Error(InvalidSample)
                    False ->
                      scan(rest, depth, False, False, <<>>, False, False, [
                        name,
                        ..keys
                      ])
                  }
                }
              }
            }
            _, _ ->
              case is_key && bit_array.byte_size(token) > 64 {
                True -> Error(InvalidSample)
                False ->
                  scan(
                    rest,
                    depth,
                    True,
                    False,
                    case is_key {
                      True -> <<token:bits, c>>
                      False -> <<>>
                    },
                    is_key,
                    expecting_key,
                    keys,
                  )
              }
          }
        False ->
          case c {
            34 ->
              scan(
                rest,
                depth,
                True,
                False,
                case expecting_key {
                  True -> <<34>>
                  False -> <<>>
                },
                expecting_key,
                False,
                keys,
              )
            123 if depth == 1 && keys == [] ->
              scan(rest, depth + 1, False, False, <<>>, False, True, keys)
            123 -> Error(InvalidSample)
            91 if depth < 8 ->
              scan(rest, depth + 1, False, False, <<>>, False, False, keys)
            91 -> Error(InvalidSample)
            125 | 93 if depth > 0 ->
              scan(rest, depth - 1, False, False, <<>>, False, False, keys)
            125 | 93 -> Error(InvalidSample)
            44 if depth == 2 ->
              scan(rest, depth, False, False, <<>>, False, True, keys)
            _ ->
              scan(rest, depth, False, False, <<>>, False, expecting_key, keys)
          }
      }
    _ -> Error(InvalidSample)
  }
}

fn sample(
  body: String,
  expected_key: String,
) -> Result(Option(Envelope), Error) {
  use _ <- result.try(
    scan(bit_array.from_string(body), 0, False, False, <<>>, False, False, []),
  )
  use values <- result.try(
    json.parse(body, decode.list(sample_decoder()))
    |> result.map_error(fn(_) { InvalidSample }),
  )
  case values {
    [] -> Ok(None)
    [#(key, value)] if key == expected_key -> Ok(Some(value))
    _ -> Error(InvalidSample)
  }
}

fn get(config: Config, key: String) -> Result(Option(Envelope), Error) {
  use response <- result.try(
    http.request(config.endpoint, http.Get, key, "", 500)
    |> result.map_error(Http),
  )
  sample(response.body, key)
}

fn store(config: Config, key: String, value: Envelope) -> Result(Nil, Error) {
  use old <- result.try(get(config, key))
  case old {
    Some(existing) if existing == value -> Ok(Nil)
    Some(_) -> Error(NamespaceConflict)
    None -> {
      use _ <- result.try(
        http.request(config.endpoint, http.Put, key, encode(value), 500)
        |> result.map_error(Http),
      )
      use readback <- result.try(get(config, key))
      case readback == Some(value) {
        True -> Ok(Nil)
        False -> Error(NamespaceConflict)
      }
    }
  }
}

fn publish(state: State) -> Result(State, Error) {
  case state.pending {
    Some(Custodied(frame, seq)) -> {
      // A timed-out report may already have retired this exact frame. Keep the
      // known broker custody across ticks, and reconcile only that ID.
      let reported =
        peers.report_delivery(
          state.peer,
          frame.id,
          frame.destination,
          peer.TransportAccepted,
        )
      case reported {
        Ok(_) | Error(peer.NotOutstanding) ->
          Ok(
            State(
              ..state,
              pending: None,
              send_seq: dict.insert(state.send_seq, frame.destination, seq + 1),
              stats: Stats(
                ..state.stats,
                published: state.stats.published + 1,
                custody_pending: False,
              ),
            ),
          )
        Error(error) -> Error(Peer(error))
      }
    }
    None -> publish_new(state)
  }
}

fn publish_new(state: State) -> Result(State, Error) {
  case state.stats.published >= max_publications {
    True -> Error(RunQuota)
    False -> {
      use frames <- result.try(
        peers.pull(state.peer, 1) |> result.map_error(Peer),
      )
      case frames {
        [] -> Ok(state)
        [frame, ..] -> {
          case list.contains(state.config.peers, frame.destination) {
            False -> Error(InvalidConfig)
            True -> {
              let seq =
                dict.get(state.send_seq, frame.destination) |> result.unwrap(1)
              use _ <- result.try(store(
                state.config,
                key(state.config, state.config.local, frame.destination, seq),
                envelope(frame, state.config.local),
              ))
              // Commit custody before attempting the fallible peer report on the
              // next tick. Report failure cannot roll back this publication phase.
              Ok(
                State(
                  ..state,
                  pending: Some(Custodied(frame, seq)),
                  stats: Stats(
                    ..state.stats,
                    custody_pending: True,
                    last_stored_wire: Some(frame.wire),
                  ),
                ),
              )
            }
          }
        }
      }
    }
  }
}

fn consume(state: State) -> Result(State, Error) {
  case list.first(list.drop(state.config.peers, state.next_peer)) {
    Error(_) -> Ok(state)
    Ok(sender) -> {
      let seq = dict.get(state.recv_seq, sender) |> result.unwrap(1)
      case seq > max_publications {
        True -> Error(RunQuota)
        False -> {
          use sample <- result.try(get(
            state.config,
            key(state.config, sender, state.config.local, seq),
          ))
          case sample {
            None -> Ok(state)
            Some(value) -> {
              case
                value.sender == sender
                && value.destination == state.config.local
              {
                False -> Error(InvalidSample)
                True -> {
                  use _ <- result.try(
                    peers.receive_wire(state.peer, sender, value.wire)
                    |> result.map_error(Peer),
                  )
                  Ok(
                    State(
                      ..state,
                      recv_seq: dict.insert(state.recv_seq, sender, seq + 1),
                      stats: Stats(
                        ..state.stats,
                        applied: state.stats.applied + 1,
                        last_applied_wire: Some(value.wire),
                      ),
                    ),
                  )
                }
              }
            }
          }
        }
      }
    }
  }
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Snapshot(reply) -> {
      process.send(reply, state.stats)
      actor.continue(state)
    }
    Shutdown(reply) -> {
      let _ = process.cancel_timer(state.timer)
      process.send(reply, state.stats)
      actor.stop()
    }
    Tick -> {
      let outcome = case state.publish_turn {
        True -> publish(state)
        False -> consume(state)
      }
      let next = case outcome {
        Ok(next) -> State(..next, stats: Stats(..next.stats, last_error: None))
        Error(error) ->
          State(
            ..state,
            stats: Stats(
              ..state.stats,
              failures: int.min(mesh_wire.max_integer, state.stats.failures + 1),
              last_error: Some(error),
              halted: error == Http(http.CleanupUnconfirmed),
            ),
          )
      }
      let next_peer = case state.publish_turn {
        True -> state.next_peer
        False ->
          { state.next_peer + 1 } % int.max(1, list.length(state.config.peers))
      }
      case next.stats.halted {
        True -> actor.continue(next)
        False -> {
          let timer = process.send_after(state.subject, 20, Tick)
          actor.continue(
            State(
              ..next,
              timer: timer,
              publish_turn: !state.publish_turn,
              next_peer: next_peer,
            ),
          )
        }
      }
    }
  }
}

pub fn start(
  config: Config,
  peer_handle: peers.Handle,
) -> actor.StartResult(Handle) {
  actor.new_with_initialiser(1500, fn(subject) {
    use view <- result.try(
      peers.snapshot(peer_handle)
      |> result.map_error(fn(_) { "peer unavailable" }),
    )
    let engine = peer.engine_snapshot(view.peer)
    case
      engine.local_node_id == config.local
      && list.sort(list.map(engine.peers, fn(p) { p.node_id }), string.compare)
      == list.sort(config.peers, string.compare)
    {
      False -> Error("peer configuration mismatch")
      True -> {
        case
          register_worker(
            #("uos.ev98.transport", config.run, config.local),
            process.self(),
          )
        {
          No -> Error("transport worker already exists for run/local identity")
          Yes -> {
            let timer = process.send_after(subject, 20, Tick)
            Ok(
              actor.initialised(State(
                config,
                peer_handle,
                subject,
                timer,
                dict.new(),
                dict.new(),
                0,
                True,
                None,
                Stats(0, 0, 0, None, False, False, None, None),
              ))
              |> actor.returning(Handle(subject)),
            )
          }
        }
      }
    }
  })
  |> actor.on_message(handle)
  |> actor.start
}

/// One worker per local identity/run. Restarts refuse collisions; recovery uses
/// an explicitly fresh run. Caller must bound control mailbox demand.
pub fn supervised(
  config: Config,
  peer_handle: peers.Handle,
) -> supervision.ChildSpecification(Handle) {
  supervision.worker(fn() { start(config, peer_handle) })
  |> supervision.restart(supervision.Transient)
  |> supervision.timeout(4000)
}

fn call(
  handle: Handle,
  message: fn(Subject(Stats)) -> Message,
) -> Result(Stats, Error) {
  use owner <- result.try(
    process.subject_owner(handle.subject)
    |> result.map_error(fn(_) { Unavailable }),
  )
  let monitor = process.monitor(owner)
  let reply = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select_map(reply, Ok)
    |> process.select_specific_monitor(monitor, fn(_) { Error(Unavailable) })
  process.send(handle.subject, message(reply))
  let response =
    process.selector_receive(selector, 4000)
    |> result.map_error(fn(_) { Unavailable })
    |> result.flatten
  process.demonitor_process(monitor)
  response
}

pub fn snapshot(handle: Handle) -> Result(Stats, Error) {
  call(handle, Snapshot)
}

pub fn shutdown(handle: Handle) -> Result(Stats, Error) {
  call(handle, Shutdown)
}
