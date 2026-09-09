//// =============================================================================
//// [EV97/EV99] FOCUSED SCHEDULER REPAIR RUNNER
//// =============================================================================

import heijunka_scheduler_test
import work_stealing_test

pub fn main() {
  heijunka_scheduler_test.enqueue_priority_ordering_test()
  heijunka_scheduler_test.pull_batch_nominal_controller_test()
  heijunka_scheduler_test.pull_batch_throttled_controller_test()
  heijunka_scheduler_test.pull_batch_respects_remaining_concurrency_after_prior_leases_test()
  heijunka_scheduler_test.pull_batch_halted_controller_test()
  heijunka_scheduler_test.task_completion_and_reclaim_test()
  heijunka_scheduler_test.reclaim_expired_preserves_original_task_identity_test()
  heijunka_scheduler_test.reclaim_expired_keeps_pending_depth_bounded_test()
  heijunka_scheduler_test.complete_task_does_not_release_another_workers_lease_test()
  heijunka_scheduler_test.complete_task_does_not_release_another_plans_lease_test()
  heijunka_scheduler_test.pull_batch_drains_deferred_reclaims_test()
  work_stealing_test.work_stealing_init_test()
  work_stealing_test.work_stealing_enqueue_and_cluster_count_test()
  work_stealing_test.work_stealing_victim_selection_heaviest_test()
  work_stealing_test.work_stealing_victim_selection_lyapunov_test()
  work_stealing_test.work_stealing_request_and_transfer_handshake_test()
  work_stealing_test.apply_steal_response_is_idempotent_for_a_replayed_transfer_test()
  work_stealing_test.apply_steal_response_deduplicates_tasks_inside_one_transfer_test()
  work_stealing_test.apply_steal_response_keeps_distinct_plan_task_identities_test()
  work_stealing_test.apply_steal_response_remains_replay_safe_after_accepted_work_leaves_test()
  work_stealing_test.apply_steal_response_rejects_a_response_for_another_recipient_test()
  work_stealing_test.handle_steal_request_replays_its_original_response_test()
  work_stealing_test.handle_steal_request_rejects_a_request_for_another_donor_test()
  work_stealing_test.apply_steal_response_bounds_empty_transfer_receipts_test()
  work_stealing_test.apply_steal_response_requires_a_reserved_request_test()
  work_stealing_test.full_receiver_does_not_send_a_request_that_can_strand_donor_work_test()
  work_stealing_test.receiver_reserves_the_last_slot_before_requesting_a_single_batch_test()
  work_stealing_test.wrong_donor_rejection_cannot_consume_another_donor_reservation_test()
}
