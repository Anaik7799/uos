//// Bounded command adapter for verified BEAM loading and live-evolution
//// observation actors. Each primary/backup command starts its own clock guard.
//// It observes the durable session lease for writer status; it never claims,
//// renews, releases, routes traffic, or publishes shared state.

import argv
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import uos_swarm/board_reader
import uos_swarm/clock_contract as clock
import uos_swarm/clock_guard as guard
import uos_swarm/coord
import uos_swarm/live_evolution as evolution
import uos_swarm/session_sync

@external(erlang, "session_sync_ffi", "halt")
fn halt(status: Int) -> Nil

const readiness_ttl_us = 120_000_000

type InstanceKind {
  Primary
  Backup
}

type LeaseObservation {
  LeaseObservation(
    host_id: String,
    boot_id: String,
    observed_boot_us: Int,
    resource: String,
    holder: String,
    epoch: Int,
    expires_boot_us: Int,
  )
}

fn parse_kind(value: String) -> Result(InstanceKind, String) {
  case value {
    "primary" -> Ok(Primary)
    "backup" -> Ok(Backup)
    _ -> Error("instance role must be primary or backup")
  }
}

fn expected_active(root: String) -> Result(List(String), String) {
  use journal <- result.try(session_sync.read_journal(root))
  use state <- result.try(session_sync.replay(journal))
  Ok(
    state.sessions
    |> dict.values
    |> list.filter(fn(session) { !session.retired })
    |> list.map(fn(session) { session.id })
    |> list.sort(string.compare),
  )
}

fn board_snapshot(
  path: String,
  expected: List(String),
) -> Result(guard.BoardSnapshot, String) {
  use body <- result.try(board_reader.read_file(path, board_reader.max_bytes))
  use input <- result.try(board_reader.from_zenoh(body))
  case input.malformed_count {
    0 -> Ok(guard.from_board_input(input, expected))
    _ -> Error("board snapshot contains malformed events")
  }
}

fn lease_json(
  state: session_sync.State,
  boot_id: String,
  now: Int,
  resource: String,
  holder: String,
) -> Result(json.Json, String) {
  use lease <- result.try(
    coord.live_leases(state.coordinator, now)
    |> list.find(fn(lease) {
      lease.resource == resource && lease.holder == holder
    })
    |> result.replace_error("primary has no current matching writer lease"),
  )
  Ok(
    json.object([
      #("host_id", json.string(state.host_id)),
      #("boot_id", json.string(boot_id)),
      #("observed_boot_us", json.int(now)),
      #("resource", json.string(lease.resource)),
      #("holder", json.string(lease.holder)),
      #("epoch", json.int(lease.epoch)),
      #("expires_boot_us", json.int(lease.expires_us)),
    ]),
  )
}

fn lease_decoder() -> decode.Decoder(LeaseObservation) {
  use host <- decode.field("host_id", decode.string)
  use boot <- decode.field("boot_id", decode.string)
  use observed <- decode.field("observed_boot_us", decode.int)
  use resource <- decode.field("resource", decode.string)
  use holder <- decode.field("holder", decode.string)
  use epoch <- decode.field("epoch", decode.int)
  use expires <- decode.field("expires_boot_us", decode.int)
  decode.success(LeaseObservation(
    host,
    boot,
    observed,
    resource,
    holder,
    epoch,
    expires,
  ))
}

fn current_writer(
  root: String,
  resource: String,
  holder: String,
  guard_state: guard.State,
) -> Result(evolution.WriterFence, String) {
  use reading <- result.try(option.to_result(
    guard_state.previous,
    "clock guard has no verified current reading",
  ))
  let clock.Reading(domain, _, guard_now) = reading
  let clock.Domain(host_id, boot_id) = domain
  use encoded <- result.try(
    session_sync.observe(root, fn(state, local_boot, now) {
      lease_json(state, local_boot, now, resource, holder)
    }),
  )
  use lease <- result.try(
    json.parse(encoded, lease_decoder())
    |> result.replace_error("invalid session lease observation"),
  )
  use _ <- result.try(case lease.boot_id == boot_id {
    True -> Ok(Nil)
    False -> Error("clock guard and writer lease use different boot domains")
  })
  use _ <- result.try(
    case
      lease.host_id != ""
      && guard_now >= lease.observed_boot_us
      && guard_now < lease.expires_boot_us
    {
      True -> Ok(Nil)
      False -> Error("writer lease observation is future, expired, or hostless")
    },
  )
  Ok(evolution.WriterFence(
    lease.resource,
    lease.holder,
    lease.epoch,
    evolution.ClockDomain(host_id, boot_id),
    guard_now,
    lease.expires_boot_us,
  ))
}

fn guard_snapshot(subject) -> Result(guard.State, String) {
  let reply = process.new_subject()
  process.send(subject, guard.Snapshot(reply))
  process.receive(reply, 2000)
  |> result.replace_error("clock guard snapshot timeout")
}

fn instance_snapshot(subject) -> Result(evolution.InstanceHeartbeat, String) {
  let reply = process.new_subject()
  process.send(subject, evolution.Snapshot(reply))
  process.receive(reply, 2000)
  |> result.replace_error("live evolution snapshot timeout")
}

fn probe(subject, instance_id, release) {
  use state <- result.try(guard_snapshot(subject))
  use reading <- result.try(option.to_result(
    state.previous,
    "clock guard has no verified current reading",
  ))
  evolution.readiness_from_clock_guard(
    instance_id,
    release,
    state,
    reading.boot_us,
    readiness_ttl_us,
  )
  |> result.map_error(fn(_) { "clock guard readiness is unhealthy" })
}

fn pulse(guard_subject, instance_subject) -> Result(String, String) {
  process.send(guard_subject, guard.Tick)
  let _ = guard_snapshot(guard_subject)
  process.send(instance_subject, evolution.Tick)
  use heartbeat <- result.try(instance_snapshot(instance_subject))
  Ok(json.to_string(evolution.heartbeat_json(heartbeat)))
}

fn observe_many(
  guard_subject,
  instance_subject,
  remaining: Int,
  interval_ms: Int,
  output: List(String),
) -> Result(String, String) {
  case remaining <= 0 {
    True -> Ok(output |> list.reverse |> string.join("\n"))
    False -> {
      use line <- result.try(pulse(guard_subject, instance_subject))
      case remaining > 1 {
        True -> process.sleep(interval_ms)
        False -> Nil
      }
      observe_many(guard_subject, instance_subject, remaining - 1, interval_ms, [
        line,
        ..output
      ])
    }
  }
}

fn run_instance(
  kind: InstanceKind,
  count: Int,
  interval_ms: Int,
  instance_id: String,
  resource: String,
  candidate: String,
  digest: String,
  board_path: String,
  session_root: String,
  floor_path: String,
) -> Result(String, String) {
  use floor <- result.try(guard.load_floor(floor_path))
  use expected <- result.try(expected_active(session_root))
  let board = fn() { board_snapshot(board_path, expected) }
  let guard.Config(version, _, actor_ttl, retention, policy) =
    guard.strict_config()
  let config = guard.Config(version, interval_ms, actor_ttl, retention, policy)
  use guard_started <- result.try(
    guard.start_actor(config, floor, guard.live_sample, board, fn(value) {
      guard.store_floor(floor_path, value)
    })
    |> result.replace_error("clock guard actor failed to start"),
  )
  process.send(guard_started.data, guard.Tick)
  let guard_state = guard_snapshot(guard_started.data)
  let release = evolution.Release(candidate, digest, 1)
  let configured = case kind, guard_state {
    Backup, Ok(_) -> Ok(#(evolution.WarmObserver, None))
    Primary, Ok(state) -> {
      use fence <- result.try(current_writer(
        session_root,
        resource,
        instance_id,
        state,
      ))
      Ok(#(evolution.ServingWriter(fence.epoch), Some(fence)))
    }
    _, Error(reason) -> Error(reason)
  }
  let outcome = case configured {
    Error(reason) -> Error(reason)
    Ok(configuration) -> {
      let #(role, writer) = configuration
      use started <- result.try(
        evolution.start_instance(
          evolution.InstanceConfig(
            instance_id,
            role,
            release,
            writer,
            interval_ms,
          ),
          fn() { probe(guard_started.data, instance_id, release) },
        )
        |> result.replace_error("live evolution actor failed to start"),
      )
      let result =
        observe_many(guard_started.data, started.data, count, interval_ms, [])
      process.send(started.data, evolution.Stop)
      result
    }
  }
  process.send(guard_started.data, guard.Stop)
  outcome
}

pub fn run(args: List(String)) -> Result(String, String) {
  case args {
    ["modules"] -> Ok(evolution.allowed_modules() |> string.join("\n"))
    ["inspect-loaded", label] -> {
      use artifact <- result.try(evolution.loaded_artifact(label))
      Ok(
        json.to_string(
          json.object([
            #("module", json.string(label)),
            #("artifact_root", json.string(artifact.0)),
            #("sha256", json.string(artifact.1)),
          ]),
        ),
      )
    }
    ["verify", root, label, digest] ->
      evolution.verify_artifact(root, label, digest)
    ["load", root, label, digest] ->
      evolution.load_verified(root, label, digest)
    [
      "instance-once",
      kind,
      instance,
      resource,
      candidate,
      digest,
      board,
      session_root,
      floor,
    ] -> {
      use kind <- result.try(parse_kind(kind))
      run_instance(
        kind,
        1,
        60_000,
        instance,
        resource,
        candidate,
        digest,
        board,
        session_root,
        floor,
      )
    }
    [
      "instance-watch",
      kind,
      count_text,
      interval_text,
      instance,
      resource,
      candidate,
      digest,
      board,
      session_root,
      floor,
    ] -> {
      use kind <- result.try(parse_kind(kind))
      use count <- result.try(
        int.parse(count_text)
        |> result.replace_error("count must be an integer"),
      )
      use interval <- result.try(
        int.parse(interval_text)
        |> result.replace_error("interval must be an integer"),
      )
      use _ <- result.try(
        case
          count > 0 && count <= 100 && interval >= 50 && interval <= 3_600_000
        {
          True -> Ok(Nil)
          False ->
            Error("watch bounds are count 1..100 and interval 50..3600000 ms")
        },
      )
      run_instance(
        kind,
        count,
        interval,
        instance,
        resource,
        candidate,
        digest,
        board,
        session_root,
        floor,
      )
    }
    _ -> Error(usage())
  }
}

pub fn usage() -> String {
  "gleam run -m live_evolution_cli -- modules\n"
  <> "inspect-loaded <allowlisted_module>\n"
  <> "verify <absolute_artifact_root> <allowlisted_module> <sha256>\n"
  <> "load <absolute_artifact_root> <allowlisted_module> <sha256>\n"
  <> "instance-once <primary|backup> <instance_id> <runtime:resource> <candidate> <sha256> <board_json> <session_root> <primary_floor_file|backup_floor_file>\n"
  <> "instance-watch <primary|backup> <count:1..100> <interval_ms:50..3600000> <instance_id> <runtime:resource> <candidate> <sha256> <board_json> <session_root> <primary_floor_file|backup_floor_file>\n"
  <> "Each instance runs a distinct clock guard. The backup remains observer-only; the primary advertises a writer only from a current durable session lease. No command routes traffic or grants authority.\n"
}

fn respond(outcome: Result(String, String)) -> Nil {
  case outcome {
    Ok(text) -> io.println(text)
    Error(reason) -> {
      io.println(
        json.to_string(
          json.object([
            #("ok", json.bool(False)),
            #("error", json.string(reason)),
          ]),
        ),
      )
      halt(1)
    }
  }
}

pub fn main() -> Nil {
  case argv.load().arguments {
    [] | ["help"] | ["--help"] -> io.println(usage())
    arguments -> respond(run(arguments))
  }
}
