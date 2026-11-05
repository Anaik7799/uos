//// Real public MCP READINESS observation. Never a recovery mutation route.
//// The production owner and this observation use the same closed startup
//// binding. Counts do not establish live leases, review or effect authority.

import cepaf_gleam/harness/recovery_owner
import cepaf_gleam/harness/recovery_trust_discovery
import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/evidence
import cepaf_gleam/mcp/types.{
  type Outcome, Complete, NonRetryable, Refused, ToolError,
}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/result

pub const fixed_plan = "uos/codex-handover-open-items-fractal-plan/20261031-1240"

fn counts(raw: String) -> Result(json.Json, Nil) {
  let decoder = {
    use plan <- decode.field("plan_id", decode.string)
    use total <- decode.field("total_tasks", decode.int)
    use completed <- decode.field("completed_tasks", decode.int)
    use executing <- decode.field("executing_tasks", decode.int)
    use available <- decode.field("available_tasks", decode.int)
    decode.success(#(plan, total, completed, executing, available))
  }
  use #(plan, total, completed, executing, available) <- result.try(
    json.parse(raw, decoder) |> result.map_error(fn(_) { Nil }),
  )
  case
    plan == fixed_plan
    && total >= 0
    && completed >= 0
    && executing >= 0
    && available >= 0
    && completed + executing + available == total
  {
    True ->
      Ok(
        json.object([
          #("status", json.string("OBSERVED_COUNTS")),
          #("total", json.int(total)),
          #("completed", json.int(completed)),
          #("executing", json.int(executing)),
          #("available", json.int(available)),
          #("lease_validity", json.string("NOT_ASSESSED")),
          #("dependency_readiness", json.string("NOT_ASSESSED")),
        ]),
      )
    False -> Error(Nil)
  }
}

pub fn observe(
  store: planning_read.PlanningReadStore,
  candidate: String,
  observed_ms: Int,
  args: Dict(String, String),
) -> Outcome {
  case dict.size(args) == 1 && dict.get(args, "plan_id") == Ok(fixed_plan) {
    False ->
      Refused(ToolError(
        "RECOVERY_READINESS_ARGUMENTS",
        "Status accepts only the fixed canonical plan_id; no effect, key, path or trust inputs",
        NonRetryable,
      ))
    True -> {
      let plan = case planning_read.execute(store, "sa_plan_status_for", args) {
        Complete(raw, _) -> counts(raw)
        _ -> Error(Nil)
      }
      let plan =
        result.unwrap(
          plan,
          json.object([
            #("status", json.string("UNKNOWN")),
            #("reason", json.string("PLAN_OBSERVATION_UNAVAILABLE")),
            #("lease_validity", json.string("NOT_ASSESSED")),
            #("dependency_readiness", json.string("NOT_ASSESSED")),
          ]),
        )
      let binding = case recovery_owner.production_binding() {
        recovery_owner.ProductionUnconfigured -> "UNCONFIGURED_BY_CONSTRUCTION"
      }
      let raw =
        json.object([
          #("schema", json.string("uos.recovery-control-readiness.v1")),
          #("status", json.string("HELD")),
          #("authority", json.string("NONE")),
          #("candidate", json.string(candidate)),
          #("observed_at_ms", json.int(observed_ms)),
          #("plan_id", json.string(fixed_plan)),
          #("plan_observation", plan),
          #("production_binding", json.string(binding)),
          #("owner_runtime_liveness", json.string("NOT_PROBED")),
          #("mutation_enabled", json.bool(False)),
          #("signing_enabled", json.bool(False)),
          #(
            "trust_metadata_resource",
            json.object([
              #("uri", json.string(recovery_trust_discovery.resource_uri)),
              #("access", json.string("PRINCIPAL_PRIVATE")),
              #("role", json.string("OBSERVATION_ONLY_NOT_ROSTER")),
              #("provider", json.string("UNCONFIGURED_BY_CONSTRUCTION")),
            ]),
          ),
          #("registered_operations", json.array(["status"], json.string)),
          #(
            "required_gates",
            json.array(
              [
                "TRUSTED_PROVIDER_AND_INDEPENDENT_ROSTER",
                "PROTECTED_RESOURCE_OWNER_EPOCH_BINDING",
                "FRESH_COMPLETE_PLAN_AND_REVIEWED_SELECTION",
                "ADMITTED_NATIVE_EXECUTOR_AND_MIGRATION",
                "INDEPENDENT_RELEASE_AND_RUNTIME_ACTIVATION",
              ],
              json.string,
            ),
          ),
          #("application_admitted", json.bool(False)),
          #("system_admitted", json.bool(False)),
        ])
        |> json.to_string
      evidence.classify_backend_payload(
        "public",
        "recovery_control_status",
        raw,
        candidate,
      )
    }
  }
}
