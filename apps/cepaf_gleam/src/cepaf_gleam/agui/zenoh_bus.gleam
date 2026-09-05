/// A2A Zenoh Agent Bus — agent-to-agent communication over Zenoh pub/sub.
///
/// Topic schema:
///   - `c3i/agui/events/{agent_id}` — per-agent AG-UI event streams
///   - `c3i/a2a/{source}/{target}` — direct agent-to-agent messages
///   - `c3i/a2a/broadcast` — broadcast to all agents
///
/// STAMP: SC-GLM-CORE-001, SC-GLM-CORE-002, SC-GLM-NIF-001
import cepaf_gleam/agui/events
import cepaf_gleam/zenoh/client as zenoh
import gleam/json
import gleam/string

/// Topic prefix for AG-UI events.
const agui_events_prefix = "c3i/agui/events/"

/// Topic prefix for A2A direct messages.
const a2a_prefix = "c3i/a2a/"

/// Topic for broadcast messages to all agents.
const a2a_broadcast_topic = "c3i/a2a/broadcast"

/// Publish an AG-UI event to the Zenoh bus under the agent's event topic.
///
/// Topic: `c3i/agui/events/{agent_id}`
pub fn publish_event(
  session: zenoh.Session,
  agent_id: String,
  event: events.AgUiEvent,
) -> Result(Nil, String) {
  let topic = string.concat([agui_events_prefix, agent_id])
  let payload = json.to_string(events.to_json(event))
  zenoh.put(session, topic, payload)
}

/// Broadcast a state snapshot to all agents on the broadcast topic.
///
/// Topic: `c3i/a2a/broadcast`
pub fn broadcast_state(
  session: zenoh.Session,
  state_json: json.Json,
) -> Result(Nil, String) {
  let payload = json.to_string(state_json)
  zenoh.put(session, a2a_broadcast_topic, payload)
}

/// Send a direct A2A message from one agent to another.
///
/// Topic: `c3i/a2a/{source}/{target}`
pub fn send_to_agent(
  session: zenoh.Session,
  source: String,
  target: String,
  message: json.Json,
) -> Result(Nil, String) {
  let topic = string.concat([a2a_prefix, source, "/", target])
  let payload = json.to_string(message)
  zenoh.put(session, topic, payload)
}
