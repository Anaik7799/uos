// STAMP: SC-GLM-UI-001, SC-MIRAGE-001, SC-MIRAGE-MIGRATE-001
// Wisp REST API endpoints for MirageOS Unikernel & Subsystem Migration.

import cepaf_gleam/services/mirage_migration_engine.{type MigrationCandidate}
import cepaf_gleam/services/mirage_unikernel_daemon.{
  type MirageDaemonState, type UnikernelInstance,
}
import gleam/dict
import gleam/json
import gleam/list

pub fn candidates_json(candidates: List(MigrationCandidate)) -> json.Json {
  let projected_savings =
    mirage_migration_engine.total_projected_ram_savings(candidates)
  let verified_admitted =
    mirage_migration_engine.verified_admitted_count(candidates)

  json.object([
    #("evidence_scope", json.string("static_migration_projection")),
    #("deployment_admission", json.string("NOT_VERIFIED")),
    #("measurement_status", json.string("unknown")),
    #(
      "measurement_reason",
      json.string("No runtime benchmark receipt is attached"),
    ),
    #("total_candidates", json.int(list.length(candidates))),
    #("projected_ram_savings_mb", json.int(projected_savings)),
    #("measured_ram_savings_mb", json.null()),
    #("verified_admitted_count", json.int(verified_admitted)),
    #(
      "benchmark_spec_url",
      json.string(
        "http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-1037-mirage-benchmark-contract.md",
      ),
    ),
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
    #("declared_sil_level", json.int(c.target_sil_level)),
    #("projected_ram_saving_mb", json.int(c.projected_ram_saving_mb)),
    #("projected_speedup_pct", json.float(c.projected_speedup_pct)),
    #("status", json.string("NOT_VERIFIED")),
    #(
      "declared_stage",
      json.string(mirage_migration_engine.stage_to_string(c.status)),
    ),
    #(
      "estimate_basis",
      json.string(mirage_migration_engine.estimate_basis_to_string(
        c.estimate_basis,
      )),
    ),
    #(
      "estimate_reason",
      json.string(mirage_migration_engine.estimate_basis_reason(
        c.estimate_basis,
      )),
    ),
    #(
      "admission_status",
      json.string(mirage_migration_engine.admission_status_to_string(
        c.admission,
      )),
    ),
    #(
      "admission_reason",
      json.string(mirage_migration_engine.admission_status_reason(c.admission)),
    ),
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
    #(
      "runtime_mode",
      json.string(mirage_unikernel_daemon.runtime_mode_label(state.mode)),
    ),
    #("health", json.string("unknown")),
    #(
      "observation_status",
      json.string(mirage_unikernel_daemon.observation_status(state.observation)),
    ),
    #(
      "observation_reason",
      json.string(mirage_unikernel_daemon.observation_reason(state.observation)),
    ),
    #("configured_max_memory_mb", json.int(state.configured_max_memory_mb)),
    #("simulated_boots", json.int(state.simulated_boots)),
    #("simulated_trapped", json.int(state.simulated_trapped)),
    #(
      "simulated_running_instances_count",
      json.int(mirage_unikernel_daemon.simulated_running_count(state)),
    ),
    #(
      "simulated_terminated_instances_count",
      json.int(mirage_unikernel_daemon.simulated_terminated_count(state)),
    ),
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
    #("configured_memory_mb", json.int(inst.configured_memory_mb)),
    #("projected_cold_start_ms", json.float(inst.projected_cold_start_ms)),
    #("status", json.string(mirage_unikernel_daemon.status_label(inst.status))),
    #("simulated_invocations", json.int(inst.simulated_invocations)),
    #("simulated_trapped_threats", json.int(inst.simulated_trapped_threats)),
  ])
}
