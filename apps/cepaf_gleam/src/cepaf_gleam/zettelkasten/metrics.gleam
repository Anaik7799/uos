//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/zettelkasten/metrics</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-MATH-001, SC-SMRITI-032</stamp-controls></compliance>
//// </c3i-module>
////
//// Knowledge graph metrics — compound growth, health scoring, coverage analysis.
//// STAMP: SC-MATH-001 (discipline health), SC-SMRITI-032 (continuous health monitoring)

import cepaf_gleam/zettelkasten/types.{
  type Holon, type HolonEdge, Atomic, Ecosystem, Molecular, Organism,
}
import gleam/float
import gleam/list

/// Knowledge graph snapshot for metrics computation.
pub type KnowledgeGraphMetrics {
  KnowledgeGraphMetrics(
    total_holons: Int,
    total_edges: Int,
    fresh_count: Int,
    aging_count: Int,
    rotting_count: Int,
    excluded_count: Int,
    orphan_count: Int,
    avg_entropy: Float,
    avg_trust: Float,
    density: Float,
    level_distribution: LevelDistribution,
  )
}

pub type LevelDistribution {
  LevelDistribution(atomic: Int, molecular: Int, organism: Int, ecosystem: Int)
}

/// Health grade for the knowledge graph.
pub type KnowledgeHealth {
  Thriving
  Healthy
  Aging
  Degraded
  Critical
}

/// Compute metrics for a set of holons and edges.
pub fn compute(
  holons: List(Holon),
  edges: List(HolonEdge),
) -> KnowledgeGraphMetrics {
  let total = list.length(holons)
  let edge_count = list.length(edges)

  let fresh = list.filter(holons, fn(h) { h.entropy <. 0.3 }) |> list.length
  let aging =
    list.filter(holons, fn(h) { h.entropy >=. 0.3 && h.entropy <. 0.7 })
    |> list.length
  let rotting =
    list.filter(holons, fn(h) { h.entropy >=. 0.7 && h.entropy <. 0.9 })
    |> list.length
  let excluded = list.filter(holons, fn(h) { h.entropy >=. 0.9 }) |> list.length

  let holon_ids = list.map(holons, fn(h) { h.uuid })
  let orphans =
    list.filter(holon_ids, fn(id) {
      !list.any(edges, fn(e) { e.source_id == id || e.target_id == id })
    })
    |> list.length

  let avg_e = case total > 0 {
    True ->
      list.fold(holons, 0.0, fn(acc, h) { acc +. h.entropy })
      /. int_to_float(total)
    False -> 0.0
  }

  let avg_t = case total > 0 {
    True ->
      list.fold(holons, 0.0, fn(acc, h) {
        acc +. types.trust_for(h.rhetorical).value *. { 1.0 -. h.entropy }
      })
      /. int_to_float(total)
    False -> 0.0
  }

  let density = case total <= 1 {
    True -> 0.0
    False -> int_to_float(edge_count) /. int_to_float(total * { total - 1 })
  }

  let levels = count_levels(holons)

  KnowledgeGraphMetrics(
    total_holons: total,
    total_edges: edge_count,
    fresh_count: fresh,
    aging_count: aging,
    rotting_count: rotting,
    excluded_count: excluded,
    orphan_count: orphans,
    avg_entropy: avg_e,
    avg_trust: avg_t,
    density: density,
    level_distribution: levels,
  )
}

/// Grade the knowledge graph health.
pub fn health_grade(metrics: KnowledgeGraphMetrics) -> KnowledgeHealth {
  let rotting_pct = case metrics.total_holons > 0 {
    True ->
      int_to_float(metrics.rotting_count + metrics.excluded_count)
      /. int_to_float(metrics.total_holons)
    False -> 0.0
  }
  let orphan_pct = case metrics.total_holons > 0 {
    True ->
      int_to_float(metrics.orphan_count) /. int_to_float(metrics.total_holons)
    False -> 0.0
  }

  case rotting_pct <. 0.05 && orphan_pct <. 0.05 && metrics.avg_trust >. 0.7 {
    True -> Thriving
    False ->
      case
        rotting_pct <. 0.15 && orphan_pct <. 0.15 && metrics.avg_trust >. 0.5
      {
        True -> Healthy
        False ->
          case rotting_pct <. 0.3 {
            True -> Aging
            False ->
              case rotting_pct <. 0.5 {
                True -> Degraded
                False -> Critical
              }
          }
      }
  }
}

/// Health grade label.
pub fn health_label(health: KnowledgeHealth) -> String {
  case health {
    Thriving -> "THRIVING"
    Healthy -> "HEALTHY"
    Aging -> "AGING"
    Degraded -> "DEGRADED"
    Critical -> "CRITICAL"
  }
}

/// Project compound growth at a given monthly rate.
pub fn project_growth(
  current_holons: Int,
  monthly_new: Int,
  edges_per_holon: Float,
  months: Int,
) -> #(Int, Int) {
  case months <= 0 {
    True -> #(
      current_holons,
      float.truncate(int_to_float(current_holons) *. edges_per_holon),
    )
    False -> {
      let new_total = current_holons + monthly_new
      project_growth(new_total, monthly_new, edges_per_holon, months - 1)
    }
  }
}

// Helpers
fn count_levels(holons: List(Holon)) -> LevelDistribution {
  let a = list.filter(holons, fn(h) { h.level == Atomic }) |> list.length
  let m = list.filter(holons, fn(h) { h.level == Molecular }) |> list.length
  let o = list.filter(holons, fn(h) { h.level == Organism }) |> list.length
  let e = list.filter(holons, fn(h) { h.level == Ecosystem }) |> list.length
  LevelDistribution(atomic: a, molecular: m, organism: o, ecosystem: e)
}

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
