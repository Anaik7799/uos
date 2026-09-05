//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/testing/chaos_injector</module>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-CHAOS-001, SC-SIL4-001, SC-HA-001, SC-VER-001</stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// परित्राणाय साधूनां — For protection of the good (Gita 4.8)
////
//// F10 — Chaos Injection Testing: Netflix/Google chaos engineering pattern.
//// Pure module that generates chaos scenarios for testing system resilience.
////
//// 20+ predefined scenarios across L0-L7 fractal layers expose failure modes
//// before they surface in production. Each scenario maps to a FMEA failure mode
//// in the 16-container SIL-6 Biomorphic Mesh.
////
//// STAMP: SC-CHAOS-001, SC-HA-001, SC-SIL4-001, SC-VER-001

import gleam/int
import gleam/json
import gleam/list
import gleam/string

// =============================================================================
// Public Types
// =============================================================================

/// A single chaos scenario describing what to inject, where, and how severe.
pub type ChaosScenario {
  ChaosScenario(
    name: String,
    description: String,
    layer: String,
    severity: ChaosSeverity,
    injection: ChaosInjection,
  )
}

/// Severity classification mirrors FMEA RPN severity axis (1-10 mapped to 4 tiers).
pub type ChaosSeverity {
  /// Low: cosmetic degradation, no user impact (RPN severity 1-3)
  ChaosLow
  /// Medium: degraded performance, partial function loss (RPN severity 4-6)
  ChaosMedium
  /// High: significant function impairment, SLA breach (RPN severity 7-8)
  ChaosHigh
  /// Critical: safety-relevant failure, Jidoka halt required (RPN severity 9-10)
  ChaosCritical
}

/// The specific failure to inject. Each variant corresponds to a real-world
/// failure mode observed in SIL-6 distributed mesh deployments.
pub type ChaosInjection {
  /// Kill a process by name — mimics OOM kill, signal 9, Podman stop
  KillProcess(target: String)
  /// Partition network between a node and the mesh — split-brain scenario
  NetworkPartition(node: String)
  /// Add artificial latency to all outbound calls — degraded inference tier
  LatencySpike(ms: Int)
  /// Allocate memory until resident set exceeds threshold
  MemoryPressure(mb: Int)
  /// Fill the ephemeral disk layer — SQLite WAL write stall
  DiskFull
  /// Force a NIF crash — tests Erlang crash isolation (SC-NIF-001)
  NifFailure(nif_name: String)
  /// Drop the Zenoh session — mesh telemetry blackout
  ZenohDisconnect
  /// Take enough nodes offline to drop below 2oo3 quorum floor
  QuorumLoss
  /// Serve reads from stale data older than threshold — cache poisoning
  StaleData(age_seconds: Int)
  /// Pin all schedulers at near-capacity — OODA loop SLA breach
  CpuSaturation(percent: Int)
}

// =============================================================================
// Catalogue — 20 predefined scenarios across L0-L7
// =============================================================================

/// Returns the full catalogue of 20+ predefined chaos scenarios.
/// Scenarios span all 8 fractal layers and represent the most impactful
/// failure modes identified by FMEA analysis of the SIL-6 Biomorphic Mesh.
pub fn all_scenarios() -> List(ChaosScenario) {
  [
    // --- L0_CONSTITUTIONAL ---------------------------------------------------
    ChaosScenario(
      name: "guardian-nif-crash",
      description: "Force c3i_nif to crash — tests Erlang VM crash isolation and Guardian fallback path",
      layer: "L0_CONSTITUTIONAL",
      severity: ChaosCritical,
      injection: NifFailure(nif_name: "c3i_nif"),
    ),
    ChaosScenario(
      name: "rule-engine-nif-crash",
      description: "Crash the rule_engine_nif — Guardian validation path must degrade gracefully",
      layer: "L0_CONSTITUTIONAL",
      severity: ChaosCritical,
      injection: NifFailure(nif_name: "rule_engine_nif"),
    ),
    // --- L1_ATOMIC_DEBUG -----------------------------------------------------
    ChaosScenario(
      name: "otel-collector-kill",
      description: "Kill obs-prod OTel collector — system must buffer spans without data loss",
      layer: "L1_ATOMIC_DEBUG",
      severity: ChaosMedium,
      injection: KillProcess(target: "obs-prod"),
    ),
    ChaosScenario(
      name: "telemetry-latency-spike",
      description: "Inject 500ms latency into OTel gRPC (4317) — span publish budget must remain < 100ms",
      layer: "L1_ATOMIC_DEBUG",
      severity: ChaosLow,
      injection: LatencySpike(ms: 500),
    ),
    // --- L2_COMPONENT --------------------------------------------------------
    ChaosScenario(
      name: "wisp-port-saturation",
      description: "Saturate CPU to 95% — Wisp/Mist request handlers must not starve OODA schedulers",
      layer: "L2_COMPONENT",
      severity: ChaosMedium,
      injection: CpuSaturation(percent: 95),
    ),
    ChaosScenario(
      name: "smriti-fts5-stale-index",
      description: "Serve Smriti FTS5 queries from 48h-old index — RAG context drift detection gate",
      layer: "L2_COMPONENT",
      severity: ChaosLow,
      injection: StaleData(age_seconds: 172_800),
    ),
    // --- L3_TRANSACTION ------------------------------------------------------
    ChaosScenario(
      name: "sqlite-wal-disk-full",
      description: "Fill ephemeral disk — SQLite WAL write stalls; Smriti.db CRDT must not corrupt",
      layer: "L3_TRANSACTION",
      severity: ChaosCritical,
      injection: DiskFull,
    ),
    ChaosScenario(
      name: "planning-db-memory-pressure",
      description: "Drive RSS to 1.5 GB — DuckDB analytical queries must OOM-kill gracefully",
      layer: "L3_TRANSACTION",
      severity: ChaosHigh,
      injection: MemoryPressure(mb: 1536),
    ),
    ChaosScenario(
      name: "sa-plan-daemon-kill",
      description: "SIGKILL sa-plan-daemon — ha_election.rs must elect backup within 5s (SC-HA-001)",
      layer: "L3_TRANSACTION",
      severity: ChaosHigh,
      injection: KillProcess(target: "sa-plan-daemon"),
    ),
    // --- L4_SYSTEM -----------------------------------------------------------
    ChaosScenario(
      name: "db-prod-kill",
      description: "Stop db-prod container — Ecto pool must drain and reconnect without data loss",
      layer: "L4_SYSTEM",
      severity: ChaosHigh,
      injection: KillProcess(target: "db-prod"),
    ),
    ChaosScenario(
      name: "podman-socket-kill",
      description: "Kill podman.sock — container lifecycle operations must queue with retry",
      layer: "L4_SYSTEM",
      severity: ChaosHigh,
      injection: KillProcess(target: "podman.sock"),
    ),
    ChaosScenario(
      name: "build-cpu-saturation",
      description: "Saturate CPU to 90% during mix compile — CPU governor must throttle to 6:6 schedulers",
      layer: "L4_SYSTEM",
      severity: ChaosMedium,
      injection: CpuSaturation(percent: 90),
    ),
    // --- L5_COGNITIVE --------------------------------------------------------
    ChaosScenario(
      name: "gemini-latency-spike",
      description: "Inject 12s latency on Gemini Direct — 6-tier cascade must fall through to OpenRouter within SLA",
      layer: "L5_COGNITIVE",
      severity: ChaosMedium,
      injection: LatencySpike(ms: 12_000),
    ),
    ChaosScenario(
      name: "ollama-kill",
      description: "Kill Ollama process — tiers 3/4 down; pipeline tracer must record fallback correctly",
      layer: "L5_COGNITIVE",
      severity: ChaosHigh,
      injection: KillProcess(target: "ollama"),
    ),
    ChaosScenario(
      name: "cortex-memory-pressure",
      description: "Drive cortex container RSS to 2 GB — conversation history sliding window must evict",
      layer: "L5_COGNITIVE",
      severity: ChaosMedium,
      injection: MemoryPressure(mb: 2048),
    ),
    // --- L6_ECOSYSTEM --------------------------------------------------------
    ChaosScenario(
      name: "zenoh-router-kill",
      description: "Kill primary zenoh-router — quorum routers must absorb traffic; mesh telemetry blackout < 5s",
      layer: "L6_ECOSYSTEM",
      severity: ChaosCritical,
      injection: ZenohDisconnect,
    ),
    ChaosScenario(
      name: "zenoh-network-partition",
      description: "Partition zenoh-router-1 from mesh — split-brain detection via SC-SIL4-015 must trigger apoptosis",
      layer: "L6_ECOSYSTEM",
      severity: ChaosCritical,
      injection: NetworkPartition(node: "zenoh-router-1"),
    ),
    ChaosScenario(
      name: "quorum-loss-2-of-3",
      description: "Take 2 quorum routers offline — below floor(N/2)+1; SC-SIL4-011 fence-minority must activate",
      layer: "L6_ECOSYSTEM",
      severity: ChaosCritical,
      injection: QuorumLoss,
    ),
    // --- L7_FEDERATION -------------------------------------------------------
    ChaosScenario(
      name: "gateway-partition",
      description: "Partition Telegram gateway — no-blackhole guarantee must route via GChat fallback",
      layer: "L7_FEDERATION",
      severity: ChaosMedium,
      injection: NetworkPartition(node: "gateway-telegram"),
    ),
    ChaosScenario(
      name: "plan-data-stale-cache",
      description: "Serve sa-plan-daemon semantic cache hits from 25h-old entries — TTL=24h must have expired",
      layer: "L7_FEDERATION",
      severity: ChaosLow,
      injection: StaleData(age_seconds: 90_000),
    ),
    ChaosScenario(
      name: "leader-election-latency",
      description: "Introduce 8s network delay during ha_election leader lease renewal — backup must promote cleanly",
      layer: "L7_FEDERATION",
      severity: ChaosHigh,
      injection: LatencySpike(ms: 8000),
    ),
  ]
}

// =============================================================================
// Query API
// =============================================================================

/// Filter scenarios by fractal layer label (e.g. "L6_ECOSYSTEM").
pub fn scenarios_for_layer(layer: String) -> List(ChaosScenario) {
  list.filter(all_scenarios(), fn(s) { s.layer == layer })
}

/// Filter scenarios by severity level.
pub fn scenarios_for_severity(severity: ChaosSeverity) -> List(ChaosScenario) {
  list.filter(all_scenarios(), fn(s) { s.severity == severity })
}

/// Total number of defined scenarios.
pub fn scenario_count() -> Int {
  list.length(all_scenarios())
}

/// Human-readable single-line description of a scenario.
/// Format: "[SEVERITY] name (layer): description"
pub fn describe(scenario: ChaosScenario) -> String {
  "["
  <> severity_label(scenario.severity)
  <> "] "
  <> scenario.name
  <> " ("
  <> scenario.layer
  <> "): "
  <> scenario.description
}

/// Serialise a list of scenarios to a JSON array string.
/// Uses gleam/json — no raw string concatenation (SC-GLM-UI-003).
pub fn to_json(scenarios: List(ChaosScenario)) -> String {
  json.array(scenarios, scenario_to_json_value)
  |> json.to_string
}

// =============================================================================
// Helpers — Serialisation
// =============================================================================

fn severity_label(severity: ChaosSeverity) -> String {
  case severity {
    ChaosLow -> "LOW"
    ChaosMedium -> "MEDIUM"
    ChaosHigh -> "HIGH"
    ChaosCritical -> "CRITICAL"
  }
}

fn severity_to_int(severity: ChaosSeverity) -> Int {
  case severity {
    ChaosLow -> 1
    ChaosMedium -> 2
    ChaosHigh -> 3
    ChaosCritical -> 4
  }
}

fn injection_type_label(injection: ChaosInjection) -> String {
  case injection {
    KillProcess(_) -> "kill_process"
    NetworkPartition(_) -> "network_partition"
    LatencySpike(_) -> "latency_spike"
    MemoryPressure(_) -> "memory_pressure"
    DiskFull -> "disk_full"
    NifFailure(_) -> "nif_failure"
    ZenohDisconnect -> "zenoh_disconnect"
    QuorumLoss -> "quorum_loss"
    StaleData(_) -> "stale_data"
    CpuSaturation(_) -> "cpu_saturation"
  }
}

fn injection_target(injection: ChaosInjection) -> String {
  case injection {
    KillProcess(target) -> target
    NetworkPartition(node) -> node
    LatencySpike(ms) -> int.to_string(ms) <> "ms"
    MemoryPressure(mb) -> int.to_string(mb) <> "mb"
    DiskFull -> "ephemeral-disk"
    NifFailure(nif_name) -> nif_name
    ZenohDisconnect -> "zenoh-session"
    QuorumLoss -> "quorum-nodes"
    StaleData(age_seconds) -> int.to_string(age_seconds) <> "s"
    CpuSaturation(percent) -> int.to_string(percent) <> "%"
  }
}

fn scenario_to_json_value(scenario: ChaosScenario) -> json.Json {
  json.object([
    #("name", json.string(scenario.name)),
    #("description", json.string(scenario.description)),
    #("layer", json.string(scenario.layer)),
    #("severity", json.string(severity_label(scenario.severity))),
    #("severity_int", json.int(severity_to_int(scenario.severity))),
    #("injection_type", json.string(injection_type_label(scenario.injection))),
    #("injection_target", json.string(injection_target(scenario.injection))),
  ])
}

// =============================================================================
// Analytics
// =============================================================================

/// Count scenarios grouped by severity tier.
/// Returns a list of #(label, count) tuples ordered Critical → Low.
pub fn severity_distribution() -> List(#(String, Int)) {
  let scenarios = all_scenarios()
  [ChaosCritical, ChaosHigh, ChaosMedium, ChaosLow]
  |> list.map(fn(sev) {
    let count = list.length(list.filter(scenarios, fn(s) { s.severity == sev }))
    #(severity_label(sev), count)
  })
}

/// Count scenarios grouped by fractal layer.
pub fn layer_distribution() -> List(#(String, Int)) {
  let scenarios = all_scenarios()
  [
    "L0_CONSTITUTIONAL", "L1_ATOMIC_DEBUG", "L2_COMPONENT", "L3_TRANSACTION",
    "L4_SYSTEM", "L5_COGNITIVE", "L6_ECOSYSTEM", "L7_FEDERATION",
  ]
  |> list.map(fn(layer) {
    let count = list.length(list.filter(scenarios, fn(s) { s.layer == layer }))
    #(layer, count)
  })
}

/// Compute the maximum FMEA RPN severity integer across all scenarios.
/// Used by CI to assert no single-point-of-failure raises RPN above a threshold.
pub fn max_severity_int() -> Int {
  all_scenarios()
  |> list.fold(0, fn(acc, s) {
    let sev = severity_to_int(s.severity)
    case sev > acc {
      True -> sev
      False -> acc
    }
  })
}

/// Filter to only Critical + High scenarios — the set that requires
/// Guardian pre-approval before injection into a live environment (SC-SAFETY-001).
pub fn guardian_required_scenarios() -> List(ChaosScenario) {
  list.filter(all_scenarios(), fn(s) {
    s.severity == ChaosCritical || s.severity == ChaosHigh
  })
}

/// Unique injection types present across all scenarios.
pub fn injection_types() -> List(String) {
  all_scenarios()
  |> list.map(fn(s) { injection_type_label(s.injection) })
  |> list.unique
  |> list.sort(string.compare)
}
