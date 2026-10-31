//// Wave 2 adapter contracts: advertised schema keys and legacy aliases.

import cepaf_gleam/mcp/adapters/analysis
import cepaf_gleam/mcp/adapters/features
import cepaf_gleam/mcp/adapters/knowledge
import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/adapters/planning_write
import cepaf_gleam/mcp/adapters/system_observation
import cepaf_gleam/mcp/adapters/verification
import cepaf_gleam/mcp/admission.{type ValidatedCall, ValidatedCall}
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/types.{type Outcome, ClientProfile, Complete, Refused}
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn text(outcome: Outcome) -> String {
  let assert Complete(body, _) = outcome
  body
}

fn number(body: String, key: String) -> Int {
  json.parse(body, decode.at([key], decode.int)) |> should.be_ok
}

fn words(body: String, key: String) -> String {
  json.parse(body, decode.at([key], decode.string)) |> should.be_ok
}

fn advisory(tool: String, args: List(#(String, String))) -> String {
  analysis.execute(
    tool,
    dict.from_list(args),
    analysis.MaxDaemonOffline("offline"),
  )
  |> text
}

fn refused(outcome: Outcome, expected: String) {
  let assert Refused(error) = outcome
  error.code |> should.equal(expected)
}

pub fn ast_advertised_code_and_arbitrary_keys_are_always_trapped_test() {
  list.each(
    [
      #("code", "25503L801736"),
      #("code", "SELECT * FROM users; DROP TABLE events"),
      #("code", "abc\u{0000}def"),
      #("metadata", "UNION/**/SELECT secret"),
      #("DROP TABLE", "safe"),
    ],
    fn(field) {
      analysis.execute(
        "ast_anomaly_detect",
        dict.from_list([field]),
        analysis.MaxDaemonOffline("offline"),
      )
      |> refused("INVALID_ANALYSIS_INPUT")
    },
  )
}

pub fn ast_code_is_analyzed_with_language_and_strict_mode_test() {
  let body =
    advisory("ast_anomaly_detect", [
      #("code", "unsafe { panic(); value.unwrap() }"),
      #("language", "rust"),
      #("strict_mode", "true"),
    ])
  number(body, "sample_count") |> should.equal(1)
  number(body, "anomalies") |> should.equal(3)
  words(body, "language") |> should.equal("rust")
  json.parse(body, decode.at(["strict_mode"], decode.bool))
  |> should.equal(Ok(True))
}

pub fn schema_stpa_derives_bounded_deterministic_rpn_and_all_uca_types_test() {
  let body =
    advisory("stpa_fmea_hazard", [
      #("action", "deploy"),
      #("criticality", "4"),
      #("impact", "3"),
      #("dependency_readiness", "blocked"),
    ])
  number(body, "severity") |> should.equal(8)
  number(body, "occurrence") |> should.equal(8)
  number(body, "detection") |> should.equal(5)
  number(body, "rpn") |> should.equal(320)
  list.each(
    [
      "not_provided",
      "provided_unsafe",
      "wrong_timing_order",
      "stopped_too_soon_applied_too_long",
    ],
    fn(uca) { string.contains(body, uca) |> should.be_true },
  )
  analysis.execute(
    "stpa_fmea_hazard",
    dict.from_list([#("action", "deploy"), #("impact", "bad")]),
    analysis.MaxDaemonOffline("offline"),
  )
  |> refused("INVALID_ANALYSIS_INPUT")
}

pub fn schema_rule_array_obeys_l0_dominance_test() {
  let body =
    advisory("rete_rule_conflict", [
      #(
        "rules",
        "[{\"id\":\"unsafe\",\"layer\":\"L5\",\"condition\":\"deploy\",\"action\":\"allow\",\"salience\":100},{\"id\":\"constitution\",\"layer\":\"L0\",\"condition\":\"deploy\",\"action\":\"deny\",\"salience\":1}]",
      ),
    ])
  number(body, "conflict_count") |> should.equal(1)
  words(body, "winning_rule") |> should.equal("constitution")
}

pub fn schema_branch_raga_and_telemetry_inputs_compute_advisory_outputs_test() {
  let branch =
    advisory("ruliad_branch_eval", [
      #("source_branch", "alpha"),
      #("target_branch", "beta"),
      #("candidate_changes", "[\"one\",\"two\"]"),
      #("agents", "[\"codex\",\"agy\"]"),
    ])
  number(branch, "change_count") |> should.equal(2)
  number(branch, "agent_count") |> should.equal(2)
  let shruti =
    advisory("shruti_harmonics", [
      #("raga", "Durga"),
      #("fundamental_hz", "432.0"),
      #("telemetry", "[432,864,1296]"),
    ])
  number(shruti, "harmonic_count") |> should.equal(3)
  words(shruti, "raga") |> should.equal("Durga")
  let trend =
    advisory("lyapunov_trend_predict", [
      #("telemetry", "[1.0,0.8,0.5]"),
      #("dt", "2"),
      #("horizon_seconds", "4"),
    ])
  json.parse(trend, decode.at(["dV_dt"], decode.float))
  |> should.equal(Ok(-0.125))
  json.parse(trend, decode.at(["horizon_projection"], decode.float))
  |> should.equal(Ok(0.0))
  words(trend, "stability") |> should.equal("asymptotically_stable")
}

pub fn forecast_layer_fallback_never_claims_model_inference_test() {
  let body =
    advisory("forecast_predict", [
      #("layer", "L4_System"),
      #("horizon_seconds", "60"),
    ])
  words(body, "epistemic_class")
  |> should.equal("deterministic_kinematic_fallback")
  words(body, "max_daemon_status") |> should.equal("offline")
  analysis.execute(
    "forecast_predict",
    dict.from_list([#("layer", "L4_System"), #("source", "max_model")]),
    analysis.MaxDaemonOffline("offline"),
  )
  |> refused("INFERENCE_MODEL_UNAVAILABLE")
}

pub fn declarative_plot_inputs_survive_without_executable_content_test() {
  let body =
    advisory("ggram_synthesize", [
      #("preset", "diamonds"),
      #("code", "ggplot(df, aes(x = `total cost`, y = value)) + geom_point()"),
    ])
  words(body, "preset") |> should.equal("diamonds")
  string.contains(words(body, "code"), "aes(") |> should.be_true
  let ext = advisory("sciviz_extension_deep_dive", [#("extension", "ggfx")])
  words(ext, "extension") |> should.equal("ggfx")
  list.each(
    [
      "<script>x</script>",
      "eval(x)",
      "javascript:foo",
      "system('rm')",
      "os.execute('cmd')",
    ],
    fn(code) {
      analysis.execute(
        "ggram_synthesize",
        dict.from_list([#("code", code)]),
        analysis.MaxDaemonOffline("offline"),
      )
      |> refused("EXECUTABLE_PLOT_CODE_FORBIDDEN")
    },
  )
}

fn plan_store() -> planning_read.PlanningReadStore {
  planning_read.sample_canonical_store("p", [
    planning_read.CanonicalTaskRow("p", "a", "alpha", "available", "", 0),
    planning_read.CanonicalTaskRow("p", "e", "execute", "executing", "owner", 1),
    planning_read.CanonicalTaskRow(
      "p",
      "c",
      "complete",
      "completed",
      "owner",
      1,
    ),
  ])
}

pub fn planning_plan_and_task_id_aliases_and_status_filters_match_schema_test() {
  let body =
    planning_read.execute(
      plan_store(),
      "plan_get",
      dict.from_list([#("plan", "p"), #("id", "e")]),
    )
    |> text
  words(body, "task_id") |> should.equal("e")
  planning_read.execute(
    plan_store(),
    "sa_plan_status_for",
    dict.from_list([#("plan", "unknown")]),
  )
  |> refused("UNKNOWN_PLAN_ID")
  let filtered =
    planning_read.execute(
      plan_store(),
      "plan_list",
      dict.from_list([#("status", "in_progress")]),
    )
    |> text
  json.parse(filtered, decode.at(["rows"], decode.list(decode.dynamic)))
  |> should.be_ok
  |> list.length
  |> should.equal(1)
  planning_read.execute(plan_store(), "plan_list", dict.new())
  |> should.equal(planning_read.execute(
    plan_store(),
    "plan_list",
    dict.from_list([#("status", "all")]),
  ))
}

fn write_call(tool: String, args: List(#(String, String))) -> ValidatedCall {
  let assert Ok(spec) = registry.lookup("public", tool)
  ValidatedCall(
    spec,
    principal.from_launcher_env("owner", ClientProfile("test"), "tenant", "s"),
    dict.from_list(args),
    None,
    None,
    None,
    None,
  )
}

pub fn schema_planning_writes_accept_title_id_plan_status_and_job_aliases_test() {
  let #(added, store) =
    planning_write.execute(
      planning_write.new_store(),
      write_call("plan_add", [
        #("title", "Schema task"),
        #("priority", "P1"),
        #("id", "t"),
      ]),
    )
  let _ = text(added)
  let #(claimed, store) =
    planning_write.execute(
      store,
      write_call("plan_update", [#("id", "t"), #("status", "in_progress")]),
    )
  let _ = text(claimed)
  let #(completed, _) =
    planning_write.execute(
      store,
      write_call("sa_task_complete", [
        #("plan", "default"),
        #("task_id", "t"),
        #("attempt", "1"),
      ]),
    )
  let _ = text(completed)
  let #(job, store) =
    planning_write.execute(
      store,
      write_call("sa_job_enqueue", [
        #("id", "j"),
        #("name", "job"),
        #("queue", "default"),
        #("args", "{}"),
        #("worker", "owner"),
      ]),
    )
  let _ = text(job)
  let #(flow, store) =
    planning_write.execute(
      store,
      write_call("sa_workflow_start", [
        #("id", "wf"),
        #("name", "flow"),
        #("kind", "test"),
        #("input", "{}"),
      ]),
    )
  let _ = text(flow)
  let #(bridge, _) =
    planning_write.execute(
      store,
      write_call("sa_bridge_submit", [#("task", "bridge-task")]),
    )
  let _ = text(bridge)
}

pub fn schema_task_claim_and_complete_keep_principal_and_attempt_fences_test() {
  let #(added, store) =
    planning_write.execute(
      planning_write.new_store(),
      write_call("plan_add", [
        #("plan", "p"),
        #("id", "t"),
        #("title", "Task"),
        #("priority", "P1"),
      ]),
    )
  let _ = text(added)
  let #(claimed, store) =
    planning_write.execute(
      store,
      write_call("sa_task_claim", [
        #("plan", "p"),
        #("task_id", "t"),
        #("worker", "forged-payload-actor"),
      ]),
    )
  let _ = text(claimed)
  let assert Ok(task) = dict.get(store.tasks, #("p", "t"))
  task.worker |> should.equal("owner")
  let #(stale, unchanged) =
    planning_write.execute(
      store,
      write_call("sa_task_complete", [
        #("plan", "p"),
        #("task_id", "t"),
        #("worker", "owner"),
        #("attempt", "0"),
      ]),
    )
  stale |> refused("STALE_ATTEMPT_FENCE")
  unchanged |> should.equal(store)
  let #(done, _) =
    planning_write.execute(
      store,
      write_call("sa_task_complete", [
        #("plan", "p"),
        #("task_id", "t"),
        #("worker", "owner"),
        #("attempt", "1"),
      ]),
    )
  let _ = text(done)
}

fn feature_store() -> features.FeatureEvidenceStore {
  features.FeatureEvidenceStore(
    "candidate",
    93,
    [
      features.CapabilityRecord(
        "first",
        "public",
        "declared",
        "implemented",
        "unrun",
        "unrun",
        "not_admitted",
      ),
      features.CapabilityRecord(
        "second",
        "public",
        "declared",
        "implemented",
        "unrun",
        "unrun",
        "not_admitted",
      ),
    ],
    [],
    dict.from_list([
      #(
        "a",
        features.ExecutionReceipt("a", "candidate", 0, None, None, "digest"),
      ),
    ]),
    dict.from_list([#("i", "verify")]),
  )
}

pub fn feature_schema_pagination_digest_and_intent_aliases_test() {
  let store = feature_store()
  features.execute(
    store,
    "harness_system_feature_catalog",
    dict.from_list([#("catalog_sha256", "wrong"), #("offset", "0")]),
  )
  |> refused("CATALOG_DIGEST_MISMATCH")
  let page =
    features.execute(
      store,
      "harness_system_feature_catalog",
      dict.from_list([#("catalog_sha256", "any"), #("offset", "1")]),
    )
    |> text
  json.parse(page, decode.at(["capabilities"], decode.list(decode.dynamic)))
  |> should.be_ok
  |> list.length
  |> should.equal(1)
  let page =
    features.execute(
      store,
      "harness_system_feature_observations",
      dict.from_list([
        #("catalog_sha256", "any"),
        #("ledger_sha256", "any"),
        #("offset", "0"),
      ]),
    )
    |> text
  json.parse(page, decode.at(["observations"], decode.list(decode.dynamic)))
  |> should.be_ok
  |> list.length
  |> should.equal(1)
  let body =
    features.execute(
      store,
      "harness_system_feature_intent",
      dict.from_list([#("intent", "i")]),
    )
    |> text
  words(body, "intent") |> should.equal("verify")
}

pub fn knowledge_keyword_transclusion_has_bounded_results_and_exact_keys_work_test() {
  let corpus =
    knowledge.new_corpus("tenant", ["public"], 1000, 3)
    |> knowledge.with_entry(knowledge.CorpusEntry(
      "docs/zk/a.md",
      knowledge.RegularFile,
      "public",
      "immutable release",
    ))
    |> knowledge.with_entry(knowledge.CorpusEntry(
      "docs/wiki/b.md",
      knowledge.RegularFile,
      "public",
      "release governance",
    ))
  let body =
    knowledge.execute(
      corpus,
      ["public"],
      "zk_transclude",
      dict.from_list([#("query", "release"), #("limit", "1")]),
    )
    |> text
  json.parse(body, decode.at(["results"], decode.list(decode.dynamic)))
  |> should.be_ok
  |> list.length
  |> should.equal(1)
  knowledge.execute(
    corpus,
    ["public"],
    "zk_transclude",
    dict.from_list([#("key", "docs/zk/a.md")]),
  )
  |> text
  |> should.equal("immutable release")
}

pub fn observation_fields_use_actual_probe_metrics_instead_of_fixture_defaults_test() {
  let backend =
    system_observation.ObservedSnapshot(
      "candidate",
      "live",
      1000,
      5000,
      Some([]),
      dict.from_list([
        #("system_dashboard.status", "healthy"),
        #("system_dashboard.panels", "7"),
        #("probe_kind", "beam_sqlite"),
        #("observed_source", "otp29"),
        #("process_count", "123"),
        #("active_sessions", "4"),
        #("admitted_ev_ceiling", "93"),
      ]),
    )
  let body =
    system_observation.observe(backend, 1000, "system_dashboard", dict.new())
    |> text
  number(body, "panels") |> should.equal(7)
  number(body, "process_count") |> should.equal(123)
  number(body, "active_sessions") |> should.equal(4)
  number(body, "admitted_ev_ceiling") |> should.equal(93)
  words(body, "probe_kind") |> should.equal("beam_sqlite")
}

pub fn empty_verification_id_defaults_to_real_preflight_check_test() {
  let outcome =
    verification.execute_verification(
      "verification_run",
      "",
      "candidate",
      fn(id) {
        id |> should.equal(verification.PreflightToolchain)
        verification.CheckExecuted(0, "PASS (31 checks)", 17)
      },
    )
  let body = text(outcome)
  words(body, "check_id") |> should.equal("preflight_toolchain")
}

pub fn preflight_utility_validates_numbers_and_retains_real_check_result_test() {
  let checked =
    verification.execute_verification(
      "preflight_check",
      "preflight_toolchain",
      "candidate",
      fn(_) { verification.CheckExecuted(0, "PASS (31 checks)", 17) },
    )
  let body =
    verification.with_preflight_utility(
      checked,
      dict.from_list([
        #("actor", "owner"),
        #("action", "review"),
        #("benefit", "9.5"),
        #("cost", "2"),
      ]),
    )
    |> text
  json.parse(body, decode.at(["net_utility"], decode.float))
  |> should.equal(Ok(7.5))
  json.parse(body, decode.at(["seu_decision"], decode.bool))
  |> should.equal(Ok(True))
  number(body, "exit_code") |> should.equal(0)
  words(body, "stdout") |> should.equal("PASS (31 checks)")
  verification.with_preflight_utility(
    checked,
    dict.from_list([#("benefit", "abc"), #("cost", "2")]),
  )
  |> refused("INVALID_PARAMS")
}

pub fn live_probe_status_cannot_be_fabricated_by_global_fixture_status_test() {
  let backend =
    system_observation.ObservedSnapshot(
      "candidate",
      "live",
      1000,
      5000,
      None,
      dict.from_list([#("status", "healthy"), #("probe_kind", "beam")]),
    )
  system_observation.observe(backend, 1000, "kms_catalog", dict.new())
  |> refused("OBSERVATION_PROBE_MISSING")
}

pub fn feature_summary_rejects_wrong_ledger_digest_and_hidden_review_conflict_test() {
  let store = feature_store()
  features.execute(
    store,
    "harness_system_feature_observations",
    dict.from_list([#("offset", "0"), #("ledger_sha256", "wrong")]),
  )
  |> refused("LEDGER_DIGEST_MISMATCH")
  let bad =
    features.FeatureEvidenceStore(
      ..store,
      receipts: dict.insert(
        store.receipts,
        "z",
        features.ExecutionReceipt(
          "z",
          "candidate",
          0,
          Some("HOLD"),
          Some("PASS"),
          "digest",
        ),
      ),
    )
  features.execute(
    bad,
    "harness_system_feature_observations",
    dict.from_list([#("offset", "100")]),
  )
  |> refused("WRAPPER_RAW_VERDICT_CONFLICT")
}

pub fn pairwise_rule_kernel_refuses_more_than_64_rules_before_scanning_test() {
  let raw =
    int.range(1, 66, [], fn(acc, n) {
      [
        json.object([
          #("id", json.string(int.to_string(n))),
          #("action", json.string("allow")),
        ]),
        ..acc
      ]
    })
    |> json.array(fn(x) { x })
    |> json.to_string
  analysis.execute(
    "rete_rule_conflict",
    dict.from_list([#("rules", raw)]),
    analysis.MaxDaemonOffline("offline"),
  )
  |> refused("INVALID_ANALYSIS_INPUT")
}

pub fn numeric_conversion_refuses_unbounded_integers_instead_of_crashing_test() {
  let huge = "1" <> string.repeat("0", 400)
  let checked =
    verification.execute_verification(
      "preflight_check",
      "preflight_toolchain",
      "candidate",
      fn(_) { verification.CheckExecuted(0, "PASS", 1) },
    )
  verification.with_preflight_utility(
    checked,
    dict.from_list([#("benefit", huge), #("cost", "1")]),
  )
  |> refused("INVALID_PARAMS")
  analysis.execute(
    "stpa_fmea_hazard",
    dict.from_list([#("action", "deploy"), #("criticality", huge)]),
    analysis.MaxDaemonOffline("offline"),
  )
  |> refused("INVALID_ANALYSIS_INPUT")
}
