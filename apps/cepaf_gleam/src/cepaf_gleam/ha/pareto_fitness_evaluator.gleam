//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/pareto_fitness_evaluator</module>
////     <lineage>Pure Gleam adaptation of Indrajaal.Adaptation.FitnessEvaluator</lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <layer>L6_ECOSYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-EVO-001, SC-EVO-002, SC-EVO-003, SC-SWARM-003</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// MULTI-OBJECTIVE PARETO FITNESS EVALUATION ENGINE
//// Evaluates system mutation and configuration candidates across 4 fitness dimensions:
//// 1. Latency (lower is better, normalized 0.0 - 1.0)
//// 2. Throughput (higher is better, normalized 0.0 - 1.0)
//// 3. Error Rate (lower is better, normalized 0.0 - 1.0)
//// 4. Resource Efficiency (lower CPU/Mem is better, normalized 0.0 - 1.0)
////
//// Computes the non-dominated Pareto Frontier to guide evolutionary selection.

import gleam/list

// ---------------------------------------------------------------------------
// 1. Domain Types
// ---------------------------------------------------------------------------

pub type FitnessDimensionScores {
  FitnessDimensionScores(
    latency: Float,
    throughput: Float,
    error_rate: Float,
    resource: Float,
  )
}

pub type CandidateEvaluation {
  CandidateEvaluation(
    candidate_id: String,
    name: String,
    raw_latency_ms: Float,
    raw_throughput_ops: Float,
    raw_error_pct: Float,
    raw_cpu_pct: Float,
    scores: FitnessDimensionScores,
    composite_fitness: Float,
    is_pareto_optimal: Bool,
  )
}

pub type FitnessWeights {
  FitnessWeights(
    latency_weight: Float,
    throughput_weight: Float,
    error_weight: Float,
    resource_weight: Float,
  )
}

pub fn default_weights() -> FitnessWeights {
  FitnessWeights(
    latency_weight: 0.30,
    throughput_weight: 0.25,
    error_weight: 0.25,
    resource_weight: 0.20,
  )
}

// ---------------------------------------------------------------------------
// 2. Normalization & Scoring
// ---------------------------------------------------------------------------

/// Normalize latency (ms): optimal <= 20ms (score 1.0), worst >= 500ms (score 0.0)
pub fn normalize_latency(latency_ms: Float) -> Float {
  case True {
    _ if latency_ms <=. 20.0 -> 1.0
    _ if latency_ms >=. 500.0 -> 0.0
    _ -> { 500.0 -. latency_ms } /. 480.0
  }
}

/// Normalize throughput (ops/sec): worst <= 100 (score 0.0), optimal >= 10,000 (score 1.0)
pub fn normalize_throughput(ops_sec: Float) -> Float {
  case True {
    _ if ops_sec >=. 10_000.0 -> 1.0
    _ if ops_sec <=. 100.0 -> 0.0
    _ -> { ops_sec -. 100.0 } /. 9900.0
  }
}

/// Normalize error rate (%): optimal <= 0.01% (score 1.0), worst >= 5.0% (score 0.0)
pub fn normalize_error_rate(error_pct: Float) -> Float {
  case True {
    _ if error_pct <=. 0.01 -> 1.0
    _ if error_pct >=. 5.0 -> 0.0
    _ -> { 5.0 -. error_pct } /. 4.99
  }
}

/// Normalize CPU/Memory usage (%): optimal <= 30% (score 1.0), worst >= 95% (score 0.0)
pub fn normalize_resource(cpu_pct: Float) -> Float {
  case True {
    _ if cpu_pct <=. 30.0 -> 1.0
    _ if cpu_pct >=. 95.0 -> 0.0
    _ -> { 95.0 -. cpu_pct } /. 65.0
  }
}

/// Evaluate a candidate configuration into normalized dimensional and composite scores.
pub fn evaluate_candidate(
  id: String,
  name: String,
  latency_ms: Float,
  throughput_ops: Float,
  error_pct: Float,
  cpu_pct: Float,
  weights: FitnessWeights,
) -> CandidateEvaluation {
  let lat_score = normalize_latency(latency_ms)
  let tput_score = normalize_throughput(throughput_ops)
  let err_score = normalize_error_rate(error_pct)
  let res_score = normalize_resource(cpu_pct)

  let composite =
    { lat_score *. weights.latency_weight }
    +. { tput_score *. weights.throughput_weight }
    +. { err_score *. weights.error_weight }
    +. { res_score *. weights.resource_weight }

  CandidateEvaluation(
    candidate_id: id,
    name: name,
    raw_latency_ms: latency_ms,
    raw_throughput_ops: throughput_ops,
    raw_error_pct: error_pct,
    raw_cpu_pct: cpu_pct,
    scores: FitnessDimensionScores(
      latency: lat_score,
      throughput: tput_score,
      error_rate: err_score,
      resource: res_score,
    ),
    composite_fitness: composite,
    is_pareto_optimal: False,
  )
}

// ---------------------------------------------------------------------------
// 3. Pareto Dominance & Frontier Analysis
// ---------------------------------------------------------------------------

/// Candidate A dominates Candidate B iff:
/// A is >= B in all dimensions, and strictly > B in at least one dimension.
pub fn dominates(a: CandidateEvaluation, b: CandidateEvaluation) -> Bool {
  let sa = a.scores
  let sb = b.scores

  let all_ge =
    sa.latency >=. sb.latency
    && sa.throughput >=. sb.throughput
    && sa.error_rate >=. sb.error_rate
    && sa.resource >=. sb.resource

  let any_gt =
    sa.latency >. sb.latency
    || sa.throughput >. sb.throughput
    || sa.error_rate >. sb.error_rate
    || sa.resource >. sb.resource

  all_ge && any_gt
}

/// Compute the non-dominated Pareto Frontier across a list of candidate evaluations.
pub fn compute_pareto_frontier(
  candidates: List(CandidateEvaluation),
) -> List(CandidateEvaluation) {
  list.map(candidates, fn(c) {
    // c is non-dominated if NO other candidate dominates it
    let is_dominated =
      list.any(candidates, fn(other) {
        other.candidate_id != c.candidate_id && dominates(other, c)
      })

    CandidateEvaluation(..c, is_pareto_optimal: !is_dominated)
  })
}

/// Extract only the non-dominated Pareto-optimal candidates.
pub fn get_pareto_optimal_set(
  candidates: List(CandidateEvaluation),
) -> List(CandidateEvaluation) {
  let evaluated = compute_pareto_frontier(candidates)
  list.filter(evaluated, fn(c) { c.is_pareto_optimal })
}

/// Baseline set of candidate mutations for the UOS biomorphic engine.
pub fn default_evolution_candidates() -> List(CandidateEvaluation) {
  let w = default_weights()
  let c1 =
    evaluate_candidate(
      "cand-01-simd",
      "MAX SIMD Scorer Optimization",
      25.0,
      8500.0,
      0.02,
      48.0,
      w,
    )
  let c2 =
    evaluate_candidate(
      "cand-02-heijunka",
      "Heijunka Leveled Pull Queue",
      40.0,
      9200.0,
      0.01,
      42.0,
      w,
    )
  let c3 =
    evaluate_candidate(
      "cand-03-solo5",
      "Solo5 Sandboxed Isolation",
      65.0,
      4500.0,
      0.005,
      35.0,
      w,
    )
  let c4 =
    evaluate_candidate(
      "cand-04-suboptimal",
      "Unbounded Thread Allocator",
      320.0,
      1200.0,
      2.5,
      92.0,
      w,
    )

  compute_pareto_frontier([c1, c2, c3, c4])
}
