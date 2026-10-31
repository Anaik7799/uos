//// T12 Analysis & Inference Adapter (9 tools). Every output is advisory/veto
//// only and never grants control authority. Model-backed forecasts never
//// fabricate a synthetic prediction when the Max daemon is unavailable, and
//// generated plot specs are declarative data only and never execute code.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolError, Complete, EvidenceRecord, NonRetryable, Refused,
  Retryable, ToolError,
}
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
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
  "system(",
  "os.execute",
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
      case parse_numeric(string.trim(part)) {
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
  case dict.get(args, "layer"), dict.get(args, "source"), backend {
    Ok(layer), source, MaxDaemonOffline(_) if source != Ok("max_model") -> {
      case string.trim(layer), optional_float(args, "horizon_seconds", 60.0) {
        "", _ -> Refused(invalid_input("layer must not be empty"))
        _, Error(error) -> Refused(error)
        _, Ok(horizon) if horizon <. 0.0 ->
          Refused(invalid_input("horizon_seconds must be nonnegative"))
        _, Ok(horizon) ->
          emit("forecast_predict", candidate_id.current(), [
            #(
              "epistemic_class",
              json.string("deterministic_kinematic_fallback"),
            ),
            #("max_daemon_status", json.string("offline")),
            #("layer", json.string(layer)),
            #("horizon_seconds", json.float(horizon)),
            #("model_prediction_available", json.bool(False)),
            #(
              "projection_basis",
              json.string("no_telemetry_no_model_prediction"),
            ),
          ])
      }
    }
    _, _, _ -> {
      let source = result.unwrap(dict.get(args, "source"), "max_model")
      case source == "max_model" {
        True -> model_predict(args, backend)
        False -> reference_forecast(args, source)
      }
    }
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
          emit("forecast_predict", candidate_id.current(), [
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
              emit("forecast_predict", candidate_id.current(), [
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
  case dict.has_key(args, "severity") {
    True -> legacy_stpa_fmea_hazard(args)
    False -> schema_stpa_fmea_hazard(args)
  }
}

fn schema_stpa_fmea_hazard(args: Dict(String, String)) -> Outcome {
  let action = result.unwrap(dict.get(args, "action"), "") |> string.trim
  case
    action,
    optional_float(args, "criticality", 3.0),
    optional_float(args, "impact", 3.0)
  {
    "", _, _ ->
      Refused(invalid_input("stpa_fmea_hazard requires a nonempty action"))
    _, Ok(criticality), Ok(impact) -> {
      let severity =
        int.clamp(
          float.ceiling(float.max(criticality, impact) *. 2.0) |> float.truncate,
          1,
          10,
        )
      let context = result.unwrap(dict.get(args, "context"), "")
      let dependency =
        result.unwrap(dict.get(args, "dependency_readiness"), "ready")
        |> string.lowercase
      let occurrence = case dependency {
        "blocked" | "unknown" -> 8
        _ ->
          case string.trim(context) == "" {
            True -> 3
            False -> 5
          }
      }
      let detection = 5
      emit("stpa_fmea_hazard", candidate_id.current(), [
        #("epistemic_class", json.string("deterministic_kernel")),
        #("action", json.string(action)),
        #(
          "component",
          json.string(result.unwrap(dict.get(args, "component"), "unspecified")),
        ),
        #("context", json.string(context)),
        #("severity", json.int(severity)),
        #("occurrence", json.int(occurrence)),
        #("detection", json.int(detection)),
        #("rpn", json.int(severity * occurrence * detection)),
        #(
          "rating_basis",
          json.string(
            "bounded_heuristic_from_declared_inputs_not_measured_failure_probability",
          ),
        ),
        #(
          "uca_categories",
          json.array(
            [
              "not_provided",
              "provided_unsafe",
              "wrong_timing_order",
              "stopped_too_soon_applied_too_long",
            ],
            json.string,
          ),
        ),
      ])
    }
    _, _, _ ->
      Refused(invalid_input(
        "criticality and impact must be numeric when provided",
      ))
  }
}

fn legacy_stpa_fmea_hazard(args: Dict(String, String)) -> Outcome {
  case
    get_int(args, "severity"),
    get_int(args, "occurrence"),
    get_int(args, "detection")
  {
    Ok(severity), Ok(occurrence), Ok(detection) ->
      emit("stpa_fmea_hazard", candidate_id.current(), [
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
      case string.starts_with(string.trim(raw), "[") {
        True -> json_rule_conflicts(raw)
        False ->
          case detect_conflicts(raw) {
            Error(error) -> Refused(error)
            Ok(conflicts) ->
              emit("rete_rule_conflict", candidate_id.current(), [
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
}

pub fn detect_conflicts(raw: String) -> Result(List(String), ToolError) {
  scan_rules(
    string.split(
      raw |> string.replace("->", ":") |> string.replace(",", ";"),
      ";",
    ),
    dict.new(),
    [],
  )
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
    Error(_) -> schema_branch_eval(args)
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
              emit("ruliad_branch_eval", candidate_id.current(), [
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
    Error(_) -> schema_harmonics(args)
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
              emit("shruti_harmonics", candidate_id.current(), [
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
  let trapped =
    dict.to_list(args)
    |> list.find_map(fn(field) {
      case trap_reason(field.0), trap_reason(field.1) {
        Some(reason), _ | _, Some(reason) -> Ok(reason)
        _, _ -> Error(Nil)
      }
    })
    |> option.from_result
  case trapped {
    Some(reason) -> Refused(invalid_input(reason))
    None ->
      case dict.get(args, "samples") {
        Error(_) ->
          case dict.get(args, "code") {
            Error(_) ->
              emit("ast_anomaly_detect", candidate_id.current(), [
                #("epistemic_class", json.string("deterministic_kernel")),
                #("sample_count", json.int(0)),
                #("anomalies", json.int(0)),
              ])
            Ok(code) -> {
              let strict = result.unwrap(dict.get(args, "strict_mode"), "true")
              case strict == "true" || strict == "false" {
                False -> Refused(invalid_input("strict_mode must be a boolean"))
                True -> {
                  let lowered = string.lowercase(code)
                  let language =
                    result.unwrap(dict.get(args, "language"), "unspecified")
                  let constructs = case string.lowercase(language) {
                    "rust" -> ["unsafe", "panic", "todo", "unwrap()"]
                    "ocaml" -> [
                      "obj.magic",
                      "failwith",
                      "assert false",
                      "unsafe",
                    ]
                    "gleam" -> ["panic", "todo", "unsafe"]
                    "python" -> ["eval(", "exec(", "unsafe"]
                    "javascript" | "typescript" -> [
                      "eval(",
                      "new function(",
                      "unsafe",
                    ]
                    _ -> [
                      "unsafe",
                      "panic",
                      "todo",
                      "unwrap()",
                      "obj.magic",
                      "eval(",
                    ]
                  }
                  let tokens =
                    list.filter(constructs, fn(token) {
                      string.contains(lowered, token)
                    })
                  let nesting =
                    source_max_depth(bit_array.from_string(code), 0, 0)
                  let excessive_nesting = nesting > 32
                  let anomalies =
                    list.length(tokens)
                    + case excessive_nesting {
                      True -> 1
                      False -> 0
                    }
                  emit("ast_anomaly_detect", candidate_id.current(), [
                    #("epistemic_class", json.string("deterministic_kernel")),
                    #(
                      "analysis_kind",
                      json.string("bounded_token_scan_not_language_parser"),
                    ),
                    #("sample_count", json.int(1)),
                    #("anomalies", json.int(anomalies)),
                    #("language", json.string(language)),
                    #("strict_mode", json.bool(strict == "true")),
                    #(
                      "strict_pass",
                      json.bool(strict == "false" || anomalies == 0),
                    ),
                    #("unsafe_constructs", json.array(tokens, json.string)),
                    #("max_nesting", json.int(nesting)),
                  ])
                }
              }
            }
          }
        Ok(samples_raw) ->
          case parse_int_csv(samples_raw) {
            Error(error) -> Refused(error)
            Ok(samples) ->
              emit("ast_anomaly_detect", candidate_id.current(), [
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
  case dict.get(args, "series"), dict.get(args, "telemetry") {
    Error(_), Error(_) ->
      Refused(invalid_input(
        "lyapunov_trend_predict requires a numeric comma separated series",
      ))
    raw_series, raw_telemetry -> {
      let raw = result.unwrap(raw_series, result.unwrap(raw_telemetry, ""))
      case
        parse_numeric_sequence(raw),
        optional_float(args, "dt", 1.0),
        optional_float(args, "horizon_seconds", 60.0),
        optional_float(args, "critical_threshold", 0.0)
      {
        Ok(values), Ok(dt), Ok(horizon), Ok(threshold)
          if dt >=. 0.000_000_001 && horizon >=. 0.0
        ->
          case list.length(values) >= 2 {
            False ->
              Refused(invalid_input(
                "lyapunov_trend_predict requires at least two points",
              ))
            True -> {
              let first = list.first(values) |> result.unwrap(0.0)
              let last = list.last(values) |> result.unwrap(0.0)
              let drift = last -. first
              let derivative =
                drift /. { int.to_float(list.length(values) - 1) *. dt }
              emit("lyapunov_trend_predict", candidate_id.current(), [
                #("epistemic_class", json.string("deterministic_kernel")),
                #("point_count", json.int(list.length(values))),
                #("drift", json.float(drift)),
                #("dV_dt", json.float(derivative)),
                #("dt", json.float(dt)),
                #("horizon_seconds", json.float(horizon)),
                #(
                  "horizon_projection",
                  json.float(last +. derivative *. horizon),
                ),
                #("critical_threshold", json.float(threshold)),
                #(
                  "threshold_exceeded",
                  json.bool(last +. derivative *. horizon >. threshold),
                ),
                #(
                  "stability",
                  json.string(case derivative <. 0.0 {
                    True -> "asymptotically_stable"
                    False -> "diverging"
                  }),
                ),
              ])
            }
          }
        _, _, _, _ ->
          Refused(invalid_input(
            "numeric telemetry, positive dt and nonnegative horizon required",
          ))
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
      emit(tool_name, candidate_id.current(), [
        #("spec_kind", json.string("grammar_of_graphics")),
        #("declarative_only", json.bool(True)),
        #("code_executed", json.bool(False)),
        #("mark", json.string(result.unwrap(dict.get(args, "mark"), "point"))),
        #("x", json.string(result.unwrap(dict.get(args, "x"), "x"))),
        #("y", json.string(result.unwrap(dict.get(args, "y"), "y"))),
        #(
          "extension",
          json.string(result.unwrap(dict.get(args, "extension"), "all")),
        ),
        #(
          "preset",
          json.string(result.unwrap(dict.get(args, "preset"), "custom")),
        ),
        #("code", json.string(result.unwrap(dict.get(args, "code"), ""))),
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

fn optional_float(
  args: Dict(String, String),
  key: String,
  default: Float,
) -> Result(Float, ToolError) {
  case dict.get(args, key) {
    Error(_) -> Ok(default)
    Ok(raw) ->
      parse_numeric(string.trim(raw))
      |> result.map_error(fn(_) { invalid_input(key <> " must be numeric") })
  }
}

fn parse_numeric(raw: String) -> Result(Float, Nil) {
  case float.parse(raw) {
    Ok(n) if n >=. -9_007_199_254_740_991.0 && n <=. 9_007_199_254_740_991.0 ->
      Ok(n)
    Ok(_) -> Error(Nil)
    Error(_) ->
      case int.parse(raw) {
        Ok(n) if n >= -9_007_199_254_740_991 && n <= 9_007_199_254_740_991 ->
          Ok(int.to_float(n))
        _ -> Error(Nil)
      }
  }
}

fn numeric_decoder() -> decode.Decoder(Float) {
  decode.one_of(
    decode.then(decode.float, fn(n) {
      case n >=. -9_007_199_254_740_991.0 && n <=. 9_007_199_254_740_991.0 {
        True -> decode.success(n)
        False -> decode.failure(0.0, "bounded numeric scalar")
      }
    }),
    [
      decode.then(decode.int, fn(n) {
        case n >= -9_007_199_254_740_991 && n <= 9_007_199_254_740_991 {
          True -> decode.success(int.to_float(n))
          False -> decode.failure(0.0, "I-JSON safe integer")
        }
      }),
    ],
  )
}

fn parse_numeric_sequence(raw: String) -> Result(List(Float), ToolError) {
  case string.starts_with(string.trim(raw), "[") {
    False -> parse_float_csv(raw)
    True ->
      json.parse(raw, decode.list(numeric_decoder()))
      |> result.map_error(fn(_) {
        invalid_input("telemetry must be a JSON numeric array or numeric CSV")
      })
  }
}

fn string_sequence(
  args: Dict(String, String),
  key: String,
) -> Result(List(String), ToolError) {
  case dict.get(args, key) {
    Error(_) -> Ok([])
    Ok(raw) ->
      case string.starts_with(string.trim(raw), "[") {
        True ->
          json.parse(raw, decode.list(decode.string))
          |> result.map_error(fn(_) {
            invalid_input(key <> " must be a string array")
          })
        False ->
          Ok(
            string.split(raw, ",")
            |> list.map(string.trim)
            |> list.filter(fn(x) { x != "" }),
          )
      }
  }
}

fn schema_branch_eval(args: Dict(String, String)) -> Outcome {
  let source = result.unwrap(dict.get(args, "source_branch"), "") |> string.trim
  let target = result.unwrap(dict.get(args, "target_branch"), "") |> string.trim
  case
    source,
    target,
    string_sequence(args, "candidate_changes"),
    string_sequence(args, "agents")
  {
    "", _, _, _ | _, "", _, _ ->
      Refused(invalid_input("source_branch and target_branch must not be blank"))
    _, _, Ok(changes), Ok(agents) -> {
      let divergent = source != target
      let quorum = list.length(list.unique(agents)) >= 2
      emit("ruliad_branch_eval", candidate_id.current(), [
        #("epistemic_class", json.string("deterministic_kernel")),
        #("source_branch", json.string(source)),
        #("target_branch", json.string(target)),
        #(
          "branch_divergence",
          json.int(case divergent {
            True -> 1
            False -> 0
          }),
        ),
        #("change_count", json.int(list.length(changes))),
        #("agent_count", json.int(list.length(list.unique(agents)))),
        #("quorum_ready", json.bool(quorum)),
        #(
          "merge_readiness",
          json.string(case divergent && !quorum {
            True -> "review_required"
            False -> "advisory_ready"
          }),
        ),
        #(
          "distance_basis",
          json.string("declared_branch_identity_and_change_count_not_vcs_diff"),
        ),
      ])
    }
    _, _, _, _ ->
      Refused(invalid_input(
        "candidate_changes and agents must be arrays of strings",
      ))
  }
}

fn schema_harmonics(args: Dict(String, String)) -> Outcome {
  let raga = result.unwrap(dict.get(args, "raga"), "") |> string.trim
  let fundamental_default = case string.lowercase(raga) {
    "bhairav" -> 256.0
    _ -> 432.0
  }
  case raga, optional_float(args, "fundamental_hz", fundamental_default) {
    "", _ -> Refused(invalid_input("raga must not be blank"))
    _, Ok(fundamental) if fundamental >=. 0.000_000_001 -> {
      let telemetry = case dict.get(args, "telemetry") {
        Error(_) -> Ok([fundamental, fundamental *. 2.0, fundamental *. 3.0])
        Ok(raw) -> parse_numeric_sequence(raw)
      }
      case telemetry {
        Ok(frequencies) if frequencies != [] -> {
          case list.all(frequencies, fn(f) { f >. 0.0 }) {
            False ->
              Refused(invalid_input("harmonic frequencies must be positive"))
            True -> {
              let ratios = list.map(frequencies, fn(f) { f /. fundamental })
              let dissonance =
                list.fold(ratios, 0.0, fn(acc, ratio) {
                  acc
                  +. float.absolute_value(
                    ratio -. int.to_float(float.round(ratio)),
                  )
                })
                /. int.to_float(list.length(ratios))
              emit("shruti_harmonics", candidate_id.current(), [
                #("epistemic_class", json.string("deterministic_kernel")),
                #("raga", json.string(raga)),
                #("fundamental_hz", json.float(fundamental)),
                #("harmonic_count", json.int(list.length(frequencies))),
                #("harmonic_ratios", json.array(ratios, json.float)),
                #("dissonance_score", json.float(dissonance)),
                #("consonance_score", json.float(1.0 -. dissonance)),
                #(
                  "score_basis",
                  json.string(
                    "distance_from_integer_harmonics_not_psychoacoustic_measurement",
                  ),
                ),
              ])
            }
          }
        }
        _ ->
          Refused(invalid_input(
            "telemetry must contain at least one numeric frequency",
          ))
      }
    }
    _, _ ->
      Refused(invalid_input("fundamental_hz must be positive and numeric"))
  }
}

fn source_max_depth(bytes: BitArray, depth: Int, maximum: Int) -> Int {
  case bytes {
    <<>> -> maximum
    <<byte, rest:bits>> ->
      case byte {
        40 | 91 | 123 ->
          source_max_depth(rest, depth + 1, int.max(maximum, depth + 1))
        41 | 93 | 125 -> source_max_depth(rest, int.max(0, depth - 1), maximum)
        _ -> source_max_depth(rest, depth, maximum)
      }
    _ -> maximum
  }
}

type Rule {
  Rule(
    id: String,
    domain: String,
    action: String,
    rank: Int,
    salience: Float,
    specificity: Float,
    score: Float,
  )
}

fn rule_text(rule: value.Value, field: String, default: String) -> String {
  case value.get(rule, field) {
    Ok(value.Text(text)) -> text
    _ -> default
  }
}

fn rule_number(rule: value.Value, field: String, default: Float) -> Float {
  case value.get(rule, field) {
    Ok(value.Number(n)) -> n
    Ok(value.Integer(n)) -> int.to_float(n)
    _ -> default
  }
}

fn parse_rule(rule: value.Value, index: Int) -> Result(Rule, ToolError) {
  case rule {
    value.Object(_) -> {
      use _ <- result.try(validate_rule_numbers(rule))
      let id =
        rule_text(
          rule,
          "id",
          rule_text(rule, "name", "rule-" <> int.to_string(index)),
        )
      let domain =
        rule_text(
          rule,
          "condition",
          rule_text(rule, "when", rule_text(rule, "domain", "global")),
        )
      let action = rule_text(rule, "action", rule_text(rule, "then", ""))
      let rank = case rule_text(rule, "layer", "") {
        "L0" -> 0
        _ -> float.truncate(rule_number(rule, "layer_rank", 9.0))
      }
      Ok(Rule(
        id,
        domain,
        action,
        rank,
        rule_number(rule, "salience", 0.0),
        rule_number(
          rule,
          "specificity",
          rule_number(rule, "matched_conditions", 0.0),
        ),
        rule_number(rule, "score", 0.0),
      ))
    }
    _ -> Error(invalid_input("each rule must be a JSON object"))
  }
}

fn validate_rule_numbers(rule: value.Value) -> Result(Nil, ToolError) {
  let valid =
    list.all(
      ["layer_rank", "salience", "specificity", "matched_conditions", "score"],
      fn(key) {
        case value.get(rule, key) {
          Error(_) -> True
          Ok(value.Number(n)) ->
            n >=. -9_007_199_254_740_991.0 && n <=. 9_007_199_254_740_991.0
          Ok(value.Integer(n)) ->
            n >= -9_007_199_254_740_991 && n <= 9_007_199_254_740_991
          _ -> False
        }
      },
    )
  case valid {
    True -> Ok(Nil)
    False ->
      Error(invalid_input(
        "rule rank/priority fields must be bounded numeric scalars",
      ))
  }
}

fn outranks(a: Rule, b: Rule) -> Bool {
  case a.rank == 0, b.rank == 0 {
    True, False -> True
    False, True -> False
    _, _ ->
      case a.rank == b.rank {
        False -> a.rank < b.rank
        True ->
          case a.salience == b.salience {
            False -> a.salience >. b.salience
            True ->
              case a.specificity == b.specificity {
                False -> a.specificity >. b.specificity
                True -> a.score >. b.score
              }
          }
      }
  }
}

fn pair_conflicts(rules: List(Rule)) -> List(String) {
  case rules {
    [] -> []
    [first, ..rest] ->
      list.append(
        list.filter_map(rest, fn(other) {
          case first.domain == other.domain && first.action != other.action {
            True -> Ok(first.id <> ":" <> other.id)
            False -> Error(Nil)
          }
        }),
        pair_conflicts(rest),
      )
  }
}

fn json_rule_conflicts(raw: String) -> Outcome {
  let parsed =
    json.parse(raw, decode.list(value.decoder()))
    |> result.map_error(fn(_) {
      invalid_input("rules must be a JSON array of objects")
    })
  let parsed =
    result.try(parsed, fn(values) {
      case list.length(values) <= 64 {
        False ->
          Error(invalid_input(
            "rules exceed the bounded 64-rule pairwise kernel",
          ))
        True ->
          list.index_map(values, fn(v, n) { parse_rule(v, n) }) |> result.all
      }
    })
  case parsed {
    Error(error) -> Refused(error)
    Ok(rules) -> {
      let conflicts = pair_conflicts(rules)
      let winner =
        list.reduce(rules, fn(current, next) {
          case outranks(next, current) {
            True -> next
            False -> current
          }
        })
      emit("rete_rule_conflict", candidate_id.current(), [
        #(
          "matcher_kind",
          json.string("bounded_pairwise_conflict_scan_not_full_rete_ul"),
        ),
        #("epistemic_class", json.string("deterministic_kernel")),
        #("rule_count", json.int(list.length(rules))),
        #("conflict_count", json.int(list.length(conflicts))),
        #("conflicts", json.array(conflicts, json.string)),
        #(
          "winning_rule",
          json.string(case winner {
            Ok(winner) -> winner.id
            Error(_) -> ""
          }),
        ),
        #("constitutional_l0_dominance", json.bool(True)),
      ])
    }
  }
}
