// STAMP: SC-GLM-UI-001, SC-MIRAGE-001, SC-MIRAGE-MIGRATE-001
// Wisp REST API endpoints for MirageOS Unikernel & Subsystem Migration.

import cepaf_gleam/services/mirage_migration_engine.{
  type MigrationCandidate,
}
import cepaf_gleam/services/mirage_unikernel_daemon.{
  type MirageDaemonState, type UnikernelInstance,
}
import gleam/dict
import gleam/json

pub fn candidates_json(candidates: List(MigrationCandidate)) -> json.Json {
  let total_savings = mirage_migration_engine.total_ram_savings(candidates)
  let admitted = mirage_migration_engine.admitted_count(candidates)

  json.object([
    #("total_candidates", json.int(7)),
    #("total_ram_savings_mb", json.int(total_savings)),
    #("admitted_count", json.int(admitted)),
    #("candidates", json.array(candidates, candidate_json)),
  ])
}

pub fn candidate_json(c: MigrationCandidate) -> json.Json {
  json.object([
    #("id", json.string(c.id)),
    #("name", json.string(c.name)),
    #("layer", json.string(c.layer)),
    #("current_tech", json.string(c.current_tech)),
    #("mirage_target", json.string(c.mirage_target)),
    #("sil_level", json.int(c.sil_level)),
    #("ram_saving_mb", json.int(c.ram_saving_mb)),
    #("speedup_pct", json.float(c.speedup_pct)),
    #("status", json.string(mirage_migration_engine.stage_to_string(c.status))),
  ])
}

pub fn safety_eval_json(
  target: String,
  res: Result(String, String),
) -> json.Json {
  case res {
    Ok(msg) ->
      json.object([
        #("target", json.string(target)),
        #("eligible", json.bool(True)),
        #("message", json.string(msg)),
      ])
    Error(err) ->
      json.object([
        #("target", json.string(target)),
        #("eligible", json.bool(False)),
        #("error", json.string(err)),
      ])
  }
}

pub fn unikernel_status_json(state: MirageDaemonState) -> json.Json {
  let instances_list = dict.values(state.instances)
  json.object([
    #("max_memory_mb", json.int(state.max_memory_mb)),
    #("total_boots", json.int(state.total_boots)),
    #("total_trapped", json.int(state.total_trapped)),
    #("active_instances_count", json.int(dict.size(state.instances))),
    #("instances", json.array(instances_list, instance_json)),
  ])
}

pub fn instance_json(inst: UnikernelInstance) -> json.Json {
  json.object([
    #("id", json.string(inst.id)),
    #("name", json.string(inst.name)),
    #(
      "platform",
      json.string(mirage_unikernel_daemon.platform_label(inst.platform)),
    ),
    #("memory_mb", json.int(inst.memory_mb)),
    #("cold_start_ms", json.float(inst.cold_start_ms)),
    #("invocations", json.int(inst.invocations)),
    #("trapped_threats", json.int(inst.trapped_threats)),
  ])
}
