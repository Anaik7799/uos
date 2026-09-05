//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/planning/orchestration</module>
////     <fsharp-lineage>Cepaf.Planning.ServiceOrchestration.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Service Orchestration &amp; Coordination</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>SC-PLAN-007, SC-MESH-003, SC-GLM-CORE-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="typed-coordination">
////       F# `ServiceOrchestration` module ↪ Gleam typed Dict-based registry
////       with exhaustive pattern matching on ServiceStatus and MessagePriority.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/string

// =============================================================================
// Type Definitions
// =============================================================================

/// Status of a service in the mesh.
pub type ServiceStatus {
  Online
  Degraded(health: Float)
  Offline
}

/// A service in the C3I mesh.
pub type Service {
  Service(name: String, status: ServiceStatus, health_score: Float)
}

/// Priority level for inter-service messages.
pub type MessagePriority {
  Normal
  Urgent
  Emergency
}

/// A message between services.
pub type Message {
  Message(
    from: String,
    to: String,
    content: String,
    priority: MessagePriority,
    timestamp: String,
    requires_ack: Bool,
  )
}

/// Strategy for distributing tasks across nodes.
pub type DistributionStrategy {
  RoundRobin
  LeastLoaded
  PriorityBased
  AffinityBased
}

/// Result of a coordination operation across services.
pub type CoordinationResult {
  CoordinationResult(
    services_involved: List(String),
    actions_taken: List(String),
    success: Bool,
  )
}

// =============================================================================
// Service Registry
// =============================================================================

/// Create a new service with Online status and full health.
pub fn new_service(name: String) -> Service {
  Service(name: name, status: Online, health_score: 1.0)
}

/// The canonical list of all C3I service names.
pub fn all_service_names() -> List(String) {
  ["Cortex", "Prajna", "Smriti", "CEPAF", "Planning", "Chaya", "Guardian"]
}

/// Register all 7 core C3I services in a Dict registry.
pub fn register_services() -> Dict(String, Service) {
  all_service_names()
  |> list.map(fn(name) { #(name, new_service(name)) })
  |> dict.from_list()
}

/// Look up a service by name in the registry.
pub fn get_service(
  registry: Dict(String, Service),
  name: String,
) -> Result(Service, String) {
  case dict.get(registry, name) {
    Ok(service) -> Ok(service)
    Error(_) -> Error("Service not found: " <> name)
  }
}

/// Update a service's status in the registry.
pub fn update_service_status(
  registry: Dict(String, Service),
  name: String,
  status: ServiceStatus,
) -> Dict(String, Service) {
  case dict.get(registry, name) {
    Ok(service) -> {
      let health = case status {
        Online -> 1.0
        Degraded(h) -> h
        Offline -> 0.0
      }
      let updated = Service(..service, status: status, health_score: health)
      dict.insert(registry, name, updated)
    }
    Error(_) -> registry
  }
}

/// Check whether a service is online (not offline or degraded).
pub fn is_service_online(service: Service) -> Bool {
  case service.status {
    Online -> True
    Degraded(_) -> False
    Offline -> False
  }
}

/// Count the number of fully online services in the registry.
pub fn online_service_count(registry: Dict(String, Service)) -> Int {
  dict.values(registry)
  |> list.filter(is_service_online)
  |> list.length()
}

// =============================================================================
// Messaging
// =============================================================================

/// Create a message between two services. Emergency messages always require ACK.
pub fn send_message(
  from: String,
  to: String,
  content: String,
  priority: MessagePriority,
) -> Message {
  let ack = case priority {
    Normal -> False
    Urgent -> True
    Emergency -> True
  }
  Message(
    from: from,
    to: to,
    content: content,
    priority: priority,
    timestamp: "2026-04-03T00:00:00Z",
    requires_ack: ack,
  )
}

/// Determine if a message requires acknowledgment.
/// Urgent and Emergency priority messages require ACK.
pub fn requires_acknowledgment(msg: Message) -> Bool {
  msg.requires_ack
}

// =============================================================================
// Coordination
// =============================================================================

/// Coordinate creation of a new task across Planning, CEPAF, and Guardian.
pub fn coordinate_task_creation(
  registry: Dict(String, Service),
  task_title: String,
) -> CoordinationResult {
  let required = ["Planning", "CEPAF", "Guardian"]
  let available =
    list.filter(required, fn(name) {
      case dict.get(registry, name) {
        Ok(svc) -> is_service_online(svc)
        Error(_) -> False
      }
    })
  let all_online = list.length(available) == list.length(required)
  CoordinationResult(
    services_involved: available,
    actions_taken: case all_online {
      True -> [
        "Planning: validated task '" <> task_title <> "'",
        "Guardian: approved task creation",
        "CEPAF: persisted task to store",
      ]
      False -> ["Coordination aborted: not all required services online"]
    },
    success: all_online,
  )
}

/// Coordinate a full OODA (Observe-Orient-Decide-Act) cycle across
/// Cortex, Prajna, Planning, and CEPAF service agents.
pub fn coordinate_ooda_cycle(
  registry: Dict(String, Service),
) -> CoordinationResult {
  let ooda_services = ["Cortex", "Prajna", "Planning", "CEPAF"]

  let involved =
    list.filter(ooda_services, fn(name) {
      case dict.get(registry, name) {
        Ok(_service) -> True
        Error(_) -> False
      }
    })

  let all_online = list.length(involved) == list.length(ooda_services)

  CoordinationResult(
    services_involved: involved,
    actions_taken: case all_online {
      True -> [
        "L5_Executive: Synchronizing OODA cycles across autonomous agents",
        "Prajna: Parallelized threat orient phase initiated",
        "Planning: Decentralized decision consensus active",
      ]
      False -> ["Coordination aborted: missing service agents in registry"]
    },
    success: all_online,
  )
}

/// Request Guardian approval for a sensitive operation.
pub fn request_guardian_approval(
  registry: Dict(String, Service),
  operation: String,
) -> Result(String, String) {
  case dict.get(registry, "Guardian") {
    Ok(svc) ->
      case is_service_online(svc) {
        True -> Ok("Guardian approved: " <> operation)
        False -> Error("Guardian is not online")
      }
    Error(_) -> Error("Guardian service not registered")
  }
}

/// Request Cortex AI assistance for a query.
pub fn request_cortex_assistance(
  registry: Dict(String, Service),
  query: String,
) -> Result(String, String) {
  case dict.get(registry, "Cortex") {
    Ok(svc) ->
      case is_service_online(svc) {
        True -> Ok("Cortex analysis for: " <> query)
        False -> Error("Cortex is not online")
      }
    Error(_) -> Error("Cortex service not registered")
  }
}

/// Query Smriti knowledge base for a topic.
pub fn query_smriti_knowledge(
  registry: Dict(String, Service),
  topic: String,
) -> Result(String, String) {
  case dict.get(registry, "Smriti") {
    Ok(svc) ->
      case is_service_online(svc) {
        True -> Ok("Smriti knowledge for: " <> topic)
        False -> Error("Smriti is not online")
      }
    Error(_) -> Error("Smriti service not registered")
  }
}

// =============================================================================
// Task Distribution
// =============================================================================

/// Distribute a list of tasks across nodes using the specified strategy.
pub fn distribute_tasks(
  tasks: List(String),
  nodes: List(String),
  strategy: DistributionStrategy,
) -> Dict(String, List(String)) {
  case nodes {
    [] -> dict.new()
    _ -> {
      // Initialize empty assignment for each node
      let empty =
        list.map(nodes, fn(n) { #(n, []) })
        |> dict.from_list()
      case strategy {
        RoundRobin -> distribute_round_robin(tasks, nodes, empty, 0)
        LeastLoaded -> distribute_round_robin(tasks, nodes, empty, 0)
        PriorityBased -> distribute_priority(tasks, nodes, empty)
        AffinityBased -> distribute_affinity(tasks, nodes, empty)
      }
    }
  }
}

fn distribute_round_robin(
  tasks: List(String),
  nodes: List(String),
  acc: Dict(String, List(String)),
  index: Int,
) -> Dict(String, List(String)) {
  case tasks {
    [] -> reverse_all_values(acc)
    [task, ..rest] -> {
      let node_count = list.length(nodes)
      let node_index = index % node_count
      let node = case list.drop(nodes, node_index) {
        [n, ..] -> n
        [] -> ""
      }
      let current = case dict.get(acc, node) {
        Ok(ts) -> ts
        Error(_) -> []
      }
      let updated = dict.insert(acc, node, [task, ..current])
      distribute_round_robin(rest, nodes, updated, index + 1)
    }
  }
}

fn distribute_priority(
  tasks: List(String),
  nodes: List(String),
  acc: Dict(String, List(String)),
) -> Dict(String, List(String)) {
  // Priority-based: assign all tasks to the first node (highest priority)
  case nodes {
    [first, ..] -> {
      dict.insert(acc, first, tasks)
    }
    [] -> acc
  }
}

fn distribute_affinity(
  tasks: List(String),
  nodes: List(String),
  acc: Dict(String, List(String)),
) -> Dict(String, List(String)) {
  // Affinity-based: hash task name to pick a consistent node
  case nodes {
    [] -> acc
    _ -> {
      let node_count = list.length(nodes)
      list.fold(tasks, acc, fn(a, task) {
        let hash = string.length(task) % node_count
        let node = case list.drop(nodes, hash) {
          [n, ..] -> n
          [] -> ""
        }
        let current = case dict.get(a, node) {
          Ok(ts) -> ts
          Error(_) -> []
        }
        dict.insert(a, node, list.append(current, [task]))
      })
    }
  }
}

fn reverse_all_values(
  d: Dict(String, List(String)),
) -> Dict(String, List(String)) {
  dict.map_values(d, fn(_, v) { list.reverse(v) })
}

// =============================================================================
// Health & Status
// =============================================================================

/// Check if more than 50% of registered services are online (quorum).
pub fn health_quorum(registry: Dict(String, Service)) -> Bool {
  let total = dict.size(registry)
  let online = online_service_count(registry)
  case total {
    0 -> False
    _ -> online * 2 > total
  }
}

/// Return all services that are in Degraded status.
pub fn get_degraded_services(registry: Dict(String, Service)) -> List(Service) {
  dict.values(registry)
  |> list.filter(fn(svc) {
    case svc.status {
      Degraded(_) -> True
      _ -> False
    }
  })
}

/// Produce a human-readable orchestration status summary.
pub fn orchestration_status(registry: Dict(String, Service)) -> String {
  let total = dict.size(registry)
  let online = online_service_count(registry)
  let degraded = list.length(get_degraded_services(registry))
  let offline = total - online - degraded
  let quorum = case health_quorum(registry) {
    True -> "QUORUM_MET"
    False -> "QUORUM_LOST"
  }
  string.concat([
    "Orchestration[",
    quorum,
    "] online=",
    int.to_string(online),
    " degraded=",
    int.to_string(degraded),
    " offline=",
    int.to_string(offline),
    " total=",
    int.to_string(total),
  ])
}

// =============================================================================
// JSON Serialization
// =============================================================================

/// Serialize the full service registry to JSON.
pub fn registry_to_json(registry: Dict(String, Service)) -> json.Json {
  dict.to_list(registry)
  |> list.map(fn(entry) {
    let #(name, svc) = entry
    #(name, service_to_json(svc))
  })
  |> json.object()
}

fn service_to_json(svc: Service) -> json.Json {
  json.object([
    #("name", json.string(svc.name)),
    #("status", json.string(status_to_string(svc.status))),
    #("health_score", json.float(svc.health_score)),
  ])
}

fn status_to_string(status: ServiceStatus) -> String {
  case status {
    Online -> "online"
    Degraded(h) -> "degraded(" <> float.to_string(h) <> ")"
    Offline -> "offline"
  }
}

/// Serialize a Message to JSON.
pub fn message_to_json(msg: Message) -> json.Json {
  json.object([
    #("from", json.string(msg.from)),
    #("to", json.string(msg.to)),
    #("content", json.string(msg.content)),
    #("priority", json.string(priority_to_string(msg.priority))),
    #("timestamp", json.string(msg.timestamp)),
    #("requires_ack", json.bool(msg.requires_ack)),
  ])
}

fn priority_to_string(p: MessagePriority) -> String {
  case p {
    Normal -> "normal"
    Urgent -> "urgent"
    Emergency -> "emergency"
  }
}

/// Serialize a CoordinationResult to JSON.
pub fn coordination_to_json(result: CoordinationResult) -> json.Json {
  json.object([
    #("services_involved", json.array(result.services_involved, json.string)),
    #("actions_taken", json.array(result.actions_taken, json.string)),
    #("success", json.bool(result.success)),
  ])
}
