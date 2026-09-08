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
    max_tasks: Int,
    epoch_us: Int,
  )
}

/// Protocol response returning stolen tasks from donor to initiator.
pub type StealResponse {
  StealResponse(
    donor_node: String,
    stolen_tasks: List(StealableTask),
    remaining_queue_depth: Int,
    epoch_us: Int,
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
    list.any(engine.peer_queues, fn(p) {
      list.length(p.queue) > 1
    })
  is_idle && has_no_local_work && has_eligible_peers
}

/// Select the best victim node to steal work from based on strategy.
pub fn select_victim_node(
  engine: WorkStealingEngine,
  strategy: StealStrategy,
) -> Option(String) {
  let candidates =
    list.filter(engine.peer_queues, fn(p) {
      list.length(p.queue) > 1
    })

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
  _victim_node: String,
  now_us: Int,
) -> StealRequest {
  let available_slots = engine.capacity - engine.active_workers
  let max_to_steal = int.max(1, available_slots / 2)
  StealRequest(
    initiator_node: engine.local_node_id,
    max_tasks: max_to_steal,
    epoch_us: now_us,
  )
}

/// Donor handles an incoming steal request and yields up to half its queue.
pub fn handle_steal_request(
  engine: WorkStealingEngine,
  req: StealRequest,
  now_us: Int,
) -> #(WorkStealingEngine, StealResponse) {
  let queue_len = list.length(engine.local_queue)
  
  case queue_len > 1 {
    True -> {
      let steal_quota = int.min(req.max_tasks, queue_len / 2)
      let #(stolen, remaining) = list.split(engine.local_queue, steal_quota)
      let updated_engine =
        WorkStealingEngine(
          ..engine,
          local_queue: remaining,
        )
      let resp =
        StealResponse(
          donor_node: engine.local_node_id,
          stolen_tasks: stolen,
          remaining_queue_depth: list.length(remaining),
          epoch_us: now_us,
        )
      #(updated_engine, resp)
    }
    False -> {
      let resp =
        StealResponse(
          donor_node: engine.local_node_id,
          stolen_tasks: [],
          remaining_queue_depth: queue_len,
          epoch_us: now_us,
        )
      #(engine, resp)
    }
  }
}

/// Apply a steal response by adopting the transferred tasks into local queue.
pub fn apply_steal_response(
  engine: WorkStealingEngine,
  resp: StealResponse,
) -> WorkStealingEngine {
  let count = list.length(resp.stolen_tasks)
  let updated_queue = list.append(engine.local_queue, resp.stolen_tasks)
  WorkStealingEngine(
    ..engine,
    local_queue: updated_queue,
    steal_history_count: engine.steal_history_count + count,
    last_steal_epoch_us: resp.epoch_us,
  )
}

/// Calculate total queued tasks across the entire cluster visible to this engine.
pub fn total_cluster_queued_tasks(engine: WorkStealingEngine) -> Int {
  let local_count = list.length(engine.local_queue)
  let peer_count =
    list.fold(engine.peer_queues, 0, fn(acc, p) {
      acc + list.length(p.queue)
    })
  local_count + peer_count
}
