//// Shared typed MCP tool registry across public, development-private, and
//// successor-private routes.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/mcp as dev_mcp
import cepaf_gleam/harness/successor_mcp
import cepaf_gleam/mcp/protocol.{type ToolDefinition}
import cepaf_gleam/mcp/tools
import cepaf_gleam/mcp/types.{
  type AccessView, type EffectClass, type ProtocolProfile, type ToolError,
  type ToolSpec, ControlActuation, DeclaredCatalogView, Mutating, NonRetryable,
  OperationalView, PrivateDevelopmentView, PrivateSuccessorView, ReadOnly,
  ToolError, ToolSpec, VerificationGate,
}
import gleam/json.{type Json}
import gleam/list

pub fn all_specs() -> List(ToolSpec) {
  list.flatten([
    route_specs("public"),
    route_specs("development"),
    route_specs("successor"),
  ])
}

pub fn lookup(route: String, name: String) -> Result(ToolSpec, ToolError) {
  let specs = route_specs(route)
  case list.find(specs, fn(s) { s.name == name }) {
    Ok(spec) -> Ok(spec)
    Error(_) ->
      Error(ToolError(
        "UNKNOWN_ROUTE_OR_TOOL",
        "Unknown tool " <> name <> " on route " <> route,
        NonRetryable,
      ))
  }
}

pub fn definitions(
  _profile: ProtocolProfile,
  access: AccessView,
) -> List(ToolSpec) {
  case access {
    OperationalView ->
      tools.operational_tool_definitions()
      |> list.map(public_spec)
    DeclaredCatalogView ->
      tools.get_tool_definitions()
      |> list.map(public_spec)
    PrivateDevelopmentView ->
      dev_mcp.tool_definitions()
      |> list.map(development_spec)
    PrivateSuccessorView ->
      successor_mcp.tool_definitions()
      |> list.map(successor_spec)
  }
}

pub fn verify_schema_digest(
  spec: ToolSpec,
  candidate_schema: Json,
) -> Result(Nil, ToolError) {
  let actual = files.digest(json.to_string(candidate_schema))
  case actual == spec.schema_digest {
    True -> Ok(Nil)
    False ->
      Error(ToolError(
        "SCHEMA_MIGRATION_REQUIRED",
        "Schema digest mismatch for " <> spec.route <> ":" <> spec.name,
        NonRetryable,
      ))
  }
}

fn route_specs(route: String) -> List(ToolSpec) {
  case route {
    "public" -> list.map(tools.get_tool_definitions(), public_spec)
    "development" -> list.map(dev_mcp.tool_definitions(), development_spec)
    "successor" -> list.map(successor_mcp.tool_definitions(), successor_spec)
    _ -> []
  }
}

fn public_spec(def: ToolDefinition) -> ToolSpec {
  let #(family, owner_task, layer, effect, backend, budget) =
    classify_public(def.name)
  ToolSpec(
    route: "public",
    name: def.name,
    description: def.description,
    family: family,
    owner_task: owner_task,
    primary_layer: layer,
    input_schema: def.input_schema,
    schema_digest: files.digest(json.to_string(def.input_schema)),
    effect_class: effect,
    backend: backend,
    budget_ms: budget,
  )
}

fn development_spec(def: ToolDefinition) -> ToolSpec {
  ToolSpec(
    route: "development",
    name: def.name,
    description: def.description,
    family: "private_development",
    owner_task: "T14",
    primary_layer: 3,
    input_schema: def.input_schema,
    schema_digest: files.digest(json.to_string(def.input_schema)),
    effect_class: classify_harness_effect(def.name),
    backend: "gleam_development_harness",
    budget_ms: 60_000,
  )
}

fn successor_spec(def: ToolDefinition) -> ToolSpec {
  ToolSpec(
    route: "successor",
    name: def.name,
    description: def.description,
    family: "private_successor",
    owner_task: "T14",
    primary_layer: 3,
    input_schema: def.input_schema,
    schema_digest: files.digest(json.to_string(def.input_schema)),
    effect_class: classify_harness_effect(def.name),
    backend: "gleam_successor_harness",
    budget_ms: 60_000,
  )
}

fn classify_harness_effect(name: String) -> EffectClass {
  case name {
    "harness_status"
    | "harness_clock"
    | "harness_read_file"
    | "harness_peers"
    | "harness_peer_read"
    | "harness_feature_status"
    | "harness_system_feature_catalog"
    | "harness_system_feature_observations"
    | "harness_execution_progress" -> ReadOnly
    "harness_test" | "harness_build" | "harness_risk_check" -> VerificationGate
    _ -> Mutating
  }
}

fn classify_public(
  name: String,
) -> #(String, String, Int, EffectClass, String, Int) {
  case name {
    "plan_status"
    | "plan_list_pending"
    | "plan_list"
    | "plan_get"
    | "plan_search"
    | "sa_plan_status"
    | "sa_plan_status_for"
    | "sa_plan_list"
    | "feature_tracker_status" -> #(
      "planning_read",
      "T05",
      3,
      ReadOnly,
      "sa_plan",
      3000,
    )
    "plan_add"
    | "plan_update"
    | "sa_task_claim"
    | "sa_task_complete"
    | "sa_job_enqueue"
    | "sa_workflow_start"
    | "sa_bridge_submit" -> #(
      "planning_write",
      "T06",
      3,
      Mutating,
      "sa_plan",
      5000,
    )
    "system_health"
    | "system_dashboard"
    | "system_immune"
    | "system_zenoh"
    | "system_verification"
    | "podman_containers"
    | "metabolic_state"
    | "ooda_phase"
    | "fractal_status"
    | "prajna_health"
    | "dark_cockpit_mode"
    | "integrity_check"
    | "evolution_metrics"
    | "mesh_topology"
    | "ooda_decide"
    | "kms_catalog"
    | "holon_status"
    | "swarm_status"
    | "agent_hierarchy" -> #(
      "observability",
      "T07",
      4,
      ReadOnly,
      "system_observation",
      3000,
    )
    "control_loop" | "safety_status" | "registry_status" -> #(
      "control_safety_registry",
      "T08",
      0,
      ControlActuation,
      "control_plane",
      3000,
    )
    "verification_run" | "run_selfcheck" | "run_gate" | "preflight_check" -> #(
      "verification",
      "T09",
      9,
      VerificationGate,
      "verification_supervisor",
      60_000,
    )
    "knowledge_search" | "read_file" | "zk_search" | "zk_transclude" -> #(
      "knowledge_files",
      "T10",
      5,
      ReadOnly,
      "knowledge_triad",
      3000,
    )
    "vault_status"
    | "vault_list_secrets"
    | "vault_policy_get"
    | "vault_audit_tail"
    | "vault_health" -> #(
      "vault_metadata",
      "T11",
      0,
      ReadOnly,
      "vault_supervisor",
      3000,
    )
    "forecast_predict"
    | "stpa_fmea_hazard"
    | "rete_rule_conflict"
    | "ruliad_branch_eval"
    | "shruti_harmonics"
    | "ast_anomaly_detect"
    | "lyapunov_trend_predict"
    | "sciviz_extension_deep_dive"
    | "ggram_synthesize" -> #(
      "analysis_inference_sciviz",
      "T12",
      5,
      ReadOnly,
      "max_hermes_sciviz",
      5000,
    )
    "mcp_capability_inventory"
    | "harness_system_feature_catalog"
    | "harness_system_feature_observations"
    | "harness_system_feature_intent"
    | "harness_execution_progress" -> #(
      "feature_evidence",
      "T13",
      9,
      ReadOnly,
      "system_feature_store",
      3000,
    )
    _ -> #(
      "unclassified",
      "T01",
      0,
      ControlActuation,
      "unclassified_fail_closed",
      3000,
    )
  }
}
