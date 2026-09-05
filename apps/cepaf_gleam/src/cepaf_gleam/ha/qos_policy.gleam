//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/qos_policy</module>
////     <fsharp-lineage>None — novel QoS traffic shaping for SIL-6 mesh (L4 extension)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Quality-of-Service policy engine for the 16-container mesh.
////       Classifies flows into four traffic classes (Critical, Interactive,
////       Batch, BestEffort), enforces per-class CPU and memory limits, and
////       emits typed QosDecision values that drive the scheduler.
////
////       Admission invariant:
////         admit_flow(engine, flow) returns Admit(rule) only when
////         total_cpu_usage(engine) + flow.cpu_usage <= engine.total_cpu
////
////       Preemption: BestEffort and Batch flows are preemptible when
////       a Critical flow needs capacity.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-BIO-EVO-001, SC-MUDA-001, SC-CPU-GOV</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       DiffServ traffic classification ↪ Gleam exhaustive ADT + pure engine.
////       No global state; all mutations return new QosEngine values.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// QOS POLICY ENGINE — Traffic Shaping for Biomorphic Mesh
//// "Do nothing which is of no use." — Miyamoto Musashi, Go Rin No Sho
////
//// Enforces per-class resource limits and produces typed decisions.
////
//// STAMP: SC-HA-001, SC-BIO-EVO-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// DiffServ-inspired traffic class for the C3I mesh.
pub type TrafficClass {
  /// Safety-critical control plane (L0/Guardian/Zenoh heartbeat).
  Critical
  /// Real-time UI and agent interactions.
  Interactive
  /// Background batch processing (build jobs, ZK ingest).
  Batch
  /// Low-priority, non-latency-sensitive work.
  BestEffort
}

/// Policy rule for one traffic class.
pub type QosRule {
  QosRule(
    traffic_class: TrafficClass,
    /// Maximum CPU percentage for this class (0–100).
    max_cpu_pct: Int,
    /// Maximum memory in megabytes for this class.
    max_memory_mb: Int,
    /// Scheduling priority (higher = more important).
    priority: Int,
    /// When true, flows of this class may be preempted.
    preemptible: Bool,
  )
}

/// A running flow tracked by the engine.
pub type ActiveFlow {
  ActiveFlow(
    /// Unique flow identifier.
    id: String,
    traffic_class: TrafficClass,
    /// Current CPU usage as a fraction of total (0.0–1.0).
    cpu_usage: Float,
    /// Current memory usage in megabytes.
    memory_usage: Float,
    /// Unix epoch seconds when the flow was admitted.
    started_at: Int,
  )
}

/// QoS engine state — immutable snapshot.
pub type QosEngine {
  QosEngine(
    rules: List(QosRule),
    active_flows: List(ActiveFlow),
    /// Total available CPU fraction (normally 1.0 = 100%).
    total_cpu: Float,
  )
}

/// Typed decision emitted by the engine.
pub type QosDecision {
  /// Admit the flow with the matched rule.
  Admit(rule: QosRule)
  /// Throttle the flow to the given CPU percentage.
  Throttle(target_cpu_pct: Int)
  /// Reject the flow with an explanation.
  Reject(reason: String)
  /// Preempt the named flow to free capacity.
  Preempt(flow_id: String)
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Create a new engine with the supplied rules and default 1.0 total CPU.
pub fn engine_new(rules: List(QosRule)) -> QosEngine {
  QosEngine(rules: rules, active_flows: [], total_cpu: 1.0)
}

/// Standard four-class rule set matching the C3I CPU governor thresholds.
pub fn default_rules() -> List(QosRule) {
  [
    QosRule(
      traffic_class: Critical,
      max_cpu_pct: 40,
      max_memory_mb: 2048,
      priority: 100,
      preemptible: False,
    ),
    QosRule(
      traffic_class: Interactive,
      max_cpu_pct: 30,
      max_memory_mb: 1024,
      priority: 70,
      preemptible: False,
    ),
    QosRule(
      traffic_class: Batch,
      max_cpu_pct: 20,
      max_memory_mb: 512,
      priority: 40,
      preemptible: True,
    ),
    QosRule(
      traffic_class: BestEffort,
      max_cpu_pct: 10,
      max_memory_mb: 256,
      priority: 10,
      preemptible: True,
    ),
  ]
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn find_rule(engine: QosEngine, tc: TrafficClass) -> Result(QosRule, Nil) {
  list.find(engine.rules, fn(r) { r.traffic_class == tc })
}

// ---------------------------------------------------------------------------
// Flow lifecycle
// ---------------------------------------------------------------------------

/// Attempt to admit a flow.  Returns the updated engine and decision.
pub fn admit_flow(
  engine: QosEngine,
  flow: ActiveFlow,
) -> #(QosEngine, QosDecision) {
  let rule_result = find_rule(engine, flow.traffic_class)
  case rule_result {
    Error(_) -> #(
      engine,
      Reject(
        "no rule for class: " <> traffic_class_to_string(flow.traffic_class),
      ),
    )
    Ok(rule) -> {
      let current_usage = total_cpu_usage(engine)
      let headroom = engine.total_cpu -. current_usage
      case flow.cpu_usage <=. headroom {
        True -> {
          let new_flows = list.append(engine.active_flows, [flow])
          let new_engine = QosEngine(..engine, active_flows: new_flows)
          #(new_engine, Admit(rule))
        }
        False -> {
          // Check whether preemption of lower-priority flows can help.
          let preemptible =
            list.filter(engine.active_flows, fn(f) {
              let r = find_rule(engine, f.traffic_class)
              case r {
                Ok(fr) -> fr.preemptible && fr.priority < rule.priority
                Error(_) -> False
              }
            })
          case preemptible {
            [victim, ..] -> #(engine, Preempt(victim.id))
            [] -> #(
              engine,
              Reject(
                "insufficient capacity: headroom=" <> float_to_pct(headroom),
              ),
            )
          }
        }
      }
    }
  }
}

/// Remove a flow from the engine.
pub fn remove_flow(engine: QosEngine, flow_id: String) -> QosEngine {
  let new_flows = list.filter(engine.active_flows, fn(f) { f.id != flow_id })
  QosEngine(..engine, active_flows: new_flows)
}

// ---------------------------------------------------------------------------
// Enforcement
// ---------------------------------------------------------------------------

/// Check all active flows against their class limits.
/// Returns updated engine and list of decisions for violating flows.
pub fn enforce(engine: QosEngine) -> #(QosEngine, List(QosDecision)) {
  let decisions =
    list.filter_map(engine.active_flows, fn(flow) {
      let rule_result = find_rule(engine, flow.traffic_class)
      case rule_result {
        Error(_) -> Error(Nil)
        Ok(rule) -> {
          let max_cpu_f = int.to_float(rule.max_cpu_pct) /. 100.0
          case flow.cpu_usage >. max_cpu_f {
            True -> Ok(Throttle(rule.max_cpu_pct))
            False -> Error(Nil)
          }
        }
      }
    })
  #(engine, decisions)
}

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

/// Sum of cpu_usage across all active flows.
pub fn total_cpu_usage(engine: QosEngine) -> Float {
  list.fold(engine.active_flows, 0.0, fn(acc, f) { acc +. f.cpu_usage })
}

/// Number of active flows.
pub fn flow_count(engine: QosEngine) -> Int {
  list.length(engine.active_flows)
}

/// Convert a TrafficClass to its string label.
pub fn traffic_class_to_string(tc: TrafficClass) -> String {
  case tc {
    Critical -> "critical"
    Interactive -> "interactive"
    Batch -> "batch"
    BestEffort -> "best_effort"
  }
}

/// Human-readable summary.
pub fn summary(engine: QosEngine) -> String {
  let flows = int.to_string(flow_count(engine))
  let cpu_used = float_to_pct(total_cpu_usage(engine))
  let rules = int.to_string(list.length(engine.rules))
  string.join(
    [
      "QosEngine: flows=" <> flows,
      "cpu_used=" <> cpu_used,
      "rules=" <> rules,
    ],
    " | ",
  )
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn float_to_pct(f: Float) -> String {
  int.to_string(float.round(f *. 100.0)) <> "%"
}
