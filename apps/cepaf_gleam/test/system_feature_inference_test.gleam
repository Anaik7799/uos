import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/system_feature_census as census
import cepaf_gleam/harness/system_features as features
import cepaf_gleam/services/max_inference_daemon as max
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import system_feature_tracker_test as fixture

pub const expected_names = [
  "health",
  "metrics",
  "modalities",
  "infer_text",
  "infer_audio",
  "embed",
  "detect_ast_anomaly",
  "match_zk_transclusion",
  "predict_lyapunov_trend",
  "infer_stpa_fmea_hazard",
  "eval_rete_rule_conflict",
  "evaluate_ruliad_branch",
  "synthesize_biomorphic_harmonics",
]

pub const methods = [
  max.Health,
  max.Metrics,
  max.Modalities,
  max.InferText,
  max.InferAudio,
  max.Embed,
  max.DetectAstAnomaly,
  max.MatchZkTransclusion,
  max.PredictLyapunovTrend,
  max.InferStpaFmeaHazard,
  max.EvalReteRuleConflict,
  max.EvaluateRuliadBranch,
  max.SynthesizeBiomorphicHarmonics,
]

pub fn requests(id: String) -> List(String) {
  [
    max.build_health_request(id),
    max.build_metrics_request(id),
    max.build_modalities_request(id),
    max.build_infer_text_request(id, "prompt", "model", 17),
    max.build_infer_audio_request(id, "Durga", 2.5),
    max.build_embed_request(id, ["alpha", "beta"], 3),
    max.build_detect_ast_anomaly_request(id, "pub fn x() { 1 }", "gleam", True),
    max.build_match_zk_transclusion_request(id, "query", 2, Some("L4")),
    max.build_predict_lyapunov_trend_request(id, [1.0, 2.0], 0.5, 3.0, 8.0),
    max.build_infer_stpa_fmea_request(
      id,
      "act",
      "component",
      "context",
      5,
      "unknown",
      4,
    ),
    max.build_eval_rete_rule_conflict_request(id, [], ["fact"]),
    max.build_evaluate_ruliad_branch_request(
      id,
      "source",
      "target",
      ["change"],
      ["agent"],
    ),
    max.build_synthesize_shruti_harmonics_request(
      id,
      [1.0, 2.0],
      "Durga",
      440.0,
    ),
  ]
}

pub fn finite_methods_match_independent_constructor_and_name_oracles_test() {
  max.all_methods() |> should.equal(methods)
  list.map(max.all_methods(), max.method_name) |> should.equal(expected_names)
  list.length(list.unique(max.all_methods())) |> should.equal(13)
}

pub fn structurally_complete_counterfixtures_are_decodable_not_verified_test() {
  max.decode_infer_stpa_fmea_response(
    "{\"id\":\"fixture\",\"status\":\"fixture-only-not-executed\",\"latency_us\":1,\"action\":\"act\",\"component\":\"fixture\",\"uca_count\":0,\"ucas\":[],\"severity\":5,\"occurrence\":3,\"detection\":4,\"rpn\":60,\"rpn_band\":5,\"fmea_factor\":5,\"composite_score\":3125,\"gate_decision\":\"HOLD\",\"sil_rating\":\"UNASSESSED\"}",
  )
  |> should.be_ok
  max.decode_eval_rete_conflict_response(
    "{\"id\":\"fixture\",\"status\":\"fixture-only-not-executed\",\"latency_us\":1,\"rules_evaluated\":0,\"winner\":null,\"suppressed_count\":0,\"suppressed\":[],\"firing_strategy\":\"fixture\",\"constitutional_layer\":\"L0\"}",
  )
  |> should.be_ok
  max.decode_evaluate_ruliad_branch_response(
    "{\"id\":\"fixture\",\"status\":\"fixture-only-not-executed\",\"latency_us\":1,\"source_branch\":\"source\",\"target_branch\":\"target\",\"branchial_distance\":0.0,\"branchial_similarity\":0.0,\"branchial_entropy\":0.0,\"conflict_probability\":0.0,\"convergence_status\":\"UNVERIFIED\",\"participating_agents\":[],\"optimal_collapse_path\":[]}",
  )
  |> should.be_ok
  max.decode_synthesize_shruti_harmonics_response(
    "{\"id\":\"fixture\",\"status\":\"fixture-only-not-executed\",\"latency_us\":1,\"raga\":\"fixture\",\"fundamental_hz\":440.0,\"swara_count\":0,\"harmonics\":[],\"spectral_entropy\":0.0,\"consonance_index\":0.0,\"acoustic_health\":\"UNVERIFIED\",\"jawari_shimmer_active\":false}",
  )
  |> should.be_ok
}

pub fn all_request_method_observations_commute_test() {
  list.each(["", "fixture", "é🙂", "quoted\"\\\n", "\u{0}"], fn(id) {
    let observed =
      list.map(requests(id), fn(request) {
        let decoder = {
          use actual_id <- decode.field("id", decode.string)
          use method <- decode.field("method", decode.string)
          decode.success(#(actual_id, method))
        }
        let assert Ok(value) = json.parse(request, decoder)
        value.0 |> should.equal(id)
        value.1
      })
    observed |> should.equal(expected_names)
    observed |> should.equal(list.map(max.all_methods(), max.method_name))
  })
}

pub fn full_request_wire_matches_pre_refactor_oracle_test() {
  requests("fixture")
  |> string.join("\n")
  |> files.digest
  |> should.equal(
    "77b366b07d4e7f17e84f10dfffedff2d25948791e3fbc796282b5cf3f43c0317",
  )
}

pub fn pin() -> census.Pin {
  census.Pin(
    fixture.digest(),
    census.MaxClient,
    [
      census.SourceBinding(
        "apps/cepaf_gleam/manifest.toml",
        "b9727adbbb2bfb167348da0c7eaa8f3dbdda3b4fd49a456dbb031279944a5169",
      ),
      census.SourceBinding(
        "apps/cepaf_gleam/src/cepaf_gleam/services/max_inference_daemon.gleam",
        "d6c06ac0ad69ada55dd244af9f62c06c84fe0f87cb6d1effff980c55efa8c06e",
      ),
    ],
    13,
    "d326d0fb7f37af03de8dceec3bb5e57f4d09ebd77004ce5a23412b3f414cf373",
  )
}

fn bodies(pin: census.Pin) -> List(#(String, String)) {
  list.map(pin.bindings, fn(binding) {
    let assert Ok(body) = files.read(dev.root, binding.path)
    #(binding.path, body)
  })
}

pub fn client_inventory_is_not_mcp_or_transport_availability_test() {
  let pin = pin()
  let assert Ok(snapshot) = census.extract(pin, bodies(pin))
  census.entries(snapshot)
  |> list.map(fn(entry) { entry.source_id })
  |> should.equal(list.sort(expected_names, string.compare))
  list.each(census.entries(snapshot), fn(entry) {
    entry.feature.endpoints |> should.equal([])
    entry.feature.owner |> should.equal(None)
    entry.feature.holon |> should.equal(None)
    entry.feature.dependencies |> should.equal(None)
    entry.feature.layers |> should.equal(None)
    entry.feature.declared_stage
    |> should.equal(features.Declaration(
      "CLIENT_METHOD_DECLARED_TRANSPORT_UNVERIFIED",
    ))
  })
}

pub fn every_client_source_is_required_and_permutation_invariant_test() {
  let pin = pin()
  let bodies = bodies(pin)
  list.each(bodies, fn(selected) {
    census.extract(pin, list.filter(bodies, fn(body) { body.0 != selected.0 }))
    |> should.be_error
    census.extract(
      pin,
      list.map(bodies, fn(body) {
        case body.0 == selected.0 {
          True -> #(body.0, body.1 <> " ")
          False -> body
        }
      }),
    )
    |> should.be_error
    census.extract(
      census.Pin(
        ..pin,
        bindings: list.filter(pin.bindings, fn(binding) {
          binding.path != selected.0
        }),
      ),
      bodies,
    )
    |> should.be_error
  })
  census.extract(census.Pin(..pin, expected_count: 12), bodies)
  |> should.be_error
  census.extract(
    census.Pin(..pin, expected_ids_sha256: fixture.digest()),
    bodies,
  )
  |> should.be_error
  let assert [first, ..] = bodies
  census.extract(pin, [first, ..bodies]) |> should.be_error
  let assert Ok(forward) = census.extract(pin, bodies)
  let assert Ok(reverse) =
    census.extract(
      census.Pin(..pin, bindings: list.reverse(pin.bindings)),
      list.reverse(bodies),
    )
  census.encode_manifest(reverse)
  |> should.equal(census.encode_manifest(forward))
}

pub fn four_worker_placeholder_and_unknown_method_responses_are_rejected_test() {
  let assert Ok(worker) =
    files.read(dev.root, "services/inference/max/max_worker.py")
  files.digest(worker)
  |> should.equal(
    "89ec73f80bd7c73f11093eb80a19fe033b2812c296b20d46f83a403101d044da",
  )
  list.each(
    [
      "{\"id\": req_id, \"status\": \"ok\", \"passed\": True, \"hazard_level\": \"LOW\", \"rpn\": 12, \"psi_interlocks\": \"PASS\"}",
      "{\"id\": req_id, \"status\": \"ok\", \"passed\": True, \"conflicts\": [], \"l0_dominant\": True}",
      "{\"id\": req_id, \"status\": \"ok\", \"passed\": True, \"branch_status\": \"CONVERGENT\", \"depth\": 3}",
      "{\"id\": req_id, \"status\": \"ok\", \"passed\": True, \"harmonics_ratio\": 1.5, \"shannon_entropy\": 2.8}",
    ],
    fn(source) {
      string.contains(worker, source) |> should.be_true
      let response =
        source
        |> string.replace("req_id", "\"fixture\"")
        |> string.replace("True", "true")
        |> string.replace("}", ",\"latency_us\":1}")
      let common = {
        use id <- decode.field("id", decode.string)
        use status <- decode.field("status", decode.string)
        use latency <- decode.field("latency_us", decode.int)
        decode.success(#(id, status, latency))
      }
      json.parse(response, common) |> should.equal(Ok(#("fixture", "ok", 1)))
      max.decode_infer_stpa_fmea_response(response) |> should.be_error
      max.decode_eval_rete_conflict_response(response) |> should.be_error
      max.decode_evaluate_ruliad_branch_response(response) |> should.be_error
      max.decode_synthesize_shruti_harmonics_response(response)
      |> should.be_error
    },
  )
  list.each(list.drop(expected_names, 9), fn(method) {
    let response =
      json.object([
        #("id", json.string("fixture")),
        #("status", json.string("error")),
        #("error", json.string("Unknown method: " <> method)),
        #("latency_us", json.int(1)),
      ])
      |> json.to_string
    max.decode_infer_stpa_fmea_response(response) |> should.be_error
    max.decode_eval_rete_conflict_response(response) |> should.be_error
    max.decode_evaluate_ruliad_branch_response(response) |> should.be_error
    max.decode_synthesize_shruti_harmonics_response(response) |> should.be_error
  })
}
