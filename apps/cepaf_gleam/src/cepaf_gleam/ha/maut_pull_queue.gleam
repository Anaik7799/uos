//// =============================================================================
//// [C3I-SIL6-MSTS] MULTI-ATTRIBUTE UTILITY THEORY (MAUT) PULL QUEUE SCHEDULER
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/maut_pull_queue</module>
////     <fsharp-lineage>None — novel MAUT scheduler resolving GAP-CODEX-05</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Computes multi-attribute utility across candidate tasks, evaluates
////       Pareto optimality frontier, and pulls highest-utility non-blocked task
////       into the Heijunka leveled execution stream.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>
////       SC-SIL6-001, SC-JIDOKA-001, SC-SA-PLAN-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/list

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
  // If dependency readiness is zero, utility drops to zero (cannot be scheduled)
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

  // Tag Pareto optimality (a task is dominated if another task has strictly higher
  // priority, higher readiness, lower risk, and lower cost)
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

  // Filter matching worker affinity and non-zero utility
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
