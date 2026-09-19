//// =============================================================================
//// [C3I-SIL6-MSTS] MULTI-ATTRIBUTE UTILITY THEORY (MAUT) PULL QUEUE SCHEDULER
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/maut_pull_queue</module>
////     <lineage>OpenAI Codex GPT 6 Astra MAUT Scheduler Enforcement</lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Computes 5-attribute utility across candidate tasks (Criticality, STPA,
////       Readiness, FMEA, Impact), evaluates Pareto optimality frontier, issues
////       monotonic lease fencing tokens, and pulls highest-utility tasks into
////       the Heijunka leveled execution stream.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>
////       SC-SIL6-001, SC-JIDOKA-001, SC-SA-PLAN-001, SC-MUDA-001, SC-RISK-PRIORITY-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/list

// -----------------------------------------------------------------------------
// Legacy 4-Attribute Formulation (Maintained for Backward Compatibility)
// -----------------------------------------------------------------------------

pub type UtilityWeights {
  UtilityWeights(
    weight_priority: Float,
    weight_dependency: Float,
    weight_risk: Float,
    weight_cost: Float,
  )
}

pub type CandidateTask {
  CandidateTask(
    task_id: String,
    plan_id: String,
    priority: Float,
    dependency_readiness: Float,
    fmea_risk: Float,
    resource_cost: Float,
    required_affinity: String,
  )
}

pub type ScoredTask {
  ScoredTask(
    task: CandidateTask,
    utility_score: Float,
    is_pareto_optimal: Bool,
  )
}

pub fn default_weights() -> UtilityWeights {
  UtilityWeights(
    weight_priority: 0.40,
    weight_dependency: 0.30,
    weight_risk: 0.20,
    weight_cost: 0.10,
  )
}

pub fn compute_utility(task: CandidateTask, weights: UtilityWeights) -> Float {
  case task.dependency_readiness <=. 0.0 {
    True -> 0.0
    False -> {
      let positive_component =
        { task.priority *. weights.weight_priority }
        +. { task.dependency_readiness *. weights.weight_dependency }
      let penalty_component =
        { task.fmea_risk *. weights.weight_risk }
        +. { task.resource_cost *. weights.weight_cost }
      let raw_utility = positive_component -. penalty_component
      case raw_utility <. 0.0 {
        True -> 0.0
        False -> raw_utility
      }
    }
  }
}

pub fn score_candidate_queue(
  candidates: List(CandidateTask),
  weights: UtilityWeights,
) -> List(ScoredTask) {
  let scored =
    list.map(candidates, fn(task) {
      let score = compute_utility(task, weights)
      ScoredTask(task: task, utility_score: score, is_pareto_optimal: False)
    })

  list.map(scored, fn(st) {
    let dominated =
      list.any(candidates, fn(other) {
        other.task_id != st.task.task_id
        && other.priority >=. st.task.priority
        && other.dependency_readiness >=. st.task.dependency_readiness
        && other.fmea_risk <=. st.task.fmea_risk
        && other.resource_cost <=. st.task.resource_cost
        && {
          other.priority >. st.task.priority
          || other.dependency_readiness >. st.task.dependency_readiness
          || other.fmea_risk <. st.task.fmea_risk
          || other.resource_cost <. st.task.resource_cost
        }
      })
    ScoredTask(..st, is_pareto_optimal: !dominated)
  })
}

pub fn pull_highest_utility_task(
  candidates: List(CandidateTask),
  worker_affinity: String,
  weights: UtilityWeights,
) -> Result(ScoredTask, String) {
  let scored_queue = score_candidate_queue(candidates, weights)

  let matching =
    list.filter(scored_queue, fn(st) {
      { st.task.required_affinity == worker_affinity || st.task.required_affinity == "any" }
      && st.utility_score >. 0.0
    })

  case matching {
    [] -> Error("No eligible candidate tasks in queue")
    _ -> {
      let sorted =
        list.sort(matching, fn(a, b) {
          float.compare(b.utility_score, a.utility_score)
        })
      case list.first(sorted) {
        Ok(best) -> Ok(best)
        Error(_) -> Error("Queue empty after sorting")
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Codex Astra 5-Attribute Formulation (SC-RISK-PRIORITY-001 & GAP-CODEX-05)
// U(T) = w_C * C + w_S * S + w_D * D - (w_F * F + w_I * I)
// -----------------------------------------------------------------------------

pub type UtilityWeights5 {
  UtilityWeights5(
    weight_criticality: Float,
    weight_stpa: Float,
    weight_dependency: Float,
    weight_fmea: Float,
    weight_impact_cost: Float,
  )
}

pub type CandidateTask5 {
  CandidateTask5(
    task_id: String,
    plan_id: String,
    criticality: Float,
    stpa_hazard: Float,
    dependency_readiness: Float,
    fmea_risk: Float,
    resource_cost: Float,
    required_affinity: String,
  )
}

pub type ScoredTask5 {
  ScoredTask5(
    task: CandidateTask5,
    utility_score: Float,
    is_pareto_optimal: Bool,
  )
}

pub type FencedClaim {
  FencedClaim(
    task_id: String,
    worker_id: String,
    fencing_token: Int,
    lease_until_ms: Int,
    utility_score: Float,
  )
}

pub fn default_weights_5() -> UtilityWeights5 {
  UtilityWeights5(
    weight_criticality: 0.30,
    weight_stpa: 0.25,
    weight_dependency: 0.25,
    weight_fmea: 0.10,
    weight_impact_cost: 0.10,
  )
}

pub fn compute_utility_5(task: CandidateTask5, weights: UtilityWeights5) -> Float {
  case task.dependency_readiness <=. 0.0 {
    True -> 0.0
    False -> {
      let positive_component =
        { task.criticality *. weights.weight_criticality }
        +. { task.stpa_hazard *. weights.weight_stpa }
        +. { task.dependency_readiness *. weights.weight_dependency }
      let penalty_component =
        { task.fmea_risk *. weights.weight_fmea }
        +. { task.resource_cost *. weights.weight_impact_cost }
      let raw_utility = positive_component -. penalty_component
      case raw_utility <. 0.0 {
        True -> 0.0
        False -> raw_utility
      }
    }
  }
}

pub fn score_candidate_queue_5(
  candidates: List(CandidateTask5),
  weights: UtilityWeights5,
) -> List(ScoredTask5) {
  let scored =
    list.map(candidates, fn(task) {
      let score = compute_utility_5(task, weights)
      ScoredTask5(task: task, utility_score: score, is_pareto_optimal: False)
    })

  list.map(scored, fn(st) {
    let dominated =
      list.any(candidates, fn(other) {
        other.task_id != st.task.task_id
        && other.criticality >=. st.task.criticality
        && other.stpa_hazard >=. st.task.stpa_hazard
        && other.dependency_readiness >=. st.task.dependency_readiness
        && other.fmea_risk <=. st.task.fmea_risk
        && other.resource_cost <=. st.task.resource_cost
        && {
          other.criticality >. st.task.criticality
          || other.stpa_hazard >. st.task.stpa_hazard
          || other.dependency_readiness >. st.task.dependency_readiness
          || other.fmea_risk <. st.task.fmea_risk
          || other.resource_cost <. st.task.resource_cost
        }
      })
    ScoredTask5(..st, is_pareto_optimal: !dominated)
  })
}

pub fn pull_highest_utility_task_5(
  candidates: List(CandidateTask5),
  worker_affinity: String,
  weights: UtilityWeights5,
) -> Result(ScoredTask5, String) {
  let scored_queue = score_candidate_queue_5(candidates, weights)

  let matching =
    list.filter(scored_queue, fn(st) {
      { st.task.required_affinity == worker_affinity || st.task.required_affinity == "any" }
      && st.utility_score >. 0.0
    })

  case matching {
    [] -> Error("No eligible candidate tasks in queue")
    _ -> {
      let sorted =
        list.sort(matching, fn(a, b) {
          float.compare(b.utility_score, a.utility_score)
        })
      case list.first(sorted) {
        Ok(best) -> Ok(best)
        Error(_) -> Error("Queue empty after sorting")
      }
    }
  }
}

pub fn issue_fenced_lease(
  best: ScoredTask5,
  worker_id: String,
  current_epoch: Int,
  lease_duration_ms: Int,
) -> FencedClaim {
  FencedClaim(
    task_id: best.task.task_id,
    worker_id: worker_id,
    fencing_token: current_epoch + 1,
    lease_until_ms: current_epoch + lease_duration_ms,
    utility_score: best.utility_score,
  )
}
