//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Decentralized Work-Stealing Swarm Mesh Verification
//// =============================================================================

import cepaf_gleam/ha/work_stealing.{
  HeaviestQueueFirst, LyapunovDivergentFirst, NodeQueueState, RandomVictim,
  StealResponse, StealableTask, WorkStealingEngine, apply_steal_response,
  enqueue_local_task, generate_steal_request, handle_steal_request,
  init_work_stealing, select_victim_node, should_initiate_steal,
  total_cluster_queued_tasks, update_peer_queue,
}
import gleam/option.{Some}
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

  let steal_req =
    generate_steal_request(thief_engine, "vm-1", "transfer-1", 1000)
  let #(updated_donor, steal_resp) =
    handle_steal_request(donor_engine, steal_req, 1000)

  // Half of donor queue stolen (4 / 2 = 2 tasks)
  list_len(steal_resp.stolen_tasks) |> should.equal(2)
  total_cluster_queued_tasks(updated_donor) |> should.equal(2)

  // Thief adopts the tasks
  let updated_thief = apply_steal_response(thief_engine, steal_resp)
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
  let request = generate_steal_request(thief, "donor", "transfer-2", 1000)
  let #(_, response) = handle_steal_request(donor, request, 1000)

  let after_first = apply_steal_response(thief, response)
  let after_replay = apply_steal_response(after_first, response)

  // Replaying the same transfer must not create duplicate local work.
  total_cluster_queued_tasks(after_replay) |> should.equal(2)
  after_replay.steal_history_count |> should.equal(2)
}

pub fn apply_steal_response_deduplicates_tasks_inside_one_transfer_test() {
  let task = StealableTask("same", "plan", 1, 10, "payload")
  let response =
    StealResponse("donor", "thief", "transfer-3", [task, task], 0, 1000)

  let accepted = apply_steal_response(init_work_stealing("thief", 8), response)

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
    )

  let accepted = apply_steal_response(init_work_stealing("thief", 8), response)

  // Same task IDs from different plans remain distinct while the duplicate is rejected.
  total_cluster_queued_tasks(accepted) |> should.equal(2)
  accepted.steal_history_count |> should.equal(2)
}

pub fn apply_steal_response_remains_replay_safe_after_accepted_work_leaves_test() {
  let task = StealableTask("task", "plan", 1, 10, "payload")
  let response = StealResponse("donor", "thief", "transfer-5", [task], 0, 1000)
  let first = apply_steal_response(init_work_stealing("thief", 8), response)
  let drained = WorkStealingEngine(..first, local_queue: [])

  let replay = apply_steal_response(drained, response)

  // A receipt remains in the model after the accepted task is completed elsewhere.
  total_cluster_queued_tasks(replay) |> should.equal(0)
  replay.steal_history_count |> should.equal(1)
}

pub fn apply_steal_response_rejects_a_response_for_another_recipient_test() {
  let task = StealableTask("task", "plan", 1, 10, "payload")
  let response =
    StealResponse("donor", "other-node", "transfer-6", [task], 0, 1000)

  let rejected = apply_steal_response(init_work_stealing("thief", 8), response)

  total_cluster_queued_tasks(rejected) |> should.equal(0)
  rejected.steal_history_count |> should.equal(0)
}

fn list_len(l: List(a)) -> Int {
  case l {
    [] -> 0
    [_, ..rest] -> 1 + list_len(rest)
  }
}
