import evidence_falsifiers_test
import gleam/io
import private_http_fixture_test

pub fn main() {
  io.println("=== RUNNING EVIDENCE FALSIFIER TESTS ===")
  evidence_falsifiers_test.falsifier_missing_runtime_refuses_freshness_test()
  io.println("PASS: falsifier_missing_runtime_refuses_freshness_test")
  evidence_falsifiers_test.falsifier_fallback_stub_refuses_freshness_test()
  io.println("PASS: falsifier_fallback_stub_refuses_freshness_test")
  evidence_falsifiers_test.falsifier_empty_and_malformed_payload_refuses_freshness_test()
  io.println(
    "PASS: falsifier_empty_and_malformed_payload_refuses_freshness_test",
  )
  evidence_falsifiers_test.falsifier_timestamp_only_payload_refuses_freshness_test()
  io.println("PASS: falsifier_timestamp_only_payload_refuses_freshness_test")
  evidence_falsifiers_test.falsifier_offline_or_error_with_current_timestamp_refuses_freshness_test()
  io.println(
    "PASS: falsifier_offline_or_error_with_current_timestamp_refuses_freshness_test",
  )
  evidence_falsifiers_test.falsifier_wrong_typed_required_fields_refuses_freshness_test()
  io.println(
    "PASS: falsifier_wrong_typed_required_fields_refuses_freshness_test",
  )
  evidence_falsifiers_test.falsifier_future_timestamp_even_within_tolerance_refuses_live_test()
  io.println(
    "PASS: falsifier_future_timestamp_even_within_tolerance_refuses_live_test",
  )
  evidence_falsifiers_test.falsifier_conflicting_timestamp_fields_refuses_freshness_test()
  io.println(
    "PASS: falsifier_conflicting_timestamp_fields_refuses_freshness_test",
  )
  evidence_falsifiers_test.falsifier_stale_timestamp_refuses_freshness_test()
  io.println("PASS: falsifier_stale_timestamp_refuses_freshness_test")
  evidence_falsifiers_test.positive_fresh_samples_do_not_overclaim_all_wiring_test()
  io.println("PASS: positive_fresh_samples_do_not_overclaim_all_wiring_test")
  evidence_falsifiers_test.falsifier_whitespace_and_keyorder_offline_status_test()
  io.println("PASS: falsifier_whitespace_and_keyorder_offline_status_test")
  evidence_falsifiers_test.falsifier_whitespace_and_keyorder_error_field_test()
  io.println("PASS: falsifier_whitespace_and_keyorder_error_field_test")
  evidence_falsifiers_test.falsifier_negative_counters_refused_test()
  io.println("PASS: falsifier_negative_counters_refused_test")
  evidence_falsifiers_test.falsifier_healthy_count_exceeding_container_count_refused_test()
  io.println(
    "PASS: falsifier_healthy_count_exceeding_container_count_refused_test",
  )
  evidence_falsifiers_test.falsifier_timestamp_alias_type_error_with_valid_sibling_refused_test()
  io.println(
    "PASS: falsifier_timestamp_alias_type_error_with_valid_sibling_refused_test",
  )
  evidence_falsifiers_test.falsifier_duplicate_keys_refused_test()
  io.println("PASS: falsifier_duplicate_keys_refused_test")

  evidence_falsifiers_test.unicode_duplicate_key_refused_test()
  evidence_falsifiers_test.malformed_and_oversized_json_refused_test()
  evidence_falsifiers_test.exact_freshness_boundary_test()
  evidence_falsifiers_test.observed_empty_plan_is_valid_test()
  io.println(
    "PASS: four Unicode, malformed JSON, empty-plan and boundary regression tests",
  )

  io.println("=== RUNNING PRIVATE HTTP FIXTURE TESTS ===")
  private_http_fixture_test.private_http_health_freshness_candidate_test()
  io.println("PASS: private_http_health_freshness_candidate_test")
  private_http_fixture_test.private_http_health_candidate_test()
  io.println("PASS: private_http_health_candidate_test")
  private_http_fixture_test.private_http_snapshot_candidate_test()
  io.println("PASS: private_http_snapshot_candidate_test")

  io.println("=== ALL 23 TELEMETRY REPAIR TESTS PASSED ===")
}
