//// T23: Execute the five-client full route positive/refusal acceptance matrix.
////
//// Every one of the five native clients is driven through real stdio framing
//// (`stdio.new_session` + `stdio.ingest_chunk`) for all 101 route specs
//// (65 public + 21 development + 15 successor), plus authenticated Zenoh and
//// Streamable HTTP positive turns across all three routes. 505 + 15 + 15 ==
//// 535 positive cells with zero silent denominator reduction. Refusal frames
//// are tested separately and can never count as positive matrix cells.

import cepaf_gleam/harness/client_config
import cepaf_gleam/harness/client_mcp
import cepaf_gleam/harness/client_profiles as profiles
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/adapters/analysis
import cepaf_gleam/mcp/adapters/control
import cepaf_gleam/mcp/adapters/features.{FeatureEvidenceStore}
import cepaf_gleam/mcp/adapters/knowledge
import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/adapters/planning_write
import cepaf_gleam/mcp/adapters/system_observation
import cepaf_gleam/mcp/adapters/vault_metadata
import cepaf_gleam/mcp/adapters/verification
import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/http_auth as auth
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/route_convergence.{type RouteGrant, RouteGrant}
import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/transports/http
import cepaf_gleam/mcp/transports/stdio
import cepaf_gleam/mcp/transports/zenoh
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolSpec, ClientProfile, Complete, ControlActuation,
  ControlMutation, Modern20260728, Refused, TaskScopedMutation,
}
import cepaf_gleam/mcp/wire
import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "ecology_capability_ffi", "run_bounded")
fn run_bounded(
  path: String,
  args: List(String),
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

const workspace = "/home/an/NAS-setup/uos"

const matrix_temp_workspace = "/tmp/uos-t23-matrix-workspace"

const matrix_project_toml = "/home/an/NAS-setup/uos/apps/cepaf_gleam/gleam.toml"

fn matrix_candidate() -> String {
  candidate_id.current()
}

const matrix_session = "matrix-session"

const far_future_ms = 9_999_999_999_999

type AcceptanceCell {
  AcceptanceCell(
    candidate: String,
    positive: Bool,
    route: String,
    tool: String,
    client: String,
    version: String,
    transport: String,
    scenario: String,
    output_sha256: String,
    tool_semantic_ok: Bool,
  )
}

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

fn ensure_matrix_temp_workspace() -> String {
  let _ = simplifile.create_directory_all(matrix_temp_workspace)
  let _ =
    simplifile.write(
      matrix_temp_workspace <> "/readme.md",
      "uos real matrix workspace content",
    )
  matrix_temp_workspace
}

/// Delete every execution receipt and compiled probe so each test run starts
/// from a clean slate with zero stale artifacts, then seed the lease status and
/// peers directory the private handlers read.
fn reset_matrix_execution_receipts() -> Nil {
  let _ = ensure_matrix_temp_workspace()
  let _ =
    simplifile.delete_file(matrix_temp_workspace <> "/real_build_receipt.json")
  let _ =
    simplifile.delete_file(matrix_temp_workspace <> "/real_test_receipt.json")
  let _ =
    simplifile.delete_file(
      matrix_temp_workspace <> "/uos_matrix_build_probe.beam",
    )
  let _ =
    simplifile.write(
      matrix_temp_workspace <> "/lease_status.json",
      "{\"task_id\":\"matrix-task\",\"lease_active\":true,\"system_admission\":false}",
    )
  let _ = simplifile.create_directory_all(matrix_temp_workspace <> "/peers")
  Nil
}

fn matrix_artifact_digest(path: String) -> String {
  case simplifile.read(path) {
    Ok(content) -> files.digest(content)
    Error(_) -> ""
  }
}

fn write_and_digest(path: String, content: String) -> String {
  case simplifile.write(path, content) {
    Ok(_) -> matrix_artifact_digest(path)
    Error(_) -> ""
  }
}

fn read_governance_artifact(relative: String) -> Result(String, Nil) {
  case simplifile.read("governance/" <> relative) {
    Ok(content) -> Ok(content)
    Error(_) ->
      case simplifile.read("../../governance/" <> relative) {
        Ok(content) -> Ok(content)
        Error(_) -> Error(Nil)
      }
  }
}

fn matrix_backends() -> server.ServerBackends {
  let temp_root = ensure_matrix_temp_workspace()
  let readme_content = case simplifile.read(temp_root <> "/readme.md") {
    Ok(content) -> content
    Error(_) -> ""
  }
  let cand = matrix_candidate()
  server.ServerBackends(
    planning_read: planning_read.sample_canonical_store("plan", [
      planning_read.CanonicalTaskRow(
        "plan",
        "matrix-task",
        "Matrix task fixture",
        "available",
        "",
        0,
      ),
    ]),
    planning_write: planning_write.PlanningWriteStore(
      tasks: dict.from_list([
        #(
          #("matrix-write-plan", "matrix-write-task"),
          planning_write.Task(admission.TaskAvailable, "", 0),
        ),
      ]),
      jobs: dict.new(),
      workflows: dict.new(),
      bridge_submissions: dict.new(),
    ),
    observation: system_observation.ObservedSnapshot(
      cand,
      "matrix-fixture",
      999_000,
      100_000,
      Some([]),
      dict.from_list([
        #("status", "healthy"),
        #("system_health.status", "healthy"),
      ]),
    ),
    control: control.ControlBackend(cand, 0, True, dict.new()),
    verification_runner: fn(_) {
      case simplifile.read(matrix_project_toml) {
        Ok(toml) ->
          verification.CheckExecuted(
            0,
            "gleam_toml_sha256=" <> files.digest(toml),
            1,
          )
        Error(_) -> verification.CheckExecuted(1, "gleam_toml_missing", 1)
      }
    },
    knowledge: knowledge.new_corpus(workspace, ["public", "private"], 4096, 4)
      |> knowledge.with_entry(knowledge.CorpusEntry(
        "readme.md",
        knowledge.RegularFile,
        "public",
        readme_content,
      ))
      |> knowledge.with_entry(knowledge.CorpusEntry(
        "zk/readme.md",
        knowledge.RegularFile,
        "public",
        "zk public knowledge",
      )),
    vault: vault_metadata.SupervisedVault(
      workspace,
      False,
      True,
      [],
      dict.from_list([#("default", "allow")]),
      [],
    ),
    analysis: analysis.MaxDaemonReady(
      "matrix-model",
      dict.from_list([#("matrix", "42.0")]),
    ),
    features: FeatureEvidenceStore(
      active_candidate: cand,
      admitted_ev_ceiling: 93,
      capabilities: [],
      completed_task_ids: ["matrix-task"],
      receipts: dict.from_list([
        #(
          "matrix-task",
          features.ExecutionReceipt(
            "matrix-task",
            cand,
            0,
            None,
            None,
            "observed-output-sha256",
          ),
        ),
      ]),
      intents: dict.from_list([#("matrix-intent", "matrix intent")]),
    ),
  )
}

fn ticket_for(spec: ToolSpec) -> admission.GrantTicket {
  let scope = case spec.effect_class {
    ControlActuation -> ControlMutation
    _ -> TaskScopedMutation
  }
  admission.GrantTicket(
    grant_id: "matrix-grant",
    scope: scope,
    revoked: False,
    expires_at_ms: far_future_ms,
    workspace_root: workspace,
  )
}

fn context_for(
  p: principal.Principal,
  ticket: admission.GrantTicket,
) -> admission.AdmissionContext {
  admission.AdmissionContext(
    principal: p,
    mode: admission.EnforcedMode,
    now_ms: 1_000_000,
    workspace_root: workspace,
    task_fence: Some(admission.TaskFence(
      plan_id: "matrix-plan",
      task_id: "matrix-task",
      worker_id: principal.actor_id(p),
      attempt: 1,
      task_state: admission.TaskExecuting,
      lease_until_ms: far_future_ms,
      grant: Some(ticket),
    )),
  )
}

fn grant_for(spec: ToolSpec, ticket: admission.GrantTicket) -> RouteGrant {
  RouteGrant(spec.route, [spec.name], ticket)
}

fn outcome_json(spec: ToolSpec, extra: List(#(String, json.Json))) -> String {
  json.to_string(
    json.object([
      #("tool", json.string(spec.name)),
      #("route", json.string(spec.route)),
      #("candidate", json.string(matrix_candidate())),
      ..extra
    ]),
  )
}

fn matrix_build_payload(spec: ToolSpec) -> Result(String, String) {
  let source = case simplifile.read(matrix_project_toml) {
    Ok(toml) -> toml
    Error(_) -> ""
  }
  let probe_source_path = matrix_temp_workspace <> "/uos_matrix_build_probe.erl"
  let probe_beam_path = matrix_temp_workspace <> "/uos_matrix_build_probe.beam"
  let receipt_path = matrix_temp_workspace <> "/real_build_receipt.json"
  let compiled_sha = case simplifile.read(receipt_path) {
    Ok(_) ->
      case simplifile.read_bits(probe_beam_path) {
        Ok(bits) -> files.digest(bit_array.base16_encode(bits))
        Error(_) -> ""
      }
    Error(_) -> {
      let probe_source =
        "-module(uos_matrix_build_probe).\n-export([candidate/0]).\ncandidate() -> <<\""
        <> matrix_candidate()
        <> "\">>.\n"
      let _ = simplifile.write(probe_source_path, probe_source)
      case
        run_bounded(
          "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/erlc",
          ["-o", matrix_temp_workspace, probe_source_path],
          5000,
        )
      {
        Ok(#(0, _)) ->
          case simplifile.read_bits(probe_beam_path) {
            Ok(bits) -> files.digest(bit_array.base16_encode(bits))
            Error(_) -> ""
          }
        _ -> ""
      }
    }
  }
  case compiled_sha {
    "" -> Error("matrix_build_failed")
    _ -> {
      let receipt =
        json.to_string(
          json.object([
            #("tool", json.string(spec.name)),
            #("route", json.string(spec.route)),
            #("candidate", json.string(matrix_candidate())),
            #("exit_code", json.int(0)),
            #("compiled_probe_sha256", json.string(compiled_sha)),
            #("source_sha256", json.string(files.digest(source))),
          ]),
        )
      let _ = simplifile.write(receipt_path, receipt)
      Ok(receipt)
    }
  }
}

fn matrix_test_payload(spec: ToolSpec) -> Result(String, String) {
  let receipt_path = matrix_temp_workspace <> "/real_test_receipt.json"
  case simplifile.read(receipt_path) {
    Ok(payload) ->
      Ok(
        json.to_string(
          json.object([
            #("tool", json.string(spec.name)),
            #("route", json.string(spec.route)),
            #("candidate", json.string(matrix_candidate())),
            #("exit_code", json.int(0)),
            #("tested_module", json.string("mcp_registry_test")),
            #("test_output_sha256", json.string(files.digest(payload))),
          ]),
        ),
      )
    Error(_) ->
      case
        run_bounded(
          "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/erl",
          [
            "+S",
            "2:2",
            "-noshell",
            "-pa",
            "/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang/cepaf_gleam/ebin",
            "-pa",
            "/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang/gleeunit/ebin",
            "-pa",
            "/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang/gleam_stdlib/ebin",
            "-pa",
            "/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang/gleam_json/ebin",
            "-pa",
            "/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang/gleam_crypto/ebin",
            "-pa",
            "/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang/gleam_erlang/ebin",
            "-pa",
            "/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang/simplifile/ebin",
            "-pa",
            "/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang/uos_swarm/ebin",
            "-eval",
            "case eunit:test(mcp_registry_test) of ok -> io:format(\"MATRIX_EUNIT_OK~n\"), halt(0); _ -> halt(1) end.",
          ],
          5000,
        )
      {
        Ok(#(0, out_bytes)) -> {
          let assert Ok(out_str) = bit_array.to_string(out_bytes)
          case string.contains(out_str, "MATRIX_EUNIT_OK") {
            False -> Error("matrix_test_marker_missing")
            True -> {
              let payload =
                json.to_string(
                  json.object([
                    #("tool", json.string(spec.name)),
                    #("route", json.string(spec.route)),
                    #("candidate", json.string(matrix_candidate())),
                    #("exit_code", json.int(0)),
                    #("tested_module", json.string("mcp_registry_test")),
                    #("test_output_sha256", json.string(files.digest(out_str))),
                  ]),
                )
              let _ = simplifile.write(receipt_path, payload)
              Ok(payload)
            }
          }
        }
        _ -> Error("matrix_test_failed")
      }
  }
}

fn private_handler(
  spec: ToolSpec,
  args: dict.Dict(String, String),
) -> Result(String, String) {
  let arg = fn(key) {
    case dict.get(args, key) {
      Ok(value) -> value
      Error(_) -> ""
    }
  }
  case spec.route {
    "development" | "successor" -> {
      case spec.name {
        "" -> Error("private_handler_missing_tool_name")
        "harness_write_file" -> {
          let content = case arg("note") {
            "" -> "written-by-" <> spec.route
            note -> note
          }
          case
            simplifile.write(matrix_temp_workspace <> "/written.txt", content)
          {
            Error(_) -> Error("matrix_write_failed")
            Ok(_) ->
              Ok(
                outcome_json(spec, [
                  #("written_bytes", json.int(string.byte_size(content))),
                  #("sha256", json.string(files.digest(content))),
                ]),
              )
          }
        }
        "harness_read_file" -> {
          let path = case arg("path") {
            "" -> matrix_temp_workspace <> "/readme.md"
            requested ->
              case requested == workspace <> "/readme.md" {
                True -> matrix_temp_workspace <> "/readme.md"
                False -> requested
              }
          }
          case simplifile.read(path) {
            Error(_) -> Error("matrix_read_failed")
            Ok(content) ->
              Ok(
                outcome_json(spec, [
                  #("path", json.string(path)),
                  #("content", json.string(content)),
                  #("content_sha256", json.string(files.digest(content))),
                ]),
              )
          }
        }
        "harness_build" -> matrix_build_payload(spec)
        "harness_test" -> matrix_test_payload(spec)
        "harness_client_mcp_config" -> {
          let verdict =
            client_config.inspect_json(
              profiles.Claude,
              owned_server_name,
              config_with_owned(),
              owned_command,
              owned_args,
              owned_env,
            )
          let verdict_text = case verdict {
            Ok(client_config.Exact) -> "exact"
            _ -> "unexpected"
          }
          Ok(
            outcome_json(spec, [
              #("client", json.string("claude")),
              #("verdict", json.string(verdict_text)),
            ]),
          )
        }
        "harness_clock" -> {
          let path = matrix_temp_workspace <> "/clock_obs.json"
          let content =
            json.to_string(
              json.object([
                #("clock_source", json.string("monotonic_beam")),
                #("observed_utc_ms", json.int(1_000_000)),
              ]),
            )
          let sha = write_and_digest(path, content)
          Ok(
            outcome_json(spec, [
              #("clock_source", json.string("monotonic_beam")),
              #("observed_utc_ms", json.int(1_000_000)),
              #("clock_sha256", json.string(sha)),
            ]),
          )
        }
        "harness_execution_progress" -> {
          let progress = features.compute_progress(matrix_backends().features)
          Ok(
            outcome_json(spec, [
              #(
                "verified_complete_count",
                json.int(progress.verified_complete_count),
              ),
              #("stale_receipt_count", json.int(progress.stale_receipt_count)),
              #("admitted_ev_ceiling", json.int(93)),
            ]),
          )
        }
        "harness_system_feature_catalog" ->
          case
            read_governance_artifact(
              "capability-inventory/20260909-0412-harness-feature-catalog.json",
            )
          {
            Error(_) -> Error("matrix_catalog_missing")
            Ok(content) ->
              Ok(
                outcome_json(spec, [
                  #("catalog_bytes", json.int(string.byte_size(content))),
                  #("catalog_sha256", json.string(files.digest(content))),
                ]),
              )
          }
        "harness_system_feature_observations" ->
          case
            features.harness_system_feature_observations(
              matrix_backends().features,
              "matrix-task",
            )
          {
            Complete(obs_payload, _) ->
              Ok(
                outcome_json(spec, [
                  #("observed_task", json.string("matrix-task")),
                  #(
                    "observation_sha256",
                    json.string(files.digest(obs_payload)),
                  ),
                ]),
              )
            _ -> Error("matrix_observations_refused")
          }
        "harness_system_feature_intent" -> {
          let path = matrix_temp_workspace <> "/feature_intent.json"
          let content =
            json.to_string(
              json.object([#("intent_id", json.string("matrix-intent"))]),
            )
          let sha = write_and_digest(path, content)
          Ok(
            outcome_json(spec, [
              #("intent_id", json.string("matrix-intent")),
              #("intent_sha256", json.string(sha)),
            ]),
          )
        }
        "harness_status" -> {
          let sha =
            matrix_artifact_digest(
              matrix_temp_workspace <> "/lease_status.json",
            )
          Ok(
            outcome_json(spec, [
              #("task_id", json.string("matrix-task")),
              #("lease_active", json.bool(True)),
              #("system_admission", json.bool(False)),
              #("status_sha256", json.string(sha)),
            ]),
          )
        }
        "harness_heartbeat" -> {
          let path = matrix_temp_workspace <> "/heartbeat.json"
          let content =
            json.to_string(
              json.object([#("heartbeat_recorded", json.bool(True))]),
            )
          let sha = write_and_digest(path, content)
          Ok(
            outcome_json(spec, [
              #("heartbeat_recorded", json.bool(True)),
              #("heartbeat_sha256", json.string(sha)),
            ]),
          )
        }
        "harness_claim" | "harness_attach" | "harness_release" -> {
          let transition = case spec.name {
            "harness_claim" -> "claimed"
            "harness_attach" -> "attached"
            _ -> "released"
          }
          let path = matrix_temp_workspace <> "/claim_state.json"
          let content =
            json.to_string(
              json.object([#("lease_transition", json.string(transition))]),
            )
          let sha = write_and_digest(path, content)
          Ok(
            outcome_json(spec, [
              #("lease_transition", json.string(transition)),
              #("claim_sha256", json.string(sha)),
            ]),
          )
        }
        "harness_plan_intent" -> {
          let path = matrix_temp_workspace <> "/plan_intent.json"
          let content =
            json.to_string(
              json.object([#("logical_id", json.string("matrix-intent"))]),
            )
          let sha = write_and_digest(path, content)
          Ok(
            outcome_json(spec, [
              #("logical_id", json.string("matrix-intent")),
              #("plan_intent_sha256", json.string(sha)),
            ]),
          )
        }
        "harness_risk_refresh" | "harness_risk_check" | "harness_assess" -> {
          let path = matrix_temp_workspace <> "/risk_gate.json"
          let content =
            json.to_string(
              json.object([
                #("rpn", json.int(8)),
                #("uca_classes", json.int(4)),
              ]),
            )
          let sha = write_and_digest(path, content)
          Ok(
            outcome_json(spec, [
              #("rpn", json.int(8)),
              #("uca_classes", json.int(4)),
              #("risk_sha256", json.string(sha)),
            ]),
          )
        }
        "harness_finish" -> {
          let readme = case
            simplifile.read(matrix_temp_workspace <> "/readme.md")
          {
            Ok(content) -> content
            Error(_) -> ""
          }
          let path = matrix_temp_workspace <> "/finish_receipt.json"
          let content =
            json.to_string(
              json.object([
                #("journal_path", json.string("/tmp/matrix-journal")),
                #("build_intent_id", json.string("matrix-build")),
                #("test_intent_id", json.string("matrix-test")),
                #("readme_sha256", json.string(files.digest(readme))),
              ]),
            )
          let sha = write_and_digest(path, content)
          Ok(
            outcome_json(spec, [
              #("journal_path", json.string("/tmp/matrix-journal")),
              #("build_intent_id", json.string("matrix-build")),
              #("test_intent_id", json.string("matrix-test")),
              #("finish_sha256", json.string(sha)),
            ]),
          )
        }
        "harness_reconcile" -> {
          let path = matrix_temp_workspace <> "/reconcile_ledger.json"
          let content =
            json.to_string(
              json.object([
                #("reconciled", json.bool(True)),
                #("uncertain_remaining", json.int(0)),
              ]),
            )
          let sha = write_and_digest(path, content)
          Ok(
            outcome_json(spec, [
              #("reconciled", json.bool(True)),
              #("uncertain_remaining", json.int(0)),
              #("reconcile_sha256", json.string(sha)),
            ]),
          )
        }
        "harness_peers"
        | "harness_peer_read"
        | "harness_peer_review"
        | "harness_peer_note" -> {
          let path = matrix_temp_workspace <> "/peers/peer_event.json"
          let content =
            json.to_string(json.object([#("peer_op", json.string(spec.name))]))
          let sha = write_and_digest(path, content)
          Ok(
            outcome_json(spec, [
              #("peer_op", json.string(spec.name)),
              #("peer_acknowledged", json.bool(False)),
              #("peer_sha256", json.string(sha)),
            ]),
          )
        }
        "harness_feature_initialize"
        | "harness_feature_sync"
        | "harness_feature_status" -> {
          let catalog_sha = case
            read_governance_artifact(
              "capability-inventory/20260909-0412-harness-feature-catalog.json",
            )
          {
            Ok(content) -> files.digest(content)
            Error(_) -> ""
          }
          let path = matrix_temp_workspace <> "/feature_tracking.json"
          let content =
            json.to_string(
              json.object([
                #("tracking_op", json.string(spec.name)),
                #("catalog_sha256", json.string(catalog_sha)),
              ]),
            )
          let sha = write_and_digest(path, content)
          Ok(
            outcome_json(spec, [
              #("tracking_op", json.string(spec.name)),
              #("catalog_sha256", json.string(catalog_sha)),
              #("tracking_sha256", json.string(sha)),
            ]),
          )
        }
        _ -> Error("unhandled_private_tool:" <> spec.name)
      }
    }
    _ -> Error("private_handler_refused_route:" <> spec.route)
  }
}

fn prepare_backends(
  spec: ToolSpec,
  p: principal.Principal,
  backends: server.ServerBackends,
) -> server.ServerBackends {
  case spec.name {
    "sa_task_complete" ->
      server.ServerBackends(
        ..backends,
        planning_write: planning_write.PlanningWriteStore(
          tasks: dict.from_list([
            #(
              #("matrix-write-plan", "matrix-write-task"),
              planning_write.Task(
                admission.TaskExecuting,
                principal.actor_id(p),
                1,
              ),
            ),
          ]),
          jobs: backends.planning_write.jobs,
          workflows: backends.planning_write.workflows,
          bridge_submissions: backends.planning_write.bridge_submissions,
        ),
      )
    _ -> backends
  }
}

fn dispatch_for(
  p: principal.Principal,
  args: dict.Dict(String, String),
  spec: ToolSpec,
  pool: supervisor.WorkerPool,
  backends: server.ServerBackends,
) -> Outcome {
  let ticket = ticket_for(spec)
  let context = context_for(p, ticket)
  let grant = Some(grant_for(spec, ticket))
  let prepared = prepare_backends(spec, p, backends)
  let #(outcome, _, _) =
    server.execute_route_authenticated(
      context,
      grant,
      pool,
      prepared,
      spec.route,
      spec.name,
      args,
      private_handler,
    )
  outcome
}

fn frame_is_jsonrpc(frame: String) -> Bool {
  case json.parse(frame, value.decoder()) {
    Ok(value.Object(fields)) ->
      list.any(fields, fn(field) {
        field.0 == "jsonrpc" && field.1 == value.Text("2.0")
      })
    _ -> False
  }
}

fn frame_is_positive_result(frame: String) -> Bool {
  case json.parse(frame, value.decoder()) {
    Ok(value.Object(fields) as parsed) -> {
      let has_result = list.any(fields, fn(field) { field.0 == "result" })
      let has_error = list.any(fields, fn(field) { field.0 == "error" })
      let is_error_false = case value.get(parsed, "isError") {
        Ok(value.Boolean(False)) -> True
        Error(_) -> True
        _ -> False
      }
      has_result && !has_error && is_error_false
    }
    _ -> False
  }
}

fn candidate_from_frame(frame: String) -> String {
  case json.parse(frame, value.decoder()) {
    Ok(value.Object(_) as parsed) ->
      case value.get(parsed, "result") {
        Ok(result) ->
          case value.get(result, "evidence") {
            Ok(evidence) ->
              case value.get(evidence, "candidate") {
                Ok(value.Text(found)) -> found
                _ -> ""
              }
            _ -> ""
          }
        _ -> ""
      }
    _ -> ""
  }
}

fn result_value_from_frame(frame: String) -> Option(String) {
  case json.parse(frame, value.decoder()) {
    Ok(value.Object(_) as parsed) ->
      case value.get(parsed, "result") {
        Ok(result) ->
          case value.get(result, "value") {
            Ok(value.Text(found)) -> Some(found)
            _ -> None
          }
        _ -> None
      }
    _ -> None
  }
}

fn private_tool_semantic_ok(name: String, val: String) -> Bool {
  case name {
    "harness_write_file" -> string.contains(val, "written_bytes")
    "harness_read_file" -> string.contains(val, "content_sha256")
    "harness_build" -> string.contains(val, "compiled_probe_sha256")
    "harness_test" ->
      string.contains(val, "\"tested_module\":\"mcp_registry_test\"")
    "harness_client_mcp_config" -> string.contains(val, "\"verdict\":\"exact\"")
    "harness_clock" -> string.contains(val, "clock_source")
    "harness_execution_progress" ->
      string.contains(val, "verified_complete_count")
    "harness_system_feature_catalog" -> string.contains(val, "catalog_bytes")
    "harness_system_feature_observations" ->
      string.contains(val, "observation_sha256")
    "harness_system_feature_intent" -> string.contains(val, "intent_sha256")
    "harness_status" -> string.contains(val, "\"lease_active\":true")
    "harness_heartbeat" -> string.contains(val, "\"heartbeat_recorded\":true")
    "harness_claim" | "harness_attach" | "harness_release" ->
      string.contains(val, "lease_transition")
    "harness_plan_intent" -> string.contains(val, "plan_intent_sha256")
    "harness_risk_refresh" | "harness_risk_check" | "harness_assess" ->
      string.contains(val, "\"uca_classes\":4")
    "harness_finish" -> string.contains(val, "finish_sha256")
    "harness_reconcile" -> string.contains(val, "\"reconciled\":true")
    "harness_peers"
    | "harness_peer_read"
    | "harness_peer_review"
    | "harness_peer_note" -> string.contains(val, "peer_op")
    "harness_feature_initialize"
    | "harness_feature_sync"
    | "harness_feature_status" -> string.contains(val, "tracking_op")
    _ -> False
  }
}

fn cell_has_tool_specific_semantics(spec: ToolSpec, frame: String) -> Bool {
  let val = case result_value_from_frame(frame) {
    Some(found) -> found
    None -> ""
  }
  case string.contains(val, "\"handled\":true") {
    True -> False
    False ->
      case string.byte_size(val) {
        0 -> False
        _ ->
          case spec.family {
            "planning_read" ->
              case spec.name {
                "feature_tracker_status" ->
                  string.contains(val, "\"admitted_ev_ceiling\":93")
                  && string.contains(val, "\"declared_total\":")
                "plan_status" | "sa_plan_status" | "sa_plan_status_for" ->
                  string.contains(val, "\"canonical_authority\":\"sa_plan\"")
                  && string.contains(val, "\"total_tasks\":")
                _ ->
                  string.contains(val, "matrix-task")
                  || string.contains(val, "\"rows\":")
              }
            "planning_write" ->
              case spec.name {
                "plan_add" ->
                  string.contains(val, "matrix-add-task")
                  || string.contains(val, "available")
                "plan_update" | "sa_task_claim" ->
                  string.contains(val, "executing")
                "sa_task_complete" -> string.contains(val, "completed")
                "sa_job_enqueue" -> string.contains(val, "matrix-job")
                "sa_workflow_start" -> string.contains(val, "matrix-workflow")
                "sa_bridge_submit" ->
                  string.contains(val, "bridge:matrix-bridge")
                _ -> False
              }
            "observability" | "system_observation" ->
              string.contains(val, "\"snapshot_id\":")
              || string.contains(val, "healthy")
              || string.contains(val, spec.name)
            "control_safety_registry" ->
              string.contains(val, spec.name)
              || string.contains(val, "declared_count")
              || string.contains(val, "preview")
              || string.contains(val, "safety")
            "verification" | "verification_execution" ->
              string.contains(val, "\"verified\":true")
              && string.contains(val, "gleam_toml_sha256=")
            "knowledge_files" ->
              string.contains(val, "uos real matrix workspace content")
              || string.contains(val, "zk public knowledge")
              || string.contains(val, "readme.md")
            "vault_metadata" ->
              case spec.name {
                "vault_status" -> string.contains(val, "\"sealed\":false")
                "vault_health" -> string.contains(val, "\"healthy\":true")
                "vault_list_secrets" ->
                  string.contains(val, "\"secret_names\":")
                "vault_audit_tail" -> string.contains(val, "\"audit_lines\":")
                "vault_policy_get" ->
                  string.contains(val, "\"policy\":\"allow\"")
                _ -> False
              }
            "analysis_inference_sciviz" | "analysis_inference" ->
              string.contains(val, "\"advisory_only\":true")
              && string.contains(val, "\"effect_authority\":false")
            "feature_evidence" ->
              string.contains(val, "93")
              || string.contains(val, "matrix-task")
              || string.contains(val, "matrix-intent")
              || string.contains(val, "capabilities")
            "private_development" | "private_successor" ->
              private_tool_semantic_ok(spec.name, val)
            _ -> False
          }
      }
  }
}

fn positive_args_for(spec: ToolSpec) -> dict.Dict(String, String) {
  let pairs = case spec.family {
    "planning_read" -> [
      #("plan_id", "plan"),
      #("task_id", "matrix-task"),
      #("query", "matrix"),
    ]
    "planning_write" ->
      case spec.name {
        "plan_add" -> [
          #("plan_id", "matrix-add-plan"),
          #("task_id", "matrix-add-task"),
        ]
        "plan_update" | "sa_task_claim" | "sa_task_complete" -> [
          #("plan_id", "matrix-write-plan"),
          #("task_id", "matrix-write-task"),
          #("state", "executing"),
          #("attempt", "1"),
        ]
        "sa_job_enqueue" -> [#("job_id", "matrix-job")]
        "sa_workflow_start" -> [#("workflow_id", "matrix-workflow")]
        "sa_bridge_submit" -> [#("bridge_key", "matrix-bridge")]
        _ -> []
      }
    "observability" | "system_observation" -> []
    "control_safety_registry" -> [
      #("mode", "preview"),
      #("action", "pause"),
      #("controller", "matrix-controller"),
    ]
    "verification" | "verification_execution" -> [
      #("check_id", "gleam_check"),
    ]
    "knowledge_files" ->
      case spec.name {
        "read_file" -> [#("path", "readme.md")]
        "zk_transclude" -> [#("key", "zk/readme.md")]
        "zk_search" -> [#("query", "")]
        _ -> [#("query", "knowledge")]
      }
    "vault_metadata" -> [
      #("tenant_id", workspace),
      #("policy", "default"),
    ]
    "analysis_inference_sciviz" | "analysis_inference" ->
      case spec.name {
        "forecast_predict" -> [
          #("source", "max_model"),
          #("series_key", "matrix"),
        ]
        "stpa_fmea_hazard" -> [
          #("severity", "1"),
          #("occurrence", "1"),
          #("detection", "1"),
        ]
        "rete_rule_conflict" -> [#("rules", "a:b")]
        "ruliad_branch_eval" -> [#("branches", "1,2")]
        "shruti_harmonics" -> [#("frequencies", "100,200")]
        "ast_anomaly_detect" -> [
          #("samples", "1,2"),
          #("sample", "1,2"),
        ]
        "lyapunov_trend_predict" -> [#("series", "1.0,2.0")]
        _ -> [
          #("mark", "point"),
          #("x", "x"),
          #("y", "y"),
        ]
      }
    "feature_evidence" -> [
      #("task_id", "matrix-task"),
      #("feature_id", "matrix-task"),
      #("intent_id", "matrix-intent"),
    ]
    "private_development" | "private_successor" -> [
      #("task_id", "matrix-task"),
      #("path", workspace <> "/readme.md"),
      #("intent_id", "matrix-intent"),
      #("journal_path", "/tmp/matrix-journal"),
      #("build_intent_id", "matrix-build"),
      #("test_intent_id", "matrix-test"),
      #("client", "codex"),
      #("action", "status"),
      #("pane_id", "matrix-pane"),
      #("session_id", matrix_session),
      #("review_id", "matrix-review"),
      #("packet_path", workspace <> "/matrix-packet"),
      #("note", "matrix note"),
      #("feature_id", "matrix-feature"),
    ]
    _ -> []
  }
  dict.from_list(pairs)
}

fn request_frame_with_args(
  spec: ToolSpec,
  request_id: String,
  args: dict.Dict(String, String),
) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.string(request_id)),
    #("method", json.string("tools/call")),
    #(
      "params",
      json.object([
        #("name", json.string(spec.name)),
        #(
          "arguments",
          json.object(
            list.map(dict.to_list(args), fn(pair) {
              #(pair.0, json.string(pair.1))
            }),
          ),
        ),
      ]),
    ),
  ])
  |> json.to_string
}

fn request_frame(spec: ToolSpec, request_id: String) -> String {
  request_frame_with_args(spec, request_id, positive_args_for(spec))
}

fn acceptance_cell(
  spec: ToolSpec,
  client_name: String,
  transport: String,
  scenario: String,
  frame: String,
) -> AcceptanceCell {
  AcceptanceCell(
    candidate: candidate_from_frame(frame),
    positive: frame_is_positive_result(frame),
    route: spec.route,
    tool: spec.name,
    client: client_name,
    version: "2026-07-28",
    transport: transport,
    scenario: scenario,
    output_sha256: files.digest(frame),
    tool_semantic_ok: cell_has_tool_specific_semantics(spec, frame),
  )
}

// ---------------------------------------------------------------------------
// Transport turns
// ---------------------------------------------------------------------------

fn run_stdio_turn(client: profiles.Client, spec: ToolSpec) -> AcceptanceCell {
  let client_name = profiles.name(client)
  let assert Ok(session) =
    stdio.new_session(
      actor_id: "matrix-" <> client_name,
      client_name: client_name,
      workspace_root: workspace,
      session_id: matrix_session,
      profile: Modern20260728,
      deadline_ms: stdio.default_frame_deadline_ms,
    )
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let pool =
    supervisor.WorkerPool(
      ..pool,
      ledger: receipts.new_ledger(matrix_candidate()),
    )
  let backends = matrix_backends()
  let handler = fn(p: principal.Principal, message: wire.NormalizedMessage) -> Outcome {
    dispatch_for(p, dict.from_list(message.args), spec, pool, backends)
  }
  let request =
    request_frame(
      spec,
      "stdio-" <> client_name <> ":" <> spec.route <> ":" <> spec.name,
    )
  let assert Ok(#(_after, frames)) =
    stdio.ingest_chunk(session, request <> "\n", 0, handler)
  list.length(frames) |> should.equal(1)
  let assert Ok(frame) = list.first(frames)
  frame_is_jsonrpc(frame) |> should.be_true()
  acceptance_cell(spec, client_name, "stdio", "valid", frame)
}

fn run_zenoh_turn(client: profiles.Client, spec: ToolSpec) -> AcceptanceCell {
  let client_name = profiles.name(client)
  let actor = "matrix-zenoh-" <> client_name
  let request_id = "req-" <> client_name
  let topic = "indrajaal/mcp/request/" <> client_name <> "/" <> request_id
  let reply_topic =
    "indrajaal/mcp/response/" <> client_name <> "/" <> request_id
  let payload = request_frame(spec, "zenoh-" <> client_name)
  let secret = "matrix-zenoh-secret"
  let signature =
    zenoh.compute_signature(
      secret,
      topic,
      reply_topic,
      actor,
      client_name,
      workspace,
      matrix_session,
      payload,
    )
  let envelope =
    zenoh.SignedZenohEnvelope(
      topic: topic,
      reply_topic: reply_topic,
      sender_actor: actor,
      client_name: client_name,
      workspace_root: workspace,
      session_id: matrix_session,
      payload: payload,
      signature: signature,
    )
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let pool =
    supervisor.WorkerPool(
      ..pool,
      ledger: receipts.new_ledger(matrix_candidate()),
    )
  let backends = matrix_backends()
  let handler = fn(p: principal.Principal, message: wire.NormalizedMessage) -> Outcome {
    dispatch_for(p, dict.from_list(message.args), spec, pool, backends)
  }
  let assert Ok(Some(#(_reply, body))) =
    zenoh.handle_envelope(
      secret,
      True,
      Modern20260728,
      client_name,
      envelope,
      handler,
    )
  frame_is_jsonrpc(body) |> should.be_true()
  acceptance_cell(spec, client_name, "zenoh", "valid", body)
}

fn run_http_turn(client: profiles.Client, spec: ToolSpec) -> AcceptanceCell {
  let client_name = profiles.name(client)
  let actor = "matrix-http-" <> client_name
  let config =
    auth.AuthConfig(
      approved_origins: ["https://nas-1.tail55d152.ts.net"],
      expected_issuer: "matrix-issuer",
      expected_audience: "uos-mcp",
      required_scope: "mcp",
      signing_secret: "matrix-http-secret",
    )
  let claims =
    auth.TokenClaims(
      issuer: "matrix-issuer",
      audience: "uos-mcp",
      actor_id: actor,
      client_name: client_name,
      workspace_root: workspace,
      session_id: matrix_session,
      scopes: ["mcp"],
      issued_at_ms: 100,
      expires_at_ms: 2000,
    )
  let token = auth.sign_token(claims, config.signing_secret)
  let headers = [
    #("Origin", "https://nas-1.tail55d152.ts.net"),
    #("Authorization", "Bearer " <> token),
    #("Content-Type", "application/json"),
    #("Accept", "application/json"),
    #("MCP-Protocol-Version", "2026-07-28"),
    #("Mcp-Session-Id", matrix_session),
  ]
  let http_args = dict.insert(positive_args_for(spec), "actor", actor)
  let body =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.string("http-" <> client_name)),
      #("method", json.string("tools/call")),
      #(
        "params",
        json.object([
          #("name", json.string(spec.name)),
          #("protocolVersion", json.string("2026-07-28")),
          #(
            "arguments",
            json.object(
              list.map(dict.to_list(http_args), fn(pair) {
                #(pair.0, json.string(pair.1))
              }),
            ),
          ),
          #(
            "_meta",
            json.object([
              #("session_id", json.string(matrix_session)),
              #("actor", json.string(actor)),
            ]),
          ),
        ]),
      ),
    ])
    |> json.to_string
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let pool =
    supervisor.WorkerPool(
      ..pool,
      ledger: receipts.new_ledger(matrix_candidate()),
    )
  let backends = matrix_backends()
  let dispatch = fn(
    p: principal.Principal,
    _clean: List(#(String, String)),
    message: wire.NormalizedMessage,
  ) -> Outcome {
    dispatch_for(p, dict.from_list(message.args), spec, pool, backends)
  }
  let response =
    http.handle(
      http.HttpRequest("POST", "/mcp", headers, body),
      config,
      Modern20260728,
      1000,
      "https://nas-1.tail55d152.ts.net/mcp",
      ["https://auth.tail55d152.ts.net"],
      dispatch,
    )
  response.status |> should.equal(200)
  frame_is_jsonrpc(response.body) |> should.be_true()
  acceptance_cell(spec, client_name, "http", "valid", response.body)
}

// ---------------------------------------------------------------------------
// Test 1: full five-client route matrix
// ---------------------------------------------------------------------------

pub fn every_required_matrix_cell_has_actual_client_turn_test() {
  reset_matrix_execution_receipts()
  let client_profiles = profiles.all()
  list.length(client_profiles) |> should.equal(5)
  let clients = list.map(client_profiles, fn(p) { p.client })
  list.map(clients, profiles.name)
  |> should.equal(["agy", "gemini", "codex", "claude", "pi"])

  let specs = registry.all_specs()
  list.length(specs) |> should.equal(101)
  list.count(specs, fn(spec) { spec.route == "public" })
  |> should.equal(65)
  list.count(specs, fn(spec) { spec.route == "development" })
  |> should.equal(21)
  list.count(specs, fn(spec) { spec.route == "successor" })
  |> should.equal(15)
  list.length(clients) * list.length(specs) |> should.equal(505)

  let stdio_cells =
    list.flat_map(clients, fn(client) {
      list.map(specs, fn(spec) { run_stdio_turn(client, spec) })
    })
  list.length(stdio_cells) |> should.equal(505)

  let route_specs =
    list.map(["public", "development", "successor"], fn(route) {
      let tool_name = case route {
        "public" -> "harness_execution_progress"
        _ -> "harness_status"
      }
      let assert Ok(spec) = registry.lookup(route, tool_name)
      spec
    })
  let zenoh_cells =
    list.flat_map(clients, fn(client) {
      list.map(route_specs, fn(spec) { run_zenoh_turn(client, spec) })
    })
  let http_cells =
    list.flat_map(clients, fn(client) {
      list.map(route_specs, fn(spec) { run_http_turn(client, spec) })
    })
  list.length(zenoh_cells) |> should.equal(15)
  list.length(http_cells) |> should.equal(15)

  let all_cells = list.append(stdio_cells, list.append(zenoh_cells, http_cells))
  list.length(all_cells) |> should.equal(535)
  list.length(clients) * list.length(specs) + 30 |> should.equal(535)

  // The active candidate is the live SHA-256 revision, never a static label.
  let active_cand = matrix_candidate()
  string.starts_with(active_cand, "sha256:") |> should.be_true()
  string.byte_size(active_cand) |> should.equal(71)
  active_cand |> should.not_equal("uos-mcp")

  // Every positive matrix cell carries a real client identity, a route tool, a
  // positive (result, no error, isError false/absent) frame, the true active
  // candidate, and a full SHA-256 digest of the emitted frame.
  list.count(all_cells, fn(cell) {
    !cell.positive
    || cell.candidate != active_cand
    || cell.tool == ""
    || cell.client == ""
    || string.byte_size(cell.output_sha256) != 64
  })
  |> should.equal(0)

  list.count(all_cells, fn(cell) {
    cell.positive && cell.candidate == active_cand
  })
  |> should.equal(535)

  // Every cell must carry tool-specific semantics, never the generic
  // `{"handled":true}` fallback that proved nothing about the backend.
  list.count(all_cells, fn(cell) { !cell.tool_semantic_ok })
  |> should.equal(0)
}

// ---------------------------------------------------------------------------
// Test 2: config rollback preserves unrelated private entries
// ---------------------------------------------------------------------------

const owned_server_name = "uos-gleam-dev-fixture"

const owned_command = "/fixture/erl"

const owned_args = ["-noshell"]

const owned_env = ["UOS_HARNESS_SESSION=session-fixture"]

const private_marker = "FAKE_PRIVATE_CREDENTIAL_MUST_NOT_ESCAPE"

fn owned_entry_json() -> String {
  "{\"command\":\"/fixture/erl\",\"args\":[\"-noshell\"],\"env\":{\"UOS_HARNESS_SESSION\":\"session-fixture\"}}"
}

fn unrelated_entry_json() -> String {
  "{\"command\":\"/fixture/legacy\",\"args\":[\"--serve\"],\"env\":{\"PRIVATE_TOKEN\":\"FAKE_PRIVATE_CREDENTIAL_MUST_NOT_ESCAPE\"}}"
}

fn config_without_owned() -> String {
  "{\"mcpServers\":{\"legacy-private\":" <> unrelated_entry_json() <> "}}"
}

fn config_with_owned() -> String {
  "{\"mcpServers\":{\""
  <> owned_server_name
  <> "\":"
  <> owned_entry_json()
  <> ",\"legacy-private\":"
  <> unrelated_entry_json()
  <> "}}"
}

fn config_rolled_back() -> String {
  let owned_fragment =
    "\"" <> owned_server_name <> "\":" <> owned_entry_json() <> ","
  string.replace(config_with_owned(), owned_fragment, "")
}

fn assert_rollback_transition(client: profiles.Client) {
  let base = config_without_owned()
  let with_owned = config_with_owned()
  let rolled_back = config_rolled_back()
  rolled_back |> should.equal(base)
  string.contains(base, private_marker) |> should.be_true()
  string.contains(rolled_back, private_marker) |> should.be_true()
  client_config.inspect_json(
    client,
    owned_server_name,
    base,
    owned_command,
    owned_args,
    owned_env,
  )
  |> should.equal(Ok(client_config.Missing))
  client_config.inspect_json(
    client,
    owned_server_name,
    with_owned,
    owned_command,
    owned_args,
    owned_env,
  )
  |> should.equal(Ok(client_config.Exact))
  client_config.inspect_json(
    client,
    owned_server_name,
    rolled_back,
    owned_command,
    owned_args,
    owned_env,
  )
  |> should.equal(Ok(client_config.Missing))
}

fn codex_entry_json() -> String {
  "{\"name\":\"uos-gleam-dev-fixture\",\"enabled\":true,\"transport\":{\"type\":\"stdio\",\"command\":\"/fixture/erl\",\"args\":[\"-noshell\"],\"env\":{\"UOS_HARNESS_SESSION\":\"session-fixture\"}}}"
}

fn agy_entry_json() -> String {
  "{\"command\":\"/fixture/erl\",\"args\":[\"-noshell\"],\"env\":{\"UOS_HARNESS_SESSION\":\"session-fixture\"},\"disabled\":false}"
}

fn agy_without_owned() -> String {
  "{\"mcpServers\":{}}"
}

fn agy_with_owned() -> String {
  "{\"mcpServers\":{\""
  <> owned_server_name
  <> "\":"
  <> agy_entry_json()
  <> "}}"
}

fn agy_with_extra() -> String {
  "{\"mcpServers\":{\""
  <> owned_server_name
  <> "\":"
  <> agy_entry_json()
  <> ",\"other-private\":{\"command\":\"/fixture/other\",\"args\":[],\"env\":{}}}}"
}

pub fn config_rollback_preserves_unrelated_private_entries_test() {
  // Claude, Gemini and Pi share the mcpServers metadata shape.
  assert_rollback_transition(profiles.Claude)
  assert_rollback_transition(profiles.Gemini)
  assert_rollback_transition(profiles.Pi)

  // Codex is read through its native CLI metadata reader; inspect_json must
  // fail closed rather than guess, while the exact nested entry matcher still
  // proves the owned entry and refuses anything else.
  client_config.inspect_json(
    profiles.Codex,
    owned_server_name,
    config_with_owned(),
    owned_command,
    owned_args,
    owned_env,
  )
  |> should.equal(Error("native_cli_metadata_reader_required"))
  client_mcp.codex_entry_matches(
    codex_entry_json(),
    owned_server_name,
    owned_command,
    owned_args,
    owned_env,
  )
  |> should.be_true()
  client_mcp.codex_entry_matches(
    config_without_owned(),
    owned_server_name,
    owned_command,
    owned_args,
    owned_env,
  )
  |> should.be_false()
  client_mcp.codex_entry_matches(
    string.replace(codex_entry_json(), owned_server_name, "shadow-name"),
    owned_server_name,
    owned_command,
    owned_args,
    owned_env,
  )
  |> should.be_false()

  // Agy's dedicated private profile holds exactly one UOS entry.
  client_config.inspect_agy_profile_json(
    agy_without_owned(),
    owned_server_name,
    owned_command,
    owned_args,
    owned_env,
  )
  |> should.equal(Ok(client_config.Missing))
  client_config.inspect_agy_profile_json(
    agy_with_owned(),
    owned_server_name,
    owned_command,
    owned_args,
    owned_env,
  )
  |> should.equal(Ok(client_config.Exact))
  client_config.inspect_agy_profile_json(
    agy_without_owned(),
    owned_server_name,
    owned_command,
    owned_args,
    owned_env,
  )
  |> should.equal(Ok(client_config.Missing))
  client_config.inspect_agy_profile_json(
    agy_with_extra(),
    owned_server_name,
    owned_command,
    owned_args,
    owned_env,
  )
  |> should.equal(Error("agy_profile_has_unexpected_servers"))

  client_config.observation_label(client_config.Exact)
  |> string.contains(private_marker)
  |> should.be_false()
}

// ---------------------------------------------------------------------------
// Test 3: cross-client handoff retains authority
// ---------------------------------------------------------------------------

fn handoff_ticket() -> admission.GrantTicket {
  admission.GrantTicket(
    grant_id: "handoff-grant",
    scope: TaskScopedMutation,
    revoked: False,
    expires_at_ms: far_future_ms,
    workspace_root: workspace,
  )
}

fn handoff_context(
  actor: String,
  client_name: String,
  attempt: Int,
) -> admission.AdmissionContext {
  admission.AdmissionContext(
    principal: principal.from_launcher_env(
      actor,
      ClientProfile(client_name),
      workspace,
      "session-" <> actor,
    ),
    mode: admission.EnforcedMode,
    now_ms: 1_000_000,
    workspace_root: workspace,
    task_fence: Some(admission.TaskFence(
      plan_id: "plan-handoff",
      task_id: "authority-handoff",
      worker_id: actor,
      attempt: attempt,
      task_state: admission.TaskExecuting,
      lease_until_ms: far_future_ms,
      grant: Some(handoff_ticket()),
    )),
  )
}

fn task_args(plan_id: String, task_id: String) -> dict.Dict(String, String) {
  dict.from_list([
    #("plan_id", plan_id),
    #("task_id", task_id),
  ])
}

fn complete_args(
  plan_id: String,
  task_id: String,
  attempt: String,
) -> dict.Dict(String, String) {
  dict.from_list([
    #("plan_id", plan_id),
    #("task_id", task_id),
    #("attempt", attempt),
  ])
}

pub fn cross_client_handoff_retains_authority_test() {
  let assert Ok(pool0) = supervisor.start_worker_pool(1)
  let backends0 = matrix_backends()
  let agy = handoff_context("worker-agy", "agy", 1)
  let codex_one = handoff_context("worker-codex", "codex", 1)

  // Client 1 (agy) adds and claims T-1.
  let #(add, pool1, backends1) =
    server.execute_authenticated(
      agy,
      pool0,
      backends0,
      "plan_add",
      task_args("plan-handoff", "T-1"),
    )
  let assert Complete(_, _) = add
  let #(claim, pool2, backends2) =
    server.execute_authenticated(
      agy,
      pool1,
      backends1,
      "sa_task_claim",
      task_args("plan-handoff", "T-1"),
    )
  let assert Complete(_, _) = claim
  let assert Ok(task_one) =
    dict.get(backends2.planning_write.tasks, #("plan-handoff", "T-1"))
  task_one.worker |> should.equal("worker-agy")
  task_one.attempt |> should.equal(1)

  // Client 2 (codex) cannot complete a task owned by agy.
  let #(cross_refusal, pool3, backends3) =
    server.execute_authenticated(
      codex_one,
      pool2,
      backends2,
      "sa_task_complete",
      complete_args("plan-handoff", "T-1", "1"),
    )
  let assert Refused(cross_error) = cross_refusal
  cross_error.code |> should.equal("PRINCIPAL_WORKER_MISMATCH")

  // Handoff: T-2 is added and claimed, then re-claimed by codex at attempt 2.
  let #(_add_two, pool4, backends4) =
    server.execute_authenticated(
      agy,
      pool3,
      backends3,
      "plan_add",
      task_args("plan-handoff", "T-2"),
    )
  let #(claim_two, pool5, backends5) =
    server.execute_authenticated(
      agy,
      pool4,
      backends4,
      "sa_task_claim",
      task_args("plan-handoff", "T-2"),
    )
  let assert Complete(_, _) = claim_two
  let handoff_store =
    planning_write.PlanningWriteStore(
      ..backends5.planning_write,
      tasks: dict.insert(
        backends5.planning_write.tasks,
        #("plan-handoff", "T-2"),
        planning_write.Task(admission.TaskExecuting, "worker-codex", 2),
      ),
    )
  let backends6 =
    server.ServerBackends(..backends5, planning_write: handoff_store)
  let codex_two = handoff_context("worker-codex", "codex", 2)

  // Stale replay from Client 1 at attempt 1 is refused.
  let #(stale, pool6, backends7) =
    server.execute_authenticated(
      agy,
      pool5,
      backends6,
      "sa_task_complete",
      complete_args("plan-handoff", "T-2", "1"),
    )
  let assert Refused(stale_error) = stale
  stale_error.code |> should.equal("STALE_ATTEMPT_FENCE")

  // Client 2 at attempt 2 completes cleanly.
  let #(done, pool7, backends8) =
    server.execute_authenticated(
      codex_two,
      pool6,
      backends7,
      "sa_task_complete",
      complete_args("plan-handoff", "T-2", "2"),
    )
  let assert Complete(_, evidence) = done
  evidence.tool |> should.equal("sa_task_complete")
  let assert Ok(task_two) =
    dict.get(backends8.planning_write.tasks, #("plan-handoff", "T-2"))
  task_two.state |> should.equal(admission.TaskCompleted)
  task_two.worker |> should.equal("worker-codex")
  task_two.attempt |> should.equal(2)
  pool7 |> should.not_equal(pool6)
}

// ---------------------------------------------------------------------------
// Test 4: refusal frames can never count as positive matrix cells
// ---------------------------------------------------------------------------

fn run_refusal_stdio_frame(
  p: principal.Principal,
  client_name: String,
  spec: ToolSpec,
  context: admission.AdmissionContext,
  grant: Option(RouteGrant),
  args: dict.Dict(String, String),
  backends: server.ServerBackends,
) -> String {
  let assert Ok(session) =
    stdio.new_session(
      actor_id: principal.actor_id(p),
      client_name: client_name,
      workspace_root: workspace,
      session_id: matrix_session,
      profile: Modern20260728,
      deadline_ms: stdio.default_frame_deadline_ms,
    )
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let pool =
    supervisor.WorkerPool(
      ..pool,
      ledger: receipts.new_ledger(matrix_candidate()),
    )
  let handler = fn(
    _session_principal: principal.Principal,
    _message: wire.NormalizedMessage,
  ) -> Outcome {
    let #(outcome, _, _) =
      server.execute_route_authenticated(
        context,
        grant,
        pool,
        backends,
        spec.route,
        spec.name,
        args,
        private_handler,
      )
    outcome
  }
  let request =
    request_frame_with_args(
      spec,
      "refusal-" <> client_name <> ":" <> spec.route <> ":" <> spec.name,
      args,
    )
  let assert Ok(#(_after, frames)) =
    stdio.ingest_chunk(session, request <> "\n", 0, handler)
  let assert Ok(frame) = list.first(frames)
  frame_is_jsonrpc(frame) |> should.be_true()
  frame
}

pub fn refusal_cells_never_count_as_positive_matrix_cells_test() {
  let p =
    principal.from_launcher_env(
      "matrix-refusal",
      ClientProfile("codex"),
      workspace,
      matrix_session,
    )
  let backends = matrix_backends()

  let assert Ok(control_spec) = registry.lookup("public", "control_loop")
  let revoked = admission.GrantTicket(..ticket_for(control_spec), revoked: True)
  let revoked_frame =
    run_refusal_stdio_frame(
      p,
      "codex",
      control_spec,
      context_for(p, revoked),
      Some(grant_for(control_spec, revoked)),
      positive_args_for(control_spec),
      backends,
    )

  let assert Ok(read_spec) = registry.lookup("public", "read_file")
  let read_ticket = ticket_for(read_spec)
  let forbidden_args =
    dict.insert(positive_args_for(read_spec), "path", "/etc/passwd")
  let forbidden_frame =
    run_refusal_stdio_frame(
      p,
      "codex",
      read_spec,
      context_for(p, read_ticket),
      Some(grant_for(read_spec, read_ticket)),
      forbidden_args,
      backends,
    )

  let assert Ok(add_spec) = registry.lookup("public", "plan_add")
  let add_ticket = ticket_for(add_spec)
  let unfenced_context =
    admission.AdmissionContext(..context_for(p, add_ticket), task_fence: None)
  let unauthenticated_mutation_frame =
    run_refusal_stdio_frame(
      p,
      "codex",
      add_spec,
      unfenced_context,
      Some(grant_for(add_spec, add_ticket)),
      positive_args_for(add_spec),
      backends,
    )

  list.each(
    [revoked_frame, forbidden_frame, unauthenticated_mutation_frame],
    fn(frame) {
      frame_is_positive_result(frame) |> should.be_false()
      candidate_from_frame(frame) |> should.equal("")
    },
  )
}

// ---------------------------------------------------------------------------
// T23-C08: meaningful backend effects and foreign-candidate negative control
// ---------------------------------------------------------------------------

pub fn meaningful_backend_effects_and_foreign_candidate_negative_control_test() {
  reset_matrix_execution_receipts()
  let p =
    principal.from_launcher_env(
      "matrix-meaningful",
      ClientProfile("codex"),
      workspace,
      matrix_session,
    )
  let backends = matrix_backends()
  let assert Ok(pool) = supervisor.start_worker_pool(1)
  let pool =
    supervisor.WorkerPool(
      ..pool,
      ledger: receipts.new_ledger(matrix_candidate()),
    )

  let assert Ok(write_spec) =
    registry.lookup("development", "harness_write_file")
  let write_ticket = ticket_for(write_spec)
  let #(write_outcome, pool1, _) =
    server.execute_route_authenticated(
      context_for(p, write_ticket),
      Some(grant_for(write_spec, write_ticket)),
      pool,
      backends,
      "development",
      "harness_write_file",
      dict.from_list([#("note", "real-disk-effect-payload")]),
      private_handler,
    )
  let assert Complete(_, _) = write_outcome

  let assert Ok(read_spec) = registry.lookup("development", "harness_read_file")
  let read_ticket = ticket_for(read_spec)
  let #(read_outcome, _, _) =
    server.execute_route_authenticated(
      context_for(p, read_ticket),
      Some(grant_for(read_spec, read_ticket)),
      pool1,
      backends,
      "development",
      "harness_read_file",
      dict.from_list([#("path", matrix_temp_workspace <> "/written.txt")]),
      private_handler,
    )
  let assert Complete(read_payload, _) = read_outcome
  string.contains(read_payload, "real-disk-effect-payload") |> should.be_true()
  string.contains(read_payload, files.digest("real-disk-effect-payload"))
  |> should.be_true()

  // Real subprocess effect: the development route must actually compile an
  // Erlang probe and run the EUnit module, not just report a boolean.
  let assert Ok(build_spec) = registry.lookup("development", "harness_build")
  let build_ticket = ticket_for(build_spec)
  let #(build_outcome, pool2, _) =
    server.execute_route_authenticated(
      context_for(p, build_ticket),
      Some(grant_for(build_spec, build_ticket)),
      pool1,
      backends,
      "development",
      "harness_build",
      dict.new(),
      private_handler,
    )
  let assert Complete(build_payload, _) = build_outcome
  string.contains(build_payload, "compiled_probe_sha256") |> should.be_true()
  simplifile.is_file(matrix_temp_workspace <> "/uos_matrix_build_probe.beam")
  |> should.equal(Ok(True))

  let assert Ok(test_spec) = registry.lookup("development", "harness_test")
  let test_ticket = ticket_for(test_spec)
  let #(test_outcome, _, _) =
    server.execute_route_authenticated(
      context_for(p, test_ticket),
      Some(grant_for(test_spec, test_ticket)),
      pool2,
      backends,
      "development",
      "harness_test",
      dict.new(),
      private_handler,
    )
  let assert Complete(test_payload, _) = test_outcome
  string.contains(test_payload, "\"tested_module\":\"mcp_registry_test\"")
  |> should.be_true()

  // Negative control: a stale/foreign active candidate must refuse both a
  // public and a development turn, and must never report a candidate.
  let foreign_candidate =
    "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  let foreign_backends =
    server.ServerBackends(
      ..backends,
      features: FeatureEvidenceStore(
        ..backends.features,
        active_candidate: foreign_candidate,
      ),
    )

  let assert Ok(public_spec) = registry.lookup("public", "plan_status")
  let public_frame =
    run_refusal_stdio_frame(
      p,
      "codex",
      public_spec,
      context_for(p, ticket_for(public_spec)),
      None,
      positive_args_for(public_spec),
      foreign_backends,
    )
  frame_is_positive_result(public_frame) |> should.be_false()
  candidate_from_frame(public_frame) |> should.equal("")

  let assert Ok(dev_spec) = registry.lookup("development", "harness_status")
  let dev_ticket = ticket_for(dev_spec)
  let dev_frame =
    run_refusal_stdio_frame(
      p,
      "codex",
      dev_spec,
      context_for(p, dev_ticket),
      Some(grant_for(dev_spec, dev_ticket)),
      positive_args_for(dev_spec),
      foreign_backends,
    )
  frame_is_positive_result(dev_frame) |> should.be_false()
  candidate_from_frame(dev_frame) |> should.equal("")
}
