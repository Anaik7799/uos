//// Stateful MCP successor. A reviewed launcher grant owns identity and scope.
//// All task mutations use canonical Sa-plan through admission/operations.
import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/mcp
import cepaf_gleam/harness/operations as ops
import cepaf_gleam/harness/value
import cepaf_gleam/planning/sa_plan_bridge as sa
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type State {
  State(grant: a.Grant, initialized: Bool, closed: Bool,
    execution: Option(a.Execution), unresolved: Bool)
}
@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil
pub fn initial(grant: a.Grant) -> State { State(grant, False, False, None, False) }
pub fn main() {
  case a.load() {
    Ok(grant) -> mcp.serve(initial(grant), fn(state, line) {
      let #(next, reply) = handle(state, line)
      #(next, reply, next.closed)
    })
    Error(reason) -> { io.println_error("successor grant refused: " <> reason) halt(1) }
  }
}
fn response(id: json.Json, body: json.Json) -> String {
  json.object([#("jsonrpc", json.string("2.0")), #("id", id), #("result", body)]) |> json.to_string
}
fn error(id: json.Json, code: Int, reason: String) -> String {
  json.object([#("jsonrpc", json.string("2.0")), #("id", id),
    #("error", json.object([#("code", json.int(code)), #("message", json.string(reason))]))]) |> json.to_string
}
fn tool_result(id: json.Json, outcome: Result(json.Json, String)) -> String {
  let #(failed, text) = case outcome { Ok(body) -> #(False, json.to_string(body)) Error(e) -> #(True, e) }
  response(id, json.object([#("isError", json.bool(failed)),
    #("content", json.array([json.object([#("type", json.string("text")), #("text", json.string(text))])], fn(x) { x }))]))
}
fn schema(name: String) -> json.Json {
  let fields = ops.fields(name)
  json.object([#("name", json.string(name)), #("description", json.string("Task-scoped Gleam development service: " <> name)),
    #("inputSchema", json.object([#("type", json.string("object")),
      #("properties", json.object(list.map(fields, fn(key) { #(key, json.object([#("type", json.string("string"))])) }))),
      #("required", json.array(fields, json.string)), #("additionalProperties", json.bool(False))]))])
}
pub fn handle(state: State, line: String) -> #(State, Option(String)) {
  let decoder = {
    use rpc <- decode.field("jsonrpc", decode.string)
    use method <- decode.field("method", decode.string)
    use id <- decode.optional_field("id", None, decode.map(decode.one_of(decode.map(decode.string, json.string),
      [decode.map(decode.int, json.int)]), Some))
    decode.success(#(rpc, method, id))
  }
  case string.byte_size(line) <= mcp.frame_limit, json.parse(line, decoder) {
    False, _ -> #(state, Some(error(json.null(), -32_600, "frame_bound")))
    _, Error(_) -> #(state, Some(error(json.null(), -32_600, "invalid_request")))
    True, Ok(#("2.0", _, None)) -> #(state, None)
    True, Ok(#("2.0", method, Some(id))) -> {
      case state.closed, method {
        True, _ -> #(state, Some(error(id, -32_002, "session_closed")))
        _, "initialize" -> case state.initialized {
          True -> #(state, Some(error(id, -32_002, "already_initialized")))
          False -> {
            let body = json.object([
              #("protocolVersion", json.string("2024-11-05")),
              #("capabilities", json.object([#("tools", json.object([]))])),
              #("serverInfo", json.object([
                #("name", json.string("uos-gleam-successor-harness")),
                #("version", json.string("0.2.0")),
              ])),
            ])
            #(State(..state, initialized: True), Some(response(id, body)))
          }
        }
        _, _ if !state.initialized -> #(state, Some(error(id, -32_002, "initialize_required")))
        _, "ping" -> #(state, Some(response(id, json.object([]))))
        _, "shutdown" -> #(State(..state, closed: True), Some(response(id, json.object([]))))
        _, "tools/list" -> #(state, Some(response(id, json.object([#("tools", json.array(ops.names, schema))]))))
        _, "tools/call" -> {
          let call_decoder = {
            use name <- decode.subfield(["params", "name"], decode.string)
            use args <- decode.subfield(["params", "arguments"], value.decoder())
            decode.success(#(name, args))
          }
          case json.parse(line, call_decoder) {
            Error(_) -> #(state, Some(error(id, -32_602, "tool_arguments")))
            Ok(#(name, args)) -> {
              let #(next, outcome) = call(state, name, args)
              #(next, Some(tool_result(id, outcome)))
            }
          }
        }
        _, _ -> #(state, Some(error(id, -32_601, "unknown_method")))
      }
    }
    _, _ -> #(state, Some(error(json.null(), -32_600, "jsonrpc_version")))
  }
}
fn status(state: State) -> Result(json.Json, String) {
  use _ <- result.try(a.check(state.grant))
  let plans = list.unique(list.map(state.grant.scopes, fn(s) { s.plan }))
  use observations <- result.try(list.try_map(plans, fn(plan) {
    use raw <- result.try(sa.run_sa_plan_cli(["task", "list", plan, "--format", "json"]))
    Ok(json.object([#("plan", json.string(plan)), #("canonical_cli_jsonl", json.string(raw))]))
  }))
  let active = case state.execution { Some(e) -> a.observe_execution(e) None -> json.null() }
  Ok(json.object([#("grant_id", json.string(state.grant.id)), #("active", active),
    #("unresolved_operation", json.bool(state.unresolved)), #("plans", json.array(observations, fn(x) { x })),
    #("scope", json.string("local_development_only")), #("all_features_complete", json.bool(False)),
    #("system_admission", json.bool(False)), #("paid_model_requests", json.int(0))]))
}
pub fn call(state: State, name: String, args: value.Value) -> #(State, Result(json.Json, String)) {
  case ops.validate_args(name, args) {
    Error(e) -> #(state, Error(e))
    Ok(_) -> dispatch(state, name, args)
  }
}
fn dispatch(state: State, name: String, args: value.Value) -> #(State, Result(json.Json, String)) {
  case name {
    "harness_status" -> #(state, status(state))
    "harness_clock" -> #(state, a.check(state.grant) |> result.map(clock.to_json))
    "harness_reconcile" -> {
      let outcome = {
        use intent <- result.try(ops.text(args, "intent_id"))
        case state.execution {
          Some(execution) -> ops.reconcile(execution, intent)
          None -> ops.recover(state.grant, intent)
        }
      }
      case outcome {
        Ok(receipt) -> #(State(..state, execution: None, unresolved: False), Ok(receipt))
        Error(e) -> #(State(..state, unresolved: state.unresolved || a.outcome_unknown(e)), Error(e))
      }
    }
    "harness_heartbeat" -> {
      let outcome = {
        use heartbeat <- result.try(a.heartbeat(state.grant))
        case state.execution {
          None -> Ok(heartbeat)
          Some(e) -> {
            use proof <- result.try(a.fence(e, 0))
            use raw <- result.try(a.coordinate(["renew", e.binding.session, dev.task_resource(e.binding),
              int_string(e.binding.epoch), "3600", "successor-renew-" <> int_string(proof.clock.sample.observed.utc_us)]))
            Ok(json.object([#("heartbeat", heartbeat), #("coordinator_renewal", json.string(raw)),
              #("sa_plan_lease_until_ns", json.string(int_string(proof.lease_until_ns))),
              #("sa_plan_renewal", json.string("NOT_IMPLEMENTED_RELEASE_AND_RECLAIM_BEFORE_EXPIRY"))]))
          }
        }
      }
      #(state, outcome)
    }
    "harness_claim" | "harness_attach" -> {
      case state.execution, state.unresolved && name == "harness_claim" {
        Some(_), _ -> #(state, Error("release_or_complete_current_task_first"))
        _, True -> #(state, Error("claim_outcome_requires_explicit_attach_reconciliation"))
        None, False -> {
          let selected = {
            use plan <- result.try(ops.text(args, "plan"))
            use task <- result.try(ops.text(args, "task"))
            use intent <- result.try(ops.text(args, "intent_id"))
            use scope <- result.try(a.lookup(state.grant, plan, task))
            case name { "harness_claim" -> a.claim(state.grant, scope, intent) _ -> a.attach(state.grant, scope, intent) }
          }
          case selected {
            Ok(execution) -> #(State(..state, execution: Some(execution), unresolved: False), Ok(a.observe_execution(execution)))
            Error(e) -> #(State(..state, unresolved: state.unresolved || a.outcome_unknown(e)), Error(e))
          }
        }
      }
    }
    _ -> case state.execution {
      None -> #(state, Error("current_task_required"))
      Some(execution) -> active_call(state, execution, name, args)
    }
  }
}
@external(erlang, "erlang", "integer_to_binary")
fn int_string(n: Int) -> String
fn active_call(state: State, execution: a.Execution, name: String, args: value.Value) -> #(State, Result(json.Json, String)) {
  case name {
    "harness_read_file" -> #(state, ops.text(args, "path") |> result.try(ops.read_file(execution, _)))
    "harness_assess" -> case ops.assess(execution, args) {
      Ok(next) -> #(State(..state, execution: Some(next)), Ok(a.observe_execution(next)))
      Error(e) -> #(state, Error(e))
    }
    "harness_release" -> {
      let outcome = ops.text(args, "intent_id") |> result.try(ops.release(execution, _))
      case outcome {
        Ok(receipt) -> #(State(..state, execution: None, unresolved: False), Ok(receipt))
        Error(e) -> #(State(..state, unresolved: state.unresolved || a.outcome_unknown(e)), Error(e))
      }
    }
    "harness_finish" if state.unresolved -> #(state, Error("unresolved_operation_stop_line"))
    "harness_finish" -> case ops.finish(execution, args) {
      Ok(receipt) -> #(State(..state, execution: None, unresolved: False), Ok(receipt))
      Error(e) -> #(State(..state, unresolved: state.unresolved || a.outcome_unknown(e)), Error(e))
    }
    "harness_write_file" | "harness_build" | "harness_test" ->
      case state.unresolved {
        True -> #(state, Error("unresolved_operation_stop_line"))
        False -> {
          let outcome = ops.effect(execution, name, args)
          case outcome {
            Error(e) -> #(State(..state, unresolved: state.unresolved || a.outcome_unknown(e)), outcome)
            Ok(_) -> #(state, outcome)
          }
        }
      }
    _ -> #(state, Error("unknown_tool"))
  }
}
