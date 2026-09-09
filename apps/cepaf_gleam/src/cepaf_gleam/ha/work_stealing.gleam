//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/work_stealing</module>
////     <fsharp-lineage>N/A — Pure Gleam Decentralized Work-Stealing Swarm Mesh</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <layer>L6_ECOSYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-STEAL-001, SC-SIL6-001, SC-JIDOKA-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="anti-starvation">Underloaded nodes pull from overloaded peers to minimize cluster latency</property>
////     <property name="conservation">Total cluster task count is strictly invariant under work-stealing transfers</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt, Lt}

pub const max_transfer_receipts = 256

/// Strategy for selecting a donor/victim node during work stealing.
pub type StealStrategy {
  RandomVictim
  HeaviestQueueFirst
  LyapunovDivergentFirst
}

/// A stealable task payload representation.
pub type StealableTask {
  StealableTask(
    task_id: String,
    plan_id: String,
    priority: Int,
    estimated_duration_ms: Int,
    payload: String,
  )
}

/// Queue and health status snapshot of a cluster node.
pub type NodeQueueState {
  NodeQueueState(
    node_id: String,
    queue: List(StealableTask),
    active_workers: Int,
    capacity: Int,
    lyapunov_exponent: Float,
  )
}

/// Protocol request sent to initiate work stealing from a peer.
pub type StealRequest {
  StealRequest(
    initiator_node: String,
    donor_node: String,
    transfer_id: String,
    max_tasks: Int,
    epoch_us: Int,
  )
}

/// Protocol response returning stolen tasks from donor to initiator.
pub type StealResponse {
  StealResponse(
    donor_node: String,
    recipient_node: String,
    transfer_id: String,
    stolen_tasks: List(StealableTask),
    remaining_queue_depth: Int,
    epoch_us: Int,
    status: TransferStatus,
  )
}

/// A donor reply is either a transferable batch or a rejection that cannot consume a reservation.
pub type TransferStatus {
  TransferAccepted
  TransferRejected
}

/// Durable-for-model receipt that fences a response to one receiver and transfer.
pub type AcceptedTransfer {
  AcceptedTransfer(
    donor_node: String,
    recipient_node: String,
    transfer_id: String,
  )
}

/// Receiver-side reservation made before asking a donor to remove any work.
pub type PendingTransfer {
  PendingTransfer(
    donor_node: String,
    recipient_node: String,
    transfer_id: String,
  )
}

/// Donor-side replay receipt retaining the first response for one transfer.
pub type HandledTransfer {
  HandledTransfer(
    initiator_node: String,
    transfer_id: String,
    response: StealResponse,
  )
}

/// Decentralized work-stealing engine state.
pub type WorkStealingEngine {
  WorkStealingEngine(
    local_node_id: String,
    local_queue: List(StealableTask),
    active_workers: Int,
    capacity: Int,
    peer_queues: List(NodeQueueState),
    accepted_transfers: List(AcceptedTransfer),
    pending_transfers: List(PendingTransfer),
    handled_transfers: List(HandledTransfer),
    steal_history_count: Int,
    last_steal_epoch_us: Int,
  )
}

/// Initialize the work-stealing engine for a node.
pub fn init_work_stealing(
  local_node_id: String,
  capacity: Int,
) -> WorkStealingEngine {
  WorkStealingEngine(
    local_node_id: local_node_id,
    local_queue: [],
    active_workers: 0,
    capacity: capacity,
    peer_queues: [],
    accepted_transfers: [],
    pending_transfers: [],
    handled_transfers: [],
    steal_history_count: 0,
    last_steal_epoch_us: 0,
  )
}

/// Enqueue a task onto the local work queue.
pub fn enqueue_local_task(
  engine: WorkStealingEngine,
  task: StealableTask,
) -> WorkStealingEngine {
  let updated_queue = [task, ..engine.local_queue]
  WorkStealingEngine(..engine, local_queue: updated_queue)
}

/// Update observed queue telemetry for a remote peer node.
pub fn update_peer_queue(
  engine: WorkStealingEngine,
  peer: NodeQueueState,
) -> WorkStealingEngine {
  let filtered =
    list.filter(engine.peer_queues, fn(p) { p.node_id != peer.node_id })
  WorkStealingEngine(..engine, peer_queues: [peer, ..filtered])
}

/// Determine if the local node has idle capacity and an empty queue.
pub fn should_initiate_steal(engine: WorkStealingEngine) -> Bool {
  let is_idle = engine.active_workers < engine.capacity
  let has_no_local_work = list.is_empty(engine.local_queue)
  let has_eligible_peers =
    list.any(engine.peer_queues, fn(p) { list.length(p.queue) > 1 })
  is_idle && has_no_local_work && has_eligible_peers
}

/// Select the best victim node to steal work from based on strategy.
pub fn select_victim_node(
  engine: WorkStealingEngine,
  strategy: StealStrategy,
) -> Option(String) {
  let candidates =
    list.filter(engine.peer_queues, fn(p) { list.length(p.queue) > 1 })

  case strategy {
    HeaviestQueueFirst -> {
      let sorted =
        list.sort(candidates, fn(a, b) {
          int.compare(list.length(b.queue), list.length(a.queue))
        })
      case sorted {
        [heaviest, ..] -> Some(heaviest.node_id)
        [] -> None
      }
    }
    LyapunovDivergentFirst -> {
      let sorted =
        list.sort(candidates, fn(a, b) {
          case a.lyapunov_exponent >. b.lyapunov_exponent {
            True -> Lt
            False -> Gt
          }
        })
      case sorted {
        [divergent, ..] -> Some(divergent.node_id)
        [] -> None
      }
    }
    RandomVictim -> {
      case candidates {
        [victim, ..] -> Some(victim.node_id)
        [] -> None
      }
    }
  }
}

/// Generate a steal request for a targeted victim.
pub fn generate_steal_request(
  engine: WorkStealingEngine,
  victim_node: String,
  transfer_id: String,
  now_us: Int,
) -> #(WorkStealingEngine, Option(StealRequest)) {
  let available_slots = engine.capacity - engine.active_workers
  let max_to_steal = int.max(1, available_slots / 2)
  let request =
    StealRequest(
      initiator_node: engine.local_node_id,
      donor_node: victim_node,
      transfer_id: transfer_id,
      max_tasks: max_to_steal,
      epoch_us: now_us,
    )
  let pending =
    PendingTransfer(
      donor_node: victim_node,
      recipient_node: engine.local_node_id,
      transfer_id: transfer_id,
    )
  let accepted =
    AcceptedTransfer(
      donor_node: victim_node,
      recipient_node: engine.local_node_id,
      transfer_id: transfer_id,
    )
  case
    has_pending_transfer(engine.pending_transfers, pending)
    || list.any(engine.accepted_transfers, fn(receipt) { receipt == accepted })
  {
    True -> #(engine, Some(request))
    False -> {
      let reserved_count =
        list.length(engine.accepted_transfers)
        + list.length(engine.pending_transfers)
      case reserved_count >= max_transfer_receipts {
        True -> #(engine, None)
        False -> #(
          WorkStealingEngine(..engine, pending_transfers: [
            pending,
            ..engine.pending_transfers
          ]),
          Some(request),
        )
      }
    }
  }
}

/// Donor handles an incoming steal request and yields up to half its queue.
pub fn handle_steal_request(
  engine: WorkStealingEngine,
  req: StealRequest,
  now_us: Int,
) -> #(WorkStealingEngine, StealResponse) {
  case req.donor_node != engine.local_node_id {
    True -> #(engine, rejected_response(engine, req, now_us))
    False -> {
      case find_handled_transfer(engine.handled_transfers, req) {
        Some(response) -> #(engine, response)
        None -> {
          case list.length(engine.handled_transfers) >= max_transfer_receipts {
            True -> #(engine, rejected_response(engine, req, now_us))
            False -> serve_new_request(engine, req, now_us)
          }
        }
      }
    }
  }
}

/// Apply a steal response by adopting the transferred tasks into local queue.
pub fn apply_steal_response(
  engine: WorkStealingEngine,
  resp: StealResponse,
) -> WorkStealingEngine {
  let receipt =
    AcceptedTransfer(resp.donor_node, resp.recipient_node, resp.transfer_id)
  let is_recipient = resp.recipient_node == engine.local_node_id
  let already_accepted =
    list.any(engine.accepted_transfers, fn(accepted) { accepted == receipt })
  let pending =
    PendingTransfer(resp.donor_node, resp.recipient_node, resp.transfer_id)
  let #(has_reservation, remaining_pending) =
    remove_pending_transfer(engine.pending_transfers, pending)
  let receipt_capacity_available =
    list.length(engine.accepted_transfers) < max_transfer_receipts
  case
    is_recipient
    && resp.status == TransferAccepted
    && has_reservation
    && !already_accepted
    && receipt_capacity_available
  {
    False -> engine
    True -> {
      let new_tasks = unseen_tasks(resp.stolen_tasks, engine.local_queue)
      let count = list.length(new_tasks)
      WorkStealingEngine(
        ..engine,
        local_queue: list.append(engine.local_queue, new_tasks),
        accepted_transfers: [receipt, ..engine.accepted_transfers],
        pending_transfers: remaining_pending,
        steal_history_count: engine.steal_history_count + count,
        last_steal_epoch_us: resp.epoch_us,
      )
    }
  }
}

fn has_pending_transfer(
  transfers: List(PendingTransfer),
  pending: PendingTransfer,
) -> Bool {
  list.any(transfers, fn(current) { current == pending })
}

fn remove_pending_transfer(
  transfers: List(PendingTransfer),
  pending: PendingTransfer,
) -> #(Bool, List(PendingTransfer)) {
  case transfers {
    [] -> #(False, [])
    [current, ..remaining] -> {
      case current == pending {
        True -> #(True, remaining)
        False -> {
          let #(removed, retained) = remove_pending_transfer(remaining, pending)
          #(removed, [current, ..retained])
        }
      }
    }
  }
}

fn serve_new_request(
  engine: WorkStealingEngine,
  req: StealRequest,
  now_us: Int,
) -> #(WorkStealingEngine, StealResponse) {
  let queue_len = list.length(engine.local_queue)
  let #(stolen, remaining) = case queue_len > 1 {
    True ->
      list.split(engine.local_queue, int.min(req.max_tasks, queue_len / 2))
    False -> #([], engine.local_queue)
  }
  let response =
    StealResponse(
      donor_node: engine.local_node_id,
      recipient_node: req.initiator_node,
      transfer_id: req.transfer_id,
      stolen_tasks: stolen,
      remaining_queue_depth: list.length(remaining),
      epoch_us: now_us,
      status: TransferAccepted,
    )
  let receipt = HandledTransfer(req.initiator_node, req.transfer_id, response)
  let updated_engine =
    WorkStealingEngine(..engine, local_queue: remaining, handled_transfers: [
      receipt,
      ..engine.handled_transfers
    ])
  #(updated_engine, response)
}

fn rejected_response(
  engine: WorkStealingEngine,
  req: StealRequest,
  now_us: Int,
) -> StealResponse {
  StealResponse(
    donor_node: engine.local_node_id,
    recipient_node: req.initiator_node,
    transfer_id: req.transfer_id,
    stolen_tasks: [],
    remaining_queue_depth: list.length(engine.local_queue),
    epoch_us: now_us,
    status: TransferRejected,
  )
}

fn find_handled_transfer(
  receipts: List(HandledTransfer),
  request: StealRequest,
) -> Option(StealResponse) {
  case receipts {
    [] -> None
    [receipt, ..remaining] -> {
      case
        receipt.initiator_node == request.initiator_node
        && receipt.transfer_id == request.transfer_id
      {
        True -> Some(receipt.response)
        False -> find_handled_transfer(remaining, request)
      }
    }
  }
}

fn unseen_tasks(
  tasks: List(StealableTask),
  known_tasks: List(StealableTask),
) -> List(StealableTask) {
  case tasks {
    [] -> []
    [task, ..remaining] -> {
      case
        list.any(known_tasks, fn(known) { same_task_identity(known, task) })
      {
        True -> unseen_tasks(remaining, known_tasks)
        False -> [task, ..unseen_tasks(remaining, [task, ..known_tasks])]
      }
    }
  }
}

fn same_task_identity(left: StealableTask, right: StealableTask) -> Bool {
  left.plan_id == right.plan_id && left.task_id == right.task_id
}

/// Calculate total queued tasks across the entire cluster visible to this engine.
pub fn total_cluster_queued_tasks(engine: WorkStealingEngine) -> Int {
  let local_count = list.length(engine.local_queue)
  let peer_count =
    list.fold(engine.peer_queues, 0, fn(acc, p) { acc + list.length(p.queue) })
  local_count + peer_count
}
