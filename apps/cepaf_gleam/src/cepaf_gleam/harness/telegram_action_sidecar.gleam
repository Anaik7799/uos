//// ControlledAction adapter for `/sidecar <name>` (contract 20261026-0115).
//// Preview describes the planned Mirage/Solo5 sidecar from the declared
//// migration catalog and a SIMULATED boot (`mirage_unikernel_daemon` models
//// lifecycle only). Starting a unikernel or container is a real effect that is
//// not boundable in development, so `execute` returns
//// `backend_unavailable:mirage_unikernel_daemon` and writes nothing.
//// Grants no authority.

import cepaf_gleam/harness/files
import cepaf_gleam/services/mirage_migration_engine as migration
import cepaf_gleam/services/mirage_unikernel_daemon as daemon
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub opaque type Request {
  Request(name: String)
}

const literal_text = "/sidecar"

const max_args = 256

const max_reply = 3500

const backend = "mirage_unikernel_daemon"

const nominal_memory_mb = 16

fn names() -> List(String) {
  migration.get_migration_candidates()
  |> list.map(fn(c) { short_name(c.id) })
}

fn short_name(id: String) -> String {
  id |> string.drop_start(7) |> string.lowercase
}

fn usage() -> String {
  "usage: /sidecar <" <> string.join(names(), "|") <> ">"
}

pub fn literal() -> String {
  literal_text
}

/// Pure: no process, no container, no filesystem.
pub fn parse(args: String) -> Result(Request, String) {
  let tokens =
    args
    |> string.split(" ")
    |> list.map(string.trim)
    |> list.filter(fn(t) { t != "" })
  case string.byte_size(args) <= max_args, tokens {
    True, [name] ->
      case list.contains(names(), name) {
        True -> Ok(Request(name))
        False -> Error(usage())
      }
    _, _ -> Error(usage())
  }
}

pub fn effect_id(r: Request) -> String {
  files.digest("uos.telegram.action.sidecar.v1|name=" <> r.name)
}

fn reply(fields: List(#(String, json.Json))) -> String {
  let text = json.object(fields) |> json.to_string
  case string.byte_size(text) <= max_reply {
    True -> text
    False ->
      json.object([
        #("status", json.string("denied")),
        #("literal", json.string(literal_text)),
        #("reason", json.string("reply_bound")),
      ])
      |> json.to_string
  }
}

fn denied(r: Request, reason: String) -> String {
  reply([
    #("status", json.string("denied")),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect_id(r))),
    #("reason", json.string(reason)),
    #("authority", json.string("NONE")),
  ])
}

/// Read-only: declared catalog plus a simulated boot; no process is created.
pub fn preview(r: Request) -> String {
  let found =
    migration.get_migration_candidates()
    |> list.find(fn(c) { short_name(c.id) == r.name })
  let booted = case found {
    Ok(_) ->
      daemon.simulate_boot_unikernel(
        daemon.new_daemon_state(),
        "sidecar-" <> r.name,
        r.name,
        daemon.TargetSolo5Spt,
        nominal_memory_mb,
      )
    Error(_) -> Error("sidecar_not_in_catalog")
  }
  case found, booted {
    Ok(c), Ok(#(state, instance)) ->
      reply([
        #("status", json.string("preview")),
        #("literal", json.string(literal_text)),
        #("effect_id", json.string(effect_id(r))),
        #("confidence", json.string("simulated")),
        #(
          "effect",
          json.string("would boot one sidecar unikernel; nothing is started"),
        ),
        #("sidecar", json.string(r.name)),
        #("candidate_id", json.string(c.id)),
        #("layer", json.string(c.layer)),
        #("current_tech", json.string(c.current_tech)),
        #("mirage_target", json.string(c.mirage_target)),
        #("target_sil_level", json.int(c.target_sil_level)),
        #("platform", json.string(daemon.platform_label(instance.platform))),
        #("configured_memory_mb", json.int(instance.configured_memory_mb)),
        #(
          "projected_cold_start_ms",
          json.float(instance.projected_cold_start_ms),
        ),
        #("runtime_mode", json.string(daemon.runtime_mode_label(state.mode))),
        #(
          "runtime_observation",
          json.string(daemon.observation_status(state.observation)),
        ),
        #(
          "admission",
          json.string(migration.admission_status_to_string(c.admission)),
        ),
        #("backend", json.string("unavailable:" <> backend)),
        #("authority", json.string("NONE")),
      ])
    _, Error(reason) -> denied(r, reason)
    Error(_), _ -> denied(r, "sidecar_not_in_catalog")
  }
}

/// Typed `backend_unavailable` reply for the service to relay.
pub fn unavailable_reply(r: Request) -> String {
  reply([
    #("status", json.string("backend_unavailable")),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect_id(r))),
    #("backend", json.string(backend)),
    #(
      "reason",
      json.string(
        "starting a unikernel or container is not boundable in development",
      ),
    ),
    #("authority", json.string("NONE")),
  ])
}

/// Never starts anything and never writes: a present evidence dir yields only
/// the typed unavailable error.
pub fn execute(_r: Request, evidence_dir: String) -> Result(String, String) {
  use _ <- result.try(case simplifile.is_directory(evidence_dir) {
    Ok(True) -> Ok(Nil)
    _ -> Error("evidence_dir_unavailable")
  })
  Error("backend_unavailable:" <> backend)
}
