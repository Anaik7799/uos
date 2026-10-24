//// =============================================================================
//// [C3I-TEST-EVIDENCE] Negative Falsifiers & Controls for Telemetry Freshness
//// =============================================================================
//// Evaluates all critical failure modes:
//// 1. Missing runtime fails closed.
//// 2. Fallback stubs from c3i_nif.erl rejected.
//// 3. Empty & malformed payloads rejected.
//// 4. Timestamp-only payloads without required domain fields rejected.
//// 5. Offline/error payloads with current timestamp rejected.
//// 6. Wrong-typed required fields rejected.
//// 7. Future timestamps (even within 1s) must not imply observed data.
//// 8. Conflicting timestamp fields rejected.
//// 9. Stale timestamps (>60s) classified as stale.
//// 10. Valid samples accepted for samples_fresh, but all_wiring_functional stays False without WS evidence.

import cepaf_gleam/c3i/evidence.{
  ConflictingTimestamps, EmptyPayload, Fresh, FutureDated, LiveVerified,
  MalformedPayload, MissingRequiredFields, OfflineOrError, Stale, StaleSample,
  StubPayload, Unavailable, Unknown, WrongTypedField,
}

import gleeunit/should

const fixed_now_ms = 1_729_750_000_000

pub fn falsifier_missing_runtime_refuses_freshness_test() {
  let valid_plan =
    "{\"active\":1,\"pending\":0,\"completed\":5,\"total\":6,\"timestamp_ms\":1729749999000}"
  let valid_health =
    "{\"container_count\":15,\"healthy_count\":15,\"threat_level\":\"nominal\",\"zenoh_connected\":true,\"timestamp_ms\":1729749999000}"

  let proj =
    evidence.evaluate_freshness_custom(
      False,
      valid_plan,
      valid_health,
      fixed_now_ms,
    )

  proj.runtime_loaded |> should.be_false()
  proj.samples_fresh |> should.be_false()
  proj.all_wiring_functional |> should.be_false()
  proj.plan_status_valid |> should.be_false()
  proj.system_health_valid |> should.be_false()
  proj.staleness |> should.equal(Unavailable)
  evidence.staleness_to_string(proj.staleness) |> should.equal("unavailable")
}

pub fn falsifier_fallback_stub_refuses_freshness_test() {
  let stub_plan =
    "{\"active\":0,\"pending\":0,\"completed\":0,\"blocked\":0,\"total\":0}"
  let stub_health =
    "{\"container_count\":0,\"healthy_count\":0,\"threat_level\":\"unknown\",\"zenoh_connected\":false}"

  let proj =
    evidence.evaluate_freshness_custom(
      True,
      stub_plan,
      stub_health,
      fixed_now_ms,
    )

  proj.all_wiring_functional |> should.be_false()
  proj.samples_fresh |> should.be_false()
  proj.plan_status_valid |> should.be_false()
  proj.system_health_valid |> should.be_false()
  proj.staleness |> should.equal(Unavailable)
  evidence.staleness_to_string(proj.staleness) |> should.equal("unavailable")
}

pub fn falsifier_empty_and_malformed_payload_refuses_freshness_test() {
  evidence.validate_plan_sample("", fixed_now_ms, 60_000)
  |> should.equal(EmptyPayload)

  evidence.validate_health_sample("{broken json", fixed_now_ms, 60_000)
  |> should.equal(MalformedPayload)

  let proj =
    evidence.evaluate_freshness_custom(True, "", "{bad", fixed_now_ms)
  proj.all_wiring_functional |> should.be_false()
  proj.samples_fresh |> should.be_false()
  proj.staleness |> should.equal(Unavailable)
}

pub fn falsifier_timestamp_only_payload_refuses_freshness_test() {
  // Timestamp-only JSON must NOT be accepted as live plan or health
  let ts_only = "{\"timestamp_ms\":1729749999000}"

  evidence.validate_plan_sample(ts_only, fixed_now_ms, 60_000)
  |> should.equal(MissingRequiredFields("active, pending, completed"))

  evidence.validate_health_sample(ts_only, fixed_now_ms, 60_000)
  |> should.equal(
    MissingRequiredFields(
      "container_count, healthy_count, threat_level, zenoh_connected",
    ),
  )

  let proj =
    evidence.evaluate_freshness_custom(True, ts_only, ts_only, fixed_now_ms)
  proj.all_wiring_functional |> should.be_false()
  proj.samples_fresh |> should.be_false()
  proj.staleness |> should.equal(Unavailable)
}

pub fn falsifier_offline_or_error_with_current_timestamp_refuses_freshness_test() {
  // Error / offline payloads with fresh timestamps must be refused
  let error_plan =
    "{\"error\":\"storage_unreachable\",\"timestamp_ms\":1729749999000}"
  let offline_health =
    "{\"status\":\"offline\",\"container_count\":0,\"healthy_count\":0,\"threat_level\":\"nominal\",\"zenoh_connected\":false,\"timestamp_ms\":1729749999000}"

  case evidence.validate_plan_sample(error_plan, fixed_now_ms, 60_000) {
    OfflineOrError(_) -> True
    _ -> False
  }
  |> should.be_true()

  case evidence.validate_health_sample(offline_health, fixed_now_ms, 60_000) {
    OfflineOrError(_) -> True
    _ -> False
  }
  |> should.be_true()
}


pub fn falsifier_wrong_typed_required_fields_refuses_freshness_test() {
  // Wrong types: active string instead of integer
  let bad_type_plan =
    "{\"active\":\"not_an_int\",\"pending\":0,\"completed\":0,\"timestamp_ms\":1729749999000}"

  case evidence.validate_plan_sample(bad_type_plan, fixed_now_ms, 60_000) {
    MissingRequiredFields(_) | MalformedPayload -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn falsifier_future_timestamp_even_within_tolerance_refuses_live_test() {
  // Future timestamp by 1000ms must NOT be accepted as live verified
  let future_ts = fixed_now_ms + 1000
  let future_plan =
    "{\"active\":1,\"pending\":0,\"completed\":2,\"timestamp_ms\":1729750001000}"
  let future_health =
    "{\"container_count\":10,\"healthy_count\":10,\"threat_level\":\"nominal\",\"zenoh_connected\":true,\"timestamp_ms\":1729750001000}"

  evidence.validate_plan_sample(future_plan, fixed_now_ms, 60_000)
  |> should.equal(FutureDated(future_ts - fixed_now_ms))

  let proj =
    evidence.evaluate_freshness_custom(
      True,
      future_plan,
      future_health,
      fixed_now_ms,
    )
  proj.all_wiring_functional |> should.be_false()
  proj.samples_fresh |> should.be_false()
  proj.staleness |> should.equal(Unknown)
  evidence.staleness_to_string(proj.staleness) |> should.equal("unknown")
}

pub fn falsifier_conflicting_timestamp_fields_refuses_freshness_test() {
  // Conflicting timestamps: timestamp_ms != ts_ms
  let conflicting_plan =
    "{\"active\":1,\"pending\":0,\"completed\":2,\"timestamp_ms\":1729749999000,\"ts_ms\":1729740000000}"

  evidence.validate_plan_sample(conflicting_plan, fixed_now_ms, 60_000)
  |> should.equal(ConflictingTimestamps)
}

pub fn falsifier_stale_timestamp_refuses_freshness_test() {
  // Sample timestamp 120s old (max_age = 60s)
  let stale_plan =
    "{\"active\":1,\"pending\":0,\"completed\":2,\"timestamp_ms\":1729749880000}"
  let stale_health =
    "{\"container_count\":10,\"healthy_count\":10,\"threat_level\":\"nominal\",\"zenoh_connected\":true,\"timestamp_ms\":1729749880000}"

  evidence.validate_plan_sample(stale_plan, fixed_now_ms, 60_000)
  |> should.equal(StaleSample(120_000))

  let proj =
    evidence.evaluate_freshness_custom(
      True,
      stale_plan,
      stale_health,
      fixed_now_ms,
    )
  proj.all_wiring_functional |> should.be_false()
  proj.samples_fresh |> should.be_false()
  proj.staleness |> should.equal(Stale)
  evidence.staleness_to_string(proj.staleness) |> should.equal("stale")
}

pub fn positive_fresh_samples_do_not_overclaim_all_wiring_test() {
  // Fresh plan & health samples (5s old)
  let fresh_plan =
    "{\"active\":2,\"pending\":0,\"completed\":10,\"timestamp_ms\":1729749995000}"
  let fresh_health =
    "{\"container_count\":15,\"healthy_count\":15,\"threat_level\":\"nominal\",\"zenoh_connected\":true,\"timestamp_ms\":1729749995000}"

  evidence.validate_plan_sample(fresh_plan, fixed_now_ms, 60_000)
  |> should.equal(LiveVerified(1729749995000, 5000))

  evidence.validate_health_sample(fresh_health, fixed_now_ms, 60_000)
  |> should.equal(LiveVerified(1729749995000, 5000))

  let proj =
    evidence.evaluate_freshness_custom(
      True,
      fresh_plan,
      fresh_health,
      fixed_now_ms,
    )

  // Narrower claim: samples_fresh = True
  proj.samples_fresh |> should.be_true()
  proj.plan_status_valid |> should.be_true()
  proj.system_health_valid |> should.be_true()
  proj.staleness |> should.equal(Fresh)

  // Invariant: all_wiring_functional MUST NOT be True without websocket evidence!
  proj.all_wiring_functional |> should.be_false()
  proj.ws_planning_active |> should.be_false()
  proj.ws_dashboard_active |> should.be_false()
  proj.ws_availability |> should.equal("unknown")
}

pub fn falsifier_whitespace_and_keyorder_offline_status_test() {
  // Semantically equivalent JSON with whitespace, newlines, and scrambled key order
  let spaced_offline_plan =
    "{\n  \"completed\" : 10 ,\n  \"status\"  :  \"offline\"  ,\n  \"active\" : 2 ,\n  \"pending\" : 0 ,\n  \"timestamp_ms\" : 1729749999000\n}"

  case evidence.validate_plan_sample(spaced_offline_plan, fixed_now_ms, 60_000) {
    OfflineOrError(_) -> True
    _ -> False
  }
  |> should.be_true()

  // Status variants: "down", "failed", "degraded"
  let failed_health =
    "{\n  \"status\": \"failed\",\n  \"container_count\": 10,\n  \"healthy_count\": 5,\n  \"threat_level\": \"elevated\",\n  \"zenoh_connected\": true,\n  \"timestamp_ms\": 1729749999000\n}"

  case evidence.validate_health_sample(failed_health, fixed_now_ms, 60_000) {
    OfflineOrError(_) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn falsifier_whitespace_and_keyorder_error_field_test() {
  // Semantically equivalent JSON with whitespace around error field
  let spaced_error =
    "{  \"error\"  :  \"NIF not loaded\"  ,  \"active\" : 0 , \"pending\" : 0 , \"completed\" : 0 }"

  case evidence.validate_plan_sample(spaced_error, fixed_now_ms, 60_000) {
    StubPayload(_) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn falsifier_negative_counters_refused_test() {
  // Negative plan counter
  let negative_plan =
    "{\"active\": -1, \"pending\": 0, \"completed\": 10, \"timestamp_ms\": 1729749999000}"

  case evidence.validate_plan_sample(negative_plan, fixed_now_ms, 60_000) {
    WrongTypedField(_) -> True
    _ -> False
  }
  |> should.be_true()

  // Negative health container count
  let negative_health =
    "{\"container_count\": -5, \"healthy_count\": 0, \"threat_level\": \"nominal\", \"zenoh_connected\": true, \"timestamp_ms\": 1729749999000}"

  case evidence.validate_health_sample(negative_health, fixed_now_ms, 60_000) {
    WrongTypedField(_) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn falsifier_healthy_count_exceeding_container_count_refused_test() {
  // Impossible domain value: 16 healthy out of 10 containers
  let invalid_health =
    "{\"container_count\": 10, \"healthy_count\": 16, \"threat_level\": \"nominal\", \"zenoh_connected\": true, \"timestamp_ms\": 1729749999000}"

  case evidence.validate_health_sample(invalid_health, fixed_now_ms, 60_000) {
    WrongTypedField(_) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn falsifier_timestamp_alias_type_error_with_valid_sibling_refused_test() {
  // timestamp_ms is string (type error), but sibling ts_ms is valid int.
  // The type error MUST NOT be ignored!
  let bad_alias_plan =
    "{\"active\": 1, \"pending\": 0, \"completed\": 0, \"timestamp_ms\": \"invalid_str\", \"ts_ms\": 1729749999000}"

  case evidence.validate_plan_sample(bad_alias_plan, fixed_now_ms, 60_000) {
    WrongTypedField(_) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn falsifier_duplicate_keys_refused_test() {
  // Ambiguous JSON duplicate keys must NOT mint freshness!
  let duplicate_plan =
    "{\"active\": 1, \"active\": 2, \"pending\": 0, \"completed\": 0, \"timestamp_ms\": 1729749999000}"

  case evidence.validate_plan_sample(duplicate_plan, fixed_now_ms, 60_000) {
    MalformedPayload -> True
    _ -> False
  }
  |> should.be_true()

  let duplicate_timestamp =
    "{\"active\": 1, \"pending\": 0, \"completed\": 0, \"timestamp_ms\": 1729749999000, \"timestamp_ms\": 1729749999000}"

  case evidence.validate_plan_sample(duplicate_timestamp, fixed_now_ms, 60_000) {
    MalformedPayload | ConflictingTimestamps -> True
    _ -> False
  }
  |> should.be_true()
}
