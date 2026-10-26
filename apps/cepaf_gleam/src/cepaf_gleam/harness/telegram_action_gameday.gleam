//// Telegram ControlledAction adapter for the `/gameday` literal.
//// Contract: docs/design/20261026-0115-telegram-controlled-action-adapter-contract.md
////
//// Backend: `immune/chaos_immune_engine`. One gameday scenario is run in PURE
//// SIMULATION (a fresh in-memory immune engine state, one fault, one response);
//// every reply is labelled "confidence":"simulated". The only effect `execute`
//// has is one exclusive-create receipt under the caller's evidence directory.
//// No process, port, service or network is touched. Grants no authority.

import cepaf_gleam/harness/files
import cepaf_gleam/immune/chaos_immune_engine as engine
import gleam/float
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

const literal_name = "/gameday"

const max_args_bytes = 256

const max_reply_bytes = 3500

const max_stored_inline = 1800

pub opaque type Request {
  Request(scenario: String, fault: engine.ChaosFault)
}

pub fn literal() -> String {
  literal_name
}

/// Fixed scenario table; every row is one `ChaosFault` constructor of the
/// backend with fixed parameters. Callers select a name, never a parameter.
fn scenarios() -> List(#(String, engine.ChaosFault)) {
  [
    #("packet-loss-moderate", engine.PacketLoss(0.3)),
    #("packet-loss-catastrophic", engine.PacketLoss(0.8)),
    #("heartbeat-jitter-minor", engine.HeartbeatJitter(500)),
    #("heartbeat-jitter-severe", engine.HeartbeatJitter(3000)),
    #("worker-oom", engine.WorkerOom("synthetic-worker")),
    #("queue-latency-minor", engine.QueueLatencySpike(100.0)),
    #("queue-latency-spike", engine.QueueLatencySpike(900.0)),
  ]
}

fn names() -> List(String) {
  list.map(scenarios(), fn(row) { row.0 })
}

fn usage() -> String {
  "usage: /gameday <scenario> (pure simulation only); scenarios: "
  <> string.join(names(), ", ")
}

fn safe_token(text: String) -> Bool {
  text != ""
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("abcdefghijklmnopqrstuvwxyz0123456789-", c)
  })
}

pub fn parse(args: String) -> Result(Request, String) {
  let name = string.trim(args)
  case string.byte_size(args) <= max_args_bytes && safe_token(name) {
    False -> Error(usage())
    True ->
      case list.find(scenarios(), fn(row) { row.0 == name }) {
        Ok(#(n, fault)) -> Ok(Request(n, fault))
        Error(_) -> Error(usage())
      }
  }
}

pub fn effect_id(r: Request) -> String {
  files.digest("uos.telegram.action.v1|" <> literal_name <> "|" <> r.scenario)
}

fn fault_label(fault: engine.ChaosFault) -> String {
  case fault {
    engine.PacketLoss(_) -> "packet_loss"
    engine.HeartbeatJitter(_) -> "heartbeat_jitter"
    engine.WorkerOom(_) -> "worker_oom"
    engine.QueueLatencySpike(_) -> "queue_latency"
  }
}

fn response_kind(response: engine.ImmuneResponse) -> #(String, String) {
  case response {
    engine.AntibodyNeutralized(id, _) -> #("antibody_neutralized", id)
    engine.HotReloadTriggered(component) -> #("hot_reload_triggered", component)
    engine.ThrottlingEngaged(_) -> #("throttling_engaged", "concurrency_clamp")
    engine.AndonEmergencyHalt(_) -> #("andon_emergency_halt", "simulated_halt")
  }
}

fn milli(x: Float) -> Int {
  float.round(x *. 1000.0)
}

/// Pure simulation of one fault against a fresh in-memory engine state.
fn simulate(r: Request) -> List(#(String, json.Json)) {
  let #(state, response) =
    engine.inject_fault(engine.init_immune_engine(), r.fault)
  let #(kind, detail) = response_kind(response)
  [
    #("fault", json.string(fault_label(r.fault))),
    #("response", json.string(kind)),
    #("response_detail", json.string(detail)),
    #("andon_tripped", json.bool(state.is_andon_tripped)),
    #(
      "containment_preserved",
      json.bool(engine.is_containment_preserved(state)),
    ),
    #("faults_injected", json.int(state.total_faults_injected)),
    #("neutralized", json.int(state.total_neutralized)),
    #(
      "metabolic_health_milli",
      json.int(milli(engine.compute_metabolic_health(state))),
    ),
    #("lyapunov_milli", json.int(milli(state.lyapunov_exponent))),
  ]
}

fn denied(reason: String) -> String {
  json.object([
    #("status", json.string("denied")),
    #("literal", json.string(literal_name)),
    #("reason", json.string(reason)),
  ])
  |> json.to_string
}

fn bounded(reply: String) -> String {
  case string.byte_size(reply) <= max_reply_bytes {
    True -> reply
    False -> denied("reply_bound")
  }
}

fn head(status: String, r: Request) -> List(#(String, json.Json)) {
  [
    #("status", json.string(status)),
    #("literal", json.string(literal_name)),
    #("confidence", json.string("simulated")),
    #("effect_id", json.string(effect_id(r))),
    #("scenario", json.string(r.scenario)),
  ]
}

/// Read-only. Runs the pure simulation to show what the receipt would contain;
/// nothing is written and no live system is observed (confidence "simulated").
pub fn preview(r: Request) -> String {
  list.flatten([
    head("preview", r),
    simulate(r),
    [
      #("execute", json.string("pure_simulation_with_receipt")),
      #("real_effects", json.string("none")),
    ],
  ])
  |> json.object
  |> json.to_string
  |> bounded
}

fn receipt(r: Request) -> String {
  list.flatten([
    head("executed", r),
    simulate(r),
    [#("real_effects", json.string("none"))],
  ])
  |> json.object
  |> json.to_string
}

fn require_directory(dir: String) -> Result(Nil, String) {
  case string.byte_size(dir) > 0 && !string.contains(dir, "\u{0}") {
    False -> Error("evidence_dir_required")
    True ->
      case simplifile.link_info(dir) {
        Ok(info) ->
          case simplifile.file_info_type(info) == simplifile.Directory {
            True -> Ok(Nil)
            False -> Error("evidence_dir_required")
          }
        Error(_) -> Error("evidence_dir_required")
      }
  }
}

fn duplicate(r: Request, stored: String) -> String {
  let inline = case string.byte_size(stored) <= max_stored_inline {
    True -> stored
    False -> "omitted_over_bound"
  }
  json.object([
    #("status", json.string("duplicate")),
    #("literal", json.string(literal_name)),
    #("confidence", json.string("simulated")),
    #("effect_id", json.string(effect_id(r))),
    #("receipt_sha256", json.string(files.digest(stored))),
    #("stored_receipt", json.string(inline)),
  ])
  |> json.to_string
  |> bounded
}

/// Idempotent by effect_id; exclusive-create receipt under `evidence_dir`.
pub fn execute(r: Request, evidence_dir: String) -> Result(String, String) {
  use _ <- result.try(require_directory(evidence_dir))
  let relative = effect_id(r) <> ".json"
  case files.read(evidence_dir, relative) {
    Ok(stored) -> Ok(duplicate(r, stored))
    Error(_) -> {
      let body = receipt(r)
      case files.create(evidence_dir, relative, body) {
        Ok(Nil) -> Ok(bounded(body))
        Error(_) ->
          case files.read(evidence_dir, relative) {
            Ok(stored) -> Ok(duplicate(r, stored))
            Error(_) -> Error("receipt_write_failed")
          }
      }
    }
  }
}
