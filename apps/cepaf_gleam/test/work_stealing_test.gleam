//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Decentralized Work-Stealing Swarm Mesh Verification
//// =============================================================================

import cepaf_gleam/ha/work_stealing.{
  type WorkStealingEngine, HeaviestQueueFirst, LyapunovDivergentFirst,
  NodeQueueState, RandomVictim, StealResponse, StealableTask, TransferAccepted,
  TransferRejected, WorkStealingEngine, apply_steal_response, enqueue_local_task,
  generate_steal_request, handle_steal_request, init_work_stealing,
  select_victim_node, should_initiate_steal, total_cluster_queued_tasks,
  update_peer_queue,
}
import gleam/int
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn work_stealing_init_test() {
  let engine = init_work_stealing("nas-1", 16)
  engine.local_node_id |> should.equal("nas-1")
  engine.capacity |> should.equal(16)
  engine.active_workers |> should.equal(0)
  should_initiate_steal(engine) |> should.be_false()
  total_cluster_queued_tasks(engine) |> should.equal(0)
}

pub fn work_stealing_enqueue_and_cluster_count_test() {
  let task1 = StealableTask("t1", "plan-1", 10, 100, "payload1")
  let task2 = StealableTask("t2", "plan-1", 20, 200, "payload2")

  let engine =
    init_work_stealing("nas-1", 16)
    |> enqueue_local_task(task1)
    |> enqueue_local_task(task2)

  total_cluster_queued_tasks(engine) |> should.equal(2)
}

pub fn work_stealing_victim_selection_heaviest_test() {
  let task_a = StealableTask("ta", "p1", 1, 10, "")
  let task_b = StealableTask("tb", "p1", 1, 10, "")
  let task_c = StealableTask("tc", "p1", 1, 10, "")
  let task_d = StealableTask("td", "p1", 1, 10, "")

  let peer_vm1 =
    NodeQueueState(
      node_id: "vm-1",
      queue: [task_a, task_b],
      active_workers: 4,
      capacity: 16,
      lyapunov_exponent: -3.0,
    )
  let peer_vm2 =
    NodeQueueState(
      node_id: "vm-2",
      queue: [task_a, task_b, task_c, task_d],
      active_workers: 8,
      capacity: 16,
      lyapunov_exponent: -2.0,
    )

  let engine =
    init_work_stealing("nas-1", 16)
    |> update_peer_queue(peer_vm1)
    |> update_peer_queue(peer_vm2)

  should_initiate_steal(engine) |> should.be_true()

  let victim = select_victim_node(engine, HeaviestQueueFirst)
  victim |> should.equal(Some("vm-2"))
}

pub fn work_stealing_victim_selection_lyapunov_test() {
  let task = StealableTask("t", "p", 1, 10, "")
  let peer_healthy =
    NodeQueueState(
      node_id: "vm-healthy",
      queue: [task, task, task],
      active_workers: 4,
      capacity: 16,
      lyapunov_exponent: -3.5,
    )
  let peer_unstable =
    NodeQueueState(
      node_id: "vm-unstable",
      queue: [task, task],
      active_workers: 4,
      capacity: 16,
      lyapunov_exponent: 0.8,
    )

  let engine =
    init_work_stealing("nas-1", 16)
    |> update_peer_queue(peer_healthy)
    |> update_peer_queue(peer_unstable)

  let victim = select_victim_node(engine, LyapunovDivergentFirst)
  victim |> should.equal(Some("vm-unstable"))
}

pub fn work_stealing_request_and_transfer_handshake_test() {
  let t1 = StealableTask("t1", "p", 1, 10, "")
  let t2 = StealableTask("t2", "p", 2, 20, "")
  let t3 = StealableTask("t3", "p", 3, 30, "")
  let t4 = StealableTask("t4", "p", 4, 40, "")

  let donor_engine =
    init_work_stealing("vm-1", 16)
    |> enqueue_local_task(t1)
    |> enqueue_local_task(t2)
    |> enqueue_local_task(t3)
    |> enqueue_local_task(t4)

  let thief_engine = init_work_stealing("nas-1", 8)

  let #(reserved_thief, request) =
    generate_steal_request(thief_engine, "vm-1", "transfer-1", 1000)
  let assert Some(steal_req) = request
  let #(updated_donor, steal_resp) =
    handle_steal_request(donor_engine, steal_req, 1000)

  // Half of donor queue stolen (4 / 2 = 2 tasks)
  list_len(steal_resp.stolen_tasks) |> should.equal(2)
  total_cluster_queued_tasks(updated_donor) |> should.equal(2)

  // Thief adopts the tasks
  let updated_thief = apply_steal_response(reserved_thief, steal_resp)
  total_cluster_queued_tasks(updated_thief) |> should.equal(2)
  updated_thief.steal_history_count |> should.equal(2)
  updated_thief.last_steal_epoch_us |> should.equal(1000)
}

pub fn apply_steal_response_is_idempotent_for_a_replayed_transfer_test() {
  let task1 = StealableTask("t1", "plan", 1, 10, "payload-1")
  let task2 = StealableTask("t2", "plan", 2, 20, "payload-2")
  let donor =
    init_work_stealing("donor", 8)
    |> enqueue_local_task(task1)
    |> enqueue_local_task(task2)
    |> enqueue_local_task(StealableTask("t3", "plan", 3, 30, "payload-3"))
    |> enqueue_local_task(StealableTask("t4", "plan", 4, 40, "payload-4"))
  let thief = init_work_stealing("thief", 8)
  let #(reserved_thief, request_option) =
    generate_steal_request(thief, "donor", "transfer-2", 1000)
  let assert Some(request) = request_option
  let #(_, response) = handle_steal_request(donor, request, 1000)

  let after_first = apply_steal_response(reserved_thief, response)
  let after_replay = apply_steal_response(after_first, response)

  // Replaying the same transfer must not create duplicate local work.
  total_cluster_queued_tasks(after_replay) |> should.equal(2)
  after_replay.steal_history_count |> should.equal(2)
}

pub fn apply_steal_response_deduplicates_tasks_inside_one_transfer_test() {
  let task = StealableTask("same", "plan", 1, 10, "payload")
  let response =
    StealResponse(
      "donor",
      "thief",
      "transfer-3",
      [task, task],
      0,
      1000,
      TransferAccepted,
    )

  let accepted =
    apply_steal_response(
      reserve_receiver("donor", "thief", "transfer-3"),
      response,
    )

  // One transfer cannot create two local copies of one logical task.
  total_cluster_queued_tasks(accepted) |> should.equal(1)
  accepted.steal_history_count |> should.equal(1)
}

pub fn apply_steal_response_keeps_distinct_plan_task_identities_test() {
  let plan_a = StealableTask("same-id", "plan-a", 1, 10, "a")
  let plan_b = StealableTask("same-id", "plan-b", 1, 10, "b")
  let response =
    StealResponse(
      "donor",
      "thief",
      "transfer-4",
      [plan_a, plan_b, plan_a],
      0,
      1000,
      TransferAccepted,
    )

  let accepted =
    apply_steal_response(
      reserve_receiver("donor", "thief", "transfer-4"),
      response,
    )

  // Same task IDs from different plans remain distinct while the duplicate is rejected.
  total_cluster_queued_tasks(accepted) |> should.equal(2)
  accepted.steal_history_count |> should.equal(2)
}

pub fn apply_steal_response_remains_replay_safe_after_accepted_work_leaves_test() {
  let task = StealableTask("task", "plan", 1, 10, "payload")
  let response =
    StealResponse(
      "donor",
      "thief",
      "transfer-5",
      [task],
      0,
      1000,
      TransferAccepted,
    )
  let first =
    apply_steal_response(
      reserve_receiver("donor", "thief", "transfer-5"),
      response,
    )
  let drained = WorkStealingEngine(..first, local_queue: [])

  let replay = apply_steal_response(drained, response)

  // A receipt remains in the model after the accepted task is completed elsewhere.
  total_cluster_queued_tasks(replay) |> should.equal(0)
  replay.steal_history_count |> should.equal(1)
}

pub fn apply_steal_response_rejects_a_response_for_another_recipient_test() {
  let task = StealableTask("task", "plan", 1, 10, "payload")
  let response =
    StealResponse(
      "donor",
      "other-node",
      "transfer-6",
      [task],
      0,
      1000,
      TransferAccepted,
    )

  let rejected = apply_steal_response(init_work_stealing("thief", 8), response)

  total_cluster_queued_tasks(rejected) |> should.equal(0)
  rejected.steal_history_count |> should.equal(0)
}

pub fn handle_steal_request_replays_its_original_response_test() {
  let donor =
    init_work_stealing("donor", 8)
    |> enqueue_local_task(StealableTask("t1", "plan", 1, 10, "one"))
    |> enqueue_local_task(StealableTask("t2", "plan", 1, 10, "two"))
    |> enqueue_local_task(StealableTask("t3", "plan", 1, 10, "three"))
    |> enqueue_local_task(StealableTask("t4", "plan", 1, 10, "four"))
  let thief = init_work_stealing("thief", 8)
  let #(_, request_option) =
    generate_steal_request(thief, "donor", "transfer-replay", 1000)
  let assert Some(request) = request_option
  let #(after_first, first_response) =
    handle_steal_request(donor, request, 1000)
  let #(after_replay, replayed_response) =
    handle_steal_request(after_first, request, 1001)

  // A duplicate request returns the original response and removes no second batch.
  total_cluster_queued_tasks(after_replay) |> should.equal(2)
  replayed_response |> should.equal(first_response)
}

pub fn handle_steal_request_rejects_a_request_for_another_donor_test() {
  let donor =
    init_work_stealing("donor-a", 8)
    |> enqueue_local_task(StealableTask("t1", "plan", 1, 10, "one"))
    |> enqueue_local_task(StealableTask("t2", "plan", 1, 10, "two"))
  let #(_, request_option) =
    generate_steal_request(
      init_work_stealing("thief", 8),
      "donor-b",
      "wrong-donor",
      1000,
    )
  let assert Some(request) = request_option

  let #(after_request, response) = handle_steal_request(donor, request, 1000)

  total_cluster_queued_tasks(after_request) |> should.equal(2)
  list_len(response.stolen_tasks) |> should.equal(0)
}

pub fn apply_steal_response_bounds_empty_transfer_receipts_test() {
  let accepted = apply_empty_responses(init_work_stealing("thief", 8), 1000)

  // Full receipt state rejects new unique empty transfers instead of growing forever.
  list_len(accepted.accepted_transfers) |> should.equal(256)
}

pub fn apply_steal_response_requires_a_reserved_request_test() {
  let task = StealableTask("task", "plan", 1, 10, "payload")
  let unsolicited =
    StealResponse(
      "donor",
      "thief",
      "unsolicited",
      [task],
      0,
      1000,
      TransferAccepted,
    )

  let rejected =
    apply_steal_response(init_work_stealing("thief", 8), unsolicited)

  // A response cannot make work runnable unless this receiver reserved its transfer.
  total_cluster_queued_tasks(rejected) |> should.equal(0)
  list_len(rejected.accepted_transfers) |> should.equal(0)
}

pub fn full_receiver_does_not_send_a_request_that_can_strand_donor_work_test() {
  let receiver = apply_empty_responses(init_work_stealing("thief", 8), 256)
  let donor = four_task_donor()
  let #(after_request, request) =
    generate_steal_request(receiver, "donor", "full", 1000)

  // With every receipt slot consumed, no donor batch may be removed.
  request |> should.equal(None)
  list_len(after_request.pending_transfers) |> should.equal(0)
  total_cluster_queued_tasks(donor) |> should.equal(4)
}

pub fn receiver_reserves_the_last_slot_before_requesting_a_single_batch_test() {
  let receiver = apply_empty_responses(init_work_stealing("thief", 8), 255)
  let donor = four_task_donor()
  let #(after_first_request, first_option) =
    generate_steal_request(receiver, "donor", "first", 1000)
  let assert Some(first) = first_option
  let #(after_second_request, second) =
    generate_steal_request(after_first_request, "donor", "second", 1001)
  let #(after_first, first_response) = handle_steal_request(donor, first, 1000)
  let after_first_response =
    apply_steal_response(after_first_request, first_response)

  // The receiver can reserve only one final receipt slot, so one donor batch remains runnable.
  second |> should.equal(None)
  list_len(after_second_request.pending_transfers) |> should.equal(1)
  total_cluster_queued_tasks(after_first) |> should.equal(2)
  total_cluster_queued_tasks(after_first_response) |> should.equal(2)
  list_len(after_first_response.pending_transfers) |> should.equal(0)
}

pub fn wrong_donor_rejection_cannot_consume_another_donor_reservation_test() {
  let receiver = init_work_stealing("thief", 8)
  let #(after_a_reservation, a_request_option) =
    generate_steal_request(receiver, "donor-a", "shared-transfer", 1000)
  let assert Some(a_request) = a_request_option
  let #(after_b_reservation, b_request_option) =
    generate_steal_request(
      after_a_reservation,
      "donor-b",
      "shared-transfer",
      1001,
    )
  let assert Some(b_request) = b_request_option
  let donor_a = four_task_donor_for("donor-a")

  // A request for donor-b is misrouted to donor-a and must not acknowledge donor-a.
  let #(after_misroute, rejection) =
    handle_steal_request(donor_a, b_request, 1002)
  let after_rejection = apply_steal_response(after_b_reservation, rejection)
  let #(after_a_response, a_response) =
    handle_steal_request(after_misroute, a_request, 1003)
  let recovered = apply_steal_response(after_rejection, a_response)

  list_len(after_rejection.pending_transfers) |> should.equal(2)
  rejection.status |> should.equal(TransferRejected)
  total_cluster_queued_tasks(after_a_response) |> should.equal(2)
  total_cluster_queued_tasks(recovered) |> should.equal(2)
  list_len(recovered.pending_transfers) |> should.equal(1)
}

fn four_task_donor() -> WorkStealingEngine {
  four_task_donor_for("donor")
}

fn four_task_donor_for(node_id: String) -> WorkStealingEngine {
  init_work_stealing(node_id, 8)
  |> enqueue_local_task(StealableTask("t1", "plan", 1, 10, "one"))
  |> enqueue_local_task(StealableTask("t2", "plan", 1, 10, "two"))
  |> enqueue_local_task(StealableTask("t3", "plan", 1, 10, "three"))
  |> enqueue_local_task(StealableTask("t4", "plan", 1, 10, "four"))
}

fn reserve_receiver(
  donor_node: String,
  recipient_node: String,
  transfer_id: String,
) -> WorkStealingEngine {
  let #(reserved, request) =
    generate_steal_request(
      init_work_stealing(recipient_node, 8),
      donor_node,
      transfer_id,
      1000,
    )
  let assert Some(_) = request
  reserved
}

fn apply_empty_responses(engine, remaining) {
  case remaining {
    0 -> engine
    _ -> {
      let response =
        StealResponse(
          "donor",
          "thief",
          "empty-" <> int.to_string(remaining),
          [],
          0,
          remaining,
          TransferAccepted,
        )
      let #(reserved, request) =
        generate_steal_request(
          engine,
          "donor",
          "empty-" <> int.to_string(remaining),
          remaining,
        )
      case request {
        None -> engine
        Some(_) ->
          apply_empty_responses(
            apply_steal_response(reserved, response),
            remaining - 1,
          )
      }
    }
  }
}

fn list_len(l: List(a)) -> Int {
  case l {
    [] -> 0
    [_, ..rest] -> 1 + list_len(rest)
  }
}
