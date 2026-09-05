//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/zettelkasten/rules</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-IKE-002, SC-IKE-003, SC-SMRITI-032</stamp-controls></compliance>
//// </c3i-module>
////
//// Knowledge-aware RETE-UL rules for Zettelkasten health.
//// §3.7 of the metacognition vision — proactive knowledge monitoring.
//// STAMP: SC-IKE-002 (entropy gating), SC-IKE-003 (drift detection)

import cepaf_gleam/zettelkasten/entropy
import cepaf_gleam/zettelkasten/linker
import cepaf_gleam/zettelkasten/metrics
import cepaf_gleam/zettelkasten/types.{type Holon, type HolonEdge}
import gleam/list

/// Knowledge rule evaluation result.
pub type KnowledgeAlert {
  StaleArchitecture(title: String, entropy: Float, days_since_update: Int)
  OrphanedConstraint(stamp_ref: String)
  KnowledgeGap(topic: String, miss_count: Int)
  IncidentRecurrence(current_signature: String, past_incident_title: String)
  DriftDetected(module_name: String, spec_name: String, days_drift: Int)
  RotCountExceeded(rotting_count: Int, total_count: Int, pct: Float)
  LowDensity(density: Float, threshold: Float)
  OrphanSurge(orphan_count: Int, total_count: Int)
}

/// Alert severity for prioritization.
pub type AlertSeverity {
  Critical
  High
  Medium
  Low
}

/// Evaluate all knowledge health rules against current graph state.
pub fn evaluate_knowledge(
  holons: List(Holon),
  edges: List(HolonEdge),
) -> List(#(KnowledgeAlert, AlertSeverity)) {
  let m = metrics.compute(holons, edges)
  let alerts = []

  // Rule 1: StaleArchitecture — ecosystem docs with entropy > 0.7
  let stale_alerts =
    holons
    |> list.filter(fn(h) { h.level == types.Ecosystem && entropy.is_rotting(h) })
    |> list.map(fn(h) {
      #(
        StaleArchitecture(
          title: h.title,
          entropy: h.entropy,
          days_since_update: 0,
        ),
        High,
      )
    })

  // Rule 2: OrphanedConstraint — constraint zettels with no inbound code edges
  let constraint_holons =
    list.filter(holons, fn(h) {
      h.rhetorical == types.Axiom && h.stamp_refs != []
    })
  let orphaned_constraints =
    constraint_holons
    |> list.filter(fn(h) { linker.edge_count_for(h.uuid, edges) == 0 })
    |> list.flat_map(fn(h) {
      list.map(h.stamp_refs, fn(ref) {
        #(OrphanedConstraint(stamp_ref: ref), Medium)
      })
    })

  // Rule 3: RotCountExceeded — more than 30% of holons rotting
  let rot_alerts = case m.total_holons > 0 {
    True -> {
      let rot_pct =
        int_to_float(m.rotting_count + m.excluded_count)
        /. int_to_float(m.total_holons)
      case rot_pct >. 0.3 {
        True -> [
          #(
            RotCountExceeded(
              rotting_count: m.rotting_count + m.excluded_count,
              total_count: m.total_holons,
              pct: rot_pct,
            ),
            Critical,
          ),
        ]
        False -> []
      }
    }
    False -> []
  }

  // Rule 4: LowDensity — graph density below 0.01 (sparse, poorly connected)
  let density_alerts = case m.total_holons > 10 && m.density <. 0.01 {
    True -> [#(LowDensity(density: m.density, threshold: 0.01), Medium)]
    False -> []
  }

  // Rule 5: OrphanSurge — more than 20% orphaned holons
  let orphan_alerts = case m.total_holons > 10 {
    True -> {
      let orphan_pct =
        int_to_float(m.orphan_count) /. int_to_float(m.total_holons)
      case orphan_pct >. 0.2 {
        True -> [
          #(
            OrphanSurge(
              orphan_count: m.orphan_count,
              total_count: m.total_holons,
            ),
            High,
          ),
        ]
        False -> []
      }
    }
    False -> []
  }

  // Combine all alerts
  list.flatten([
    alerts,
    stale_alerts,
    orphaned_constraints,
    rot_alerts,
    density_alerts,
    orphan_alerts,
  ])
}

/// Check if a current anomaly signature matches any past incident zettel.
pub fn check_incident_recurrence(
  signature: String,
  incident_holons: List(Holon),
) -> List(#(KnowledgeAlert, AlertSeverity)) {
  incident_holons
  |> list.filter(fn(h) { list.any(h.tags, fn(tag) { tag == signature }) })
  |> list.map(fn(h) {
    #(
      IncidentRecurrence(
        current_signature: signature,
        past_incident_title: h.title,
      ),
      High,
    )
  })
}

/// Count alerts by severity.
pub fn count_by_severity(
  alerts: List(#(KnowledgeAlert, AlertSeverity)),
) -> #(Int, Int, Int, Int) {
  let critical = list.filter(alerts, fn(a) { a.1 == Critical }) |> list.length
  let high = list.filter(alerts, fn(a) { a.1 == High }) |> list.length
  let medium = list.filter(alerts, fn(a) { a.1 == Medium }) |> list.length
  let low = list.filter(alerts, fn(a) { a.1 == Low }) |> list.length
  #(critical, high, medium, low)
}

/// Alert severity label.
pub fn severity_label(s: AlertSeverity) -> String {
  case s {
    Critical -> "CRITICAL"
    High -> "HIGH"
    Medium -> "MEDIUM"
    Low -> "LOW"
  }
}

// Helper
fn int_to_float(n: Int) -> Float {
  case n {
    0 -> 0.0
    1 -> 1.0
    _ -> {
      let half = int_to_float(n / 2)
      let rem = case n % 2 {
        0 -> 0.0
        _ -> 1.0
      }
      half +. half +. rem
    }
  }
}
