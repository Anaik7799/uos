//// Control Safety Registry Adapter (T08): control_loop, safety_status,
//// registry_status.
////
//// Safety invariants:
////   * Registry declaration is never conflated with observed runtime health;
////     a DeclaredOnly controller always reports runtime_state=unobserved and
////     runtime_healthy=false.
////   * Safety verdicts are derived strictly from the live interlock, the count
////     of open STPA hazards, and the health of observed controllers, never
////     hardcoded.
////   * control_loop preview is side-effect free (backend returned unchanged);
////     execute/revert recheck running state, safety constraints, principal
////     ownership, and the fencing attempt at effect time.

import cepaf_gleam/mcp/admission.{type ValidatedCall}
import cepaf_gleam/mcp/evidence
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolError, NonRetryable, Refused, ToolError,
}
import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type ControlIntent {
  PreviewStep(stage: String)
  ExecuteReversibleStep(stage: String)
  RevertLastStep
}

pub type ControllerEntry {
  DeclaredOnly(controller_id: String, layer: Int)
  ObservedInstance(
    controller_id: String,
    layer: Int,
    runtime_healthy: Bool,
    constraints_satisfied: Bool,
    owner_worker: String,
    attempt: Int,
    current_stage: String,
    previous_stage: Option(String),
  )
}

pub type ControlBackend {
  ControlBackend(
    candidate: String,
    stpa_hazards_open: Int,
    interlock_armed: Bool,
    controllers: Dict(String, ControllerEntry),
  )
}

/// Closed allowlist of reversible control stages. Arbitrary action strings are
/// rejected fail-closed by `parse_control_intent`.
pub const reversible_stages = [
  "pause",
  "resume",
  "quiesce",
  "drain",
  "throttle",
]

pub fn parse_control_intent(
  mode mode: String,
  action action: String,
) -> Result(ControlIntent, ToolError) {
  let normalized_mode = string.lowercase(string.trim(mode))
  let normalized_action = string.lowercase(string.trim(action))
  case normalized_mode {
    "preview" ->
      case is_reversible_stage(normalized_action) {
        True -> Ok(PreviewStep(normalized_action))
        False -> disallowed_control_intent(mode, action)
      }
    "execute" ->
      case normalized_action {
        "revert" -> Ok(RevertLastStep)
        _ ->
          case is_reversible_stage(normalized_action) {
            True -> Ok(ExecuteReversibleStep(normalized_action))
            False -> disallowed_control_intent(mode, action)
          }
      }
    "revert" ->
      case normalized_action {
        "last" | "" -> Ok(RevertLastStep)
        _ -> disallowed_control_intent(mode, action)
      }
    _ -> disallowed_control_intent(mode, action)
  }
}

pub fn execute(
  backend backend: ControlBackend,
  call call: ValidatedCall,
) -> #(Outcome, ControlBackend) {
  case call.spec.name {
    "registry_status" -> #(registry_status(backend, call), backend)
    "safety_status" -> #(safety_status(backend, call), backend)
    "control_loop" -> control_loop(backend, call)
    _ -> #(
      Refused(ToolError(
        "UNSUPPORTED_CONTROL_TOOL",
        "Unsupported tool in control adapter: " <> call.spec.name,
        NonRetryable,
      )),
      backend,
    )
  }
}

fn registry_status(backend: ControlBackend, call: ValidatedCall) -> Outcome {
  let entries =
    backend.controllers
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  let declared_count = list.length(entries)
  let observed_running_count =
    entries
    |> list.filter(fn(pair) {
      case pair.1 {
        ObservedInstance(_, _, runtime_healthy, _, _, _, _, _) ->
          runtime_healthy
        DeclaredOnly(_, _) -> False
      }
    })
    |> list.length
  let payload =
    json.object([
      #("tool", json.string(call.spec.name)),
      #("declared_count", json.int(declared_count)),
      #("observed_running_count", json.int(observed_running_count)),
      #(
        "controllers",
        json.array(entries, fn(pair) { controller_json(pair.0, pair.1) }),
      ),
    ])
    |> json.to_string
  complete(backend, call, payload)
}

fn controller_json(controller_id: String, entry: ControllerEntry) -> Json {
  case entry {
    DeclaredOnly(_, layer) ->
      json.object([
        #("controller_id", json.string(controller_id)),
        #("layer", json.int(layer)),
        #("declaration_state", json.string("declared")),
        #("runtime_state", json.string("unobserved")),
        #("runtime_healthy", json.bool(False)),
        #("constraints_satisfied", json.bool(False)),
      ])
    ObservedInstance(
      _,
      layer,
      runtime_healthy,
      constraints_satisfied,
      owner_worker,
      attempt,
      current_stage,
      previous_stage,
    ) ->
      json.object([
        #("controller_id", json.string(controller_id)),
        #("layer", json.int(layer)),
        #("declaration_state", json.string("declared")),
        #("runtime_state", json.string("observed")),
        #("runtime_healthy", json.bool(runtime_healthy)),
        #("constraints_satisfied", json.bool(constraints_satisfied)),
        #("owner_worker", json.string(owner_worker)),
        #("attempt", json.int(attempt)),
        #("current_stage", json.string(current_stage)),
        #("previous_stage", optional_string(previous_stage)),
      ])
  }
}

fn safety_status(backend: ControlBackend, call: ValidatedCall) -> Outcome {
  let observed =
    backend.controllers
    |> dict.to_list
    |> list.filter(fn(pair) {
      case pair.1 {
        ObservedInstance(_, _, _, _, _, _, _, _) -> True
        DeclaredOnly(_, _) -> False
      }
    })
  let observed_count = list.length(observed)
  let all_observed_healthy =
    list.all(observed, fn(pair) {
      case pair.1 {
        ObservedInstance(_, _, runtime_healthy, _, _, _, _, _) ->
          runtime_healthy
        DeclaredOnly(_, _) -> True
      }
    })
  let safe =
    backend.interlock_armed
    && backend.stpa_hazards_open == 0
    && all_observed_healthy
  let verdict = case observed_count == 0 {
    True -> "unobserved"
    False ->
      case safe {
        True -> "healthy"
        False -> "unsafe"
      }
  }
  let payload =
    json.object([
      #("tool", json.string(call.spec.name)),
      #("interlock_armed", json.bool(backend.interlock_armed)),
      #("stpa_hazards_open", json.int(backend.stpa_hazards_open)),
      #("observed_count", json.int(observed_count)),
      #("all_observed_healthy", json.bool(all_observed_healthy)),
      #("safety_verdict", json.string(verdict)),
    ])
    |> json.to_string
  complete(backend, call, payload)
}

fn control_loop(
  backend: ControlBackend,
  call: ValidatedCall,
) -> #(Outcome, ControlBackend) {
  case parse_control_intent(arg(call, "mode"), arg(call, "action")) {
    Error(error) -> #(Refused(error), backend)
    Ok(PreviewStep(stage)) -> {
      let payload =
        json.object([
          #("tool", json.string(call.spec.name)),
          #("mode", json.string("preview")),
          #("mutated", json.bool(False)),
          #("controller", json.string(arg(call, "controller"))),
          #("stage", json.string(stage)),
        ])
        |> json.to_string
      // Preview must be completely side-effect free: return backend unchanged.
      #(complete(backend, call, payload), backend)
    }
    Ok(ExecuteReversibleStep(stage)) -> execute_step(backend, call, stage)
    Ok(RevertLastStep) -> revert_step(backend, call)
  }
}

fn execute_step(
  backend: ControlBackend,
  call: ValidatedCall,
  stage: String,
) -> #(Outcome, ControlBackend) {
  case lookup_controller(backend, call) {
    Error(error) -> #(Refused(error), backend)
    Ok(#(controller, entry)) ->
      case entry {
        DeclaredOnly(_, _) -> #(
          Refused(controller_not_running(controller)),
          backend,
        )
        ObservedInstance(
          _,
          _,
          runtime_healthy,
          constraints_satisfied,
          owner_worker,
          attempt,
          current_stage,
          _,
        ) as instance ->
          case
            recheck(
              backend,
              call,
              runtime_healthy,
              constraints_satisfied,
              owner_worker,
              attempt,
            )
          {
            Error(error) -> #(Refused(error), backend)
            Ok(_) ->
              case current_stage == stage {
                // Idempotent replay: the controller is already in the target
                // stage, so preserve `previous_stage` and leave backend as-is.
                // Overwriting it here would destroy the revert target.
                True -> {
                  let payload =
                    json.object([
                      #("tool", json.string(call.spec.name)),
                      #("mode", json.string("execute")),
                      #("mutated", json.bool(False)),
                      #("controller", json.string(controller)),
                      #("stage", json.string(stage)),
                    ])
                    |> json.to_string
                  #(complete(backend, call, payload), backend)
                }
                False -> {
                  let updated_entry =
                    ObservedInstance(
                      ..instance,
                      current_stage: stage,
                      previous_stage: Some(current_stage),
                    )
                  let updated =
                    ControlBackend(
                      ..backend,
                      controllers: dict.insert(
                        backend.controllers,
                        controller,
                        updated_entry,
                      ),
                    )
                  let payload =
                    json.object([
                      #("tool", json.string(call.spec.name)),
                      #("mode", json.string("execute")),
                      #("mutated", json.bool(True)),
                      #("controller", json.string(controller)),
                      #("stage", json.string(stage)),
                      #("previous_stage", json.string(current_stage)),
                    ])
                    |> json.to_string
                  #(complete(updated, call, payload), updated)
                }
              }
          }
      }
  }
}

fn revert_step(
  backend: ControlBackend,
  call: ValidatedCall,
) -> #(Outcome, ControlBackend) {
  case lookup_controller(backend, call) {
    Error(error) -> #(Refused(error), backend)
    Ok(#(controller, entry)) ->
      case entry {
        DeclaredOnly(_, _) -> #(
          Refused(controller_not_running(controller)),
          backend,
        )
        ObservedInstance(
          _,
          _,
          runtime_healthy,
          constraints_satisfied,
          owner_worker,
          attempt,
          current_stage,
          previous_stage,
        ) as instance ->
          case
            recheck(
              backend,
              call,
              runtime_healthy,
              constraints_satisfied,
              owner_worker,
              attempt,
            )
          {
            Error(error) -> #(Refused(error), backend)
            Ok(_) ->
              case previous_stage {
                None -> #(
                  Refused(ToolError(
                    "NO_PREVIOUS_STAGE",
                    "Controller has no reversible previous stage: "
                      <> controller,
                    NonRetryable,
                  )),
                  backend,
                )
                Some(target_stage) -> {
                  let updated_entry =
                    ObservedInstance(
                      ..instance,
                      current_stage: target_stage,
                      previous_stage: None,
                    )
                  let updated =
                    ControlBackend(
                      ..backend,
                      controllers: dict.insert(
                        backend.controllers,
                        controller,
                        updated_entry,
                      ),
                    )
                  let payload =
                    json.object([
                      #("tool", json.string(call.spec.name)),
                      #("mode", json.string("revert")),
                      #("mutated", json.bool(True)),
                      #("controller", json.string(controller)),
                      #("from_stage", json.string(current_stage)),
                      #("to_stage", json.string(target_stage)),
                    ])
                    |> json.to_string
                  #(complete(updated, call, payload), updated)
                }
              }
          }
      }
  }
}

fn lookup_controller(
  backend: ControlBackend,
  call: ValidatedCall,
) -> Result(#(String, ControllerEntry), ToolError) {
  let controller = arg(call, "controller")
  case dict.get(backend.controllers, controller) {
    Ok(entry) -> Ok(#(controller, entry))
    Error(_) ->
      Error(ToolError(
        "UNKNOWN_CONTROLLER",
        "Controller is not declared in the registry: " <> controller,
        NonRetryable,
      ))
  }
}

fn recheck(
  backend: ControlBackend,
  call: ValidatedCall,
  runtime_healthy: Bool,
  constraints_satisfied: Bool,
  owner_worker: String,
  attempt: Int,
) -> Result(Nil, ToolError) {
  case backend.interlock_armed {
    False -> Error(safety_constraint_violation())
    True ->
      case backend.stpa_hazards_open == 0 {
        False -> Error(safety_constraint_violation())
        True ->
          case runtime_healthy && all_observed_healthy(backend) {
            False -> Error(safety_constraint_violation())
            True ->
              case constraints_satisfied {
                False -> Error(safety_constraint_violation())
                True ->
                  case principal.actor_id(call.principal) == owner_worker {
                    False ->
                      Error(ToolError(
                        "CONTROL_PRINCIPAL_MISMATCH",
                        "Principal does not own the observed controller instance",
                        NonRetryable,
                      ))
                    True ->
                      case call.attempt == Some(attempt) {
                        False ->
                          Error(ToolError(
                            "CONTROL_STALE_ATTEMPT",
                            "Control fencing attempt does not match observed instance",
                            NonRetryable,
                          ))
                        True -> Ok(Nil)
                      }
                  }
              }
          }
      }
  }
}

/// Every observed controller in the backend must be runtime-healthy before any
/// actuation; a single unhealthy observed instance fails the whole backend
/// closed. Declared-only controllers carry no runtime health and are ignored.
fn all_observed_healthy(backend: ControlBackend) -> Bool {
  backend.controllers
  |> dict.to_list
  |> list.all(fn(pair) {
    case pair.1 {
      ObservedInstance(_, _, runtime_healthy, _, _, _, _, _) -> runtime_healthy
      DeclaredOnly(_, _) -> True
    }
  })
}

fn arg(call: ValidatedCall, key: String) -> String {
  case dict.get(call.arguments, key) {
    Ok(value) -> value
    Error(_) -> ""
  }
}

fn complete(
  backend: ControlBackend,
  call: ValidatedCall,
  payload: String,
) -> Outcome {
  evidence.classify_backend_payload(
    call.spec.route,
    call.spec.name,
    payload,
    backend.candidate,
  )
}

fn optional_string(value: Option(String)) -> Json {
  case value {
    Some(text) -> json.string(text)
    None -> json.null()
  }
}

fn is_reversible_stage(action: String) -> Bool {
  list.contains(reversible_stages, action)
}

fn controller_not_running(controller: String) -> ToolError {
  ToolError(
    "CONTROLLER_NOT_RUNNING",
    "Controller is declared but has no observed runtime instance: "
      <> controller,
    NonRetryable,
  )
}

fn safety_constraint_violation() -> ToolError {
  ToolError(
    "SAFETY_CONSTRAINT_VIOLATION",
    "Interlock, open STPA hazards, or controller constraints forbid actuation",
    NonRetryable,
  )
}

fn disallowed_control_intent(
  mode: String,
  action: String,
) -> Result(ControlIntent, ToolError) {
  Error(ToolError(
    "DISALLOWED_CONTROL_INTENT",
    "Control intent is not in the closed allowlist: mode="
      <> mode
      <> " action="
      <> action,
    NonRetryable,
  ))
}
