//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/network_slicing</module>
////     <fsharp-lineage>None — novel Zenoh topic QoS network slicing registry (NET-SLICE-1)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <mesh-domain>
////       Lightweight network slicing registry for the Zenoh backplane (SC-ZMOF-001).
////       Assigns Zenoh topics to named slices with Quality-of-Service policies so
////       that critical control-plane traffic (L0 constitutional, health heartbeats)
////       is isolated from best-effort telemetry.
////
////       Design follows 3GPP-inspired slice model reduced to three reliability tiers:
////         Guaranteed  — control plane, Guardian approval, OTel span upload
////         BestEffort  — telemetry, logs, chat inference results
////         Lossy       — metrics samples, ruliology traces (drop-OK)
////
////       Assignment algorithm:
////         1. Search active slices whose QoS priority >= min_priority.
////         2. Among candidates, pick the slice whose topic list contains a
////            matching prefix, falling back to the highest-priority slice.
////         3. If no slice qualifies, recommend CreateNew with default QoS.
////         4. If min_priority > max available, Reject.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-ZMOF-001, SC-ZMOF-COMMS-001, SC-HA-001, SC-MUDA-001, SC-SIL4-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       3GPP network slice concept ↪ Gleam pure value registry.
////       All state passed by value; no mutable globals; caller owns persistence.
////     </morphism>
////     <morphism type="surjective" loss="no-runtime-qos-enforcement">
////       QoS policies are metadata only — actual Zenoh reliability configuration
////       must be applied by the caller when opening Zenoh sessions.
////       Mitigation: SliceDecision carries all required QoS parameters for the
////       caller to apply via the Zenoh NIF.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// NETWORK SLICING REGISTRY — NET-SLICE-1
//// नायकं प्रकृतिं यान्ति — They return to their own nature (Gita 3.33)
//// Every topic finds its natural slice.
////
//// Priority scale: 0 (lowest) … 100 (highest)
////   90–100: L0 Constitutional — Guardian, emergency stop
////    70–89: L2 Health / quorum — heartbeats, 2oo3 votes
////    50–69: L4 System — container lifecycle, podman events
////    30–49: L5 Cognitive — OODA, MCP, inference results
////    10–29: L1 Telemetry — OTel spans, metrics
////     0–9:  L6/L7 Background — ruliology traces, feed updates
////
//// STAMP: SC-ZMOF-001, SC-ZMOF-COMMS-001, SC-HA-001, SC-MUDA-001

import gleam/int
import gleam/list
import gleam/string

// =============================================================================
// Public types
// =============================================================================

/// Reliability tier for a network slice.
pub type Reliability {
  /// Delivery is guaranteed — use Zenoh reliable mode with retransmission.
  Guaranteed
  /// Best-effort — use Zenoh default (unreliable OK).
  BestEffort
  /// Lossy — samples may be dropped without consequence.
  Lossy
}

/// Quality-of-Service policy attached to a network slice.
pub type QosPolicy {
  QosPolicy(
    /// Descriptive name for this policy (e.g. "control-plane-critical").
    name: String,
    /// Priority 0–100. Higher = served first.
    priority: Int,
    /// Maximum bandwidth in kbps. 0 = unconstrained.
    max_bandwidth_kbps: Int,
    /// Maximum acceptable end-to-end latency in milliseconds. 0 = unconstrained.
    latency_budget_ms: Int,
    /// Delivery reliability tier.
    reliability: Reliability,
  )
}

/// A named network slice mapping Zenoh topics to a QoS policy.
pub type NetworkSlice {
  NetworkSlice(
    /// Unique identifier for this slice (e.g. "control-plane").
    slice_id: String,
    /// List of Zenoh topic prefixes or exact keys assigned to this slice.
    topics: List(String),
    /// QoS policy applied to all traffic on this slice.
    qos: QosPolicy,
    /// Whether this slice is currently accepting new topic assignments.
    active: Bool,
    /// Unix epoch ms when this slice was created.
    created_at: Int,
  )
}

/// Registry of all network slices in the Zenoh backplane.
pub type SliceRegistry {
  SliceRegistry(
    /// All registered slices (active and inactive).
    slices: List(NetworkSlice),
    /// Fallback QoS used when creating a new slice on-demand.
    default_qos: QosPolicy,
  )
}

/// Decision returned by `assign_topic/3`.
pub type SliceDecision {
  /// Assign the topic to an existing slice identified by slice_id.
  Assign(slice_id: String)
  /// No suitable slice exists — create a new one with this QoS.
  CreateNew(qos: QosPolicy)
  /// Assignment is not possible (e.g. min_priority exceeds all available slices).
  Reject(reason: String)
}

// =============================================================================
// Default QoS factory
// =============================================================================

/// Return the system default QoS policy: BestEffort, priority 20.
pub fn default_qos() -> QosPolicy {
  QosPolicy(
    name: "default",
    priority: 20,
    max_bandwidth_kbps: 0,
    latency_budget_ms: 0,
    reliability: BestEffort,
  )
}

/// Pre-built QoS policy for L0 constitutional / Guardian traffic.
pub fn control_plane_qos() -> QosPolicy {
  QosPolicy(
    name: "control-plane-critical",
    priority: 95,
    max_bandwidth_kbps: 1024,
    latency_budget_ms: 50,
    reliability: Guaranteed,
  )
}

/// Pre-built QoS policy for health heartbeat traffic.
pub fn health_qos() -> QosPolicy {
  QosPolicy(
    name: "health-heartbeat",
    priority: 75,
    max_bandwidth_kbps: 512,
    latency_budget_ms: 100,
    reliability: Guaranteed,
  )
}

/// Pre-built QoS policy for telemetry / OTel spans.
pub fn telemetry_qos() -> QosPolicy {
  QosPolicy(
    name: "telemetry-best-effort",
    priority: 15,
    max_bandwidth_kbps: 0,
    latency_budget_ms: 0,
    reliability: BestEffort,
  )
}

// =============================================================================
// Registry construction
// =============================================================================

/// Create an empty slice registry with the default QoS policy.
pub fn registry_new() -> SliceRegistry {
  SliceRegistry(slices: [], default_qos: default_qos())
}

// =============================================================================
// Slice lifecycle
// =============================================================================

/// Register a new slice. If a slice with the same ID already exists it is
/// replaced (idempotent upsert).
pub fn create_slice(
  registry: SliceRegistry,
  slice_id: String,
  topics: List(String),
  qos: QosPolicy,
) -> SliceRegistry {
  let without = list.filter(registry.slices, fn(s) { s.slice_id != slice_id })
  let new_slice =
    NetworkSlice(
      slice_id: slice_id,
      topics: topics,
      qos: qos,
      active: True,
      created_at: 0,
    )
  SliceRegistry(..registry, slices: list.append(without, [new_slice]))
}

/// Activate a slice by ID. No-op if slice does not exist.
pub fn activate_slice(
  registry: SliceRegistry,
  slice_id: String,
) -> SliceRegistry {
  let updated =
    list.map(registry.slices, fn(s) {
      case s.slice_id == slice_id {
        True -> NetworkSlice(..s, active: True)
        False -> s
      }
    })
  SliceRegistry(..registry, slices: updated)
}

/// Deactivate a slice by ID. Deactivated slices remain registered but will
/// not be selected for new topic assignments.
pub fn deactivate_slice(
  registry: SliceRegistry,
  slice_id: String,
) -> SliceRegistry {
  let updated =
    list.map(registry.slices, fn(s) {
      case s.slice_id == slice_id {
        True -> NetworkSlice(..s, active: False)
        False -> s
      }
    })
  SliceRegistry(..registry, slices: updated)
}

// =============================================================================
// Topic assignment
// =============================================================================

/// Assign a Zenoh topic to a slice satisfying min_priority.
///
/// Algorithm:
///   1. Filter to active slices with qos.priority >= min_priority.
///   2. Prefer a slice that already has a topic with a matching prefix.
///   3. Fall back to the highest-priority active slice.
///   4. If no active slice meets min_priority → CreateNew(default_qos).
///   5. If min_priority > 100 → Reject.
pub fn assign_topic(
  registry: SliceRegistry,
  topic: String,
  min_priority: Int,
) -> #(SliceRegistry, SliceDecision) {
  case min_priority > 100 {
    True -> #(
      registry,
      Reject(
        "min_priority=" <> int.to_string(min_priority) <> " exceeds maximum 100",
      ),
    )
    False -> {
      let candidates =
        list.filter(registry.slices, fn(s) {
          s.active && s.qos.priority >= min_priority
        })
      case candidates {
        [] -> #(registry, CreateNew(registry.default_qos))
        _ -> {
          // Prefer a slice that already owns a matching topic prefix
          let with_prefix =
            list.filter(candidates, fn(s) {
              list.any(s.topics, fn(t) {
                string.starts_with(topic, t) || string.starts_with(t, topic)
              })
            })
          let chosen = case with_prefix {
            [first, ..rest] ->
              list.fold(rest, first, fn(best, s) {
                case s.qos.priority > best.qos.priority {
                  True -> s
                  False -> best
                }
              })
            [] ->
              list.fold(
                list.drop(candidates, 1),
                list_head_or_default(candidates),
                fn(best, s) {
                  case s.qos.priority > best.qos.priority {
                    True -> s
                    False -> best
                  }
                },
              )
          }
          // Add the topic to the chosen slice if not already present
          let updated_slices =
            list.map(registry.slices, fn(s) {
              case s.slice_id == chosen.slice_id {
                False -> s
                True ->
                  case list.contains(s.topics, topic) {
                    True -> s
                    False ->
                      NetworkSlice(..s, topics: list.append(s.topics, [topic]))
                  }
              }
            })
          let updated_registry =
            SliceRegistry(..registry, slices: updated_slices)
          #(updated_registry, Assign(chosen.slice_id))
        }
      }
    }
  }
}

// =============================================================================
// Query helpers
// =============================================================================

/// Count of all registered slices (active and inactive).
pub fn slice_count(registry: SliceRegistry) -> Int {
  list.length(registry.slices)
}

/// Return only the active slices.
pub fn active_slices(registry: SliceRegistry) -> List(NetworkSlice) {
  list.filter(registry.slices, fn(s) { s.active })
}

/// Produce a human-readable summary of the registry.
pub fn summary(registry: SliceRegistry) -> String {
  let total = list.length(registry.slices)
  let active = list.length(active_slices(registry))
  let topic_count =
    list.fold(registry.slices, 0, fn(acc, s) { acc + list.length(s.topics) })
  "SliceRegistry(total="
  <> int.to_string(total)
  <> " active="
  <> int.to_string(active)
  <> " topics="
  <> int.to_string(topic_count)
  <> ")"
}

/// Return reliability as a display string.
pub fn reliability_to_string(r: Reliability) -> String {
  case r {
    Guaranteed -> "guaranteed"
    BestEffort -> "best-effort"
    Lossy -> "lossy"
  }
}

// =============================================================================
// Private helpers
// =============================================================================

fn list_head_or_default(items: List(NetworkSlice)) -> NetworkSlice {
  case items {
    [h, ..] -> h
    [] ->
      NetworkSlice(
        slice_id: "none",
        topics: [],
        qos: default_qos(),
        active: False,
        created_at: 0,
      )
  }
}
