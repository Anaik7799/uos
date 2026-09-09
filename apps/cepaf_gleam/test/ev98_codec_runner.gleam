import crdt_delta_state_test
import crdt_health_bridge_test
import crdt_mesh_sync_test
import deadman_freshness_test
import delta_mesh_engine_test
import gleam/io
import mesh_sync_codec_test

pub fn main() {
  io.println("START mesh_sync_codec_test.diagnostic_delta_retains_payload_test")
  mesh_sync_codec_test.diagnostic_delta_retains_payload_test()
  io.println("PASS mesh_sync_codec_test.diagnostic_delta_retains_payload_test")
  io.println(
    "START mesh_sync_codec_test.all_fields_and_forwarding_origin_roundtrip_test",
  )
  mesh_sync_codec_test.all_fields_and_forwarding_origin_roundtrip_test()
  io.println(
    "PASS mesh_sync_codec_test.all_fields_and_forwarding_origin_roundtrip_test",
  )
  io.println("START mesh_sync_codec_test.digest_and_ack_roundtrip_test")
  mesh_sync_codec_test.digest_and_ack_roundtrip_test()
  io.println("PASS mesh_sync_codec_test.digest_and_ack_roundtrip_test")
  io.println(
    "START mesh_sync_codec_test.empty_delta_and_zero_boundaries_roundtrip_test",
  )
  mesh_sync_codec_test.empty_delta_and_zero_boundaries_roundtrip_test()
  io.println(
    "PASS mesh_sync_codec_test.empty_delta_and_zero_boundaries_roundtrip_test",
  )
  io.println("START mesh_sync_codec_test.independent_exact_wire_layout_test")
  mesh_sync_codec_test.independent_exact_wire_layout_test()
  io.println("PASS mesh_sync_codec_test.independent_exact_wire_layout_test")
  io.println(
    "START mesh_sync_codec_test.wire_reconciliation_matches_typed_oracle_test",
  )
  mesh_sync_codec_test.wire_reconciliation_matches_typed_oracle_test()
  io.println(
    "PASS mesh_sync_codec_test.wire_reconciliation_matches_typed_oracle_test",
  )
  io.println(
    "START mesh_sync_codec_test.malformed_wire_refuses_before_reconciliation_test",
  )
  mesh_sync_codec_test.malformed_wire_refuses_before_reconciliation_test()
  io.println(
    "PASS mesh_sync_codec_test.malformed_wire_refuses_before_reconciliation_test",
  )
  io.println("START mesh_sync_codec_test.exact_byte_decode_boundary_test")
  mesh_sync_codec_test.exact_byte_decode_boundary_test()
  io.println("PASS mesh_sync_codec_test.exact_byte_decode_boundary_test")
  io.println("START mesh_sync_codec_test.exact_byte_encode_boundary_test")
  mesh_sync_codec_test.exact_byte_encode_boundary_test()
  io.println("PASS mesh_sync_codec_test.exact_byte_encode_boundary_test")
  io.println(
    "START mesh_sync_codec_test.depth_checked_before_recursive_parse_test",
  )
  mesh_sync_codec_test.depth_checked_before_recursive_parse_test()
  io.println(
    "PASS mesh_sync_codec_test.depth_checked_before_recursive_parse_test",
  )
  io.println("START mesh_sync_codec_test.collection_boundary_and_order_test")
  mesh_sync_codec_test.collection_boundary_and_order_test()
  io.println("PASS mesh_sync_codec_test.collection_boundary_and_order_test")
  io.println("START mesh_sync_codec_test.utf8_string_byte_boundaries_test")
  mesh_sync_codec_test.utf8_string_byte_boundaries_test()
  io.println("PASS mesh_sync_codec_test.utf8_string_byte_boundaries_test")
  io.println(
    "START mesh_sync_codec_test.safe_integer_and_negative_boundaries_test",
  )
  mesh_sync_codec_test.safe_integer_and_negative_boundaries_test()
  io.println(
    "PASS mesh_sync_codec_test.safe_integer_and_negative_boundaries_test",
  )
  io.println(
    "START mesh_sync_codec_test.closed_grammar_rejects_ambiguous_and_malformed_inputs_test",
  )
  mesh_sync_codec_test.closed_grammar_rejects_ambiguous_and_malformed_inputs_test()
  io.println(
    "PASS mesh_sync_codec_test.closed_grammar_rejects_ambiguous_and_malformed_inputs_test",
  )
  io.println(
    "START mesh_sync_codec_test.duplicate_clock_and_counter_keys_refused_test",
  )
  mesh_sync_codec_test.duplicate_clock_and_counter_keys_refused_test()
  io.println(
    "PASS mesh_sync_codec_test.duplicate_clock_and_counter_keys_refused_test",
  )
  io.println(
    "START mesh_sync_codec_test.duplicate_health_keys_and_mismatched_nodes_refused_test",
  )
  mesh_sync_codec_test.duplicate_health_keys_and_mismatched_nodes_refused_test()
  io.println(
    "PASS mesh_sync_codec_test.duplicate_health_keys_and_mismatched_nodes_refused_test",
  )
  io.println(
    "START mesh_sync_codec_test.duplicate_live_tombstone_and_cross_set_dots_refused_test",
  )
  mesh_sync_codec_test.duplicate_live_tombstone_and_cross_set_dots_refused_test()
  io.println(
    "PASS mesh_sync_codec_test.duplicate_live_tombstone_and_cross_set_dots_refused_test",
  )
  io.println("START mesh_sync_codec_test.empty_node_identities_refused_test")
  mesh_sync_codec_test.empty_node_identities_refused_test()
  io.println("PASS mesh_sync_codec_test.empty_node_identities_refused_test")
  io.println(
    "START mesh_sync_codec_test.physical_and_logical_health_times_survive_independently_test",
  )
  mesh_sync_codec_test.physical_and_logical_health_times_survive_independently_test()
  io.println(
    "PASS mesh_sync_codec_test.physical_and_logical_health_times_survive_independently_test",
  )
  io.println(
    "START mesh_sync_codec_test.nonfinite_numeric_literals_are_refused_test",
  )
  mesh_sync_codec_test.nonfinite_numeric_literals_are_refused_test()
  io.println(
    "PASS mesh_sync_codec_test.nonfinite_numeric_literals_are_refused_test",
  )
  io.println(
    "START mesh_sync_codec_test.exact_float_extremes_and_escaped_strings_roundtrip_test",
  )
  mesh_sync_codec_test.exact_float_extremes_and_escaped_strings_roundtrip_test()
  io.println(
    "PASS mesh_sync_codec_test.exact_float_extremes_and_escaped_strings_roundtrip_test",
  )
  io.println(
    "START mesh_sync_codec_test.every_composite_collection_has_an_encoder_bound_test",
  )
  mesh_sync_codec_test.every_composite_collection_has_an_encoder_bound_test()
  io.println(
    "PASS mesh_sync_codec_test.every_composite_collection_has_an_encoder_bound_test",
  )
  io.println(
    "START mesh_sync_codec_test.malformed_nested_wire_records_refused_test",
  )
  mesh_sync_codec_test.malformed_nested_wire_records_refused_test()
  io.println(
    "PASS mesh_sync_codec_test.malformed_nested_wire_records_refused_test",
  )
  io.println("START crdt_mesh_sync_test.mesh_sync_digest_and_drift_test")
  crdt_mesh_sync_test.mesh_sync_digest_and_drift_test()
  io.println("PASS crdt_mesh_sync_test.mesh_sync_digest_and_drift_test")
  io.println("START crdt_mesh_sync_test.mesh_sync_reconciliation_and_ack_test")
  crdt_mesh_sync_test.mesh_sync_reconciliation_and_ack_test()
  io.println("PASS crdt_mesh_sync_test.mesh_sync_reconciliation_and_ack_test")
  io.println(
    "START crdt_delta_state_test.vector_clock_semilattice_properties_test",
  )
  crdt_delta_state_test.vector_clock_semilattice_properties_test()
  io.println(
    "PASS crdt_delta_state_test.vector_clock_semilattice_properties_test",
  )
  io.println("START crdt_delta_state_test.lww_register_convergence_test")
  crdt_delta_state_test.lww_register_convergence_test()
  io.println("PASS crdt_delta_state_test.lww_register_convergence_test")
  io.println("START crdt_delta_state_test.orset_add_remove_convergence_test")
  crdt_delta_state_test.orset_add_remove_convergence_test()
  io.println("PASS crdt_delta_state_test.orset_add_remove_convergence_test")
  io.println("START crdt_delta_state_test.pncounter_increment_decrement_test")
  crdt_delta_state_test.pncounter_increment_decrement_test()
  io.println("PASS crdt_delta_state_test.pncounter_increment_decrement_test")
  io.println("START crdt_delta_state_test.mesh_delta_state_composition_test")
  crdt_delta_state_test.mesh_delta_state_composition_test()
  io.println("PASS crdt_delta_state_test.mesh_delta_state_composition_test")
  io.println("START crdt_health_bridge_test.record_and_merge_health_test")
  crdt_health_bridge_test.record_and_merge_health_test()
  io.println("PASS crdt_health_bridge_test.record_and_merge_health_test")
  io.println(
    "START crdt_health_bridge_test.health_telemetry_lww_convergence_test",
  )
  crdt_health_bridge_test.health_telemetry_lww_convergence_test()
  io.println(
    "PASS crdt_health_bridge_test.health_telemetry_lww_convergence_test",
  )
  io.println(
    "START delta_mesh_engine_test.health_observation_advances_causal_clock_test",
  )
  delta_mesh_engine_test.health_observation_advances_causal_clock_test()
  io.println(
    "PASS delta_mesh_engine_test.health_observation_advances_causal_clock_test",
  )
  io.println(
    "START delta_mesh_engine_test.worker_observation_epoch_cannot_regress_test",
  )
  delta_mesh_engine_test.worker_observation_epoch_cannot_regress_test()
  io.println(
    "PASS delta_mesh_engine_test.worker_observation_epoch_cannot_regress_test",
  )
  io.println(
    "START delta_mesh_engine_test.stale_health_does_not_advance_clock_test",
  )
  delta_mesh_engine_test.stale_health_does_not_advance_clock_test()
  io.println(
    "PASS delta_mesh_engine_test.stale_health_does_not_advance_clock_test",
  )
  io.println("START delta_mesh_engine_test.gossip_queue_is_bounded_test")
  delta_mesh_engine_test.gossip_queue_is_bounded_test()
  io.println("PASS delta_mesh_engine_test.gossip_queue_is_bounded_test")
  io.println("START delta_mesh_engine_test.engine_init_test")
  delta_mesh_engine_test.engine_init_test()
  io.println("PASS delta_mesh_engine_test.engine_init_test")
  io.println("START delta_mesh_engine_test.engine_register_peer_test")
  delta_mesh_engine_test.engine_register_peer_test()
  io.println("PASS delta_mesh_engine_test.engine_register_peer_test")
  io.println(
    "START delta_mesh_engine_test.engine_local_mutation_and_gossip_test",
  )
  delta_mesh_engine_test.engine_local_mutation_and_gossip_test()
  io.println(
    "PASS delta_mesh_engine_test.engine_local_mutation_and_gossip_test",
  )
  io.println("START delta_mesh_engine_test.engine_two_node_reconciliation_test")
  delta_mesh_engine_test.engine_two_node_reconciliation_test()
  io.println("PASS delta_mesh_engine_test.engine_two_node_reconciliation_test")
  io.println("START delta_mesh_engine_test.engine_health_aggregation_test")
  delta_mesh_engine_test.engine_health_aggregation_test()
  io.println("PASS delta_mesh_engine_test.engine_health_aggregation_test")
  io.println(
    "START delta_mesh_engine_test.full_queue_rejects_without_advancing_round_and_can_drain_test",
  )
  delta_mesh_engine_test.full_queue_rejects_without_advancing_round_and_can_drain_test()
  io.println(
    "PASS delta_mesh_engine_test.full_queue_rejects_without_advancing_round_and_can_drain_test",
  )
  io.println(
    "START delta_mesh_engine_test.outbound_drain_retains_fifo_and_is_empty_on_repeat_test",
  )
  delta_mesh_engine_test.outbound_drain_retains_fifo_and_is_empty_on_repeat_test()
  io.println(
    "PASS delta_mesh_engine_test.outbound_drain_retains_fifo_and_is_empty_on_repeat_test",
  )
  io.println(
    "START delta_mesh_engine_test.full_queue_defers_delta_application_until_retry_test",
  )
  delta_mesh_engine_test.full_queue_defers_delta_application_until_retry_test()
  io.println(
    "PASS delta_mesh_engine_test.full_queue_defers_delta_application_until_retry_test",
  )
  io.println(
    "START delta_mesh_engine_test.full_queue_can_receive_ack_and_peer_time_does_not_regress_test",
  )
  delta_mesh_engine_test.full_queue_can_receive_ack_and_peer_time_does_not_regress_test()
  io.println(
    "PASS delta_mesh_engine_test.full_queue_can_receive_ack_and_peer_time_does_not_regress_test",
  )
  io.println(
    "START delta_mesh_engine_test.health_only_change_generates_delta_against_previous_clock_test",
  )
  delta_mesh_engine_test.health_only_change_generates_delta_against_previous_clock_test()
  io.println(
    "PASS delta_mesh_engine_test.health_only_change_generates_delta_against_previous_clock_test",
  )
  io.println(
    "START delta_mesh_engine_test.full_queue_rejects_both_digest_response_branches_test",
  )
  delta_mesh_engine_test.full_queue_rejects_both_digest_response_branches_test()
  io.println(
    "PASS delta_mesh_engine_test.full_queue_rejects_both_digest_response_branches_test",
  )
  io.println(
    "START delta_mesh_engine_test.gossip_timestamp_cannot_precede_latest_observation_test",
  )
  delta_mesh_engine_test.gossip_timestamp_cannot_precede_latest_observation_test()
  io.println(
    "PASS delta_mesh_engine_test.gossip_timestamp_cannot_precede_latest_observation_test",
  )
  io.println(
    "START delta_mesh_engine_test.repeated_health_sample_is_idempotent_test",
  )
  delta_mesh_engine_test.repeated_health_sample_is_idempotent_test()
  io.println(
    "PASS delta_mesh_engine_test.repeated_health_sample_is_idempotent_test",
  )
  io.println(
    "START delta_mesh_engine_test.reversed_same_tick_health_deltas_preserve_latest_sample_test",
  )
  delta_mesh_engine_test.reversed_same_tick_health_deltas_preserve_latest_sample_test()
  io.println(
    "PASS delta_mesh_engine_test.reversed_same_tick_health_deltas_preserve_latest_sample_test",
  )
  io.println(
    "START delta_mesh_engine_test.concurrent_same_target_health_converges_in_both_orders_test",
  )
  delta_mesh_engine_test.concurrent_same_target_health_converges_in_both_orders_test()
  io.println(
    "PASS delta_mesh_engine_test.concurrent_same_target_health_converges_in_both_orders_test",
  )
  io.println(
    "START delta_mesh_engine_test.local_health_after_merge_supersedes_same_tick_remote_sample_test",
  )
  delta_mesh_engine_test.local_health_after_merge_supersedes_same_tick_remote_sample_test()
  io.println(
    "PASS delta_mesh_engine_test.local_health_after_merge_supersedes_same_tick_remote_sample_test",
  )
  io.println(
    "START delta_mesh_engine_test.successive_gossip_retains_accepted_epoch_test",
  )
  delta_mesh_engine_test.successive_gossip_retains_accepted_epoch_test()
  io.println(
    "PASS delta_mesh_engine_test.successive_gossip_retains_accepted_epoch_test",
  )
  io.println(
    "START delta_mesh_engine_test.incoming_ack_and_digest_observations_advance_outgoing_epoch_test",
  )
  delta_mesh_engine_test.incoming_ack_and_digest_observations_advance_outgoing_epoch_test()
  io.println(
    "PASS delta_mesh_engine_test.incoming_ack_and_digest_observations_advance_outgoing_epoch_test",
  )
  io.println(
    "START delta_mesh_engine_test.newer_sample_time_wins_over_an_older_logical_counter_test",
  )
  delta_mesh_engine_test.newer_sample_time_wins_over_an_older_logical_counter_test()
  io.println(
    "PASS delta_mesh_engine_test.newer_sample_time_wins_over_an_older_logical_counter_test",
  )
  io.println(
    "START deadman_freshness_test.repeated_trip_emits_no_duplicate_actions_test",
  )
  deadman_freshness_test.repeated_trip_emits_no_duplicate_actions_test()
  io.println(
    "PASS deadman_freshness_test.repeated_trip_emits_no_duplicate_actions_test",
  )
  io.println(
    "START deadman_freshness_test.backward_tick_cannot_clear_a_trip_test",
  )
  deadman_freshness_test.backward_tick_cannot_clear_a_trip_test()
  io.println(
    "PASS deadman_freshness_test.backward_tick_cannot_clear_a_trip_test",
  )
  io.println(
    "START deadman_freshness_test.stale_heartbeat_cannot_recover_a_trip_test",
  )
  deadman_freshness_test.stale_heartbeat_cannot_recover_a_trip_test()
  io.println(
    "PASS deadman_freshness_test.stale_heartbeat_cannot_recover_a_trip_test",
  )
  io.println(
    "START deadman_freshness_test.fresh_recovery_rearms_one_new_trip_test",
  )
  deadman_freshness_test.fresh_recovery_rearms_one_new_trip_test()
  io.println(
    "PASS deadman_freshness_test.fresh_recovery_rearms_one_new_trip_test",
  )
  io.println("START deadman_freshness_test.exact_single_interval_trips_test")
  deadman_freshness_test.exact_single_interval_trips_test()
  io.println("PASS deadman_freshness_test.exact_single_interval_trips_test")
  io.println(
    "START deadman_freshness_test.repeated_warning_and_duplicate_tick_are_quiet_test",
  )
  deadman_freshness_test.repeated_warning_and_duplicate_tick_are_quiet_test()
  io.println(
    "PASS deadman_freshness_test.repeated_warning_and_duplicate_tick_are_quiet_test",
  )
  io.println(
    "START deadman_freshness_test.invalid_intervals_are_quarantined_and_not_heartbeat_recovered_test",
  )
  deadman_freshness_test.invalid_intervals_are_quarantined_and_not_heartbeat_recovered_test()
  io.println(
    "PASS deadman_freshness_test.invalid_intervals_are_quarantined_and_not_heartbeat_recovered_test",
  )
  io.println(
    "START deadman_freshness_test.stale_reregistration_cannot_clear_a_trip_test",
  )
  deadman_freshness_test.stale_reregistration_cannot_clear_a_trip_test()
  io.println(
    "PASS deadman_freshness_test.stale_reregistration_cannot_clear_a_trip_test",
  )
  io.println(
    "START deadman_freshness_test.actor_order_is_stable_across_ticks_test",
  )
  deadman_freshness_test.actor_order_is_stable_across_ticks_test()
  io.println(
    "PASS deadman_freshness_test.actor_order_is_stable_across_ticks_test",
  )
  io.println(
    "START deadman_freshness_test.explicit_valid_configuration_can_recover_quarantine_test",
  )
  deadman_freshness_test.explicit_valid_configuration_can_recover_quarantine_test()
  io.println(
    "PASS deadman_freshness_test.explicit_valid_configuration_can_recover_quarantine_test",
  )
  io.println(
    "START deadman_freshness_test.heartbeat_at_trip_observation_time_does_not_rearm_test",
  )
  deadman_freshness_test.heartbeat_at_trip_observation_time_does_not_rearm_test()
  io.println(
    "PASS deadman_freshness_test.heartbeat_at_trip_observation_time_does_not_rearm_test",
  )
  io.println("START deadman_freshness_test.deadman_init_test")
  deadman_freshness_test.deadman_init_test()
  io.println("PASS deadman_freshness_test.deadman_init_test")
  io.println("START deadman_freshness_test.deadman_registration_nominal_test")
  deadman_freshness_test.deadman_registration_nominal_test()
  io.println("PASS deadman_freshness_test.deadman_registration_nominal_test")
  io.println("START deadman_freshness_test.deadman_warning_escalation_test")
  deadman_freshness_test.deadman_warning_escalation_test()
  io.println("PASS deadman_freshness_test.deadman_warning_escalation_test")
  io.println("START deadman_freshness_test.deadman_trip_and_failover_test")
  deadman_freshness_test.deadman_trip_and_failover_test()
  io.println("PASS deadman_freshness_test.deadman_trip_and_failover_test")
}
