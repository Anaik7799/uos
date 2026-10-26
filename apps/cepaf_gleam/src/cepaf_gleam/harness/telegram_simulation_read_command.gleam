//// Bounded Telegram read commands for simulation-style literals.
//// An "ok" reply is a pure, in-repo simulation run on explicit caller inputs.
//// It is a truthful observation of that simulation, never of the live system.
//// Literals with no pure backend report backend_unavailable and name the gap.

import cepaf_gleam/crdt/health_bridge
import cepaf_gleam/crdt/spatial
import cepaf_gleam/planning/sa_plan_simulator as sim
import cepaf_gleam/zenoh/peer_simulator as peer
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string

const max_args_bytes = 256

const max_reply_bytes = 3500

const args_alphabet = "abcdefghijklmnopqrstuvwxyz0123456789 \t:,_-"

const id_alphabet = "abcdefghijklmnopqrstuvwxyz0123456789_-"

const quorum_threshold = 0.67

/// The literals this module answers.
pub fn literals() -> List(String) {
  ["/whatif", "/simulate", "/babel", "/canvas", "/whiteboard"]
}

/// Answer one literal with a JSON object rendered as text.
pub fn handle(literal: String, args: String) -> String {
  case list.contains(literals(), literal) {
    False -> denied(literal, "not handled by telegram_simulation_read_command")
    True ->
      case string.byte_size(args) <= max_args_bytes {
        False -> denied(literal, "Arguments exceed 256 bytes.")
        True ->
          case literal {
            "/whatif" -> whatif(args)
            "/simulate" -> simulate(args)
            "/canvas" -> canvas(args)
            "/babel" ->
              unavailable(
                literal,
                "cepaf_gleam/harness/telegram_collab.handle_babel",
                "Live speech translation needs a voice stream and a translation model; the only in-repo handler returns static text.",
              )
            _ ->
              unavailable(
                literal,
                "cepaf_gleam/harness/telegram_collab.handle_whiteboard",
                "Whiteboard-to-code synthesis needs an uploaded photo and a vision model; the only in-repo handler returns static text.",
              )
          }
      }
  }
}

// ---------------------------------------------------------------- replies

fn finish(body: json.Json) -> String {
  let text = json.to_string(body)
  case string.byte_size(text) <= max_reply_bytes {
    True -> text
    False ->
      json.to_string(
        json.object([
          #("status", json.string("denied")),
          #("command", json.string("unknown")),
          #("reason", json.string("reply exceeds 3500 bytes")),
        ]),
      )
  }
}

fn denied(command: String, reason: String) -> String {
  finish(
    json.object([
      #("status", json.string("denied")),
      #("command", json.string(safe_echo(command))),
      #("reason", json.string(reason)),
    ]),
  )
}

fn unavailable(command: String, backend: String, reason: String) -> String {
  finish(
    json.object([
      #("status", json.string("backend_unavailable")),
      #("command", json.string(command)),
      #("backend", json.string(backend)),
      #("reason", json.string(reason)),
    ]),
  )
}

fn ok(command: String, backend: String, observation: json.Json) -> String {
  finish(
    json.object([
      #("status", json.string("ok")),
      #("command", json.string(command)),
      #("backend", json.string(backend)),
      #("observation", observation),
    ]),
  )
}

fn safe_echo(text: String) -> String {
  case string.byte_size(text) <= 64 {
    True -> text
    False -> string.slice(text, 0, 64)
  }
}

// ---------------------------------------------------------------- parsing

fn tokens(args: String) -> Result(List(String), Nil) {
  let trimmed = string.trim(args)
  case
    list.all(string.to_graphemes(trimmed), fn(c) {
      string.contains(args_alphabet, c)
    })
  {
    False -> Error(Nil)
    True ->
      Ok(
        trimmed
        |> string.replace("\t", " ")
        |> string.split(" ")
        |> list.filter(fn(t) { t != "" }),
      )
  }
}

fn bounded_int(text: String, low: Int, high: Int) -> Result(Int, Nil) {
  case int.parse(text) {
    Ok(n) if n >= low && n <= high -> Ok(n)
    _ -> Error(Nil)
  }
}

fn valid_id(text: String) -> Bool {
  let n = string.length(text)
  n >= 1
  && n <= 16
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains(id_alphabet, c)
  })
}

// ---------------------------------------------------------------- /whatif

const whatif_backend = "cepaf_gleam/planning/sa_plan_simulator"

const whatif_usage = "Usage: /whatif claim <workers 1-15> | retry <max_attempts 1-8> | zombie <lease_until_ns> <now_ns>"

fn whatif(args: String) -> String {
  case tokens(args) {
    Ok(["claim", n]) ->
      case bounded_int(n, 1, 15) {
        Ok(count) -> whatif_claim(count)
        Error(_) -> denied("/whatif", whatif_usage)
      }
    Ok(["retry", m]) ->
      case bounded_int(m, 1, 8) {
        Ok(max) -> whatif_retry(max)
        Error(_) -> denied("/whatif", whatif_usage)
      }
    Ok(["zombie", lease, now]) ->
      case
        bounded_int(lease, 0, 1_000_000_000_000),
        bounded_int(now, 0, 1_000_000_000_000)
      {
        Ok(l), Ok(t) -> whatif_zombie(l, t)
        _, _ -> denied("/whatif", whatif_usage)
      }
    _ -> denied("/whatif", whatif_usage)
  }
}

fn synthetic_task(state: sim.SimTaskState, lease: Int) -> sim.SimTask {
  sim.SimTask(
    id: "whatif-task",
    title: "synthetic task",
    state: state,
    worker: None,
    lease_until_ns: lease,
    attempt: 0,
    result: None,
  )
}

fn task_state_text(state: sim.SimTaskState) -> String {
  case state {
    sim.SimAvailable -> "available"
    sim.SimExecuting -> "executing"
    sim.SimCompleted -> "completed"
    sim.SimFailed -> "failed"
  }
}

fn worker_names(n: Int, acc: List(String)) -> List(String) {
  case n <= 0 {
    True -> acc
    False -> worker_names(n - 1, ["w" <> int.to_string(n), ..acc])
  }
}

fn whatif_claim(count: Int) -> String {
  let workers = worker_names(count, [])
  let #(final_task, results) =
    sim.simulate_15_worker_claim(
      synthetic_task(sim.SimAvailable, 0),
      workers,
      1000,
      60_000,
    )
  let granted =
    list.count(results, fn(r) {
      case r {
        sim.ClaimGranted(..) -> True
        sim.ClaimRejected(_) -> False
      }
    })
  let winner = case results {
    [sim.ClaimGranted(_, w, _), ..] -> json.string(w)
    _ -> json.null()
  }
  let state = case final_task {
    option.Some(t) -> task_state_text(t.state)
    None -> "missing"
  }
  ok(
    "/whatif",
    whatif_backend,
    json.object([
      #("kind", json.string("pure_simulation")),
      #("scenario", json.string("concurrent_claim")),
      #("subject", json.string("synthetic task, not a live Sa-plan task")),
      #("workers", json.int(count)),
      #("granted", json.int(granted)),
      #("rejected", json.int(list.length(results) - granted)),
      #("winner", winner),
      #("final_task_state", json.string(state)),
    ]),
  )
}

fn job_step_json(job: sim.SimObanJob) -> json.Json {
  let #(state, delay) = case job.state {
    sim.JobAvailable -> #("available", 0)
    sim.JobExecuting -> #("executing", 0)
    sim.JobRetry(d) -> #("retry", d)
    sim.JobDead(_) -> #("dead", 0)
    sim.JobCompleted -> #("completed", 0)
  }
  json.object([
    #("attempt", json.int(job.attempt)),
    #("state", json.string(state)),
    #("backoff_seconds", json.int(delay)),
  ])
}

fn run_retries(job: sim.SimObanJob, budget: Int, acc: List(sim.SimObanJob)) {
  case budget <= 0 {
    True -> list.reverse(acc)
    False -> {
      let next = sim.simulate_oban_step(job)
      case next.state {
        sim.JobDead(_) -> list.reverse([next, ..acc])
        _ -> run_retries(next, budget - 1, [next, ..acc])
      }
    }
  }
}

fn whatif_retry(max: Int) -> String {
  let job =
    sim.SimObanJob(
      id: 1,
      name: "synthetic",
      state: sim.JobAvailable,
      attempt: 0,
      max_attempts: max,
    )
  let steps = run_retries(job, max + 1, [])
  ok(
    "/whatif",
    whatif_backend,
    json.object([
      #("kind", json.string("pure_simulation")),
      #("scenario", json.string("oban_retry_backoff")),
      #("subject", json.string("synthetic job, not a live Oban job")),
      #("max_attempts", json.int(max)),
      #("steps", json.array(steps, job_step_json)),
    ]),
  )
}

fn whatif_zombie(lease: Int, now: Int) -> String {
  let before = synthetic_task(sim.SimExecuting, lease)
  let after = sim.simulate_zombie_lease_reaper(before, now)
  ok(
    "/whatif",
    whatif_backend,
    json.object([
      #("kind", json.string("pure_simulation")),
      #("scenario", json.string("zombie_lease_reaper")),
      #("subject", json.string("synthetic task, not a live lease")),
      #("lease_until_ns", json.int(lease)),
      #("now_ns", json.int(now)),
      #("reaped", json.bool(after.state != before.state)),
      #("final_task_state", json.string(task_state_text(after.state))),
    ]),
  )
}

// -------------------------------------------------------------- /simulate

const simulate_backend = "cepaf_gleam/zenoh/peer_simulator"

const simulate_usage = "Usage: /simulate <node>:<mode> ... (1-7 unique nodes; mode nominal|degraded|partitioned|recovering)"

fn parse_mode(text: String) -> Result(peer.PeerSimMode, Nil) {
  case text {
    "nominal" -> Ok(peer.PeerNominal)
    "degraded" -> Ok(peer.PeerDegraded("operator_supplied_scenario"))
    "partitioned" -> Ok(peer.PeerPartitioned)
    "recovering" -> Ok(peer.PeerRecovering)
    _ -> Error(Nil)
  }
}

fn mode_text(mode: peer.PeerSimMode) -> String {
  case mode {
    peer.PeerNominal -> "nominal"
    peer.PeerDegraded(_) -> "degraded"
    peer.PeerPartitioned -> "partitioned"
    peer.PeerRecovering -> "recovering"
  }
}

fn parse_peer(token: String) -> Result(peer.PeerNodeState, Nil) {
  case string.split(token, ":") {
    [node, mode] ->
      case valid_id(node), parse_mode(mode) {
        True, Ok(m) ->
          Ok(peer.step_peer_simulation(peer.init_peer_node(node), m))
        _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn all_ok(items: List(Result(a, Nil))) -> Result(List(a), Nil) {
  list.try_map(items, fn(r) { r })
}

fn simulate(args: String) -> String {
  case tokens(args) {
    Ok(toks) -> {
      let n = list.length(toks)
      case n >= 1 && n <= 7 {
        False -> denied("/simulate", simulate_usage)
        True ->
          case all_ok(list.map(toks, parse_peer)) {
            Error(_) -> denied("/simulate", simulate_usage)
            Ok(peers) -> {
              let ids = list.map(peers, fn(p) { p.node_id })
              case list.length(list.unique(ids)) == n {
                False -> denied("/simulate", simulate_usage)
                True -> simulate_mesh(peers)
              }
            }
          }
      }
    }
    Error(_) -> denied("/simulate", simulate_usage)
  }
}

fn simulate_mesh(peers: List(peer.PeerNodeState)) -> String {
  let mesh = peer.build_simulated_mesh(health_bridge.empty_health_map(), peers)
  let #(met, avg, healthy, total) =
    peer.evaluate_mesh_quorum(mesh, quorum_threshold)
  ok(
    "/simulate",
    simulate_backend,
    json.object([
      #("kind", json.string("pure_simulation")),
      #("scenario", json.string("peer_mesh_quorum")),
      #("subject", json.string("simulated peers, not the live mesh")),
      #(
        "nodes",
        json.array(peers, fn(p) {
          json.object([
            #("node", json.string(p.node_id)),
            #("mode", json.string(mode_text(p.mode))),
            #("health_score", json.float(p.health_score)),
            #("is_stable", json.bool(p.is_stable)),
            #("circuit_state", json.string(p.circuit_state)),
          ])
        }),
      ),
      #("quorum_threshold", json.float(quorum_threshold)),
      #("quorum_met", json.bool(met)),
      #("average_health", json.float(avg)),
      #("healthy_nodes", json.int(healthy)),
      #("total_nodes", json.int(total)),
    ]),
  )
}

// ---------------------------------------------------------------- /canvas

const canvas_backend = "cepaf_gleam/crdt/spatial"

const canvas_usage = "Usage: /canvas <id>:<x>,<y>,<z> ... (1-8 unique ids, integer coordinates within +-1000000)"

fn parse_element(
  token: String,
  index: Int,
) -> Result(spatial.SpatialElement, Nil) {
  case string.split(token, ":") {
    [id, coords] ->
      case valid_id(id), string.split(coords, ",") {
        True, [x, y, z] ->
          case
            bounded_int(x, -1_000_000, 1_000_000),
            bounded_int(y, -1_000_000, 1_000_000),
            bounded_int(z, -1_000_000, 1_000_000)
          {
            Ok(a), Ok(b), Ok(c) ->
              Ok(spatial.SpatialElement(
                id: id,
                position: spatial.vec3(
                  int.to_float(a),
                  int.to_float(b),
                  int.to_float(c),
                ),
                rotation: spatial.vec3_zero(),
                scale: spatial.vec3(1.0, 1.0, 1.0),
                timestamp: index,
                node_id: "telegram",
              ))
            _, _, _ -> Error(Nil)
          }
        _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn insert_all(
  crdt: spatial.SpatialCRDT,
  elements: List(spatial.SpatialElement),
) -> spatial.SpatialCRDT {
  list.fold(elements, crdt, fn(acc, e) {
    spatial.apply_op(acc, spatial.Insert(e), e.timestamp, "telegram")
  })
}

fn canvas(args: String) -> String {
  case tokens(args) {
    Ok(toks) -> {
      let n = list.length(toks)
      case n >= 1 && n <= 8 {
        False -> denied("/canvas", canvas_usage)
        True ->
          case
            all_ok(list.index_map(toks, fn(t, i) { parse_element(t, i + 1) }))
          {
            Error(_) -> denied("/canvas", canvas_usage)
            Ok(elements) -> {
              let ids = list.map(elements, fn(e) { e.id })
              case list.length(list.unique(ids)) == n {
                False -> denied("/canvas", canvas_usage)
                True -> canvas_observe(elements)
              }
            }
          }
      }
    }
    Error(_) -> denied("/canvas", canvas_usage)
  }
}

fn vec_json(v: spatial.Vec3) -> json.Json {
  json.object([
    #("x", json.float(v.x)),
    #("y", json.float(v.y)),
    #("z", json.float(v.z)),
  ])
}

fn canvas_observe(elements: List(spatial.SpatialElement)) -> String {
  let full = insert_all(spatial.new(), elements)
  let #(odd, even) = list.partition(elements, fn(e) { e.timestamp % 2 == 1 })
  let replica_a = insert_all(spatial.new(), odd)
  let replica_b = insert_all(spatial.new(), even)
  let merged = spatial.merge(replica_a, replica_b)
  let #(low, high) = spatial.bounding_box(full)
  let extent = spatial.distance(low, high)
  ok(
    "/canvas",
    canvas_backend,
    json.object([
      #("kind", json.string("pure_simulation")),
      #("scenario", json.string("spatial_crdt_insert_and_merge")),
      #("subject", json.string("caller-supplied elements, not the live canvas")),
      #("element_count", json.int(spatial.element_count(full))),
      #("version", json.int(full.version)),
      #("bounding_box_min", vec_json(low)),
      #("bounding_box_max", vec_json(high)),
      #("diagonal_extent", json.float(extent)),
      #(
        "split_replicas_merge_converged",
        json.bool(spatial.converged(full, merged)),
      ),
    ]),
  )
}
