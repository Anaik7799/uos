// STAMP: SC-METABOLIC-001, SC-FUNC-001
// AOR: AOR-METABOLIC-001
// Criticality: Level 1 (CRITICAL) - Foundation
//
// This module defines the core domain entities for metabolic tracking.

import cepaf_gleam/core/ids.{type HolonId}

/// Represents the vital signs of a holon in the Indrajaal mesh.
pub type MetabolicState {
  MetabolicState(
    holon_id: HolonId,
    timestamp: String,
    cpu_usage_percent: Float,
    memory_usage_bytes: Int,
    network_latency_ms: Float,
    tps: Float,
    // Transactions Per Second
    error_rate: Float,
    metabolic_rate: Float,
    // Derived set-point
    health_status: HealthStatus,
  )
}

pub type HealthStatus {
  Optimal
  Stable
  Degraded
  Critical
  Dead
}
