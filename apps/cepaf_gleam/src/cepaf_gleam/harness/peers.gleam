//// Actual peer discovery and bounded review transport. Delivery is not ACK.
//// User explicitly requested Claude/Fable and AGY review in this conversation.
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import uos_swarm/herdr

pub fn names() -> List(String) {
  ["harness_peers", "harness_peer_read", "harness_peer_review", "harness_peer_note"]
}
fn field(args: value.Value, key: String) -> Result(String, String) {
  use v <- result.try(value.get(args, key))
  case v { value.Text(s) -> Ok(s) _ -> Error("peer_string_field:" <> key) }
}
fn exact(args: value.Value, keys: List(String)) -> Result(Nil, String) {
  case args {
    value.Object(fields) -> case list.length(fields) == list.length(keys) && list.all(fields, fn(p) { list.contains(keys, p.0) }) {
      True -> Ok(Nil)
      False -> Error("peer_exact_schema")
    }
    _ -> Error("peer_arguments_object")
  }
}
fn failure(f: herdr.Failure) -> String {
  herdr.failure_to_json(f) |> json.to_string
}
fn requested_scope(agent: String) -> herdr.Scope {
  // The operator specifically requested the discovered Claude reviewer. Its
  // NAS parent project is a read-only review context, not a source-write grant.
  herdr.Scope(agent == "claude", True)
}
pub fn call(binding: dev.Binding, name: String, args: value.Value) -> Result(json.Json, String) {
  use _ <- result.try(dev.fence(binding))
  case name {
    "harness_peers" -> {
      use _ <- result.try(exact(args, []))
      use peers <- result.try(herdr.discover() |> result.map_error(failure))
      Ok(json.object([#("agents", json.array(peers, herdr.agent_to_json)), #("peer_acknowledged", json.bool(False))]))
    }
    "harness_peer_read" | "harness_peer_review" | "harness_peer_note" -> {
      let keys = case name {
        "harness_peer_review" -> ["pane_id", "session_id", "review_id", "packet_path"]
        "harness_peer_note" -> ["pane_id", "session_id", "review_id", "note"]
        _ -> ["pane_id", "session_id"]
      }
      use _ <- result.try(exact(args, keys))
      use pane <- result.try(field(args, "pane_id"))
      use session <- result.try(field(args, "session_id"))
      let target = herdr.Target(pane, session)
      use peers <- result.try(herdr.discover() |> result.map_error(failure))
      use peer <- result.try(list.find(peers, fn(p) { p.pane_id == pane }) |> result.map_error(fn(_) { "peer_not_discovered" }))
      use _ <- result.try(case peer.agent == "claude" || peer.agent == "agy" {
        True -> Ok(Nil)
        False -> Error("only_requested_claude_or_agy_review")
      })
      use _ <- result.try(herdr.validate_target(target, peer, requested_scope(peer.agent)) |> result.map_error(herdr.validation_reason))
      case name {
        "harness_peer_read" -> herdr.read(target, requested_scope(peer.agent)) |> result.map(herdr.receipt_to_json) |> result.map_error(failure)
        _ -> review(binding, args, target, requested_scope(peer.agent), name == "harness_peer_note")
      }
    }
    _ -> Error("unknown_peer_tool")
  }
}
fn review(binding: dev.Binding, args: value.Value, target: herdr.Target, scope: herdr.Scope, is_note: Bool) -> Result(json.Json, String) {
  use id <- result.try(field(args, "review_id"))
  use path <- result.try(case is_note { True -> Ok("docs/design/20260909-0412-harness-evolution-review-packet.md") False -> field(args, "packet_path") })
  use _ <- result.try(case dev.valid_identifier(id) && !string.contains(id, "/") && !string.contains(id, ".")
    && path == "docs/design/20260909-0412-harness-evolution-review-packet.md" {
    True -> Ok(Nil)
    False -> Error("peer_review_scope")
  })
  use packet <- result.try(files.read(dev.root, path))
  let initial_message = "Operator explicitly requires comprehensive independent Claude/Fable and AGY review of all UOS harness evolution decisions. Please acknowledge your actual session/model identity and read " <> dev.root <> "/" <> path
    <> " (sha256 " <> files.digest(packet) <> "). Review requirements, denotations/algebra, implementation/FFI, authority/Jidoka/TPS, replay/clock, OpenRouter $10/day, evaluation, dev/prod/standby/hot upgrade, SDLC/SRE and all 17 aspects. Use your own canonical Sa-plan review claim and preserve concurrent work. Read-only review; no production effects or broad edits. The operator approved a one-time development bootstrap for needed harness repair; prefer admitted MCP/Zenoh services, record any unavailable surface. Return explicit ACK and candidate/source-bound findings with file/line, severity, falsifier, fix and residual gap. Review delivery is not approval or admission. Do not treat counts, models, catalogs or prior EV claims as passing evidence. Root coordinator session: " <> binding.session <> ". Review request ID: " <> id <> "."
  use message <- result.try(case is_note {
    True -> field(args, "note") |> result.map(fn(note) { "UOS harness review follow-up from root " <> binding.session <> ": " <> note })
    False -> Ok(initial_message)
  })
  use _ <- result.try(herdr.validate_message(message) |> result.map_error(herdr.validation_reason))
  let signature = files.digest(target.pane_id <> "\n" <> target.session_id <> "\n" <> message)
  let pending = dev.effects <> "20260909-0412-peer-" <> id <> "-intent.json"
  // Presence is a stop line for ambiguous prompt retries, including after timeout.
  use _ <- result.try(files.create(dev.root, pending, json.to_string(json.object([
    #("request_id", json.string(id)), #("signature", json.string(signature)),
    #("pane_id", json.string(target.pane_id)), #("session_id", json.string(target.session_id)),
    #("packet_path", json.string(path)), #("packet_sha256", json.string(files.digest(packet))),
  ])) <> "\n"))
  use _ <- result.try(dev.fence(binding))
  let dispatched = herdr.prompt(target, message, scope)
  let receipt = case dispatched { Ok(r) -> herdr.receipt_to_json(r) Error(f) -> herdr.failure_to_json(f) }
  use _ <- result.try(files.create(dev.root, dev.effects <> "20260909-0412-peer-" <> id <> "-result.json", json.to_string(receipt) <> "\n"))
  case dispatched { Ok(_) -> Ok(receipt) Error(f) -> Error(failure(f)) }
}
