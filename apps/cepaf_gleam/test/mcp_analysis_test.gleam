import cepaf_gleam/mcp/adapters/analysis
import cepaf_gleam/mcp/types.{Complete, Refused, Retryable}
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/string
import gleeunit/should

fn offline() -> analysis.InferenceBackend {
  analysis.MaxDaemonOffline("max daemon socket absent")
}

pub fn model_absence_is_not_synthetic_prediction_test() {
  let args = dict.from_list([#("series", "sensor-a")])

  // An unavailable Max daemon must refuse, never fabricate a prediction.
  case analysis.execute("forecast_predict", args, offline()) {
    Refused(error) -> {
      error.code |> should.equal("INFERENCE_MODEL_UNAVAILABLE")
      error.retryability |> should.equal(Retryable)
      string.contains(error.reason, "max daemon socket absent")
      |> should.be_true()
    }
    Complete(payload, _) -> {
      string.contains(payload, "prediction") |> should.be_false()
      should.fail()
    }
    _ -> should.fail()
  }

  // A ready daemon without the requested series is also refused, not invented.
  let ready =
    analysis.MaxDaemonReady(
      model_id: "max-1",
      predictions: dict.from_list([#("other-series", "42.0")]),
    )
  let args = dict.from_list([#("series_key", "sensor-a")])
  case analysis.execute("forecast_predict", args, ready) {
    Refused(error) -> error.code |> should.equal("INFERENCE_SERIES_MISSING")
    _ -> should.fail()
  }
}

pub fn inference_cannot_authorize_control_test() {
  let authorize = dict.from_list([#("authorize_control", "true")])
  case analysis.execute("stpa_fmea_hazard", authorize, offline()) {
    Refused(error) ->
      error.code |> should.equal("INFERENCE_CANNOT_AUTHORIZE_CONTROL")
    _ -> should.fail()
  }

  let execute_effect = dict.from_list([#("execute_effect", "true")])
  case analysis.execute("shruti_harmonics", execute_effect, offline()) {
    Refused(error) ->
      error.code |> should.equal("INFERENCE_CANNOT_AUTHORIZE_CONTROL")
    _ -> should.fail()
  }
}

pub fn generated_plot_code_is_not_executed_test() {
  let bad =
    dict.from_list([
      #("mark", "point"),
      #("x", "<script>alert(1)</script>"),
    ])
  case analysis.execute("ggram_synthesize", bad, offline()) {
    Refused(error) ->
      error.code |> should.equal("EXECUTABLE_PLOT_CODE_FORBIDDEN")
    _ -> should.fail()
  }

  let eval_input = dict.from_list([#("y", "eval(1)")])
  case analysis.execute("sciviz_extension_deep_dive", eval_input, offline()) {
    Refused(error) ->
      error.code |> should.equal("EXECUTABLE_PLOT_CODE_FORBIDDEN")
    _ -> should.fail()
  }

  let good =
    dict.from_list([#("mark", "line"), #("x", "time"), #("y", "value")])
  case analysis.execute("sciviz_extension_deep_dive", good, offline()) {
    Complete(payload, _) -> {
      assert_json_bool(payload, "declarative_only", True)
      assert_json_bool(payload, "code_executed", False)
      string.contains(payload, "<script") |> should.be_false()
    }
    _ -> should.fail()
  }
}

pub fn deterministic_kernels_compute_real_outputs_and_honest_labels_test() {
  // STPA/FMEA: exact RPN from parsed integer args.
  let stpa =
    dict.from_list([
      #("severity", "2"),
      #("occurrence", "3"),
      #("detection", "4"),
    ])
  case analysis.execute("stpa_fmea_hazard", stpa, offline()) {
    Complete(payload, _) -> {
      assert_json_int(payload, "rpn", 24)
      assert_json_string(payload, "epistemic_class", "deterministic_kernel")
      assert_json_bool(payload, "advisory_only", True)
      assert_json_bool(payload, "effect_authority", False)
    }
    _ -> should.fail()
  }

  // Rete conflict scan is labelled honestly as a naive forward scan.
  let rete = dict.from_list([#("rules", "door_open:allow,door_open:deny")])
  case analysis.execute("rete_rule_conflict", rete, offline()) {
    Complete(payload, _) -> {
      assert_json_string(
        payload,
        "matcher_kind",
        "naive_forward_conflict_scan_not_full_rete_ul",
      )
      assert_json_int(payload, "conflict_count", 1)
    }
    _ -> should.fail()
  }

  // Lyapunov drift is the actual finite difference (last - first).
  let lyapunov = dict.from_list([#("series", "1.0,2.5,4.0")])
  case analysis.execute("lyapunov_trend_predict", lyapunov, offline()) {
    Complete(payload, _) -> assert_json_float(payload, "drift", 3.0)
    _ -> should.fail()
  }

  // Malformed inputs fail closed.
  let malformed = dict.from_list([#("severity", "not-a-number")])
  case analysis.execute("stpa_fmea_hazard", malformed, offline()) {
    Refused(error) -> error.code |> should.equal("INVALID_ANALYSIS_INPUT")
    _ -> should.fail()
  }
}

pub fn ast_anomaly_detect_traps_nul_and_sql_evasion_test() {
  // Raw NUL byte is refused before any interpretation.
  let nul = dict.from_list([#("sample", "before\u{0000}after")])
  case analysis.execute("ast_anomaly_detect", nul, offline()) {
    Refused(error) -> error.code |> should.equal("INVALID_ANALYSIS_INPUT")
    _ -> should.fail()
  }

  // SQL split by a comment must not evade detection.
  let comment_sql = dict.from_list([#("sample", "UNION/**/SELECT x FROM y")])
  case analysis.execute("ast_anomaly_detect", comment_sql, offline()) {
    Refused(error) -> error.code |> should.equal("INVALID_ANALYSIS_INPUT")
    _ -> should.fail()
  }

  // Tabs and newlines inside SQL must be normalized before matching.
  let tab_sql = dict.from_list([#("source", "SELECT\tcol FROM t")])
  case analysis.execute("ast_anomaly_detect", tab_sql, offline()) {
    Refused(error) -> error.code |> should.equal("INVALID_ANALYSIS_INPUT")
    _ -> should.fail()
  }

  let newline_sql = dict.from_list([#("source", "DROP\nTABLE users")])
  case analysis.execute("ast_anomaly_detect", newline_sql, offline()) {
    Refused(error) -> error.code |> should.equal("INVALID_ANALYSIS_INPUT")
    _ -> should.fail()
  }
}

pub fn denied_nvme_serial_is_refused_test() {
  let args = dict.from_list([#("sample", analysis.denied_nvme_serial)])
  case analysis.execute("ast_anomaly_detect", args, offline()) {
    Refused(error) -> error.code |> should.equal("INVALID_ANALYSIS_INPUT")
    _ -> should.fail()
  }
}

pub fn negative_ruliad_branch_max_is_not_clamped_test() {
  let args = dict.from_list([#("branches", "-5,-3")])
  case analysis.execute("ruliad_branch_eval", args, offline()) {
    Complete(payload, _) -> {
      assert_json_int(payload, "branch_max", -3)
      assert_json_int(payload, "branch_sum", -8)
    }
    _ -> should.fail()
  }
}

pub fn plot_token_matching_is_case_insensitive_test() {
  let script =
    dict.from_list([
      #("mark", "point"),
      #("x", "<SCRIPT>alert(1)</SCRIPT>"),
    ])
  case analysis.execute("ggram_synthesize", script, offline()) {
    Refused(error) ->
      error.code |> should.equal("EXECUTABLE_PLOT_CODE_FORBIDDEN")
    _ -> should.fail()
  }

  let javascript = dict.from_list([#("y", "javascript:alert(1)")])
  case analysis.execute("sciviz_extension_deep_dive", javascript, offline()) {
    Refused(error) ->
      error.code |> should.equal("EXECUTABLE_PLOT_CODE_FORBIDDEN")
    _ -> should.fail()
  }
}

fn assert_json_bool(payload: String, field: String, expected: Bool) -> Nil {
  case json.parse(payload, decode.at([field], decode.bool)) {
    Ok(value) -> value |> should.equal(expected)
    Error(_) -> should.fail()
  }
}

fn assert_json_int(payload: String, field: String, expected: Int) -> Nil {
  case json.parse(payload, decode.at([field], decode.int)) {
    Ok(value) -> value |> should.equal(expected)
    Error(_) -> should.fail()
  }
}

fn assert_json_float(payload: String, field: String, expected: Float) -> Nil {
  case json.parse(payload, decode.at([field], decode.float)) {
    Ok(value) -> value |> should.equal(expected)
    Error(_) -> should.fail()
  }
}

fn assert_json_string(payload: String, field: String, expected: String) -> Nil {
  case json.parse(payload, decode.at([field], decode.string)) {
    Ok(value) -> value |> should.equal(expected)
    Error(_) -> should.fail()
  }
}
