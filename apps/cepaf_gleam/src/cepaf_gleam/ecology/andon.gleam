//// Shared backend Jidoka state. These gates grant no task or effect authority.
//// Each runtime starts stopped. Only a valid actual probe can make it ready.

import cepaf_gleam/ecology/capability_port.{
  type Outcome, Engaged, Masked, Unavailable,
}
import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Phase {
  Ready
  Stopped
  Recovering
}

pub type Receipt {
  Receipt(
    sequence: Int,
    cycle: Int,
    observed_at_us: Int,
    holon_id: String,
    outcome: Outcome,
  )
}

pub type Service {
  Service(
    capability: String,
    phase: Phase,
    reason: String,
    failure_count: Int,
    recovery_attempts: Int,
    recovery_count: Int,
    last_failure: Option(Receipt),
    last_recovery: Option(Receipt),
  )
}

pub fn initial() -> List(Service) {
  list.map(["modular_max", "openrouter_free"], fn(capability) {
    Service(
      capability,
      Stopped,
      "startup_recovery_required",
      0,
      0,
      0,
      None,
      None,
    )
  })
}

pub fn shared(capability: String) -> Bool {
  capability == "modular_max" || capability == "openrouter_free"
}

pub fn phase_label(phase: Phase) -> String {
  case phase {
    Ready -> "ready"
    Stopped -> "stopped"
    Recovering -> "recovering"
  }
}

pub fn find(
  services: List(Service),
  capability: String,
) -> Result(Service, Nil) {
  list.find(services, fn(service) { service.capability == capability })
}

pub fn admission(
  services: List(Service),
  capability: String,
) -> Result(Nil, String) {
  case find(services, capability) {
    Ok(Service(phase: Ready, ..)) -> Ok(Nil)
    Ok(service) ->
      Error("andon_" <> phase_label(service.phase) <> ": " <> service.reason)
    Error(_) ->
      case shared(capability) {
        True -> Error("andon_stopped: missing_service_gate")
        False -> Ok(Nil)
      }
  }
}

pub fn begin_recovery(
  services: List(Service),
  capability: String,
) -> Result(List(Service), String) {
  case find(services, capability) {
    Error(_) -> Error("recovery_not_shared_service")
    Ok(Service(phase: Ready, ..)) -> Error("recovery_service_not_stopped")
    Ok(Service(phase: Recovering, ..)) -> Error("recovery_already_in_progress")
    Ok(_) ->
      Ok(
        list.map(services, fn(service) {
          case service.capability == capability {
            False -> service
            True ->
              Service(
                ..service,
                phase: Recovering,
                recovery_attempts: service.recovery_attempts + 1,
              )
          }
        }),
      )
  }
}

/// Caller and scheduling rejection cannot turn a ready shared backend off.
/// Explicit malformed backend receipts precede generic invalid-input prefixes.
pub fn serious_failure(reason: String) -> Bool {
  case reason {
    "invalid_max_response"
    | "invalid_engaged_backend_receipt"
    | "backend_outcome_mismatch" -> True
    _ ->
      !list.any(
        [
          "invalid_", "invalid_request:", "advisory_input_or_token_bound",
          "prompt refused", "max_input_bound", "input_limit_exceeded",
          "input exceeds ", "capability_worker_busy", "holon_not_found",
          "andon_", "recovery_",
        ],
        fn(prefix) { string.starts_with(reason, prefix) },
      )
  }
}

/// Production external ports wrap their parsed backend receipt in this field.
/// A forged/null/empty Engaged constructor is not a recovery observation.
pub fn checked_outcome(capability: String, outcome: Outcome) -> Outcome {
  let actual = case outcome {
    Engaged(name, _, _, _) | Unavailable(name, _) | Masked(name) -> name
  }
  case actual != capability {
    True -> Unavailable(capability, "backend_outcome_mismatch")
    False ->
      case outcome, shared(capability) {
        Engaged(_, backend, evidence, detail), True -> {
          let expected = case capability {
            "modular_max" -> "supervised_max_daemon"
            _ -> "openrouter_free_policy_client"
          }
          let decoder = {
            use body <- decode.field("backend_result_json", decode.string)
            decode.success(body)
          }
          let receipt = json.parse(json.to_string(detail), decoder)
          let valid = case receipt {
            Ok(body) ->
              case string.byte_size(body) <= 1_048_576 {
                True ->
                  case
                    json.parse(body, decode.dict(decode.string, decode.dynamic))
                  {
                    Ok(object) -> dict.size(object) > 0
                    _ -> False
                  }
                False -> False
              }
            _ -> False
          }
          case backend == expected && evidence != "" && valid {
            True -> outcome
            False -> Unavailable(capability, "invalid_engaged_backend_receipt")
          }
        }
        _, _ -> outcome
      }
  }
}

pub fn finish(
  services: List(Service),
  capability: String,
  recovery: Bool,
  receipt: Receipt,
) -> List(Service) {
  list.map(services, fn(service) {
    case
      service.capability != capability
      || { recovery && service.phase != Recovering }
    {
      True -> service
      False ->
        case recovery, receipt.outcome {
          True, Engaged(..) ->
            Service(
              ..service,
              phase: Ready,
              reason: "",
              recovery_count: service.recovery_count + 1,
              last_recovery: Some(receipt),
            )
          True, Unavailable(_, reason) ->
            Service(
              ..service,
              phase: Stopped,
              reason: reason,
              last_recovery: Some(receipt),
              failure_count: service.failure_count
                + case serious_failure(reason) {
                  True -> 1
                  False -> 0
                },
              last_failure: case serious_failure(reason) {
                True -> Some(receipt)
                False -> service.last_failure
              },
            )
          True, Masked(_) ->
            Service(
              ..service,
              phase: Stopped,
              reason: "recovery_masked",
              last_recovery: Some(receipt),
            )
          False, Unavailable(_, reason) ->
            case serious_failure(reason) {
              True ->
                Service(
                  ..service,
                  phase: Stopped,
                  reason: reason,
                  failure_count: service.failure_count + 1,
                  last_failure: Some(receipt),
                )
              False -> service
            }
          False, _ -> service
        }
    }
  })
}

fn receipt_json(receipt: Option(Receipt)) -> Json {
  case receipt {
    None -> json.null()
    Some(r) ->
      json.object([
        #("sequence", json.int(r.sequence)),
        #("cycle", json.int(r.cycle)),
        #("observed_at_us", json.int(r.observed_at_us)),
        #("holon_id", json.string(r.holon_id)),
        #("outcome", capability_port.outcome_to_json(r.outcome)),
      ])
  }
}

pub fn to_json(service: Service) -> Json {
  json.object([
    #("capability", json.string(service.capability)),
    #("phase", json.string(phase_label(service.phase))),
    #("reason", json.string(service.reason)),
    #("failure_count", json.int(service.failure_count)),
    #("recovery_attempts", json.int(service.recovery_attempts)),
    #("recovery_count", json.int(service.recovery_count)),
    #("last_failure", receipt_json(service.last_failure)),
    #("last_recovery", receipt_json(service.last_recovery)),
    #(
      "scope",
      json.string(
        "all participant models in this ecology actor; recovery required after every restart",
      ),
    ),
  ])
}

pub fn summary(services: List(Service)) -> String {
  list.map(services, fn(service) {
    service.capability
    <> ": "
    <> phase_label(service.phase)
    <> case service.reason {
      "" -> ""
      reason -> " — " <> reason
    }
  })
  |> string.join("\n")
}
