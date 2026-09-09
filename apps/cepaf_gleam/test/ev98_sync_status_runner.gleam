import delta_mesh_engine_test
import gleam/io

pub fn main() {
  delta_mesh_engine_test.engine_two_node_reconciliation_test()
  io.println("PASS engine_two_node_reconciliation_test")
  delta_mesh_engine_test.digest_only_exchange_does_not_claim_remote_state_test()
  io.println("PASS digest_only_exchange_does_not_claim_remote_state_test")
  delta_mesh_engine_test.local_mutation_invalidates_prior_peer_coverage_test()
  io.println("PASS local_mutation_invalidates_prior_peer_coverage_test")
  delta_mesh_engine_test.stale_ack_cannot_restore_peer_coverage_after_local_change_test()
  io.println("PASS stale_ack_cannot_restore_peer_coverage_after_local_change_test")
  delta_mesh_engine_test.stale_ack_cannot_erase_a_newer_peer_frontier_test()
  io.println("PASS stale_ack_cannot_erase_a_newer_peer_frontier_test")
  delta_mesh_engine_test.stale_delta_cannot_erase_a_newer_peer_frontier_test()
  io.println("PASS stale_delta_cannot_erase_a_newer_peer_frontier_test")
  delta_mesh_engine_test.remote_ahead_ack_requests_the_missing_delta_test()
  io.println("PASS remote_ahead_ack_requests_the_missing_delta_test")
  delta_mesh_engine_test.full_two_way_exchange_converges_only_after_remote_delta_test()
  io.println("PASS full_two_way_exchange_converges_only_after_remote_delta_test")
  delta_mesh_engine_test.incoming_merge_invalidates_other_peer_coverage_test()
  io.println("PASS incoming_merge_invalidates_other_peer_coverage_test")
  delta_mesh_engine_test.stale_ack_recovery_refuses_when_outbound_queue_is_full_test()
  io.println("PASS stale_ack_recovery_refuses_when_outbound_queue_is_full_test")
  delta_mesh_engine_test.incoming_ack_and_digest_observations_advance_outgoing_epoch_test()
  io.println("PASS incoming_ack_and_digest_observations_advance_outgoing_epoch_test")
}
