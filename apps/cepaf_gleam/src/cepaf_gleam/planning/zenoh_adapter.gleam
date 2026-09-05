//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/planning/zenoh_adapter</module>
////     <fsharp-lineage>Cepaf.Planning.ZenohEvents.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <mesh-domain>Planning Zenoh Event Publishing</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>SC-ZENOH-001, SC-PLAN-008, SC-GLM-CORE-002</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="graceful-degradation">
////       F# `ZenohEvents.publish*` ↪ Gleam functions using `zenoh/client.put`
////       with graceful fallback when Zenoh session is unavailable.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/zenoh/client as zenoh
import gleam/json
import gleam/string

// =============================================================================
// Constants — Zenoh topic prefixes for planning events
// =============================================================================

const task_prefix = "c3i/planning/tasks/"

const sync_prefix = "c3i/planning/sync/"

// =============================================================================
// Internal Helpers
// =============================================================================

/// Attempt to open a Zenoh session and publish a payload to a topic.
/// Returns Ok(Nil) gracefully if Zenoh is unavailable.
fn try_publish(topic: String, payload: String) -> Result(Nil, String) {
  case zenoh.open("{}") {
    Ok(session) -> zenoh.put(session, topic, payload)
    // Zenoh unavailable — degrade gracefully per SC-GLM-CORE-002
    Error(_) -> Ok(Nil)
  }
}

// =============================================================================
// Task Event Publishers
// =============================================================================

/// Publish a task-created event to Zenoh.
///
/// Topic: `c3i/planning/tasks/{task_id}/created`
pub fn publish_task_created(
  task_id: String,
  title: String,
) -> Result(Nil, String) {
  let topic = string.concat([task_prefix, task_id, "/created"])
  let payload =
    json.object([
      #("event", json.string("task_created")),
      #("task_id", json.string(task_id)),
      #("title", json.string(title)),
    ])
    |> json.to_string()
  try_publish(topic, payload)
}

/// Publish a task-updated event to Zenoh.
///
/// Topic: `c3i/planning/tasks/{task_id}/updated`
pub fn publish_task_updated(
  task_id: String,
  new_status: String,
) -> Result(Nil, String) {
  let topic = string.concat([task_prefix, task_id, "/updated"])
  let payload =
    json.object([
      #("event", json.string("task_updated")),
      #("task_id", json.string(task_id)),
      #("new_status", json.string(new_status)),
    ])
    |> json.to_string()
  try_publish(topic, payload)
}

/// Publish a task-completed event to Zenoh.
///
/// Topic: `c3i/planning/tasks/{task_id}/completed`
pub fn publish_task_completed(task_id: String) -> Result(Nil, String) {
  let topic = string.concat([task_prefix, task_id, "/completed"])
  let payload =
    json.object([
      #("event", json.string("task_completed")),
      #("task_id", json.string(task_id)),
    ])
    |> json.to_string()
  try_publish(topic, payload)
}

// =============================================================================
// Sync Event Publishers
// =============================================================================

/// Publish a sync-started event to Zenoh.
///
/// Topic: `c3i/planning/sync/started`
pub fn publish_sync_started() -> Result(Nil, String) {
  let topic = string.concat([sync_prefix, "started"])
  let payload =
    json.object([
      #("event", json.string("sync_started")),
    ])
    |> json.to_string()
  try_publish(topic, payload)
}

/// Publish a sync-completed event to Zenoh.
///
/// Topic: `c3i/planning/sync/completed`
pub fn publish_sync_completed(success: Bool, errors: Int) -> Result(Nil, String) {
  let topic = string.concat([sync_prefix, "completed"])
  let payload =
    json.object([
      #("event", json.string("sync_completed")),
      #("success", json.bool(success)),
      #("errors", json.int(errors)),
    ])
    |> json.to_string()
  try_publish(topic, payload)
}

// =============================================================================
// Subscription Topic Constants
// =============================================================================

/// Zenoh topic for planning task events.
pub const planning_events_topic = "c3i/planning/events"

/// Zenoh topic for OODA cycle results.
pub const ooda_topic = "c3i/ooda/cycle"

/// Zenoh topic for safety reasoning.
pub const safety_reasoning_topic = "c3i/safety/reasoning"

/// Zenoh topic for enforcer circuit changes.
pub const enforcer_circuit_topic = "c3i/enforcer/circuit"

/// Zenoh topic for AG-UI event streams.
pub fn agui_events_topic(agent_id: String) -> String {
  "c3i/agui/events/" <> agent_id
}

/// All planning-related Zenoh topics for bulk subscription.
pub fn all_planning_topics() -> List(String) {
  [
    planning_events_topic,
    ooda_topic,
    safety_reasoning_topic,
    enforcer_circuit_topic,
  ]
}
