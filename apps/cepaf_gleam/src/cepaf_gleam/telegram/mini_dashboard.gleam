//// Actual dashboard observations. Reachability, registration and counters are not health proof.
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/ha/beam_metrics as beam
import cepaf_gleam/harness/observer_policy as policy
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Io {
  Io(
    podman: fn(Int) -> Result(api.Observation, String),
    peers: fn(Int) -> Result(String, String),
    probe: fn(String, Int) -> Result(Int, String),
    metrics: fn(Int) -> Result(beam.BeamMetrics, String),
    monotonic_ms: fn() -> Int,
    unix_seconds: fn() -> Int,
  )
}
pub const services = ["matrix", "cockpit", "zenoh", "peer_runtime"]
type Part { Part(fields: List(#(String, String)), observed: Bool) }

fn require(ok: Bool) -> Result(Nil, String) {
  case ok { True -> Ok(Nil) False -> Error("dashboard_observation_refused") }
}

fn step(io: Io, last: Int, deadline: Int, cap: Int,
  read: fn(Int) -> Result(a, String)) -> Result(#(Result(a, String), Int), String) {
  let before = io.monotonic_ms()
  use _ <- result.try(require(before >= last && deadline - before >= 100))
  let observed = read(int.min(cap, deadline - before))
  let after = io.monotonic_ms()
  use _ <- result.try(require(after >= before && after < deadline))
  Ok(#(observed, after))
}

pub fn observe(io: Io) -> api.Observation {
  case collect(io) {
    Ok(observation) -> observation
    Error(_) -> api.Unavailable("dashboard_deadline_or_clock_refused")
  }
}

fn collect(io: Io) -> Result(api.Observation, String) {
  let started = io.monotonic_ms()
  let deadline = started + 4500
  use #(podman, t1) <- result.try(step(io, started, deadline, 1200, io.podman))
  use #(peers, t2) <- result.try(step(io, t1, deadline, 1500, io.peers))
  use #(probes, t3) <- result.try(probe_all(io, services, [], t2, deadline))
  use #(metrics, t4) <- result.try(step(io, t3, deadline, 100, io.metrics))
  let ended = io.monotonic_ms()
  let now = io.unix_seconds()
  use _ <- result.try(require(ended >= t4 && ended < deadline && now > 0))
  let podman = podman_part(podman, now)
  let peers = peers_part(peers)
  let metrics = metrics_part(metrics)
  let parts = [podman, peers, ..probes]
  case list.any(parts, fn(p) { p.observed }) {
    False -> Ok(api.Unavailable("dashboard_sources_unavailable"))
    True -> {
      let complete = list.all([metrics, ..parts], fn(p) { p.observed })
      let base = [
        #("Scope", "Local service-account Podman inventory, coordinator records, service VM counters and fixed HTTP probes"),
        #("Overall health", "UNKNOWN: counters, registration and reachability do not prove application or fleet health"),
        #("Observation completeness", case complete { True -> "All configured observation sources answered" False -> "Partial: one or more sources unavailable" }),
        #("Runtime admission", "NOT_GRANTED"),
        #("Agent liveness", "Not probed; registered sessions and self-reported heartbeats are not process liveness"),
        #("HTTP meaning", "Status headers only; redirects are not followed; successful HTTP is not application health"),
      ]
      let fields = list.fold([metrics, ..parts], base, fn(acc, p) {
        list.append(acc, p.fields)
      })
      use _ <- result.try(require(list.length(fields) <= 100 && list.all(fields, fn(p) {
        string.byte_size(p.0) <= 128 && string.byte_size(p.1) <= 2048
      })))
      Ok(api.Observed(now, "operational_dashboard", dict.from_list(fields)))
    }
  }
}

fn probe_all(io: Io, remaining: List(String), acc: List(Part), last: Int, deadline: Int)
  -> Result(#(List(Part), Int), String) {
  case remaining {
    [] -> Ok(#(list.reverse(acc), last))
    [name, ..rest] -> {
      use #(reply, at) <- result.try(step(io, last, deadline, 300, fn(budget) {
        io.probe(name, budget)
      }))
      let part = case reply {
        Ok(code) if code >= 200 && code <= 599 -> {
          let state = case code {
            n if n < 300 -> "responding"
            n if n < 400 -> "redirect not followed"
            401 | 403 -> "authentication required"
            _ -> "HTTP error"
          }
          Part([#("Service " <> name, "HTTP " <> int.to_string(code) <> ": " <> state)], True)
        }
        _ -> Part([#("Service " <> name, "Unavailable or refused")], False)
      }
      probe_all(io, rest, [part, ..acc], at, deadline)
    }
  }
}

fn count(fields: dict.Dict(String, String), key: String) -> Result(Int, String) {
  use raw <- result.try(dict.get(fields, key) |> result.replace_error("missing count"))
  use n <- result.try(int.parse(raw) |> result.replace_error("bad count"))
  use _ <- result.try(require(n >= 0 && n <= 128 && raw == int.to_string(n)))
  Ok(n)
}

fn podman_counts(observation: api.Observation, now: Int) -> Result(List(#(String, String)), String) {
  case observation {
    api.Observed(at, "local_podman_cli", fields) -> {
      use _ <- result.try(require(at > 0 && now >= at && now - at <= 10))
      use total <- result.try(count(fields, "Container count"))
      use running <- result.try(count(fields, "Running containers"))
      use images <- result.try(count(fields, "Image references"))
      use _ <- result.try(require(running <= total))
      Ok([
        #("Container count", int.to_string(total)),
        #("Running containers", int.to_string(running)),
        #("Image references", int.to_string(images)),
        #("Podman observation", "Observed local inventory; running is not healthy"),
      ])
    }
    _ -> Error("podman observation unavailable")
  }
}

fn podman_part(observation: Result(api.Observation, String), now: Int) -> Part {
  case observation |> result.try(fn(o) { podman_counts(o, now) }) {
    Ok(fields) -> Part(fields, True)
    Error(_) -> Part([#("Podman observation", "Unavailable; counts unknown")], False)
  }
}

type Peers { Peers(schema: String, view: String, authority: String, admission: String,
  sequence: Int, digest: String, total: Int, shown: Int, truncated: Bool, actual: Int) }

fn peers_decoder() -> decode.Decoder(Peers) {
  use schema <- decode.field("schema", decode.string)
  use view <- decode.field("view", decode.string)
  use authority <- decode.field("authority", decode.string)
  use admission <- decode.field("runtime_admission", decode.string)
  use sequence <- decode.field("sequence", decode.int)
  use digest <- decode.field("journal_digest", decode.string)
  use total <- decode.field("total_sessions", decode.int)
  use shown <- decode.field("shown", decode.int)
  use truncated <- decode.field("truncated", decode.bool)
  use sessions <- decode.field("sessions", decode.list(decode.dynamic))
  decode.success(Peers(schema, view, authority, admission, sequence, digest,
    total, shown, truncated, list.length(sessions)))
}

fn peers_fields(raw: String) -> Result(List(#(String, String)), String) {
  use _ <- result.try(require(string.byte_size(raw) <= 32768))
  use p <- result.try(json.parse(raw, peers_decoder()) |> result.replace_error("invalid peers"))
  use _ <- result.try(require(
    p.schema == "uos.telegram.coordination.v1" && p.view == "peers"
    && p.authority == "observation_only" && p.admission == "NOT_GRANTED"
    && p.sequence >= 0 && policy.valid_digest(p.digest)
    && p.total >= 0 && p.total <= 256 && p.shown == int.min(p.total, 20)
    && p.actual == p.shown && p.truncated == {p.total > p.shown}
  ))
  Ok([
    #("Registered sessions", int.to_string(p.total)),
    #("Displayed peer records", int.to_string(p.shown)),
    #("Coordinator sequence", int.to_string(p.sequence)),
    #("Coordinator journal digest", p.digest),
    #("Peer coverage", case p.truncated { True -> "Details truncated; total count covers all registered sessions" False -> "All registered sessions counted" }),
    #("Coordinator observation", "Observed read-only ledger; no admission or process liveness inferred"),
  ])
}

fn peers_part(raw: Result(String, String)) -> Part {
  case raw |> result.try(peers_fields) {
    Ok(fields) -> Part(fields, True)
    Error(_) -> Part([#("Coordinator observation", "Unavailable; session counts unknown")], False)
  }
}

fn metrics_fields(m: beam.BeamMetrics) -> Result(List(#(String, String)), String) {
  use _ <- result.try(require(m.scheduler_count >= 1 && list.all([
    m.process_count, m.memory_total_mb, m.memory_processes_mb, m.memory_ets_mb,
    m.memory_binary_mb, m.run_queue_length, m.uptime_seconds, m.io_input_mb,
    m.io_output_mb, m.atom_count, m.port_count,
  ], fn(n) { n >= 0 && n <= 9_007_199_254_740_991 })))
  Ok([
    #("VM scope", "This serving BEAM VM; counters sampled sequentially, not an atomic fleet snapshot"),
    #("Online schedulers", int.to_string(m.scheduler_count)),
    #("VM processes", int.to_string(m.process_count)),
    #("VM memory MiB", int.to_string(m.memory_total_mb)),
    #("VM run queue", int.to_string(m.run_queue_length)),
    #("VM uptime seconds", int.to_string(m.uptime_seconds)),
    #("VM cumulative input MiB", int.to_string(m.io_input_mb)),
    #("VM cumulative output MiB", int.to_string(m.io_output_mb)),
    #("VM threshold warnings", case beam.check_thresholds(m) {
      [] -> "None of the configured VM counter thresholds exceeded; application health not assessed"
      warnings -> string.join(warnings, "; ")
    }),
  ])
}

fn metrics_part(raw: Result(beam.BeamMetrics, String)) -> Part {
  case raw |> result.try(metrics_fields) {
    Ok(fields) -> Part(fields, True)
    Error(_) -> Part([#("VM observation", "Unavailable; counters unknown")], False)
  }
}
