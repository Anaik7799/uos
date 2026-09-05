//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/fractal/l6_ecosystem</module></identity>
////   <fractal-topology><layer>L6_ECOSYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-DIST-001, SC-AGENT-001</stamp-controls></compliance></c3i-module>
////
//// L6 Ecosystem: agent mesh topology, A2A message panel, Zenoh topic tree.

import gleam/json
import gleam/list

/// SC-MUDA-001: bound agent list to prevent unbounded growth.
const max_agents = 50

/// Agent node in the mesh.
pub type AgentNode {
  AgentNode(
    agent_id: String,
    agent_type: String,
    status: AgentStatus,
    health: Float,
    zenoh_topics: List(String),
    last_heartbeat: Int,
  )
}

pub type AgentStatus {
  Online
  Offline
  Degraded
  Quarantined
}

/// A2A message for inter-agent communication.
pub type A2aMessage {
  A2aMessage(
    source: String,
    target: String,
    message_type: String,
    payload: String,
    timestamp: Int,
  )
}

/// Mesh topology state.
pub type MeshState {
  MeshState(
    agents: List(AgentNode),
    messages: List(A2aMessage),
    quorum: Bool,
    max_messages: Int,
  )
}

pub fn initial_mesh() -> MeshState {
  MeshState(agents: [], messages: [], quorum: False, max_messages: 200)
}

pub fn update_agent(state: MeshState, node: AgentNode) -> MeshState {
  let existing =
    list.filter(state.agents, fn(a) { a.agent_id != node.agent_id })
  MeshState(..state, agents: [node, ..existing] |> list.take(max_agents))
}

pub fn remove_agent(state: MeshState, agent_id: String) -> MeshState {
  MeshState(
    ..state,
    agents: list.filter(state.agents, fn(a) { a.agent_id != agent_id }),
  )
}

pub fn add_message(state: MeshState, msg: A2aMessage) -> MeshState {
  let new_msgs = [msg, ..state.messages] |> list.take(state.max_messages)
  MeshState(..state, messages: new_msgs)
}

pub fn online_agents(state: MeshState) -> List(AgentNode) {
  list.filter(state.agents, fn(a) { a.status == Online })
}

pub fn agent_count(state: MeshState) -> Int {
  list.length(state.agents)
}

pub fn online_count(state: MeshState) -> Int {
  list.length(online_agents(state))
}

pub fn set_quorum(state: MeshState, q: Bool) -> MeshState {
  MeshState(..state, quorum: q)
}

pub fn agent_to_json(node: AgentNode) -> json.Json {
  json.object([
    #("agent_id", json.string(node.agent_id)),
    #("type", json.string(node.agent_type)),
    #(
      "status",
      json.string(case node.status {
        Online -> "online"
        Offline -> "offline"
        Degraded -> "degraded"
        Quarantined -> "quarantined"
      }),
    ),
    #("health", json.float(node.health)),
    #("topics", json.array(node.zenoh_topics, json.string)),
  ])
}
