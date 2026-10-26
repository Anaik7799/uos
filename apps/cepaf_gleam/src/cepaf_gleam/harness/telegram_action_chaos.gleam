//// Telegram ControlledAction adapter for the `/chaos` literal.
//// Contract: docs/design/20261026-0115-telegram-controlled-action-adapter-contract.md
////
//// Backends: `testing/chaos_injector` (scenario catalogue) and `chaos/apoptosis`
//// (synthetic container lifecycle). The only effect `execute` has is one bounded,
//// in-process, development-only injection against a SYNTHETIC target, plus one
//// exclusive-create receipt under the caller's evidence directory. No process,
//// port, service, network or file outside `evidence_dir` is touched.
//// This module grants no authority; the service decides when `execute` runs.

import cepaf_gleam/chaos/apoptosis
import cepaf_gleam/harness/files
import cepaf_gleam/testing/chaos_injector.{
  type ChaosInjection, type ChaosScenario, type ChaosSeverity,
}
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

const literal_name = "/chaos"

const max_args_bytes = 256

const max_reply_bytes = 3500

const max_stored_inline = 1800

pub opaque type Request {
  Request(scenario: ChaosScenario)
}

pub fn literal() -> String {
  literal_name
}

fn allowlist() -> List(String) {
  chaos_injector.all_scenarios() |> list.map(fn(s) { s.name })
}

fn usage() -> String {
  "usage: /chaos <scenario> (development-only synthetic injection); scenarios: "
  <> string.join(allowlist(), ", ")
}

fn safe_token(text: String) -> Bool {
  text != ""
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("abcdefghijklmnopqrstuvwxyz0123456789-", c)
  })
}

/// Parse never performs IO. Anything outside the catalogue-derived allowlist is
/// refused with the usage text (which carries the allowlist).
pub fn parse(args: String) -> Result(Request, String) {
  let name = string.trim(args)
  case string.byte_size(args) <= max_args_bytes && safe_token(name) {
    False -> Error(usage())
    True ->
      case list.find(chaos_injector.all_scenarios(), fn(s) { s.name == name }) {
        Ok(scenario) -> Ok(Request(scenario))
        Error(_) -> Error(usage())
      }
  }
}

pub fn effect_id(r: Request) -> String {
  files.digest(
    "uos.telegram.action.v1|" <> literal_name <> "|" <> r.scenario.name,
  )
}

fn severity_label(severity: ChaosSeverity) -> String {
  case severity {
    chaos_injector.ChaosLow -> "LOW"
    chaos_injector.ChaosMedium -> "MEDIUM"
    chaos_injector.ChaosHigh -> "HIGH"
    chaos_injector.ChaosCritical -> "CRITICAL"
  }
}

fn guardian_required(severity: ChaosSeverity) -> Bool {
  case severity {
    chaos_injector.ChaosHigh | chaos_injector.ChaosCritical -> True
    _ -> False
  }
}

fn injection_label(injection: ChaosInjection) -> String {
  case injection {
    chaos_injector.KillProcess(_) -> "kill_process"
    chaos_injector.NetworkPartition(_) -> "network_partition"
    chaos_injector.LatencySpike(_) -> "latency_spike"
    chaos_injector.MemoryPressure(_) -> "memory_pressure"
    chaos_injector.DiskFull -> "disk_full"
    chaos_injector.NifFailure(_) -> "nif_failure"
    chaos_injector.ZenohDisconnect -> "zenoh_disconnect"
    chaos_injector.QuorumLoss -> "quorum_loss"
    chaos_injector.StaleData(_) -> "stale_data"
    chaos_injector.CpuSaturation(_) -> "cpu_saturation"
  }
}

fn declared_parameter(injection: ChaosInjection) -> String {
  case injection {
    chaos_injector.KillProcess(t) -> t
    chaos_injector.NetworkPartition(n) -> n
    chaos_injector.LatencySpike(ms) -> int.to_string(ms) <> "ms"
    chaos_injector.MemoryPressure(mb) -> int.to_string(mb) <> "mb"
    chaos_injector.DiskFull -> "ephemeral-disk"
    chaos_injector.NifFailure(n) -> n
    chaos_injector.ZenohDisconnect -> "zenoh-session"
    chaos_injector.QuorumLoss -> "quorum-nodes"
    chaos_injector.StaleData(s) -> int.to_string(s) <> "s"
    chaos_injector.CpuSaturation(p) -> int.to_string(p) <> "%"
  }
}

fn synthetic_target(r: Request) -> String {
  "synthetic:" <> r.scenario.name
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

/// Read-only. The catalogue is declared metadata (confidence "declared"); nothing
/// is injected and nothing is written.
pub fn preview(r: Request) -> String {
  let s = r.scenario
  json.object([
    #("status", json.string("preview")),
    #("literal", json.string(literal_name)),
    #("confidence", json.string("declared")),
    #("effect_id", json.string(effect_id(r))),
    #("scenario", json.string(s.name)),
    #("layer", json.string(s.layer)),
    #("severity", json.string(severity_label(s.severity))),
    #("guardian_required_for_live", json.bool(guardian_required(s.severity))),
    #("injection_type", json.string(injection_label(s.injection))),
    #("declared_parameter", json.string(declared_parameter(s.injection))),
    #("description", json.string(s.description)),
    #("target", json.string(synthetic_target(r))),
    #("execute", json.string("in_process_synthetic_with_receipt")),
    #("real_effects", json.string("none")),
  ])
  |> json.to_string
  |> bounded
}

/// One bounded in-process injection on a synthetic container. Pure.
fn run_synthetic(r: Request) -> #(Int, Int) {
  case r.scenario.injection {
    chaos_injector.KillProcess(_) -> {
      let container = synthetic_target(r)
      let state =
        apoptosis.init()
        |> apoptosis.register(container, 0)
        |> apoptosis.record_death(container, 1)
        |> apoptosis.record_resurrection(container, 2)
      #(state.total_deaths, state.total_resurrections)
    }
    _ -> #(0, 0)
  }
}

fn receipt(r: Request) -> String {
  let s = r.scenario
  let #(deaths, resurrections) = run_synthetic(r)
  json.object([
    #("status", json.string("executed")),
    #("literal", json.string(literal_name)),
    #("confidence", json.string("simulated")),
    #("effect_id", json.string(effect_id(r))),
    #("scenario", json.string(s.name)),
    #("layer", json.string(s.layer)),
    #("severity", json.string(severity_label(s.severity))),
    #("injection_type", json.string(injection_label(s.injection))),
    #("target", json.string(synthetic_target(r))),
    #("synthetic_deaths", json.int(deaths)),
    #("synthetic_resurrections", json.int(resurrections)),
    #("real_effects", json.string("none")),
  ])
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
    #("effect_id", json.string(effect_id(r))),
    #("receipt_sha256", json.string(files.digest(stored))),
    #("stored_receipt", json.string(inline)),
  ])
  |> json.to_string
  |> bounded
}

/// Idempotent by effect_id: first call writes `<evidence_dir>/<effect_id>.json`
/// with exclusive create; later calls return status "duplicate" with the stored
/// receipt. A missing evidence_dir is an error and nothing is created.
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
          // Lost an exclusive-create race, or the write failed: only a readable
          // stored receipt counts as a duplicate; anything else fails closed.
          case files.read(evidence_dir, relative) {
            Ok(stored) -> Ok(duplicate(r, stored))
            Error(_) -> Error("receipt_write_failed")
          }
      }
    }
  }
}
