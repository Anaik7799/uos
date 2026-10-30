//// T12 Analysis & Inference Adapter (9 tools). Every output is advisory/veto
//// only and never grants control authority. Model-backed forecasts never
//// fabricate a synthetic prediction when the Max daemon is unavailable, and
//// generated plot specs are declarative data only and never execute code.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolError, Complete, EvidenceRecord, NonRetryable, Refused,
  Retryable, ToolError,
}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type InferenceBackend {
  MaxDaemonOffline(reason: String)
  MaxDaemonReady(model_id: String, predictions: Dict(String, String))
}

pub const analysis_tools = [
  "forecast_predict",
  "stpa_fmea_hazard",
  "rete_rule_conflict",
  "ruliad_branch_eval",
  "shruti_harmonics",
  "ast_anomaly_detect",
  "lyapunov_trend_predict",
  "sciviz_extension_deep_dive",
  "ggram_synthesize",
]

pub const denied_nvme_serial = "25503L801736"

pub const sql_markers = [
  "select ",
  "insert ",
  "update ",
  "delete ",
  "drop ",
  "union ",
  ";--",
  "' or ",
]

pub const forbidden_plot_tokens = [
  "<script",
  "eval(",
  "function(",
  "os.cmd",
  "system.",
  "`",
  "javascript:",
  "onerror=",
  "onload=",
  "import(",
  "require(",
  "${",
  "\u{0000}",
]

pub fn is_analysis_tool(tool_name: String) -> Bool {
  list.contains(analysis_tools, tool_name)
}

pub fn execute(
  tool_name: String,
  args: Dict(String, String),
  backend: InferenceBackend,
) -> Outcome {
  case control_authority_requested(args) {
    True ->
      Refused(ToolError(
        code: "INFERENCE_CANNOT_AUTHORIZE_CONTROL",
        reason: "Analysis and inference outputs are advisory/veto only and never grant control authority",
        retryability: NonRetryable,
      ))
    False ->
      case tool_name {
        "forecast_predict" -> forecast_predict(args, backend)
        "stpa_fmea_hazard" -> stpa_fmea_hazard(args)
        "rete_rule_conflict" -> rete_rule_conflict(args)
        "ruliad_branch_eval" -> ruliad_branch_eval(args)
        "shruti_harmonics" -> shruti_harmonics(args)
        "ast_anomaly_detect" -> ast_anomaly_detect(args)
        "lyapunov_trend_predict" -> lyapunov_trend_predict(args)
        "sciviz_extension_deep_dive" | "ggram_synthesize" ->
          declarative_plot_spec(tool_name, args)
        _ ->
          Refused(ToolError(
            code: "UNSUPPORTED_ANALYSIS_TOOL",
            reason: "Unsupported tool in analysis adapter: " <> tool_name,
            retryability: NonRetryable,
          ))
      }
  }
}

/// Analysis never grants control authority: an explicit request to authorize
/// control or execute an effect is refused fail-closed before dispatch.
pub fn control_authority_requested(args: Dict(String, String)) -> Bool {
  let authority_keys = [
    "authorize_control",
    "execute_effect",
    "grant_control",
    "effect_authority",
    "actuate",
  ]
  let granting_values = ["true", "1", "yes"]
  list.any(authority_keys, fn(key) {
    case dict.get(args, key) {
      Ok(value) ->
        list.contains(granting_values, string.lowercase(string.trim(value)))
      Error(_) -> False
    }
  })
}

fn emit(
  tool_name: String,
  candidate: String,
  extra: List(#(String, json.Json)),
) -> Outcome {
  let base = [
    #("tool", json.string(tool_name)),
    #("advisory_only", json.bool(True)),
    #("effect_authority", json.bool(False)),
  ]
  let payload = json.object(list.append(base, extra)) |> json.to_string
  Complete(
    payload,
    EvidenceRecord(
      candidate: candidate,
      route: "public",
      tool: tool_name,
      declaration_state: "declared",
      implementation_state: "implemented",
      execution_state: "observed",
      formal_state: "unrun",
      admission_state: "not_admitted",
      output_sha256: files.digest(payload),
    ),
  )
}

fn invalid_input(reason: String) -> ToolError {
  ToolError(
    code: "INVALID_ANALYSIS_INPUT",
    reason: reason,
    retryability: NonRetryable,
  )
}

fn get_int(args: Dict(String, String), key: String) -> Result(Int, ToolError) {
  case dict.get(args, key) {
    Ok(raw) ->
      case int.parse(string.trim(raw)) {
        Ok(value) -> Ok(value)
        Error(_) ->
          Error(invalid_input(key <> " must be an integer, got: " <> raw))
      }
    Error(_) ->
      Error(invalid_input("missing required integer argument: " <> key))
  }
}

pub fn parse_int_csv(raw: String) -> Result(List(Int), ToolError) {
  parse_int_parts(string.split(raw, ","), [])
}

fn parse_int_parts(
  parts: List(String),
  acc: List(Int),
) -> Result(List(Int), ToolError) {
  case parts {
    [] -> Ok(list.reverse(acc))
    [part, ..rest] ->
      case int.parse(string.trim(part)) {
        Ok(value) -> parse_int_parts(rest, [value, ..acc])
        Error(_) ->
          Error(invalid_input("expected an integer list, got token: " <> part))
      }
  }
}

pub fn parse_float_csv(raw: String) -> Result(List(Float), ToolError) {
  parse_float_parts(string.split(raw, ","), [])
}

fn parse_float_parts(
  parts: List(String),
  acc: List(Float),
) -> Result(List(Float), ToolError) {
  case parts {
    [] -> Ok(list.reverse(acc))
    [part, ..rest] ->
      case float.parse(string.trim(part)) {
        Ok(value) -> parse_float_parts(rest, [value, ..acc])
        Error(_) ->
          Error(invalid_input("expected a numeric list, got token: " <> part))
      }
  }
}

fn forecast_predict(
  args: Dict(String, String),
  backend: InferenceBackend,
) -> Outcome {
  let source = result.unwrap(dict.get(args, "source"), "max_model")
  case source == "max_model" {
    True -> model_predict(args, backend)
    False -> reference_forecast(args, source)
  }
}

fn series_key(args: Dict(String, String)) -> String {
  case dict.get(args, "series_key") {
    Ok(key) -> key
    Error(_) -> result.unwrap(dict.get(args, "series"), "series")
  }
}

fn model_predict(
  args: Dict(String, String),
  backend: InferenceBackend,
) -> Outcome {
  let key = series_key(args)
  case backend {
    MaxDaemonOffline(reason) ->
      Refused(ToolError(
        code: "INFERENCE_MODEL_UNAVAILABLE",
        reason: reason,
        retryability: Retryable,
      ))
    MaxDaemonReady(model_id: model_id, predictions: predictions) ->
      case dict.get(predictions, key) {
        Ok(prediction) ->
          emit("forecast_predict", "uos-mcp", [
            #("source", json.string("max_model")),
            #("model_id", json.string(model_id)),
            #("series_key", json.string(key)),
            #("prediction", json.string(prediction)),
            #("epistemic_class", json.string("model_backed")),
          ])
        Error(_) ->
          Refused(ToolError(
            code: "INFERENCE_SERIES_MISSING",
            reason: "Model "
              <> model_id
              <> " has no prediction for series key "
              <> key,
            retryability: NonRetryable,
          ))
      }
  }
}

fn reference_forecast(args: Dict(String, String), source: String) -> Outcome {
  case dict.get(args, "series") {
    Error(_) ->
      Refused(invalid_input("reference forecast requires a numeric series"))
    Ok(raw) ->
      case parse_float_csv(raw) {
        Error(error) -> Refused(error)
        Ok(values) ->
          case list.length(values) >= 2 {
            False ->
              Refused(invalid_input(
                "reference forecast requires at least two points",
              ))
            True -> {
              let first = list.first(values) |> result.unwrap(0.0)
              let last = list.last(values) |> result.unwrap(0.0)
              emit("forecast_predict", "uos-mcp", [
                #("source", json.string(source)),
                #("epistemic_class", json.string("deterministic_kernel")),
                #("drift", json.float(last -. first)),
                #("point_count", json.int(list.length(values))),
              ])
            }
          }
      }
  }
}

fn stpa_fmea_hazard(args: Dict(String, String)) -> Outcome {
  case
    get_int(args, "severity"),
    get_int(args, "occurrence"),
    get_int(args, "detection")
  {
    Ok(severity), Ok(occurrence), Ok(detection) ->
      emit("stpa_fmea_hazard", "uos-mcp", [
        #("epistemic_class", json.string("deterministic_kernel")),
        #("severity", json.int(severity)),
        #("occurrence", json.int(occurrence)),
        #("detection", json.int(detection)),
        #("rpn", json.int(severity * occurrence * detection)),
      ])
    _, _, _ ->
      Refused(invalid_input(
        "stpa_fmea_hazard requires integer severity, occurrence and detection",
      ))
  }
}

fn rete_rule_conflict(args: Dict(String, String)) -> Outcome {
  case dict.get(args, "rules") {
    Error(_) ->
      Refused(invalid_input("rete_rule_conflict requires a rules argument"))
    Ok(raw) ->
      case detect_conflicts(raw) {
        Error(error) -> Refused(error)
        Ok(conflicts) ->
          emit("rete_rule_conflict", "uos-mcp", [
            #(
              "matcher_kind",
              json.string("naive_forward_conflict_scan_not_full_rete_ul"),
            ),
            #("epistemic_class", json.string("deterministic_kernel")),
            #("conflict_count", json.int(list.length(conflicts))),
            #("conflicts", json.array(conflicts, json.string)),
          ])
      }
  }
}

pub fn detect_conflicts(raw: String) -> Result(List(String), ToolError) {
  scan_rules(string.split(string.replace(raw, ",", ";"), ";"), dict.new(), [])
}

fn scan_rules(
  parts: List(String),
  seen: Dict(String, String),
  conflicts: List(String),
) -> Result(List(String), ToolError) {
  case parts {
    [] -> Ok(list.reverse(conflicts))
    [part, ..rest] -> {
      let trimmed = string.trim(part)
      case trimmed {
        "" -> scan_rules(rest, seen, conflicts)
        _ ->
          case string.split(trimmed, ":") {
            [condition, action] -> {
              let key = string.trim(condition)
              let value = string.trim(action)
              case dict.get(seen, key) {
                Ok(previous) ->
                  case previous == value {
                    True -> scan_rules(rest, seen, conflicts)
                    False -> scan_rules(rest, seen, [key, ..conflicts])
                  }
                Error(_) ->
                  scan_rules(rest, dict.insert(seen, key, value), conflicts)
              }
            }
            _ ->
              Error(invalid_input(
                "rule must be 'condition:action', got: " <> trimmed,
              ))
          }
      }
    }
  }
}

fn ruliad_branch_eval(args: Dict(String, String)) -> Outcome {
  case dict.get(args, "branches") {
    Error(_) ->
      Refused(invalid_input(
        "ruliad_branch_eval requires comma separated branch weights",
      ))
    Ok(raw) ->
      case parse_int_csv(raw) {
        Error(error) -> Refused(error)
        Ok(branches) ->
          case list.reduce(branches, int.max) {
            Error(_) ->
              Refused(invalid_input(
                "ruliad_branch_eval requires at least one branch weight",
              ))
            Ok(branch_max) ->
              emit("ruliad_branch_eval", "uos-mcp", [
                #("epistemic_class", json.string("deterministic_kernel")),
                #("branch_count", json.int(list.length(branches))),
                #("branch_sum", json.int(list.fold(branches, 0, int.add))),
                #("branch_max", json.int(branch_max)),
              ])
          }
      }
  }
}

fn shruti_harmonics(args: Dict(String, String)) -> Outcome {
  case dict.get(args, "frequencies") {
    Error(_) ->
      Refused(invalid_input(
        "shruti_harmonics requires comma separated integer frequencies",
      ))
    Ok(raw) ->
      case parse_int_csv(raw) {
        Error(error) -> Refused(error)
        Ok(frequencies) ->
          case list.reduce(frequencies, int.min) {
            Error(_) ->
              Refused(invalid_input(
                "shruti_harmonics requires at least one frequency",
              ))
            Ok(fundamental) -> {
              let doubled = list.map(frequencies, fn(f) { f * 2 })
              emit("shruti_harmonics", "uos-mcp", [
                #("epistemic_class", json.string("deterministic_kernel")),
                #("harmonic_count", json.int(list.length(frequencies))),
                #("fundamental", json.int(fundamental)),
                #("harmonics", json.array(doubled, json.int)),
              ])
            }
          }
      }
  }
}

fn ast_anomaly_detect(args: Dict(String, String)) -> Outcome {
  let raw =
    result.unwrap(
      dict.get(args, "source"),
      result.unwrap(dict.get(args, "sample"), ""),
    )
  case trap_reason(raw) {
    Some(reason) -> Refused(invalid_input(reason))
    None ->
      case dict.get(args, "samples") {
        Error(_) ->
          emit("ast_anomaly_detect", "uos-mcp", [
            #("epistemic_class", json.string("deterministic_kernel")),
            #("sample_count", json.int(0)),
            #("anomalies", json.int(0)),
          ])
        Ok(samples_raw) ->
          case parse_int_csv(samples_raw) {
            Error(error) -> Refused(error)
            Ok(samples) ->
              emit("ast_anomaly_detect", "uos-mcp", [
                #("epistemic_class", json.string("deterministic_kernel")),
                #("sample_count", json.int(list.length(samples))),
                #("anomalies", json.int(list.count(samples, fn(s) { s < 0 }))),
              ])
          }
      }
  }
}

pub fn trap_reason(raw: String) -> Option(String) {
  let normalized =
    raw
    |> string.replace("\t", " ")
    |> string.replace("\n", " ")
    |> string.replace("\r", " ")
    |> string.replace("/**/", " ")
    |> string.lowercase
  case string.contains(raw, "\u{0000}") {
    True -> Some("raw NUL byte in analysis input is forbidden")
    False ->
      case string.contains(raw, denied_nvme_serial) {
        True -> Some("denied NVMe serial is forbidden in analysis input")
        False ->
          case
            list.find(sql_markers, fn(marker) {
              string.contains(normalized, marker)
            })
          {
            Ok(marker) ->
              Some(
                "raw SQL fragment is forbidden in analysis input: " <> marker,
              )
            Error(_) -> None
          }
      }
  }
}

fn lyapunov_trend_predict(args: Dict(String, String)) -> Outcome {
  case dict.get(args, "series") {
    Error(_) ->
      Refused(invalid_input(
        "lyapunov_trend_predict requires a numeric comma separated series",
      ))
    Ok(raw) ->
      case parse_float_csv(raw) {
        Error(error) -> Refused(error)
        Ok(values) ->
          case list.length(values) >= 2 {
            False ->
              Refused(invalid_input(
                "lyapunov_trend_predict requires at least two points",
              ))
            True -> {
              let first = list.first(values) |> result.unwrap(0.0)
              let last = list.last(values) |> result.unwrap(0.0)
              emit("lyapunov_trend_predict", "uos-mcp", [
                #("epistemic_class", json.string("deterministic_kernel")),
                #("point_count", json.int(list.length(values))),
                #("drift", json.float(last -. first)),
              ])
            }
          }
      }
  }
}

fn declarative_plot_spec(
  tool_name: String,
  args: Dict(String, String),
) -> Outcome {
  case forbidden_plot_token(args) {
    Some(_) ->
      Refused(ToolError(
        code: "EXECUTABLE_PLOT_CODE_FORBIDDEN",
        reason: "Generated plot specs are declarative data only and never execute code",
        retryability: NonRetryable,
      ))
    None ->
      emit(tool_name, "uos-mcp", [
        #("spec_kind", json.string("grammar_of_graphics")),
        #("declarative_only", json.bool(True)),
        #("code_executed", json.bool(False)),
        #("mark", json.string(result.unwrap(dict.get(args, "mark"), "point"))),
        #("x", json.string(result.unwrap(dict.get(args, "x"), "x"))),
        #("y", json.string(result.unwrap(dict.get(args, "y"), "y"))),
        #("layers", json.array([], json.string)),
      ])
  }
}

pub fn forbidden_plot_token(args: Dict(String, String)) -> Option(String) {
  option.from_result(list.find_map(dict.values(args), find_token))
}

fn find_token(value: String) -> Result(String, Nil) {
  let lowered = string.lowercase(value)
  case
    list.find(forbidden_plot_tokens, fn(token) {
      string.contains(lowered, token)
    })
  {
    Ok(token) -> Ok(token)
    Error(_) -> Error(Nil)
  }
}
