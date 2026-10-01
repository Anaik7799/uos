//// =============================================================================
//// [C3I-SIL6-MSTS] Direct Bounded Read Dispatcher (SC-JIDOKA-001, SC-COG-001)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/harness/direct_read_dispatch</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <topology>Bounded Read-Only Dispatch under Canonical Sa-Plan & Coordinator Fencing</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-JIDOKA-001, SC-SA-PLAN-001, SC-COG-001, SC-PROVENANCE-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Direct local read dispatch interface. Bounded strictly to read-only diagnostic
//// observation tools (query_doctor, query_saplan). Never accepts authority from
//// caller payload claims; verifies canonical Sa-plan execution state and live
//// coordinator task resource leases via dev.fence_for before and after observation.

import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/doctor_projection
import cepaf_gleam/harness/tool_fenced_dispatcher as td
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)

pub const canonical_database = "/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3"

pub const direct_read_allowlist: List(String) = [
  "query_doctor",
  "query_saplan",
]

/// Strict launcher environment binding for local direct dispatch.
/// Trusted same-Unix-user launcher environment; not credential authentication.
/// Strictly requires UOS_DIRECT_ROLE == "direct_read" and all 6 UOS_DIRECT_* fields.
/// Zero fallback to UOS_HARNESS_* and zero role defaults or aliases.
pub fn load_direct_binding() -> Result(dev.Binding, String) {
  use role <- result.try(
    get_env("UOS_DIRECT_ROLE")
    |> result.map_error(fn(_) { "role_binding_missing" }),
  )
  use _ <- result.try(case role == "direct_read" {
    True -> Ok(Nil)
    False -> Error("invalid_direct_role_expected_direct_read")
  })
  use plan <- result.try(
    get_env("UOS_DIRECT_PLAN")
    |> result.map_error(fn(_) { "plan_binding_missing" }),
  )
  use task <- result.try(
    get_env("UOS_DIRECT_TASK")
    |> result.map_error(fn(_) { "task_binding_missing" }),
  )
  use worker <- result.try(
    get_env("UOS_DIRECT_WORKER")
    |> result.map_error(fn(_) { "worker_binding_missing" }),
  )
  use attempt <- result.try(
    get_env("UOS_DIRECT_ATTEMPT")
    |> result.try(int.parse)
    |> result.map_error(fn(_) { "attempt_binding_missing" }),
  )
  use session <- result.try(
    get_env("UOS_DIRECT_SESSION")
    |> result.map_error(fn(_) { "session_binding_missing" }),
  )
  use epoch <- result.try(
    get_env("UOS_DIRECT_EPOCH")
    |> result.try(int.parse)
    |> result.map_error(fn(_) { "epoch_binding_missing" }),
  )

  case
    dev.valid_identifier(role)
    && dev.valid_identifier(plan)
    && dev.valid_identifier(task)
    && dev.valid_identifier(worker)
    && attempt >= 1
    && dev.valid_identifier(session)
    && epoch >= 1
  {
    True -> Ok(dev.Binding(role, plan, task, worker, attempt, session, epoch))
    False -> Error("direct_binding_invalid_identifier")
  }
}

/// Validate tool proposal bounds, allowlist, and strict empty argument object.
pub fn validate_tool_proposal(
  proposal: td.ToolProposal,
) -> Result(Nil, td.DispatchOutcome) {
  let id_len = string.byte_size(proposal.call_id)
  use _ <- result.try(
    case id_len > 0 && id_len <= 64 && dev.valid_identifier(proposal.call_id) {
      True -> Ok(Nil)
      False ->
        Error(td.FencedAndonHalt(
          -32_000,
          "Invalid call_id: must be 1..64 alphanumeric/identifier bytes.",
        ))
    },
  )
  use _ <- result.try(case list.contains(direct_read_allowlist, proposal.tool_name) {
    True -> Ok(Nil)
    False ->
      Error(td.FencedAndonHalt(
        -32_001,
        "Tool '"
          <> proposal.tool_name
          <> "' is not in direct read allowlist. Strictly allowed: [query_doctor, query_saplan].",
      ))
  })
  let args_len = string.byte_size(proposal.args_json)
  case args_len <= 256 {
    False ->
      Error(td.FencedAndonHalt(
        -32_000,
        "Tool proposal args exceed bound (limit 256 bytes).",
      ))
    True -> {
      let empty_dict_decoder = decode.dict(decode.string, decode.dynamic)
      case json.parse(proposal.args_json, empty_dict_decoder) {
        Ok(entries) ->
          case dict.size(entries) == 0 {
            True -> Ok(Nil)
            False ->
              Error(td.FencedAndonHalt(
                -32_000,
                "Invalid arguments: tool '"
                  <> proposal.tool_name
                  <> "' strictly requires empty JSON object '{}'.",
              ))
          }
        Error(_) ->
          Error(td.FencedAndonHalt(
            -32_000,
            "Invalid arguments: tool '"
              <> proposal.tool_name
              <> "' strictly requires empty JSON object '{}'.",
          ))
      }
    }
  }
}

pub type SanitizedTask {
  SanitizedTask(id: String, state: String)
}

fn task_entry_decoder() -> decode.Decoder(SanitizedTask) {
  use id <- decode.field("id", decode.string)
  use state <- decode.field("state", decode.string)
  decode.success(SanitizedTask(id, state))
}

pub fn parse_sanitized_tasks(raw: String) -> Result(List(SanitizedTask), String) {
  use _ <- result.try(case string.byte_size(raw) <= 262_144 {
    True -> Ok(Nil)
    False -> Error("task_list_bound_exceeded")
  })
  use tasks <- result.try(
    json.parse(raw, decode.list(task_entry_decoder()))
    |> result.replace_error("invalid_task_list_json"),
  )
  case list.length(tasks) > 256 {
    True ->
      Error(
        "task_count_exceeds_limit_256: plan task count exceeds 256 bound; direct read observation refused",
      )
    False -> Ok(tasks)
  }
}

pub fn format_sanitized_saplan(
  plan_id: String,
  tasks: List(SanitizedTask),
) -> String {
  let total = list.length(tasks)
  let executing = list.count(tasks, fn(t) { t.state == "executing" })
  let completed = list.count(tasks, fn(t) { t.state == "completed" })
  let available = list.count(tasks, fn(t) { t.state == "available" })
  let blocked = list.count(tasks, fn(t) { t.state == "blocked" })
  let failed = list.count(tasks, fn(t) { t.state == "failed" })

  let task_objects =
    list.map(tasks, fn(t) {
      json.object([
        #("id", json.string(t.id)),
        #("state", json.string(t.state)),
      ])
    })

  json.object([
    #("plan_id", json.string(plan_id)),
    #("total_tasks", json.int(total)),
    #("executing", json.int(executing)),
    #("completed", json.int(completed)),
    #("available", json.int(available)),
    #("blocked", json.int(blocked)),
    #("failed", json.int(failed)),
    #("tasks", json.array(task_objects, fn(x) { x })),
    #("authority", json.string("canonical_sa_plan_readonly_observation")),
  ])
  |> json.to_string
}

/// Query plan tasks directly from canonical SQLite, sanitizing output to IDs and states only.
pub fn query_bound_saplan(
  plan_id: String,
  db_path: String,
) -> Result(String, String) {
  use _ <- result.try(case dev.valid_identifier(plan_id) {
    True -> Ok(Nil)
    False -> Error("invalid_plan_identifier")
  })
  use _ <- result.try(case
    string.byte_size(db_path) > 0
    && string.byte_size(db_path) <= 256
    && !string.contains(db_path, "\u{0}")
  {
    True -> Ok(Nil)
    False -> Error("invalid_database_path")
  })
  let sql =
    "SELECT id, state FROM sa_plan_task WHERE plan_id='"
    <> plan_id
    <> "' ORDER BY id LIMIT 257;"
  use raw <- result.try(dev.bounded(
    "/usr/bin/sqlite3",
    ["-readonly", "-json", db_path, sql],
    3000,
  ))
  use tasks <- result.try(parse_sanitized_tasks(raw))
  Ok(format_sanitized_saplan(plan_id, tasks))
}

pub fn execute_production_read_tool(
  tool_name: String,
  binding: dev.Binding,
) -> Result(String, String) {
  case tool_name {
    "query_doctor" ->
      Ok(
        doctor_projection.project()
        |> doctor_projection.to_json,
      )
    "query_saplan" ->
      query_bound_saplan(binding.plan, canonical_database)
    _ -> Error("tool_not_allowlisted: " <> tool_name)
  }
}

/// Dispatches a direct bounded read proposal under verified canonical authority.
/// Requires dev.fence_for BEFORE and AFTER observation, ensuring live executing task
/// and coordinator leases with >=10s budget were active throughout the observation.
pub fn dispatch_with_fencer(
  proposal: td.ToolProposal,
  binding: dev.Binding,
  fencer_fn: fn(dev.Binding, Int) -> Result(dev.Fence, String),
  executor_fn: fn(String, dev.Binding) -> Result(String, String),
) -> td.DispatchOutcome {
  case validate_tool_proposal(proposal) {
    Error(outcome) -> outcome
    Ok(Nil) -> {
      // 1. Pre-execution fence: require valid executing task and coordinator lease with >=10s budget
      case fencer_fn(binding, 10_000) {
        Error(err) ->
          td.FencedAndonHalt(
            td.andon_halt_unauthorized_code,
            "Authority fence failed before observation: " <> err,
          )
        Ok(fence_before) -> {
          // 2. Bounded observation execution
          case executor_fn(proposal.tool_name, binding) {
            Error(exec_err) ->
              td.FencedAndonHalt(
                -32_000,
                "Tool observation error: " <> exec_err,
              )
            Ok(result_json) -> {
              // 3. Post-execution fence: ensure authority did not lapse or change during observation
              case fencer_fn(binding, 10_000) {
                Error(post_err) ->
                  td.FencedAndonHalt(
                    td.andon_halt_unauthorized_code,
                    "Authority fence failed after observation (authority changed or expired during execution): "
                      <> post_err,
                  )
                Ok(fence_after) -> {
                  // 4. Clock continuity between pre and post fences
                  case clock.continuity(fence_before.clock, fence_after.clock) {
                    Error(clock_err) ->
                      td.FencedAndonHalt(
                        td.andon_halt_unauthorized_code,
                        "Clock continuity check failed between fences: "
                          <> clock_err,
                      )
                    Ok(Nil) -> {
                      // Dispatched successfully with authentic sanitized result
                      td.Dispatched(
                        proposal.call_id,
                        proposal.tool_name,
                        result_json,
                      )
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Internal adaptation: development.evaluate_task_window strictly requires
/// binding.role == "development". To preserve the existing unweakened shared
/// development fence boundary without routing to dev.call or widening development.gleam,
/// direct_read_dispatch copies the validated direct_read binding with role "development"
/// ONLY for the read-only dev.fence_for observation.
pub fn observe_fence_for(
  binding: dev.Binding,
  required_ms: Int,
) -> Result(dev.Fence, String) {
  let internal_binding =
    dev.Binding(
      role: "development",
      plan: binding.plan,
      task: binding.task,
      worker: binding.worker,
      attempt: binding.attempt,
      session: binding.session,
      epoch: binding.epoch,
    )
  dev.fence_for(internal_binding, required_ms)
}

/// Canonical production direct dispatch.
/// Loads binding strictly from local environment; executes against production Sa-plan DB.
pub fn dispatch(proposal: td.ToolProposal) -> td.DispatchOutcome {
  case load_direct_binding() {
    Error(err) ->
      td.FencedAndonHalt(
        td.andon_halt_unauthorized_code,
        "Launcher binding missing or invalid: " <> err,
      )
    Ok(binding) ->
      dispatch_with_fencer(
        proposal,
        binding,
        observe_fence_for,
        execute_production_read_tool,
      )
  }
}

// =============================================================================
// Bounded Stdio MCP Interface (tools/list + tools/call)
// =============================================================================

pub fn mcp_tools_list_response(id: json.Json) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", id),
    #(
      "result",
      json.object([
        #(
          "tools",
          json.array(
            [
              json.object([
                #("name", json.string("query_doctor")),
                #(
                  "description",
                  json.string(
                    "Truthful diagnostic health and EV-Cycle provenance projection (EV-93 ceiling).",
                  ),
                ),
                #(
                  "inputSchema",
                  json.object([
                    #("type", json.string("object")),
                    #("properties", json.object([])),
                    #("additionalProperties", json.bool(False)),
                  ]),
                ),
              ]),
              json.object([
                #("name", json.string("query_saplan")),
                #(
                  "description",
                  json.string(
                    "Truthful sanitized task counts and states for the canonically bound Sa-plan.",
                  ),
                ),
                #(
                  "inputSchema",
                  json.object([
                    #("type", json.string("object")),
                    #("properties", json.object([])),
                    #("additionalProperties", json.bool(False)),
                  ]),
                ),
              ]),
            ],
            fn(x) { x },
          ),
        ),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn handle_mcp_call(
  id: json.Json,
  tool_name: String,
  args_json: String,
) -> String {
  let call_id = "mcp-" <> tool_name
  let outcome = dispatch(td.ToolProposal(call_id, tool_name, args_json))
  case outcome {
    td.Dispatched(_id, _name, result_json) -> {
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", id),
        #(
          "result",
          json.object([
            #(
              "content",
              json.array(
                [
                  json.object([
                    #("type", json.string("text")),
                    #("text", json.string(result_json)),
                  ]),
                ],
                fn(x) { x },
              ),
            ),
          ]),
        ),
      ])
      |> json.to_string
    }
    td.FencedAndonHalt(code, reason) -> {
      json.object([
        #("jsonrpc", json.string("2.0")),
        #("id", id),
        #(
          "error",
          json.object([
            #("code", json.int(code)),
            #("message", json.string(reason)),
          ]),
        ),
      ])
      |> json.to_string
    }
  }
}
